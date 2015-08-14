#!/usr/bin/perl
#---------------------------------------
# uiExplorer.pm
#
# The dispatch handler for /webui/explorer requests.


sub get_highest_error
{
    my ($this) = @_;
    my $level = $ERROR_NONE;
    if ($this->{errors})
    {
        for my $e (@{$this->{errors}})
        {
            $level = $$e[0] if $$e[0] > $level;
        }
    }
    return $level;
}


sub has_error
{
    my ($this,$level) = @_;
    my $got = $this->get_highest_error();
    return 1 if ($got >= $level);
    return 0;
}
    



package uiExplorer;
use strict;
use warnings;
use Utils;
use Database;
use MediaFile;
use Library;
use Station;
use uiUtils;


# settings for explorer mode

my $SHOW_TRACK_HIGH = 0;
my $SHOW_FOLDER_HIGH = 1;
my $SHOW_BOTH_HIGH = 2;

# default for explorer mode if no mode passed in request

my $SHOW_HIGH = $SHOW_BOTH_HIGH;



sub explorer_request
	# station being defined is special
{
	my ($path,$params) = @_;
	display($dbg_webui,0,"explorer_request($path)");
	
	# handle request
	
	if ($path eq 'dir')
	{
		return explorer_dir($params);
	}
	elsif ($path eq 'items')
	{
		return explorer_items($params);
	}
	elsif ($path eq 'item_tags')
	{
		return explorer_item_tags($params);
	}
	elsif ($path eq 'get_station_items')
	{
		return get_station_items($params);
	}
	elsif ($path eq 'get_track')
	{
		my $dbh = db_connect();
		my $rec = get_record_db($dbh,'SELECT * FROM TRACKS WHERE ID=?',[$params->{id}]);
		db_disconnect($dbh);
		if (!$rec)
		{
			return json_error("could not get_track($params->{id})");
		}
		return json_header().json($rec);
	}
	elsif ($path eq 'get_id_path')
	{
		my @parts;
		push @parts,'track_'.$params->{track_id};
		my $dbh = db_connect();
		my $rec = get_record_db($dbh,'SELECT * FROM TRACKS WHERE ID=?',[$params->{track_id}]);
		while ($rec && $rec->{PARENT_ID} > 1)
		{
			my $parent_id = $rec->{PARENT_ID};	
			push @parts,$parent_id;
			$rec = get_record_db($dbh,'SELECT * FROM FOLDERS WHERE ID=?',[$parent_id]);
		}			
		db_disconnect($dbh);
		return json_header().json({id_path=>join('/',reverse @parts)});
	}
	else
	{
		return json_error("unknown uiExplorer command: $path");
	}
}



#-----------------------------------------------
# directory requests
#-----------------------------------------------

sub set_in_station
	# Set rec->{selected} = 1 if the folder/track is in the station.
	# For folders, we also see if it's 'partsel' and pass that
	# via extraClasses. Note that fancy tree accepts any value as true
	# including "0" and "false"
{
	my ($dbh,$rec,$station_num) = @_;

	if ($station_num)
	{
		my $station = getStation($station_num);
		my $bit = $station->station_bit();
		
		if ($rec->{STATIONS} & $bit)
		{
			$rec->{selected} = 1 
		}
		
		# defined(FULLPATH) is synonymous with FOLDERS records
		# we assume that parents with all children set are
		# themselves set, so, otherwise if any children are
		# set, it's a partsel.  This is moderately expensive
		# and it is tempting to cache the partsel state as
		# another bitwise member on the FOLDER record
		
		elsif (defined($rec->{FULLPATH}))
		{
			display(9,0,"checking partsel for $rec->{FULLPATH}");
			my $recs = get_records_db($dbh,
	           "SELECT ID FROM TRACKS WHERE ".
				"STATIONS & $bit AND ".
				"instr(FULLNAME,?) > 0",
				[$rec->{FULLPATH}."/"]);
			if ($recs && @$recs)
			{
				$rec->{extraClasses} = 'fancytree-partsel';
			}
		}
	}	
}



sub explorer_dir
	# Return the json for the list of children of the directory
	# given by params->{id}.  If $params->{station} is defined,
	# it means we are called from the station list (not explorer)
	# and the tree will include child TRACKS as leaf nodes.
	# Otherwise, albums are leaf nodes (in explorer) 
	
