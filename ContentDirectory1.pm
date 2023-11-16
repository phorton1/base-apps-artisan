#!/usr/bin/perl
#---------------------------------------
# ContentDirectory1.pm
#---------------------------------------
# handle requests to /upnp/control/ContentDirectory1,
# which is Artisan BEING a DLNA MediaServer

package ContentDirectory1;
use strict;
use warnings;
use threads;
use threads::shared;
use XML::Simple;
use artisanUtils;
use httpUtils;
use Database;
use DeviceManager;


my $dbg_input = 0;
	#  0 == show header for handle_request
	# -1 == show pretty and parsed request XML
my $dbg_params = 0;
	#  0 == show params
my $dbg_browse = 0;
	#  0 == show main stuff
	# -1 == parse didl, show headeer
	# -2 == show pretty and parsed didl
my $dbg_search = 0;
my $dbg_sql = 0;
my $dbg_output = 0;
	#  0 == show header for response
	# -1 == show pretty and parsed response XML

my $cache_timeout = 1800;


my $system_update_id:shared = 0; # time();



#=========================================================================
# handle_request()
#=========================================================================
# This is where Artisan Perl IS a DLNA MediaServer

sub handle_request
{
	my ($post_data,$action,$peer_ip,$peer_port) = @_;

	$action =~ s/"//g;
	return error("action not upnp: $action")
		if $action !~ s/^urn:schemas-upnp-org:service://;
	return error("action not ContentDirectory1: $action")
		if $action !~ s/^ContentDirectory:1#//;

	display($dbg_input,0,"ContentDirectory1.handle_request($action) from $peer_ip:$peer_port");

	my $xml = parseXML($post_data,{
		what => "CD1Request.$action",
		show_hdr => $dbg_input <= 0,
		show_dump => $dbg_input < 0,
		addl_level => 0,
		dump => 0,
		decode_didl => 0,
		raw => 0,
		pretty => 1,
		my_dump => 0,
		dumper => 1 });


	my $content = undef;

    # browser, search, bookmark

	if ($action eq 'Browse')
	{
        $content = browse_directory($xml);
    }
    elsif ($action eq 'Search')
    {
        $content = search_directory($xml);
    }

    # capability responses

	elsif ($action eq 'GetSearchCapabilities')
	{
		$content = soap_header();
		$content .= '<u:GetSearchCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$content .= '<SearchCaps>*</SearchCaps>';
		$content .= '</u:GetSearchCapabilitiesResponse>';
		$content .= soap_footer();
	}
	elsif ($action eq 'GetSortCapabilities')
	{
		$content = soap_header();
		$content .= '<u:GetSortCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$content .= '<SortCaps></SortCaps>';
		$content .= '</u:GetSortCapabilitiesResponse>';
		$content .= soap_footer();
	}
	elsif ($action eq 'GetSystemUpdateID')
	{
        warning(0,-1,"Thats the first time I've seen someone call action = GetSystemUpdateID($system_update_id)");
		$content = soap_header();
		$content .= '<u:GetSystemUpdateIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$content .= "<Id>$system_update_id</Id>";
		$content .= '</u:GetSystemUpdateIDResponse>';
		$content .= soap_footer();
	}
	elsif ($action eq 'X_GetIndexfromRID')
	{
		$content = soap_header();
		$content .= '<u:X_GetIndexfromRIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$content .= '<Index>0</Index>';
           # we are setting it to 0 - so take the first item in the list to be active
		$content .= '</u:X_GetIndexfromRIDResponse>';
		$content .= soap_footer();
	}
	else
	{
		error("ContentDirectory1: $action not supported");
		return http_header({ status_code => 501 });
	}

	# RETURN THE RESPONSE

	my $response = undef;
	if (defined($content))
	{
		display($dbg_output,1,"returning ".length($content)." bytes xml content");
		$response = http_header({ content_type => 'text/xml; charset=utf8' });
		$response .= $content;

		parseXML($content,{
			what => "CD1Request($action).response",
			show_hdr  => $dbg_output <= 0,
			show_dump => $dbg_output < 0,
			addl_level => 1,
			dump => 0,
			decode_didl => 0,
			raw => 0,
			pretty => 1,
			my_dump => 0,
			dumper => 1 });

	}
	else
	{
		error("No Response");
		$response = http_header({ status_code => 501 });
	}

	return $response;

}   # ContentDirectory1::handle_request()



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
        display($dbg_params,1,"object($field) = $val");
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
    display($dbg_search,0,"SEARCH()");

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
    display($dbg_search,1,"SEARCH(id=$id start=$start count=$count");
    # display(1,1,"filter=$filter") if ($filter && $filter ne '*');
    display($dbg_search,1,"criteria=$criteria)");
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

    my $num = 0;
	my $didl = didl_header();
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
        display($dbg_search,1,"search() found ".scalar(@$recs)." records in $table");


        my $index = 0;
        if ($table eq 'tracks')
        {
			my $folder;
			my $parent_id = 0;
            for my $track (@$recs)
            {
				if ($track->{parent_id} ne $parent_id)
				{
					$parent_id = $track->{parent_id};
					$folder = $local_library->getFolder($parent_id,$dbh);
						# re-use database connection
				}
                if ($index >= $start)
                {
                    $didl .= track_search_didl($track,$folder);
                    $num++;
                    last if ($num >= $count);
                }
                $index++;
            }
        }
        else
        {
            for my $folder (@$recs)
            {
                if ($index >= $start)
                {
                    # add_dir_data($dbh,$dir);
                    $didl .= folder_search_didl($folder);
                    $num++;
                    last if ($num >= $count);
                }
                $index++;
            }
        }

    }   # got some records
	$didl .= didl_footer();
    db_disconnect($dbh);

	my $response =
		soap_header().
		browse_header('SearchResponse').
		encode_didl($didl).
		browse_footer('SearchResponse',$num,@$recs);
		soap_footer();
    return $response;

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

    display($dbg_sql,0,"create_sql_expr()=$table,$expr");
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
	display($dbg_browse,0,"BROWSE()");

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
		display($dbg_browse,1,"browse folder($id)");
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
		display($dbg_browse,1,"$flag(id=$id,start=$start,count=$count)");
		$count = 10 if !$count;

		my $is_album = $folder->{dirtype} eq 'album' ? 1 : 0;
		my $table = $is_album ? "tracks" : "folders";
        my $subitems = $local_library->getSubitems($table, $id, $start, $count);
		my $num_items = @$subitems;

		display($dbg_browse,1,"building response for $num_items $table"."s");

		my $didl = didl_header();
        for my $item (@$subitems)
        {
            $didl .= $item->getDidl()."\r\n";
        }
		$didl .= didl_footer();

		my $content =
			soap_header().
			browse_header('BrowseResponse').
			encode_didl($didl).
			browse_footer('BrowseResponse',$num_items,$folder->{num_elements}).
			soap_footer();

		parseXML($didl,{
			what => "$flag($id).didl",
			show_hdr  => $dbg_browse <= 0,
			show_dump => $dbg_browse < 0,
			addl_level => 1,
			dump => 1,
			decode_didl => 1,
			raw => 1,
			pretty => 1,
			my_dump => 1,
			dumper => 1 });

		parseXML($content,{
			what => "$flag($id).content",
			show_hdr  => $dbg_browse <= 0,
			show_dump => $dbg_browse < 0,
			addl_level => 1,
			dump => 1,
			decode_didl => 0,
			raw => 1,
			pretty => 1,
			my_dump => 1,
			dumper => 1 });

		return $content;
    }

	# error exit

	error($error);
	return http_header({ status_code => 501 });
}



