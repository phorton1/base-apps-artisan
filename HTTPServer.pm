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
use XML::Simple;
use Utils;
use Database;
use Library;
use WebUI;

# PRH !!! THE THREADED APPROACH  NOT WORKING ON ARTISAN_WIN !!!
# Crashes when I try to "set the renderer" from the webUI
#
# The last thing appears to be the close($FH) at the end of handle_connection(),
# which is a thread created, and detached in start_webserver, below.
# Does not appear to make any difference if I etach, $FH, or init
# artisan from the main thread, or not.
#
# Then I get "Free to wrong pool during global destruction" error message
# Single thread set directly in artisan.pm

our $SINGLE_THREAD = 0;
	# SET TO 1 in ARTISAN_WIN.PM !!!
    # set this to one to see full requests
    # while debugging, otherwise you will get
    # messages from different threads interspersed
    # in debug output
my $DEBUG_SEARCH = 0;
    # Set this to one to see the full request and
    # response xml for Search requests at debug
    # level 1 or greater
my $DEBUG_BROWSE = 0;
    # Set this to one to see the full request and
    # response xml for Browse requests at debug
    # level 1 or greater

my $cache_timeout = 1800;


my $system_update_id = time();
# share($system_update_id);


sub start_webserver
	# this is a separate thread, even if $SINGLE_THREA
{
	My::Utils::set_alt_output(1);
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

    LOG(0,"HTTPServer started on $server_ip:$server_port");
	while(1)
	{
		my @connections_pending = $ss->can_read($SINGLE_THREAD?1:60);
		display($dbg_http+1,0,"accepted ".scalar(@connections_pending)." pending connections")
			if (@connections_pending);
		for my $connection (@connections_pending)
		{
			my $FH;
			my $remote = accept($FH, $connection);
			my ($peer_src_port, $peer_addr) = sockaddr_in($remote);
			my $peer_ip_addr = inet_ntoa($peer_addr);
			
			if ($SINGLE_THREAD)
			{
				handle_connection( $FH, $peer_ip_addr, $peer_src_port );
			}
			else
			{
				my $thread = threads->create(\&handle_connection, $FH, $peer_ip_addr, $peer_src_port);
				$thread->detach();
			}
		}
	}
}




sub my_parse_xml
{
	my ($post_data,$msg) = @_;
	my $xml;
	my $xmlsimple = XML::Simple->new();
	eval { $xml = $xmlsimple->XMLin($post_data) };
	if ($@)
	{
		error("Unable to parse xml $msg:".$@);
		$xml = undef;
	}
	return $xml;
}




