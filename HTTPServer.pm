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
use Pub::HTTP::Response;
use artisanUtils;
use WebUI;
use Update;
use HTTPStream;
use DeviceManager;
use ContentDirectory1;
use base qw(Pub::HTTP::ServerBase);


my $dbg_req = 1;

# debug specific methods

my $dbg_icon = 0;
my $dbg_art = 0;
my $dbg_server_desc = 1;


sub new()
{
	my ($class) = @_;
	my $no_cache =  shared_clone({
		'cache-control' => 'max-age: 603200',
	});

	my $params = {

		HTTP_DEBUG_SERVER => 0,
			# 0 is nominal debug level showing one line per request and response
		HTTP_DEBUG_REQUEST => 0,
		HTTP_DEBUG_RESPONSE => 0,

		HTTP_DEBUG_QUIET_RE => join('|',(
			'\/webui\/update',
			'\/webui\/queue\/get_queue',
			'\/debug_output\/',
			'\/images\/error_\d\.png',
		)),

		# Debugging is better specified in /mp3s/_data/artisan.prefs
		# HTTP_DEBUG_LOUD_RE => '\/upnp\/event\/ContentDirectory1',
		# HTTP_DEBUG_LOUD_RE => '\.html$',
		# HTTP_DEBUG_LOUD_RE => '^\/webui\/queue',
		# HTTP_DEBUG_LOUD_RE => '^\/webui\/renderer\/.*\/next$',
		# HTTP_DEBUG_LOUD_RE => '\/media',
		# HTTP_DEBUG_LOUD_RE => '\/webui\/getDevice',
		# HTTP_DEBUG_LOUD_RE => '\/webui\/queue',
		# HTTP_DEBUG_LOUD_RE => '^.*\.(?!jpg$|png$)[^.]+$',
			# An example that shows urls that DO NOT match .jpt and .png,
			# which shows JS, HTML, etc. And by setting DEBUG_REQUEST and
			# DEBUG_RESPONSE to -1, you only see headers for the debugging
			# at level 1.

		HTTP_MAX_THREADS => 5,
		# HTTP_KEEP_ALIVE => 0,
			# In the ebay application, KEEP_ALIVE makes all the difference
			# in the world, not spawning a new thread for all 1000 images.

		HTTP_PORT => $server_port,

		# HTTP_SSL => 1,
		# HTTP_SSL_CERT_FILE => "/dat/Private/ssl/esp32/myIOT.crt",
		# HTTP_SSL_KEY_FILE  => "/dat/Private/ssl/esp32/myIOT.key",
        #
		# HTTP_AUTH_ENCRYPTED => 1,
		# HTTP_AUTH_FILE      => "$base_data_dir/users/local_users.txt",
		# HTTP_AUTH_REALM     => "$owner_name Customs Manager Service",
        #
		# HTTP_USE_GZIP_RESPONSES => 1,
		# HTTP_DEFAULT_HEADERS => {},
        # HTTP_ALLOW_SCRIPT_EXTENSIONS_RE => '',

		HTTP_DOCUMENT_ROOT => '/base/apps/artisan/webui',
		HTTP_DEFAULT_LOCATION => 'artisan.html',
		HTTP_FAVICON => '/base/apps/artisan/webui/images/artisan.png',
        HTTP_GET_EXT_RE => 'html|js|css|jpg|gif|png|ico',

		# HTTP_MINIFIED_JS	=> 1,
		# HTTP_MINIFIED_CSS	=> 1,

		# example of setting default headers for GET_EXT_RE extensions

		# HTTP_DEFAULT_HEADERS_JPG => $no_cache,
		# HTTP_DEFAULT_HEADERS_PNG => $no_cache,
	};

	my $this = $class->SUPER::new($params);
	bless $this,$class;
	return $this;
}