sub browse_header
{
	my ($response_type) = @_;
	my $text = '';
	$text .= '<m:'.$response_type.' xmlns:m="urn:schemas-upnp-org:service:ContentDirectory:1">';
	$text .= '<Result xmlns:dt="urn:schemas-microsoft-com:datatypes" dt:dt="string">';
	return $text;
}



sub browse_footer
{
	my ($response_type,
		$num_search,
        $num_total) = @_;
    # $system_update_id++;
	# for testing responsiveness
	my $text = '</Result>';
	$text .= '<NumberReturned xmlns:dt="urn:schemas-microsoft-com:datatypes" dt:dt="ui4">';
	$text .= $num_search;
	$text .= '</NumberReturned>';
    $text .= '<TotalMatches xmlns:dt="urn:schemas-microsoft-com:datatypes" dt:dt="ui4">';
	$text .= $num_total;
	$text .= '</TotalMatches>';
    $text .= '<UpdateID xmlns:dt="urn:schemas-microsoft-com:datatypes" dt:dt="ui4">';
	$text .= $system_update_id;
	$text .= '</UpdateID>';
	$text .= '</m:'.$response_type.'>';
	return $text;
}


sub soap_header
{
	my $text = '<?xml version="1.0"?>'."\r\n";
	$text .= '<SOAP-ENV:Envelope ';
	$text .= 'xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" ';
	$text .= 'SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"';
	$text .= '>';
	$text .= '<SOAP-ENV:Body>';
	return $text;
}

sub soap_footer
{
	my $text = '';
	$text .= "</SOAP-ENV:Body>";
	$text .= '</SOAP-ENV:Envelope>'."\r\n";
    return $text;
}


sub didl_header
{
	my $text = '<DIDL-Lite ';
    $text .= 'xmlns:dc="http://purl.org/dc/elements/1.1/"'."\r\n";
    $text .= 'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"'."\r\n";;
	$text .= 'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"'."\r\n";;
	$text .= 'xmlns:microsoft="urn:schemas-microsoft-com:WMPNSS-1-0/"'."\r\n";;
  # $text .= 'xmlns:sec="http://www.sec.co.kr/dlna" ';
    $text .= 'xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/"'."\r\n";;
	$text .= '>';
	return $text;
}

sub didl_footer
{
	return '</DIDL-Lite>';
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