sub handle_connection
{
	my ($FH,$peer_ip_addr,$peer_src_port) = @_;
	binmode($FH);
	
	My::Utils::set_alt_output(1) if (!$SINGLE_THREAD);
	
	display($dbg_http+1,0,"HTTP connect from $peer_ip_addr:$peer_src_port");

	#--------------------------------
	# parse http request header
	#--------------------------------

	my $request_method;
	my $request_path;
	my %request_headers = ();

	my $first_line;
	my $request_line = <$FH>;
	while (defined($request_line) && $request_line ne "\r\n")
	{
		# next if !$request_line;
		$request_line =~ s/\r\n//g;
		chomp($request_line);

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
		error("Unable to parse HTTP from $peer_ip_addr:$peer_src_port line="._def($first_line));
		my $response = http_header({
			statuscode   => 501,
			content_type => 'text/plain' });
		print $FH $response;
		close($FH);
		return 0;
	}

    # debug display and/or log the request
	# don't want to see the stupid static requests
	
	my $dbg_request = $dbg_http;
	$dbg_request += 2  if $request_path =~ /^(\/webui\/renderer\/update_renderer|\/ContentDirectory1\.xml|\/ServerDesc\.xml)/;
	display($dbg_request,0,"$request_method $request_path from $peer_ip_addr:$peer_src_port");
	for my $key (keys %request_headers)
	{
		display($dbg_request+1,1,"$key=$request_headers{$key}");
	}

	#--------------------------------
    # Parse POST request XML
	#--------------------------------

	my $post_xml;
	if ($request_method eq "POST")
	{
		my $post_data = '';
		my $content_length = $request_headers{CONTENT_LENGTH};
		if (defined($content_length) && length($content_length) > 0)
		{
			display($dbg_http+1,1,"Reading $content_length bytes from POSTDATA");
			read($FH, $post_data, $content_length);
		}
		else
		{
			display($dbg_http+1,1,"Looking for cr-lf in POSTDATA");
			$post_data = <$FH>;
		}
		display($dbg_request+1,1,"POSTDATA: $post_data");

		$post_xml = my_parse_xml($post_data,"from $peer_ip_addr:$peer_src_port");
	
		# debug display of incoming xml
		
		if ($post_xml)
		{
		    my $dbg_this = 3; # normally we don't see the xml
            $dbg_this = 0 if ($DEBUG_SEARCH &&
                $request_path eq '/upnp/control/ContentDirectory1' &&
                $post_data =~ /Search/);
            $dbg_this = 0 if ($DEBUG_BROWSE &&
                $request_path eq '/upnp/control/ContentDirectory1' &&
                $post_data =~ /Browse/);
			display($dbg_http+1,1,"Parsed xml from $peer_ip_addr:$peer_src_port dbg_this=$dbg_this");
            debug_xml($dbg_this,0,"XML RECEIVED",$post_xml);
		}
	}


    #----------------------------------------
	# Handle the requests
    #----------------------------------------
    # Icon and Server XML descriptions


	my $response = undef;
	my $dbg_displayable = 1;
	
	if ($request_path =~ /^\/(favicon.ico|icons)/)
	{
		$response = logo();
		$dbg_displayable = 0;
	}
	elsif ($request_path =~ /\/((ServerDesc|ContentDirectory1)\.xml)/)
	{
		my $desc = $1;
		my $xml = $1 eq 'ServerDesc.xml' ?
			xml_serverdescription() :
			getTextFile("$artisan_perl_dir/xml/$desc",1);
		my @additional_header = (
			'Content-Type: text/xml; charset=utf8',
			'Content-Length: '.length($xml) );
		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header });
		$response .= $xml;
	}
	
	# The meat of the server, dispatch the request to
	# a handler method. For performance and sanity purposes,
	# we make, and pass down a database connection.
	
	else
	{
		if ($request_path eq '/upnp/control/ContentDirectory1')
		{
			$response = content_directory_1($post_xml, $request_headers{SOAPACTION}, $peer_ip_addr);
		}
		elsif ($request_path =~ /^\/media\/(.*)$/)
		{
			stream_media($1, $request_method, \%request_headers, $FH, '', $peer_ip_addr);
			$dbg_displayable = 0;
		}
		elsif ($request_path =~ /^\/get_art*\/(.*)\/folder.jpg$/)
		{
			$response = get_art($1);
			$dbg_displayable = 0;
		}
		elsif ($request_path =~ /^\/webui(\/.*)*$/)
		{
			my $param = $1;
			$param ||= '';
			$param =~ s/^\///;
			$response = WebUI::web_ui($param,\%request_headers,$post_xml);
			$dbg_displayable = 0 if ($request_path =~ /\.(gif|png)$/);
		}
	
		# unsupported request
	
		else
		{
			error("Unsupported request $request_method $request_path from $peer_ip_addr");
			$response = http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain' });
		}
	}
	
    #--------------------------------
    # send response to client
    #--------------------------------

	if ($quitting && defined($response))
	{
		warning(0,0,"not sending response in handle_connection() due to quitting");
	}
	elsif (defined($response))
	{
        my $dbg_this = 3;  # normally don't see the XML
		my $dbg_this_xml = ($response =~ /content-type:\s*text\/(json|xml)/i)  ? 1 : 0;
        $dbg_this = 0 if ($DEBUG_SEARCH && $response =~ /SearchResponse/);
        $dbg_this = 0 if ($DEBUG_BROWSE && $response =~ /BrowseResponse/);
		
		if ($debug_level >= $dbg_this)
        {
            if ($dbg_displayable)
			{
				display($dbg_http+3,1,"RAW HTTP RESPONSE");
				display($dbg_http+3,2,$response);
			}

            my $started = 0;
            my $dbg_xml_part = '';
            display($dbg_http+2,1,"HTTP HEADERS");
            for my $line (split(/\n/,$response))
            {
                $line =~ s/\s*$//;
                display($dbg_http+2,2,"$line") if (!$started);
                $dbg_xml_part .= $line."\n" if ($started);
                $started = 1 if ($line eq '');
            }
			
            debug_xml_text($dbg_this,1,"XML RESPONSE",$dbg_xml_part)
				if ($dbg_this_xml && $dbg_xml_part);
        }

		display($dbg_http+1,1,"Sending ".length($response)." byte response");
		if (!print $FH $response)
		{
			error("Could not complete HTTP Server Response len=".length($response));
		}
		display($dbg_http+1,1,"Sent response");
	}

	display($dbg_http+1,1,"Closing File Handle");
	close($FH);
	display($dbg_http+1,1,"File Handle Closed");
	return 1;

}   # handle_connection()




