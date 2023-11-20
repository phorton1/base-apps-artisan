#!/usr/bin/perl
#---------------------------------------
# HTTPServer.pm
#---------------------------------------
# inspired by: http://www.adp-gmbh.ch/perl/webserver/
# modified from pDNLA server

package HTTPServer;
use strict;
use warnings;
use threads;
use threads::shared;
use Fcntl;
use Socket;
use IO::Select;
use artisanUtils;
use httpUtils;
use HTTPStream;
use ContentDirectory1;
use WebUI;


my $dbg_http = 0;
	#  0 == lifecycle
my $dbg_post = 1;
	#  0 == show POST data
my $dbg_art = 0;
	# 0 == debug get_art() method
my $dbg_server_desc = 1;
	# 0 = show the xml to be returned for ServerDesc.xml


# use with care - debugging that cannot be filtered by call

my $dbg_connect = 1;
	#  0 == show individual connections
	# -1 == rarely used to show pending connnections in case there is
	#       more than one at a time or to debug $FH closing at end

my $dbg_hdr = 1;
	#  0 == show actual request header lines


# debugging that is filtered for renderer/xxx/update calls

my $dbg_request = 0;
	#  0 == show a header for every non renderer/xxx/update call
	# -1 == show request headers for same
	# -2 == show header for renderer/xxx/update calls, headers for all otherw
	# -3 == show headers for everything

my $dbg_response = 0;			# show the first line
	# Response never shows for filtered requests
	#  0 = single line with status line,, content_type, and length if present
	# -1 = show the actual headers
	# -2 = show the actual body, if any


# !!! MULTI-THREAD NOT WORKING in old artisanWin !!!
# Crashes when I try to "set the renderer" from the webUI
# at least in the old Wx artisanWin app ..
# The last thing appears to be the close($FH) at the end of handle_connection(),
# which is a thread created, and detached in start_webserver, below.
# Does not appear to make any difference if I detach, $FH, or init
# artisanWin from the main thread, or not.
# Then I get "Free to wrong pool during global destruction" error message
# Single thread set directly in artisan.pm

our $SINGLE_THREAD = 0;
	# 0 required the use of Win32::OLE::prhSetThreadNum(1) in localRenderer.pm.
	# used to be set to 1 in artisanWin.pm and artisan.pm
my $http_running:shared = 0;

sub running
{
	return $http_running;
}