{
	my ($params) = @_;
	my $id = $params->{id} || 0;
	my $station = $params->{station};
	display($dbg_webui,0,"explorer_dir($id,"._def($station).")");

	# sublimate id(0) to id(1)
	
	my $use_id = $id ? $id : 1;
	my $dbh = db_connect();

	# collect the child folders, or for
	# albums in station mode, the child tracks
	
	my $results;
	my $do_stations = 0;
	my $parent = get_record_db($dbh,"SELECT DIRTYPE FROM FOLDERS WHERE ID='$use_id'");
	if ($parent->{DIRTYPE} eq 'album' && defined($station))
	{
		$do_stations = 1;
		$results = get_subitems($dbh, 'TRACKS', $use_id, 0, 99999);
	}
	else
	{
		$results = get_subitems($dbh, 'FOLDERS', $use_id, 0, 99999);
	}
	
	my $started = 0;
	my $response = json_header();
	$response .= '[';
	for my $rec (@$results)
	{
		next if (!$rec->{ID});
		$response .= ',' if ($started);
		$started = 1;
		
		# inline code to do a track in the station list
		
		if ($do_stations)
		{
			$rec->{key} = "track_" . $rec->{ID};	# required
			$rec->{title} = $rec->{TITLE};
			$rec->{icon} = "/webui/icons/icon_track.png";

			set_in_station($dbh,$rec,$station);
			$response .= json($rec);
		}
		
		# 'normal' code to do a sub-folder
		
		else
		{
			$response .= explorer_dir_element($dbh,$params,$rec,$station);
		}
	}
	$response .= ']';
	
	display($dbg_webui+1,0,"dir response=$response");
	db_disconnect($dbh);
	return $response;
}



		
sub explorer_dir_element
	# return the json for one subfolder element.
	# Return lazy=1 and folder=1 for parents to be load-on-expand
	# if defined(station) and the folder is an album, it is also
	# load-on-expand.
{
	my ($dbh,$params,$rec,$station) = @_;
	
	$rec->{key} = $rec->{ID};	# required
	my $title = $rec->{TITLE};

	if ($rec->{DIRTYPE} ne 'album')
	{
		$rec->{folder} = '1';
		$rec->{lazy} = '1';
	}
	elsif (defined($station))
	{
		$rec->{folder} = '1';
		$rec->{lazy} = '1';
	}
		
	if ($rec->{DIRTYPE} eq 'album' &&
		$rec->{CLASS} !~ /dead/i)
	{
		$title = "$rec->{ARTIST} - $title"
			if $rec->{ARTIST};
		$title =~ s/_/-/g;	# fix my use of underscores for dashes
	}
	
	$rec->{title} = $title;	# required
	$rec->{ART_URI} = "http://$server_ip:$server_port/get_art/$rec->{ID}/folder.jpg";			

	# for station tree, show a folder or nothiing for albums	
	# where 0 == false == no icon
	
	if (defined($station))
	{
		my $icon_type = $rec->{DIRTYPE} eq 'album' ? 'album' : 'folder';
		$rec->{icon} = "/webui/icons/icon_$icon_type.png";
	}
	else
	{
		# assign different icon based on highest error state
		
		my $mode = defined($params->{mode}) ? $params->{mode} : $SHOW_HIGH;

		my $use_high =
			$mode == $SHOW_TRACK_HIGH ? $$rec{HIGHEST_ERROR} :
			$mode == $SHOW_FOLDER_HIGH ? $$rec{HIGHEST_FOLDER_ERROR} :
			$$rec{HIGHEST_ERROR} > $$rec{HIGHEST_FOLDER_ERROR} ?
			$$rec{HIGHEST_ERROR} : $$rec{HIGHEST_FOLDER_ERROR};
	
		$rec->{icon} = "/webui/icons/error_$use_high.png";
	}
	
	set_in_station($dbh,$rec,$station) if defined($station);
	
	Library::validate_folder(undef,$rec);
	return "\n".json($rec);
}



#-----------------------------------------------
# item (track) info request
#-----------------------------------------------
# prh - another day
#
# Kludge:  I had to introduce a td just to hold the title
# because in the car_stereo, for the life of me, I just
# could not get the fancytree-fucking-tree-title style to
# show the track_number (in the track_list) or the detail
# title correclty.  With every combination of vertical-align:middle
# that one span would always show at the top of the td.
#
# So there these methods deliver the fancytree 0th td
# 'title' as "", and defer the title to the 1st td,
# and there are extra styles in explorer.css and handling
# in explorer.js that work around this glitch.