sub handle_request
{
	my ($this,$client,$request) = @_;

	#===============================================================
	# Handle the requests
	#===============================================================

	my $response;
	my $uri = $request->{uri};
	my $method = $request->{method};
	my $use_dbg = $dbg_req + $request->{extra_debug};

	display($use_dbg,0,"handle_request($method $uri)");

	#-------------------------------------------------
	# OPTIONS request
	#-------------------------------------------------
	# Thought this was required to allow cross-origin requests from
	# the webUI running on one Artisan to another Artisan, but not so.
	# If jquery ajax is setup to 'preflight' the requests with various
	# options, then it *would* call OPTIONS asking for more info, and
	# then we NEEDED this.
	#
	# if ($request_method eq 'OPTIONS')
	# {
	# 	$response = http_header({
	# 		addl_headers=> [
	# 			"Allow: OPTIONS,GET,POST,SUBSCRIBE,UNSUBSCRIBE",
	# 			"Access-Control-Allow-Origin: *",
	# 			"Access-Control-Allow-Headers: *",
	# 			],
	# 		});
	# }

	#------------------------------------------------------------
	# Artisan Perl BEING a DLNA Media Server/Renderer
	#------------------------------------------------------------
	# These are Post Requests, and are only for us BEING a DLNA Server/Renderer
	# and, of course, supported only for the localLibrary and localRenderer

	if ($uri eq '/upnp/control/ContentDirectory1')
	{
		$response = ContentDirectory1::handle_request($request);
	}
	elsif ($uri eq '/upnp/event/ContentDirectory1')
	{
		$response = ContentDirectory1::handleSubscribe($request);
	}

	# DLNA GET REQUESTS

	elsif ($uri =~ /^\/(ServerDesc|ContentDirectory1)\.xml/)
	{
		my $desc = $1;
		my $xml = $1 eq 'ServerDesc' ?
			ServerDesc() :
			getTextFile("$artisan_perl_dir/xml/$desc.xml",1);
		$response = Pub::HTTP::Response->new($request,$xml,200,'text/xml; charset=utf8');
	}

	#------------------------------------------------------------
	# Local Library Requests
	#------------------------------------------------------------
	# STREAMING MEDIA REQUEST (also used by the webUI)
	# duplicates the header debugging, and does not return
	# a response, so note that $dbg_response doesn't work with it.

	elsif ($uri =~ /^\/media\/(.*)$/)
	{
		my $id = $1;
		$response = HTTPStream::stream_media($client,$request,$id);
	}

	# LOCAL LIBRARY GET_ART REQUEST
	# /get_art/folder_id.jpg is folded into the DLNA api AND called by the webUI

	elsif ($uri =~ /^\/get_art*\/(.*)\/folder.jpg$/)
	{
		my $folder_id = $1;
		$response = $this->get_art($request,$1);	# folder id
	}


	#------------------------------------------------------------
	# Distributed Requests
	#------------------------------------------------------------
	# WEBUI CALLS

	elsif ($uri =~ /^\/webui\/(.*)$/)
	{
		my $path = $1;
		$path ||= '';
		$path =~ s/^\///;
		$response = WebUI::webui_request($request,$path);
	}


	# currently unused NOTIFY events from remoteLibraries we are 'subscribed' to.

	elsif ($uri =~/\/remoteLibrary\/event\/(.*)$/)
	{
		my $library_uuid = $1;
		display(0,0,"got /remoteLibrary/event to $library_uuid");
		my $library = findDevice($DEVICE_TYPE_LIBRARY,$library_uuid);
		if (!$library)
		{
			$response = http_error($request,"Could not find library $library_uuid");
		}
		else
		{
			$response = $library->event_request($request);
		}
	}


	#------------------------------------------------------------
	# system requests
	#------------------------------------------------------------

	elsif ($uri eq "/reboot")
	{
		LOG(0,"Artisan rebooting the rPi");
		system("sudo reboot") if !is_win();
		$response = http_ok($request,"Rebooting Server");
	}
	elsif ($uri eq '/restart_service')
	{
		LOG(0,"Artisan restarting service in 5 seconds");
		$restart_service = time();	# if !is_win();
		$uri = http_ok($request,"Restarting Service.\nWill reload WebUI in 30 seconds..");
	}
	elsif ($uri eq '/update_system')
	{
		LOG(0,"Artisan updating system");
		my $error = Update::doSystemUpdate();
		if ($error)
		{
			$error =~ s/\r/ /g;
			$response = http_ok($request,"There was an error doing a system_update:\n$error");
		}
		else
		{
			LOG(0,"restarting service in 5 seconds");
			$restart_service = time();	# if !is_win();
			$response = http_ok($request,"Restarting Service after System Update.\nWill reload WebUI in 30 seconds..");
		}
	}

	# call base class

	else
	{
		$response = $this->SUPER::handle_request($client,$request);
	}

	return $response;

}   # handle_connection()



