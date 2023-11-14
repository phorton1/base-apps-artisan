#!/usr/bin/perl
#---------------------------------------
# ContentDirectory1.pm
#---------------------------------------
# handle requests to /upnp/control/ContentDirectory1,
# which is Artisan BEING a DLNA MediaServer

package HTTPServer;
use strict;
use warnings;
use threads;
use threads::shared;
use Fcntl;
use Socket;
use IO::Select;
use XML::Simple;
use artisanUtils;
use Database;
use DeviceManager;
use HTTPStream;
use WebUI;



my $dbg_http = 0;
	#  0 == lifecycle
my $dbg_post = 0;
	#  0 == show POST data
my $dbg_art = 0;
	# 0 == debug get_art() method
my $dbg_server_desc = 0;
	# 0 = show the xml to be returned for ServerDesc.xml


# use with care - debugging that cannot be filtered by call

my $dbg_connect = 0;
	#  0 == show individual connections
	# -1 == show pending connnections (in case more than one at a time)
my $dbg_hdr = 0;
	#  0 == show actual request header lines


# debugging that is filtered for renderer/xxx/update calls

my $dbg_request = 0;
	#  0 == show a header for every non renderer/xxx/update call
	# -1 == show request headers for same
	# -2 == show header for renderer/xxx/update calls, headers for all otherw
	# -3 == show headers for everything
my $dbg_response = 0;
	# same as for dbg_request

# DLNA/XML debugging

my $DEBUG_SEARCH = 0;
    # Set this to one to see the full request and
    # response xml for Search requests at debug
    # level 1 or greater
my $DEBUG_BROWSE = 1;
    # Set this to one to see the full request and
    # response xml for Browse requests at debug
    # level 1 or greater


# !!! THE THREADED APPROACH  NOT WORKING ON ARTISAN_WIN !!!
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

my $cache_timeout = 1800;


my $system_update_id = time();
# share($system_update_id);



#-----------------------------------------------------------------
# utilities
#-----------------------------------------------------------------

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



#=========================================================================
# handle_request()
#=========================================================================
# This is where Artisan Perl IS a DLNA MediaServer

sub handle_request
{
	# ContentDirectory1::handle_request($post_data, $request_headers{SOAPACTION}, $peer_ip, $peer_port);
	my ($xml,$action,$peer_ip_addr) = @_;
	my $response_xml = undef;
    display($dbg_http+1,0,"localContentDirectory1(xml=$xml,action=$action)");

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
		return http_header({ status_code => 501 });
	}

	# RETURN THE RESPONSE

	my $response = undef;
	if (defined($response_xml))
	{
		$response = http_header({ content_type => 'text/xml; charset=utf8' });
		$response .= $response_xml;
	}
	else
	{
		error("No Response");
		$response = http_header({ status_code => 501 });
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
					$folder = $local_library->getFolder($parent_id,$dbh);
						# re-use database connection
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
	my $folder;

	# $id ||= 'c5b5b8ca14b0c5f07a110fb727d3baa0';
	# while expermenting with DLNA browser - set root to blues album

    if (!defined($id))
    {
		$error = "No ID passed to browse_directory";
	}

	if (!$error)
	{
		display($dbg_http+1,0,"browse_directory($id)");
		$folder = $local_library->getFolder($id);
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
			$folder = $local_library->getFolder($id);
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
        my $subitems = $local_library->getSubitems($table, $id, $start, $count);
		my $num_items = @$subitems;

		display($dbg_http+1,0,"building http response for $num_items $table"."s");

		my $response_xml = xml_header();
        for my $item (@$subitems)
        {
            $response_xml .= $item->getDidl();
        }

        $response_xml .= xml_footer($num_items,$folder->{num_elements});
        display($dbg_http+1,1,"Done with numeric($id) dirlist response");
		return $response_xml;
    }

	# error exit

	error($error);
	return http_header({ status_code => 501 });
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


# SUBSCRIBE request from WMP
#
#	SUBSCRIBE /upnp/event/ContentDirectory1 HTTP/1.1
#	Cache-Control: no-cache
#	Connection: Close
#	Pragma: no-cache
#	User-Agent: Microsoft-Windows/10.0 UPnP/1.0
#	NT: upnp:event
#	Callback: <http://10.237.50.101:2869/upnp/eventing/esingnommv>
#	Timeout: Second-1800
#	Host: 10.237.50.101:8091




1;