sub start_webserver
	# this is a separate thread, even if $SINGLE_THREA
{
	# My::Utils::setOutputToSTDERR();
	# My::Utils::set_alt_output(1);
	display($dbg_http,0,"HTTPServer starting ...");

	local *S;
	socket(S, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die "Can't open HTTPServer socket: $!\n";
	setsockopt(S, SOL_SOCKET, SO_REUSEADDR, 1);
	my $ip = inet_aton($server_ip);
	bind(S, sockaddr_in($server_port, $ip));
	if (!listen(S, 5))
    {
        error("Can't listen to HTTPServer socket: $!\n");
        return;
    }

	my $ss = IO::Select->new();
	$ss->add(*S);

	$http_running = 1;

    LOG(0,"HTTPServer started on $server_ip:$server_port");
	while ($http_running)
	{
		if ($quitting)
		{
			$http_running = 0 if $http_running == 1;
		}
		else
		{
			my @connections_pending = $ss->can_read($SINGLE_THREAD?1:60);
			display($dbg_connect+1,0,"accepted ".scalar(@connections_pending)." pending connections")
				if (@connections_pending);
			for my $connection (@connections_pending)
			{
				my $FH;
				my $remote = accept($FH, $connection);
				my ($peer_port, $peer_addr) = sockaddr_in($remote);
				my $peer_ip = inet_ntoa($peer_addr);
				$http_running++;

				if ($SINGLE_THREAD)
				{
					handle_connection( $FH, $peer_ip, $peer_port );
				}
				else
				{
					my $thread = threads->create(\&handle_connection, $FH, $peer_ip, $peer_port);
					$thread->detach();
				}
			}
		}
	}
    LOG(0,"HTTPServer ended on $server_ip:$server_port");
}



sub handle_connection
{
	my ($FH,$peer_ip,$peer_port) = @_;
	binmode($FH);

	# My::Utils::setOutputToSTDERR();
	# My::Utils::set_alt_output(1) if (!$SINGLE_THREAD);

	display($dbg_connect,0,"HTTP connect from $peer_ip:$peer_port");

	#=================================
	# parse http request header
	#=================================

	my $request_method;
	my $request_path;
	my %request_headers = ();

	my $first_line;
	my $request_line = <$FH>;
	display($dbg_hdr,0,"ACTUAL HEADERS");
	while (defined($request_line) && $request_line ne "\r\n")
	{
		# next if !$request_line;
		$request_line =~ s/\r\n//g;
		chomp($request_line);

		display($dbg_hdr,1,$request_line);

		if (!$first_line)
		{
			$first_line = $request_line;
			my @parts = split(' ', $request_line);
			close $FH if @parts != 3;
			$request_method = $parts[0];
			$request_path = $parts[1];
			my $http_version = $parts[2];
		}
		else
		{
			my ($name, $value) = split(':', $request_line, 2);
			$name =~ s/-/_/g;
			$name = uc($name);
			$value =~ s/^\s//g;
			$request_headers{$name} = $value;
		}
		$request_line = <$FH>;
	}

	# if we got no request line,
	# then it is an unrecoverable error

	if (!$first_line ||
		!defined($request_method) ||
		!defined($request_path))
	{
		error("Unable to parse HTTP from $peer_ip:$peer_port line="._def($first_line));
		my $response = http_header({
			status_code   => 501,
			content_type => 'text/plain' });
		print $FH $response;
		close($FH);
		$http_running--;
		return 0;
	}

    # debug display and/or log the request
	# don't want to see the stupid static requests

	my $use_dbg_request = $dbg_request;
	my $use_dbg_response = $dbg_response;

	$use_dbg_request += 2  if $request_path =~ /^\/webui\/renderer\/(.*)\/update/; #|\/^ContentDirectory1\.xml|\/ServerDesc\.xml/;
	# $use_dbg_request -= 2  if $request_method =~ /SUBSCRIBE/;
	# $use_dbg_response -= 2  if $request_method =~ /SUBSCRIBE/;

	display($use_dbg_request,0,"$request_method $request_path from $peer_ip:$peer_port");
	for my $key (keys %request_headers)
	{
		display($use_dbg_request+1,1,"$key=$request_headers{$key}");
	}

	#=================================
    # Parse POST request XML
	#=================================

	my $post_data = '';
	if ($request_method eq "POST")
	{
		my $content_length = $request_headers{CONTENT_LENGTH};
		if (defined($content_length) && length($content_length) > 0)
		{
			display($dbg_request,1,"Reading $content_length bytes for POSTDATA");
			read($FH, $post_data, $content_length);
		}
		else
		{
			display($dbg_request,1,"Reading content until  cr-lf for POSTDATA");
			my $line = <$FH>;
			while ($line && $line ne "\r\n")
			{
				$post_data .= $line;
				$line = <$FH>;
			}
		}
		display($dbg_post,1,"POSTDATA: $post_data");
	}


	#===============================================================
	# Handle the requests
	#===============================================================

	my $response = undef;
	my $dbg_displayable = 1;

	#------------------------------------------------------------
	# Artisan Perl BEING a DLNA Media Server/Renderer
	#------------------------------------------------------------
	# These are Post Requests, and are only for us BEING a DLNA Server/Renderer
	# and, of course, supported only for the localLibrary and localRenderer

	if ($request_path eq '/upnp/control/ContentDirectory1')
	{
		$response = ContentDirectory1::handle_request($request_method, \%request_headers, $post_data, $peer_ip, $peer_port);
	}
	elsif ($request_path eq '/upnp/event/ContentDirectory1')
	{
		$response = ContentDirectory1::handleSubscribe($request_method,\%request_headers,$peer_ip,$peer_port)
	}

	# DLNA GET REQUESTS

	elsif ($request_path =~ /^\/(ServerDesc|ContentDirectory1)\.xml/)
	{
		my $desc = $1;
		my $xml = $1 eq 'ServerDesc' ?
			ServerDesc() :
			getTextFile("$artisan_perl_dir/xml/$desc.xml",1);
		$response = http_header({
			status_code => 200,
			content_type => 'text/xml; charset=utf8',
			content_length => length($xml) });
		$response .= $xml;
	}

	# STREAMING MEDIA REQUEST (also used by the webUI)
	# duplicates the header debugging, and does not return
	# a response, so note that $dbg_response doesn't work with it.

	elsif ($request_path =~ /^\/media\/(.*)$/)
	{
		my $id = $1;
		stream_media($FH,, $request_method, \%request_headers, $id);
		$dbg_displayable = 0;
	}

	# /get_art/folder_id.jpg is folded into the DLNA api AND called by the webUI

	elsif ($request_path =~ /^\/get_art*\/(.*)\/folder.jpg$/)
	{
		$response = get_art($1);	# foldeer id
		$dbg_displayable = 0;
	}


	#------------------------------------------------------------
	# WEBUI GET CALLS
	#------------------------------------------------------------

	elsif ($request_path =~ /^\/webui(\/.*)*$/)
	{
		my $path = $1;
		$path ||= '';
		$path =~ s/^\///;
		$response = WebUI::web_ui($path);	# ,\%request_headers,$post_xml);
		$dbg_displayable = 0 if $request_path =~ /^\/webui\/icons\//;
			# don't show Library /webui/icons/png files
	}


	#------------------------------------------------------------
	# all other calls
	#------------------------------------------------------------
	# generic icon request

	elsif ($request_path =~ /^\/(favicon.ico|icons)/)
	{
		$response = favicon();
		$dbg_displayable = 0;
	}

	# unsupported request

	else
	{
		error("Unsupported request $request_method $request_path from $peer_ip:$peer_port");
		$response = http_header({ status_code => 501 });
	}


    #===========================================================
    # send response to client
    #===========================================================

	if ($quitting && defined($response))
	{
		warning(0,0,"not sending response in handle_connection() due to quitting");
	}
	elsif (defined($response))
	{
		if ($use_dbg_request <= $debug_level)	# only show debugging for non-filtered requests
		{
			display($use_dbg_response,1,"Sending ".length($response)." byte response");

			my $first_line = '';
			my $content_type = '';
			my $content_len  = '';

			# run through the headers

			my $in_body = 0;
			my $started = 0;
			my @lines = split(/\n/,$response);
			for my $line (@lines)
			{
				$line =~ s/\s+$//;
				$first_line = $line if !$started;
				$started = 1;

				$content_type = "content_type($1)" if $line =~ /content-type:\s*(.*)$/;
				$content_len = "content_len($1)" if $line =~ /content-length:\s*(.*)$/;
				$in_body = ($dbg_displayable ? 100 : 1) if !$line;

				display($use_dbg_response+$in_body+1,2,$line);
			}

			display(0,1,"RESPONSE: $first_line $content_type $content_len")
				if $use_dbg_response == 0;
		}

		(print $FH $response) ?
			display($use_dbg_response+1,1,"Sent response OK") :
			error("Could not complete HTTP Server Response len=".length($response));
	}

	display($dbg_connect+1,1,"Closing File Handle");
	close($FH);
	display($dbg_connect+1,1,"File Handle Closed");

	$http_running--;
	return 1;

}   # handle_connection()



#-----------------------------------------------------------------
# Snippets
#-----------------------------------------------------------------

sub favicon
{
    display($dbg_http+2,1,"favicon()");
    my $response = http_header({ content_type => 'image/png' });
	$response .= getTextFile('artisan.png',1);
    $response .= "\r\n";
	return $response;

}


sub get_art
{
	my ($id) = @_;
    display($dbg_art,0,"get_art($id)");

	my $folder = $local_library->getFolder($id);
	if (!$folder)
	{
		error("get_art($id): could not get folder($id)");
		return http_header({ status_code => 400 });
	}

    # open the file and send it to the client

	my $filename = "$mp3_dir/$folder->{path}/folder.jpg";
    if (!(-f $filename))
    {
        error("get_art($id): file not found: $filename");
		$filename = "$artisan_perl_dir/images/no_image.jpg";
    }

    display($dbg_art,1,"get_art($id) opening file: $filename");
    if (!open(IFILE,"<$filename"))
    {
        error("get_art($id): Could not open file: $filename");
        return http_header({ status_code => 400 });
    }

    binmode IFILE;
    my $data = join('',<IFILE>);
    close IFILE;

    display($dbg_art,1,"get_art($id): sending file: $filename");
    my $response = http_header({ content_type => 'image/jpeg' });
    $response .= $data;
    $response .= "\r\n";
    return $response;

}   # get_art()




sub ServerDesc
	# server description for the DLNA Server
{
	my $xml = <<EOXML;
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
    <specVersion>
        <major>1</major>
        <minor>5</minor>
    </specVersion>
    <device>
		<UDN>uuid:$this_uuid</UDN>
        <friendlyName>$program_name</friendlyName>
        <deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>
        <manufacturer>phorton1</manufacturer>
        <manufacturerURL>https://github.com/phorton1</manufacturerURL>
        <modelName>$program_name</modelName>
        <modelDescription>a simple media server</modelDescription>
        <modelNumber>2.0</modelNumber>
        <modelURL>https://github.com/phorton1/base-apps-artisan</modelURL>
        <presentationURL>http://$server_ip:$server_port/webui/artisan.html</presentationURL>
        <serialNumber>ap-12345678</serialNumber>
		<dlna:X_DLNADOC xmlns:dlna="urn:schemas-dlna-org:device-1-0">DMS-1.50</dlna:X_DLNADOC>
        <iconList>
EOXML

    my $indent = "            ";
    for my $size (256)  # 120, 48, 32)
    {
        for my $type (qw(png)) # jpeg))
        {
            $xml .= $indent."<icon>\n";
            $xml .= $indent."    <mimetype>image/$type</mimetype>\n";
            $xml .= $indent."    <width>$size</width>\n";
            $xml .= $indent."    <height>$size</height>\n";
            $xml .= $indent."    <depth>24</depth>\n";
            $xml .= $indent."    <url>/icons/$size/icon.$type</url>\n";
            $xml .= $indent."</icon>\n";
        }
    }

    # we dont advertise that we're a connection manager,
    # since we're not ...
    #
    # <service>
    #    <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
    #    <serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
    #    <SCPDURL>ConnectionManager1.xml</SCPDURL>
    #    <controlURL>/upnp/control/ConnectionManager1</controlURL>
    #    <eventSubURL>/upnp/event/ConnectionManager1</eventSubURL>
    # </service>

    $xml .= <<EOXML;
        </iconList>
        <serviceList>
            <service>
                <serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:ContentDirectory</serviceId>
                <SCPDURL>ContentDirectory1.xml</SCPDURL>
                <controlURL>/upnp/control/ContentDirectory1</controlURL>
                <eventSubURL>/upnp/event/ContentDirectory1</eventSubURL>
            </service>
        </serviceList>
    </device>
    <URLBase>http://$server_ip:$server_port/</URLBase>
</root>
EOXML

	display($dbg_server_desc,0,$xml);
	return $xml;
}






1;