#-----------------------------------------------------------------
# Snippets
#-----------------------------------------------------------------

sub get_art
{
	my ($this,$request,$id) = @_;
    display($dbg_art,0,"get_art($id)");

	my $folder = $local_library->getFolder($id,undef,$dbg_art);
	return http_error("Could not find folder for id($id)")
		if !$folder;

    # open the file and send it to the client

	my $filename = "$mp3_dir/$folder->{path}/folder.jpg";
    if (!(-f $filename))
    {
        error("get_art($id): file not found: $filename");
		$filename = "$image_dir/no_image.jpg";
    }

	return Pub::HTTP::Response->new($request,{filename => $filename});

}   # get_art()




sub ServerDesc
	# server description for the DLNA Server
{
	# my $use_friendly = $program_name;
	my $use_friendly = "Artisan(".getMachineId().")";

	my $xml = <<EOXML;
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
    <specVersion>
        <major>1</major>
        <minor>5</minor>
    </specVersion>
    <device>
		<UDN>uuid:$this_uuid</UDN>
        <friendlyName>$use_friendly</friendlyName>
        <deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>
        <manufacturer>phorton1</manufacturer>
        <manufacturerURL>https://github.com/phorton1</manufacturerURL>
        <modelName>$program_name</modelName>
        <modelDescription>a simple media server</modelDescription>
        <modelNumber>2.0</modelNumber>
        <modelURL>https://github.com/phorton1/base-apps-artisan</modelURL>
        <presentationURL>http://$server_ip:$server_port</presentationURL>
        <serialNumber>ap-12345678</serialNumber>
		<dlna:X_DLNADOC xmlns:dlna="urn:schemas-dlna-org:device-1-0">DMS-1.50</dlna:X_DLNADOC>
        <iconList>
			<icon>
				<mimetype>image/png</mimetype>
				<width>256</width>
				<height>256</height>
				<depth>24</depth>
				<url>/images/artisan_16_large.png</url>
			</icon>\n";
		</iconList>
        <serviceList>
            <service>
                <serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:ContentDirectory</serviceId>
                <SCPDURL>/ContentDirectory1.xml</SCPDURL>
                <controlURL>/upnp/control/ContentDirectory1</controlURL>
                <eventSubURL>/upnp/event/ContentDirectory1</eventSubURL>
            </service>
        </serviceList>
    </device>
    <URLBase>http://$server_ip:$server_port/</URLBase>
</root>
EOXML


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

	display($dbg_server_desc,0,$xml);
	return $xml;
}







#------------------------------------------------------
# obsolete old webui getting of DOCUMENT_ROOT_FILES
#------------------------------------------------------