sub explorer_items
	# Return the json for a list of of files (tracks)
	# associated with a directory.  We add the HIGHEST
	# error icon, and IN_STATION members.
{
	my ($params) = @_;
	my $id = $params->{id} || 0;
	my $station = $params->{station} || 0;
	display($dbg_webui,0,"explorer_items($id,$station)");

	my $dbh = db_connect();
	my $response = json_header();

	$response .= '[';
	my $started = 0;
	my $results = get_subitems($dbh, 'TRACKS', $id, 0, 99999);
	for my $rec (@$results)
	{
		next if (!$rec->{ID});
		
		# note that the 'title' of the fancytree 0th td is the tracknum
		
		$rec->{key} = $rec->{ID};
		$rec->{title} = ''; # $rec->{TRACKNUM};
		$rec->{icon} = "/webui/icons/error_$rec->{HIGHEST_ERROR}.png";
		set_in_station($dbh,$rec,$station);

		$response .= ',' if ($started);
		$started = 1;
		$response .= json($rec);
	}
	$response .= ']';
	db_disconnect($dbh);
	return $response;

}



#------------------------------------------------------
# File details - tags 
#------------------------------------------------------

sub explorer_item_tags
	# Return the JSON for an entire treegrid with
	# detailed information about one track, in sections:
	#
	# - the database record
	# - the mediaFile record
	# - low level MP3/WMA/M4A tags
	#
	# Note that we massage the IN_STATION variable
	# in the database record.
{
	my ($params) = @_;
	my $id = $params->{id} || 0;
	my $station = $params->{station} || 0;
	display($dbg_webui,0,"explorer_item_tags($id,$station)");
	return '[]' if (!$id);

	my $use_id = 0;
	my $sections = "[\n";

	# a section that displays the database record
	
	my $dbh = db_connect();
	my $rec = get_track($dbh,$id);
	if (!$rec)
	{
		return json_error("no rec for explorer_item_tags($id)");
	}
	set_in_station($dbh,$rec,$station);
	db_disconnect($dbh);

	$sections .= add_tag_section(0,\$use_id,'Database',0,$rec);

	# a section that shows the resolved "mediaFile"
	# section(s) that shows the low level tags

	my $info = MediaFile->new($rec->{FULLNAME});
	if (!$info)
	{
		error("no mediaFile($rec->{FULLNAME}) in item_tags request!");
		# but don't return error (show the database anyways)
	}
	else
	{
		$sections .= add_tag_section(1,\$use_id,'mediaFile',0,$info,'^raw_tags$');
		
		# show any mediaFile warnings or errors
		# we need err_num to keep the keys separate to call json()
		
		my $merrors = $info->get_errors();
		if ($merrors)
		{
			my @errors;
			my @sorted = sort {$$b[0] <=> $$a[0]} @$merrors;
			for my $e (@sorted)
			{
				push @errors,[$$e[0],severity_to_str($$e[0]),$$e[1]];
			}
			$sections .= add_error_section(1,\$use_id,'mediaFileErrors',1,\@errors);
		}
		
		# then based on the underlying file type, show the raw tag sections
		# re-reading a lot of stuff for m4a's

		if ($$info{type})
		{
			if ($$info{type} eq 'wma')
			{
				$sections .= add_tag_section(1,\$use_id,'wmaTags',1,$$info{raw_tags}->{tags});
				$sections .= add_tag_section(1,\$use_id,'wmaInfo',0,$$info{raw_tags}->{info});
			}
			elsif ($$info{type} eq 'm4a')
			{
				$sections .= add_tag_section(1,\$use_id,'m4aTags',1,$$info{raw_tags}->{tags});
				$sections .= add_tag_section(1,\$use_id,'m4aInfo',0,$$info{raw_tags}->{info});
			}
			
			else
			{
				$sections .= add_tag_section(1,\$use_id,'mp3Tags',1,$$info{raw_tags});
			}
		}
	}
	
	# close the list of sections and return to caller

	my $response = json_header();
	$response .= $sections;
	$response .= "]\n";
	return $response;
}