sub debug_xml_text
{
    my ($level,$indent,$msg,$text) = @_;
    my $xml = my_parse_xml($text,"debug_xml_text($msg)");

    # always show the raw xml if the parse failed

    if (!$xml)
    {
        #$text =~ s/&lt;/</g;
        #$text =~ s/&gt;/>/g;
        #$text =~ s/&quot;/"/g;
        display(0,$indent,"");
        display(0,$indent,"XML TEXT (PARSE FAILED)");
        my $num = 1;
        for my $line (split(/\n/,$text))
        {
            display(0,$indent+1,($num++).":".$line);
        }
    }
    else
    {
        debug_xml($level,$indent,$msg,$xml);
    }
}


sub debug_xml
{
    my ($level,$indent,$msg,$xml) = @_;
    use Data::Dumper;
    $Data::Dumper::Indent = 1;
    my $dump = Dumper($xml);
    my @xml_lines = split(/\n/,$dump);
    shift @xml_lines;
    pop @xml_lines;

    display($level,$indent,"");
    display($level,$indent,$msg);
    for my $line (@xml_lines)
    {
        display($level,$indent+1,$line);
    }
    display($level,$indent,"");
}



sub http_header
{
	my ($params) = @_;

	my %HTTP_CODES = (
		200 => 'OK',
		206 => 'Partial Content',
		400 => 'Bad request',
		403 => 'Forbidden',
		404 => 'Not found',
		406 => 'Not acceptable',
		501 => 'Not implemented' );

	my @response = ();
	push(@response, "HTTP/1.1 ".$$params{'statuscode'}." ".$HTTP_CODES{$$params{'statuscode'}}); # TODO (maybe) differ between http protocol versions
	push(@response, "Server: $program_name");
	push(@response, "Content-Type: ".$params->{'content_type'}) if $params->{'content_type'};
	push(@response, "Content-Length: ".$params->{'content_length'}) if $params->{'content_length'};
	push(@response, "Date: ".http_date());
    # push(@response, "Last-Modified: ".PDLNA::Utils::http_date());

	if (defined($$params{'additional_header'}))
	{
		for my $header (@{$$params{'additional_header'}})
		{
			push(@response, $header);
		}
	}
	
	if (0)
	{
		push(@response,"ETag:");
		push(@response,'Cache-Control "max-age=0, no-cache, no-store, must-revalidate"');
		push(@response,'Pragma "no-cache"');
		push(@response,'Expires "Wed, 11 Jan 1984 05:00:00 GMT"');
	}
	else
	{
		push(@response, 'Cache-Control: no-cache');
	}
	
	push(@response, 'Connection: close');
	
	return join("\r\n", @response)."\r\n\r\n";
}



