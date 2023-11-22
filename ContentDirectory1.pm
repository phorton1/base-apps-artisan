#!/usr/bin/perl
#---------------------------------------
# ContentDirectory1.pm
#---------------------------------------
# handle requests to /upnp/control/ContentDirectory1,
# which is Artisan BEING a DLNA MediaServer
# WMP cache is at C:\Users\Patrick\AppData\Local\Microsoft\Media Player

package ContentDirectory1;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use httpUtils;
use Track;
use Folder;
use Database;
use DeviceManager;

my $PARSE_RESULTS = 0;
	# will parse results for correctness check, dumping, etc

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


my $system_update_id:shared = time();

sub getDumpDir
{
	my $dump_dir = "$temp_dir/_cd1";
	mkdir $dump_dir if !-d $dump_dir;
	return $dump_dir;
}


#=========================================================================
# handle_request()
#=========================================================================
# This is where Artisan Perl IS a DLNA MediaServer

sub handle_request
{
	my ($method, $headers, $post_data, $peer_ip,$peer_port) = @_;

	return http_error("unsupported method($method) in ContentDirectory1")
		if $method ne 'POST';

	my $action = $headers->{SOAPACTION};

	$action =~ s/"//g;
	return error("action not upnp: $action")
		if $action !~ s/^urn:schemas-upnp-org:service://;
	return error("action not ContentDirectory1: $action")
		if $action !~ s/^ContentDirectory:1#//;

	display($dbg_input,0,"ContentDirectory1.handle_request($action) from $peer_ip:$peer_port");

	my $xml = parseXML($post_data,{
		dbg => $dbg_input,
		dbg_name => "$action.request",
		dump_dir => getDumpDir(),		# comment out for no dumps
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
	# For some reason WMP asks for SortCapabilities over and over

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
	# elsif ($action eq 'GetSystemUpdateID')
	# {
    #     warning(0,-1,"Thats the first time I've seen someone call action = GetSystemUpdateID($system_update_id)");
	# 	$content = soap_header();
	# 	$content .= '<u:GetSystemUpdateIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
	# 	$content .= "<Id>$system_update_id</Id>";
	# 	$content .= '</u:GetSystemUpdateIDResponse>';
	# 	$content .= soap_footer();
	# }
	# elsif ($action eq 'X_GetIndexfromRID')
	# {
	# 	warning(0,-1,"Thats the first time I've seen someone call action = X_GetIndexfromRID()");
	# 	$content = soap_header();
	# 	$content .= '<u:X_GetIndexfromRIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
	# 	$content .= '<Index>0</Index>';
    #        # we are setting it to 0 - so take the first item in the list to be active
	# 	$content .= '</u:X_GetIndexfromRIDResponse>';
	# 	$content .= soap_footer();
	# }
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
			dbg => $dbg_input,
			dbg_name => "$action.response",
			dump_dir => getDumpDir(),		# comment out for no dumps
			decode_didl => 0,
			raw => 0,
			pretty => 1,
			my_dump => 0,
			dumper => 1 }) if $PARSE_RESULTS;
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
        display($dbg_params,1,"object($field) = '$val'");
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
#
# from bubbleUp (empty), not used in my implementation: SortCriteria;
# from bubbleUp not used in my implementation: 'xmlns:u' => 'urn:schemas-upnp-org:service:ContentDirectory:1',

sub search_directory
    # no longer using #filter
{
    my ($xml,$peer_ip_addr) = @_;
    display($dbg_search,0,"SEARCH()",0,$Pub::Utils::win_color_light_magenta);

	# upnp:class derivedfrom "object.item.audioItem" and @refID exists false
	# upnp:class derivedfrom "object.container.playlistContainer" and @refID exists false

    my ($criteria, $id, $start, $count, $filter) =
        get_xml_params($xml,'Search',qw(
            SearchCriteria
            ContainerID
            StartingIndex
            RequestedCount
            Filter ));
    if (!$criteria)
    {
        error('ERROR: Unable to find SearchCriteria in search_directory()');
        return '';  # return empty result set
    }

	$start ||= 0;
    $count ||= 0;
    display($dbg_search+1,1,"id=$id start=$start count=$count filter=$filter");
    display($dbg_search+1,1,"criteria=$criteria");
    $count ||= 10;

	# We take a braindead approach that works with WMP.
	# They either search for playlistContainers or audioItems
	# in which case we return the virtualPlaylistFolder,
	# or Tracks.

	my $ref_id = $criteria =~ s/and \@refID exists false// ? 0 : 1;
	my $what = $criteria =~ /^upnp:class derivedfrom "object\.(item|container)\.(.*)"/i ? $2 : 'unknown';
    display($dbg_search+1,1,"WHAT=$what");

	my $num = 0;
	my $total = 0;
	my $didl = didl_header();
	if ($what eq 'playlistContainer')
	{
		my $playlists = $local_library->getPlaylists('default');
		$total = @$playlists;
		display($dbg_search+1,2,"found $total playlists");

		my $max = $start+$count-1;
		$max = @$playlists-1 if $max > @$playlists-1;
		for my $i ($start .. $max)
		{
			my $playlist = $playlists->[$i];
			my $folder = $local_library->virtualPlaylistFolder($playlist);
			if ($folder)
			{
				$num++;
				$didl .= $folder->getDidl()."\r\n";
			}
		}
	}
	elsif ($what eq 'audioItem')
	{

		my $dbh = db_connect();
		my $recs = get_records_db($dbh,"SELECT * FROM tracks ORDER BY path");
		$total = @$recs;
		display($dbg_search+1,2,"found $total tracks");

		my $max = $start+$count-1;
		$max = @$recs-1 if $max > @$recs-1;
		for my $i ($start .. $max)
		{
			my $rec = $recs->[$i];
			my $track = Track->newFromHash($rec);
			if ($track)
			{
				$num++;
				$didl .= $track->getDidl()."\r\n";
			}
		}
		db_disconnect($dbh);
	}
	else
	{
		error("!!!! UNSUPPORTED SEARCH CRITERIA($criteria) !!!!!!");
	}

	$didl .= didl_footer();

    display($dbg_search,1,"didl returning $num items");

	my $content =
		soap_header().
		browse_header('SearchResponse').
		encode_didl($didl).
		browse_footer('SearchResponse',$num,$total).
		soap_footer();


	my $dbg_name = "SEARCH.$what.$id.$start.$count";

	parseXML($didl,{
		dbg => $dbg_search,
		dbg_name => "$dbg_name.didl",
		dump_dir => getDumpDir(),		# comment out to not dump
		decode_didl => 1,
		raw => 1,
		pretty => 1,
		my_dump => 1,
		dumper => 1 }) if $PARSE_RESULTS;

	parseXML($content,{
		dbg => $dbg_search,
		dbg_name => $dbg_name,
		dump_dir => getDumpDir(),		# comment out to not dump
		decode_didl => 0,
		raw => 1,
		pretty => 1,
		my_dump => 1,
		dumper => 1 }) if $PARSE_RESULTS;

    return $content;

}   # search_directory



sub currently_unused_create_sql_expr
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

	# lets try this, anything that mentions a container is a folder,
	# and anything that mentions an item is a track quey

	# my $class_is = 'upnp:class\s+derivedfrom|upnp:class\s*=';
    # if ($expr =~ s/($class_is)\s*"(object\.(item\.audioItem|container\.album\.musicAlbum))"(\s+and)*//i)
    # {
    #     $table = $3 eq 'item.audioItem' ? 'tracks' : 'folders';
    # }

	# $expr =~ s/and \@refID exists false//;
	$table = $expr =~ /container/ ? 'folders' : 'tracks';
	$expr = '';

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
	display($dbg_browse,0,"BROWSE()",0,$Pub::Utils::win_color_light_cyan);

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
		display($dbg_browse+1,1,"browse folder($id)");
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
		display($dbg_browse+1,1,"$flag(id=$id,start=$start,count=$count)");
		$count = 10 if !$count;

		my $table = $folder->{dirtype} =~ /^(album|playlist)/ ?
			"tracks" : "folders";
        my $subitems = $local_library->getSubitems($table, $id, $start, $count);
		my $num_items = @$subitems;

		display($dbg_browse+1,1,"building response for $num_items $table"."s");

		my $didl = didl_header();
        for my $item (@$subitems)
        {
            $didl .= $item->getDidl()."\r\n";
        }
		$didl .= didl_footer();

		display($dbg_browse,1,"didl returning ".scalar(@$subitems)." items");

		my $content =
			soap_header().
			browse_header('BrowseResponse').
			encode_didl($didl).
			browse_footer('BrowseResponse',$num_items,$folder->{num_elements}).
			soap_footer();

		my $dbg_name = "BROWSE.$id.$start.$count";

		parseXML($didl,{
			dbg => $dbg_browse,
			dbg_name => "$dbg_name.didl",
			dump_dir => getDumpDir(),
			decode_didl => 1,
			raw => 1,
			pretty => 1,
			my_dump => 1,
			dumper => 1 }) if 1; # $PARSE_RESULTS;

		parseXML($content,{
			dbg => $dbg_browse,
			dbg_name => $dbg_name,
			dump_dir => getDumpDir(),
			decode_didl => 0,
			raw => 1,
			pretty => 1,
			my_dump => 1,
			dumper => 1 }) if $PARSE_RESULTS;

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



#--------------------------------------------------------------------
# SUBSCRIBE & UNSUBSCRIBE
#--------------------------------------------------------------------
# SUBSCRIBE request from WMP at peer_ip, peer_port
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
#
# Will be called with SID and no CALLBACK to renew
#
# send the subscription response
# 	HTTP/1.1 200 OK
# 	DATE: when response was generated
# 	SERVER: OS/version UPnP/1.1 product/version
# 	SID: uuid:subscription-UUID
# 	CONTENT-LENGTH: 0
# 	TIMEOUT: Second-actual subscription duration


my $dbg_sub = 0;

my $next_subscriber:shared = 0;
my $subscribers:shared = shared_clone({});

sub handleSubscribe
{
	my ($method,$headers,$peer_ip,$peer_port) = @_;

	my $sid = $headers->{SID} || '';
	$sid =~ s/^uuid://;
	my $exists = $subscribers->{$sid} || '';

	if ($method eq 'SUBSCRIBE')
	{
		my $nt = $headers->{NT} || '';
		my $callback = $headers->{CALLBACK} || '';
		my $timeout = $headers->{TIMEOUT} || '';

		$callback =~ s/^<|>$//g;

		display($dbg_sub,1,"SUBSCRIBE($nt) from $peer_ip:$peer_port");
		display($dbg_sub,2,"timeout($timeout) exists(".($exists?1:0).") callback='$callback'");;

		return http_error("no callback or valid sid in SUBSCRIBE")
			if !$callback && !$exists;
		return http_error("unrecognized timeout($timeout) in SUBSCRIBE")
			if $timeout !~ s/^Second-//;
		return http_error("illegal timeout($timeout) in SUBSCRIBE")
			if !$timeout || $timeout !~ /^\d+$/;

		if (!$exists)
		{
			$sid = $this_uuid."-".sprintf("%06d",$next_subscriber++);
			my $subscriber = shared_clone({
				sid => $sid,
				callback => $callback,
				timeout => $timeout });
			$subscribers->{$sid} = $subscriber;
		}
		else
		{
			$exists->{timeout} = $timeout;
		}

		return http_header({
			addl_headers => [
				"SID: uuid:$sid",
				"TIMEOUT: $timeout", ]});
	}
	else	# method eq UNUSUBSCRIBE
	{
		display($dbg_sub,1,"UNSUBSCRIBE sid($sid) from $peer_ip:$peer_port");
		return error("could not find sid($sid) in UNSUBSCRIBE")
			if !$exists;
		delete $subscribers->{$sid};
		return http_header();
	}
}







1;