# # deliver static files
#
# my $response = undef;
# if ($path =~ /^((.*\.)(js|css|gif|png|html|json))$/)
# {
# 	my $filename = $1;
# 	my $type = $3;
# 	my $query = $5;
#
# 	# scale fancytree CSS file if it has scale param
#
# 	if (!(-f "$artisan_perl_dir/webui/$filename"))
# 	{
# 		$response = http_error("web_ui(): Could not open file: $filename");
# 	}
# 	elsif ($params->{scale} &&
# 		   $filename =~ /ui\.fancytree\.css$/)
# 	{
# 		$response = scale_fancytree_css($filename,$params->{scale});
# 	}
# 	else
# 	{
# 		my $content_type =
# 			$type eq 'js'  ? 'text/javascript' :
# 			$type eq 'css' ? 'text/css' :
# 			$type eq 'gif' ? 'image/gif' :
# 			$type eq 'png' ? 'image/png' :
# 			$type eq 'html' ? 'text/html' :
# 			$type eq 'json' ? 'application/json' :
# 			'text/plain';
#
# 		# add CORS cross-origin headers to the main HTML file
# 		# allow cross-origin requests to iPad browsers
# 		# which would not call /get_art/ to get our album art URIs otherwise
#
# 		# Modified to allow most generous CORS options while messing with
# 		# 	cross-origin webUI request, but this is not, per se, specifically
# 		# 	needed for those.
#
# 		my $addl_headers = [];
# 		if ($type eq 'html')
# 		{
# 			push @$addl_headers,"Access-Control-Allow-Origin: *";			# was http://$server_ip:$server_port";
# 			push @$addl_headers,"Access-Control-Allow-Methods: GET";		# OPTIONS, POST, SUBSCRIBE, UNSUBSCRIBE
# 		}
#
# 		$response = http_header({
# 			content_type => $content_type,
# 			addl_headers => $addl_headers });
#
# 		if ($SEND_MINIFIED_JS_AND_CSS && ($type eq 'js' || $type eq 'css'))
# 		{
# 			my $filename2 = $filename;
# 			$filename2 =~ s/$type$/min.$type/;
# 			display(5,0,"checking MIN: $filename2");
# 			if (-f "$artisan_perl_dir/webui/$filename2")
# 			{
# 				display($dbg_webui,1,"serving MIN: $filename2");
# 				$filename = $filename2;
# 			}
# 		}
#
# 		my $text = getTextFile("$artisan_perl_dir/webui/$filename",1);
# 		$text = process_html($text) if ($type eq 'html');
# 		$response .= $text."\r\n";
# 	}
# }
#
#
#	sub process_html
#	{
#		my ($html,$level) = @_;
#		$level ||= 0;
#
#		# special global variable replacement
#
#		my $is_win = is_win() ? 1 : 0;
#		my $as_service = $AS_SERVICE ? 1 : 0;
#		my $machine_id = getMachineId();
#
#		$html =~ s/is_win\(\)/$is_win/s;
#		$html =~ s/as_service\(\)/$as_service/s;
#		$html =~ s/machine_id\(\)/$machine_id/s;
#
#		while ($html =~ s/<!-- include (.*?) -->/###HERE###/s)
#		{
#			my $id = '';
#			my $spec = $1;
#			$id = $1 if ($spec =~ s/\s+id=(.*)$//);
#
#			my $filename = "$artisan_perl_dir/webui/$spec";
#			display($dbg_webui+1,0,"including $filename  id='$id'");
#			my $text = getTextFile($filename,1);
#
#			$text =~ s/{id}/$id/g;
#
#			$text = process_html($text,$level+1);
#			$text = "\n<!-- including $filename -->\n".
#				$text.
#				"\n<!-- end of included $filename -->\n";
#
#			$html =~ s/###HERE###/$text/;
#		}
#
#		if (0 && !$level)
#		{
#			while ($html =~ s/<script type="text\/javascript" src="\/(.*?)"><\/script>/###HERE###/s)
#			{
#				my $filename = $1;
#				display($dbg_webui+1,0,"including javascript $filename");
#				my $eol = "\r\n";
#				# my $text = getTextFile($filename,1);
#
#				my $text = $eol.$eol."<script type=\"text\/javascript\">".$eol.$eol;
#				my @lines = getTextLines($filename);
#				for my $line (@lines)
#				{
#					$line =~ s/\/\/.*$//;
#					$text .= $line.$eol;
#				}
#
#				while ($text =~ s/\/\*.*?\*\///s) {};
#				$text .= $eol.$eol."</script>".$eol.$eol;
#				$html =~ s/###HERE###/$text/s;
#			}
#		}
#
#		return $html;
#	}
#
#	sub scale_fancytree_css
#		# algorithmically scale fancy tree css file
#		# requires that icons$pixels.gif created by hand
#		# scale font-size pts, and certain px values
#	{
#		my ($filename,$pixels) = @_;
#		my $factor = $pixels/16;
#		display($dbg_webui+2,0,"scale($pixels = $factor) $filename");
#
#		my $text .= getTextFile("$artisan_perl_dir/webui/$filename",1);
#		$text =~ s/url\("icons\.gif"\);/url("icons$pixels.gif");/sg;
#		$text =~ s/font-size: 10pt;/'font-size: '.int($factor*10).'pt;'/sge;
#		$text =~ s/(\s*)((-)*(16|32|48|64|80|96|112|128|144))px/' '.int($factor*$2).'px'/sge;
#		# printVarToFile(1,"/junk/test.css",$text);
#
#		my $response = http_header({ content_type => 'text/css' });
#		$response .= $text;
#		$response .= "\r\n";
#		return $response;
#	}




1;