sub start_tag_section
	# start a tag section
{
	my ($comma,$use_id,$section_name,$expanded) = @_;
	my $expanded_clause = $expanded ? '"expanded":true,' : '';
	my $response = $comma ? ',' : '';
	$response .= <<EOJSON;
{
  "id"          : "$$use_id",
  "title"       : "",
  "TITLE"       : "$section_name",
  "VALUE"       : "",
  $expanded_clause
  "icon"		: false,
  "extraClasses" : "explorer_details_large_expander",
  "children"    : [
EOJSON
	return $response;
}


sub add_tag_item
	# add an item to a section escaping and
	# cleaning up the lval and rval.
	# Note use of escape_tag()!!
{
	my ($started,$use_id,$lval,$rval,$icon) = @_;
	$rval = escape_tag($rval);
	
	$rval =~ s/\\/\\\\/g;
	$rval =~ s/"/\\"/g;
	$lval =~ s/\\/\\\\/g;
	$lval =~ s/"/\\"/g;
	$lval =~ s/\t/ /g;
	
	display($dbg_webui+1,1,"$$use_id  NAME($lval) = VALUE($rval)");
	my $response = '';
	$response .= ',' if ($$started);
	$response .= "{ \"id\":\"$$use_id\", \"title\":\"\", \"TITLE\":\"$lval\",\"VALUE\":\"$rval\",\"state\":\"open\",";

	$response .= '"extraClasses" : "explorer_details_small_expander",',
	
	my $use_icon = $icon ? "\"$icon\"" : 'false';
	$response .= "\"icon\":$use_icon";

	$response .= "}\n";
	$$started = 1;
	$$use_id++;
	return $response;
}


sub add_tag_section
	# create a json record for a section of the given name
	# for every lval, rval pais in a hash
{
	my ($comma,$use_id,$section_name,$expanded,$rec,$exclude) = @_;
	my $response = start_tag_section($comma,$use_id,$section_name,$expanded);

	$$use_id++;
	my $started = 0;
	for my $lval (sort(keys(%$rec)))
	{
		my $rval = $$rec{$lval};
		next if $exclude && $lval =~ /$exclude/;
		$response .= add_tag_item(\$started,$use_id,$lval,$rval);
	}		
	$response .= "]}\n";
	return $response;
	
}	# add_tag_section()



sub add_error_section
	# add a section that consists of an array of arrays
	# where the 0th is the icon number, the 1st lval, and
	# the 2nd is the rval
{
	my ($comma,$use_id,$section_name,$state,$array) = @_;
	my $response = start_tag_section($comma,$use_id,$section_name,$state);

	$$use_id++;
	my $started = 0;
	for my $rec (@$array)
	{
		my ($i,$lval,$rval) = (@$rec);
		my $icon = "/webui/icons/error_$i.png";
		display($dbg_webui,0,"icon($lval)=$icon");
		$response .= add_tag_item(\$started,$use_id,$lval,$rval,$icon);
	}		
	$response .= "]}\n";
	return $response;
	
}	


#---------------------------------------------------
# station_list
#---------------------------------------------------
# This module (uiExplorer) handles the request to
# get all the id's for folders/tracks in a certain
# station (for the webUI edit_station_tree), which
# is more of a 'database' than a 'station" function
# and is in this file because 'explorer' connotes
# deeper database operations. This funtionality
# *could* be moved to uiStation.pm for clarity.


sub get_station_items
	# build a big hash of id=>1 or 'track_'.$id=>1
	# for items within the station. Returns an empty
	# list if station not defined or zero. Sets =>2
	# if the item is 'partsel'
{
	my ($params) = @_;
	my $dbh = db_connect();
	my $station = getStation($params->{station});
	return json_error("No station specified in get_station_items()") if !$station;
	
	my $bit = $station->station_bit();

	my $rslt = {};
	my $folders = get_records_db($dbh,"SELECT ID,PARENT_ID FROM FOLDERS WHERE STATIONS & $bit ORDER BY ID");
	for my $folder (@$folders)
	{
		$rslt->{$folder->{ID}} = 1;
		set_parents_partsel($dbh,$rslt,$folder->{PARENT_ID});
	}
	
	my $tracks = get_records_db($dbh,"SELECT ID,PARENT_ID FROM TRACKS WHERE STATIONS & $bit ORDER BY ID");
	for my $track (@$tracks)
	{
		$rslt->{'track_'.$track->{ID}} = 1;
		set_parents_partsel($dbh,$rslt,$track->{PARENT_ID});
	}
	
	db_disconnect($dbh);
	return json_header().json($rslt);
}
	
	
sub set_parents_partsel
	# if an item is in the station, then we recurse
	# thru parents until we find one that already set,
	# setting their 'rslt' to 2 for 'partsel'.  This is
	# *reasonably* efficient.
{
	my ($dbh,$rslt,$parent_id) = @_;
	while ($parent_id && !$rslt->{$parent_id})
	{
		display($dbg_webui-1,0,"setting partsel on parent_id=$parent_id");
		$rslt->{$parent_id} = 2;
		my $rec = get_record_db($dbh,"SELECT PARENT_ID FROM FOLDERS WHERE ID='$parent_id'");
		$parent_id = $rec ? $rec->{PARENT_ID} : 0;
	}
}

	



1;