#----------------------------------------------
# content_directory_1 dispatcher
#----------------------------------------------

sub content_directory_1
{
	my ($xml,$action,$peer_ip_addr) = @_;
	my $response_xml = undef;
    display($dbg_http+1,0,"content_directory_1(xml=$xml,action=$action)");

    # browser, search, bookmark

	if ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"')
	{
        $response_xml = browse_directory($xml,$peer_ip_addr);
    }
    elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#Search"')
    {
        $response_xml = search_directory($xml,$peer_ip_addr);
    }
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_SetBookmark"')
	{
        $response_xml = set_bookmark($xml,$peer_ip_addr);
	}

    # capability responses

	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSearchCapabilities"')
	{
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:GetSearchCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<SearchCaps>*</SearchCaps>';
		$response_xml .= '</u:GetSearchCapabilitiesResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSortCapabilities"')
	{
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:GetSortCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<SortCaps></SortCaps>';
		$response_xml .= '</u:GetSortCapabilitiesResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSystemUpdateID"')
	{
        warning(0,-1,"Thats the first time I've seen someone call action = GetSystemUpdateID($system_update_id)");
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:GetSystemUpdateIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= "<Id>$system_update_id</Id>";
		$response_xml .= '</u:GetSystemUpdateIDResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_GetIndexfromRID"')
	{
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:X_GetIndexfromRIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<Index>0</Index>';
           # we are setting it to 0 - so take the first item in the list to be active
		$response_xml .= '</u:X_GetIndexfromRIDResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
	else
	{
		error("Action: $action is NOT supported");
		return http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain' });
	}

	# RETURN THE RESPONSE

	my $response = undef;
	if (defined($response_xml))
	{
		$response = http_header({
			'statuscode' => 200,
			'log' => 'httpdir',
			'content_length' => length($response_xml),
			'content_type' => 'text/xml; charset=utf8' });
		$response .= $response_xml;
	}
	else
	{
		error("No Response");
		$response = http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain' });
	}

	return $response;

}   # ctrl_content_directory_1()



sub get_xml_params
{
    my ($xml,$what,@fields) = @_;

    my $object;
    my $use_content = 0;
    my $field0 = $fields[0];

    # determine which 'Browse' element was used
    # coherence seems use ns0:Browse, bubbleUp u:Browse,
    # and windows m:Browse with {content}

    if (defined($xml->{'s:Body'}->{"ns0:$what"}->{$field0}))
    {
        $object = $xml->{'s:Body'}->{"ns0:$what"};
    }
    elsif (defined($xml->{'s:Body'}->{"u:$what"}->{$field0}))
    {
        $object = $xml->{'s:Body'}->{"u:$what"};
    }
    elsif (defined($xml->{'SOAP-ENV:Body'}->{"m:$what"}->{$field0}))
    {
        $object = $xml->{'SOAP-ENV:Body'}->{"m:$what"};
        $use_content = 1;
    }
    else
    {
        error("Could not find body element in get_xml_params()");
        return;
    }

    my @rslt;
    for my $field (@fields)
    {
        my $val = $object->{$field};
        $val = $val->{content} if ($use_content);
        display($dbg_http+1,1,"object($field) = $val");
        push @rslt,$val;
    }
    return @rslt;
}


#--------------------------------------------------------
# SEARCH
#--------------------------------------------------------
# Bubbleup sends the following search requests for 'Pat Horton':
# which currently displays Albums:title(4), Albums:artist(4),
# and Tracks:artist(41). All requests but the last are for
# start=0 and count=16
#
# upnp:class = "object.container.person.musicArtist" and dc:title contains "pat horton"
#    upon which I fail (no table)
# upnp:class = "object.container.album.musicAlbum" and upnp:artist contains "pat horton"
#    to which I return four albums
# upnp:class derivedfrom "object.item.audioItem" and dc:title contains "pat horton"
#    to which I return no records
# upnp:class = "object.container.album.musicAlbum" and dc:title contains "pat horton"
#    to which I return four due to my folder naming convention
# upnp:class derivedfrom "object.item.audioItem" and (dc:creator contains "pat horton" or
#   upnp:artist contains "pat horton")
#   to which I find 41 songs and return 16 as requested ***
# upnp:class derivedfrom "object.item.videoItem" and dc:title contains "pat horton"
#    upon which I fail (no table)
#
# upnp:class derivedfrom "object.item.audioItem" and (dc:creator contains "pat horton" or
#    upnp:artist contains "pat horton")))  start=16, count=40
#    *** to which I find 41 songs and return the last 25 as requested


sub search_directory
    # no longer using #filter
{
    my ($xml,$peer_ip_addr) = @_;
    display($dbg_http+1,0,"SEARCH(xml=$xml)");

    # from bubbleUp (empty), not used in my implementation: SortCriteria;
    # from bubbleUp not used in my implementation: 'xmlns:u' => 'urn:schemas-upnp-org:service:ContentDirectory:1',

    my ($criteria, $id, $start, $count) =
        get_xml_params($xml,'Search',qw(
            SearchCriteria
            ContainerID
            StartingIndex
            RequestedCount ));
            #Filter ));

    if (!$criteria)
    {
        error('ERROR: Unable to find SearchCriteria in search_directory()');
        return '';  # return empty result set
    }

    $count ||= 0;
    # $filter = '*' if (!$filter);
    display($dbg_http,0,"SEARCH(id=$id start=$start count=$count");
    # display(1,1,"filter=$filter") if ($filter && $filter ne '*');
    display($dbg_http,1,"criteria=$criteria)");
    $count = 10 if !$count;

    my ($table,$sql_expr);
    if (1)
    {
        ($table,$sql_expr) = create_sql_expr($criteria);
        return '' if (!$table);  # returns no results, not an error
    }
    else    # a debugging expression that should work for testing
    {
        $table = ($criteria =~ /musicAlbum/) ? "folders" : "tracks";
        $sql_expr = ($table eq '') ? "title='Hard Lesson'" : "name='Blue To The Bone'";
    }

    # do the query

    my $response_xml = '';
    my $dbh = db_connect();
    my $recs = get_records_db($dbh,"SELECT * FROM $table ".($sql_expr?"WHERE $sql_expr":''));
    if (!$recs)
    {
        warning(1,1,"search(FROM $table WHERE $sql_expr) returned undef");
    }
    elsif (!@$recs)
    {
        warning(1,1,"search(FROM $table WHERE $sql_expr) returned no records");
    }
    else
    {
        display($dbg_http,1,"search() found ".scalar(@$recs)." records in $table");

        $response_xml .= xml_header(1);
        my $num = 0;
        my $index = 0;
        if ($table eq 'tracks')
        {
			my $folder;
			my $parent_id = 0;
            for my $file (@$recs)
            {
				if ($file->{parent_id} ne $parent_id)
				{
					$parent_id = $file->{parent_id};
					$folder = get_folder($parent_id);
				}
                if ($index >= $start)
                {
                    $response_xml .= xml_item($file,$folder);
                    $num++;
                    last if ($num >= $count);
                }
                $index++;
            }
        }
        else
        {
            for my $dir (@$recs)
            {
                if ($index >= $start)
                {
                    # add_dir_data($dbh,$dir);
                    $response_xml .= xml_directory($dir);
                    $num++;
                    last if ($num >= $count);
                }
                $index++;
            }
        }

        $response_xml .= xml_footer($num,scalar(@$recs),1);

    }   # got some records

    db_disconnect($dbh);
    return $response_xml;

}   # search_directory



sub create_sql_expr
    # Flat parsing of criteria into sql
{
    my ($expr) = @_;

    # unhandled things
    # bubble_up:  upnp:class = "object.container.person.musicArtist"

    if ($expr eq '*')
    {
        error("Wild card expression(*) not supported in search");
        return;
    }

    # get the table
    # upnp:class derivedfrom "object.item.audioItem"

    my $table;
    my $orig_expr = $expr;
    my $class_is = 'upnp:class\s+derivedfrom|upnp:class\s*=';
    if ($expr =~ s/($class_is)\s*"(object\.(item\.audioItem|container\.album\.musicAlbum))"(\s+and)*//i)
    {
        $table = $3 eq 'item.audioItem' ? 'tracks' : 'folders';
    }
    if (!$table)
    {
        error("Could not determine table from expression: $orig_expr");
        return;  # returns no results, not an error
    }

    my $title_field = ($table eq '') ? 'title' : 'name';
    my $artist_field = ($table eq '') ? 'artist' : 'name';
    my $creator_field = ($table eq '') ? 'artist' : 'name';
    $expr =~ s/dc:title/$title_field/g;
    $expr =~ s/upnp:artist/$artist_field/g;
    $expr =~ s/dc:creator/$creator_field/g;

    # change CONTAINS "blah" to LIKE "%blah%")

    if (1)
    {
        while ($expr =~ s/contains\s+("(.*?)")/##HERE##/)
        {
            my $value = $2;
            $expr =~ s/##HERE##/LIKE "%$value%"/;
        }
    }

    # known things that should not be in a sql expression

    if ($expr =~ /object.container|upnp:class|derivedfrom/)
    {
        error("search expression contains unparsed items: $expr");
        $expr = undef;
    }

    display($dbg_http+1,0,"create_sql_expr()=$table,$expr");
    return ($table,$expr);

}


#--------------------------------------------------------
# BROWSE
#--------------------------------------------------------
# Note that we completely ignore filtering
#

sub browse_directory
{
    my ($xml,$peer_ip_addr) = @_;
    my ($id, $start, $count, $flag) =  
        get_xml_params($xml,'Browse',qw(
            ObjectID
            StartingIndex
            RequestedCount
            BrowseFlag));
            # Filter));

    my $error = '';
    my $dbh = db_connect();
	my $folder;

    if (!defined($id))
    {
		$error = "No ID passed to browse_directory";
	}
	
	if (!$error)
	{
		display($dbg_http+1,0,"browse_directory($id)");
		$folder = get_folder($dbh,$id);
		$error = "Could not get_folder($id)"
			if (!$folder);
	}
	
	if (!$error)
	{
		if ($flag eq 'BrowseMetadata')
		{
			# set object_id to parentid
			warning(0,-1,"mis-implemented BROWSE_METADATA($id) called");
			$id = $folder->{parent_id};
			$folder = get_folder($dbh,$id);
			$error = "Could not get_folder($id)"
				if (!$folder);
		}
		elsif ($flag ne 'BrowseDirectChildren')
		{
			$error = "BrowseFlag: $flag is NOT supported";
		}
	}
	
    # build the http response
	
	if (!$error)
	{
		$count ||= 0;
		display($dbg_http,0,"BROWSE($flag,id=$id,start=$start,count=$count)");
		$count = 10 if !$count;
		
		my $is_album = $folder->{dirtype} eq 'album' ? 1 : 0;
		my $table = $is_album ? "tracks" : "folders";
        my $subitems = get_subitems($dbh, $table, $id, $start, $count);
		my $num_items = @$subitems;
		
		display($dbg_http+1,0,"building http response for $num_items $table"."s");

		my $response_xml = xml_header();
        for my $item (@$subitems)
        {
            $response_xml .= $item->getDidl();
        }

        $response_xml .= xml_footer($num_items,$folder->{num_elements});
        display($dbg_http+1,1,"Done with numeric($id) dirlist response");
	    db_disconnect($dbh);
		return $response_xml;
    }

	# error exit
	
	error($error);
	db_disconnect($dbh);
	return http_header({
		'statuscode' => 501,
		'content_type' => 'text/plain' });
}




sub logo
{
    display($dbg_http+2,1,"logo()");
    my $response = http_header({
        'statuscode' => 200,
        'additional_header' => [ 'Content-Type: image/png' ] });
	$response .= getTextFile('artisan.png',1);
    $response .= "\r\n";
	return $response;

}   # logo()




sub get_art
{
	my ($id) = @_;
    display($dbg_http+1,0,"get_art($id)");

	my $dbh = db_connect();
	my $folder = get_folder($dbh,$id);
	db_disconnect($dbh);
	if (!$folder)
	{
		error("get_art($id): could not get folder($id)");
		return http_header({
			'statuscode' => 400,
			'content_type' => 'text/plain' });
	}


    # open the file and send it to the client

	my $filename = "$mp3_dir/$folder->{path}/folder.jpg";
    if (!(-f $filename))
    {
        error("get_art($id): file not found: $filename");
		$filename = "$artisan_perl_dir/images/no_image.jpg";
    }

    display($dbg_http+1,1,"get_art($id) opening file: $filename");
    if (!open(IFILE,"<$filename"))
    {
        error("get_art($id): Could not open file: $filename");
        return http_header({
            'statuscode' => 400,
            'content_type' => 'text/plain' });
    }

    binmode IFILE;
    my $data = join('',<IFILE>);
    close IFILE;

    display($dbg_http+1,1,"get_art($id): sending file: $filename");
    my $response = http_header({
        'statuscode' => 200,
        'additional_header' => [ 'Content-Type: image/jpeg' ] });
    $response .= $data;
    $response .= "\r\n";
    return $response;

}   # get_art()






sub xml_serverdescription
	# server description for the DLNA Server
{
    display(_clip $dbg_xml+1,3,"xml_serverdescription()");

	my $xml = <<EOXML;
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
    <specVersion>
        <major>1</major>
        <minor>5</minor>
    </specVersion>
    <device>
        <deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>
        <presentationURL>http://$server_ip:$server_port/webui/</presentationURL>
        <friendlyName>$program_name</friendlyName>
        <manufacturer>Patrick Horton</manufacturer>
        <manufacturerURL>http://www.phorton.com</manufacturerURL>
        <modelDescription>a simple media server</modelDescription>
        <modelName>$program_name</modelName>
        <modelNumber>1234</modelNumber>
        <modelURL>http://www.phorton.com</modelURL>
        <serialNumber>5679</serialNumber>');
        <UDN>$uuid</UDN>
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

	return $xml;
}







sub xml_header
{
    my ($what) = @_;   # 0=Browse, 1=Search
    my $response_type = ($what ? 'Search' : 'Browse').'Response';
	my $xml = <<EOXML;
<s:Envelope
    xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
    s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:$response_type xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
        <Result>
EOXML
    $xml .= encode_didl(<<EOXML);
<DIDL-Lite
    xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
    xmlns:sec="http://www.sec.co.kr/dlna"
    xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" >
EOXML
	return $xml;
}





sub xml_footer
{
	my ($num_search,
        $num_total,
        $what) = @_;

    # $system_update_id++;
	# for testing responsiveness
	
    my $response_type = ($what ? 'Search' : 'Browse').'Response';
    my $xml .= encode_didl("</DIDL-Lite>");
	
	$xml .= <<EOXML;
        </Result>
        <NumberReturned>$num_search</NumberReturned>
        <TotalMatches>$num_total</TotalMatches>
        <UpdateID>$system_update_id</UpdateID>
        </u:$response_type>
    </s:Body>
</s:Envelope>
EOXML
    return $xml;
}





1;
