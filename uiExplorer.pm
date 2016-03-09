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
use Playlist;
use uiUtils;


#---------------------------------
# EXPLORER MODE
#---------------------------------
#
# These variables control the default errors that will show
# in the colored icon in the explorer tree.  One can choose
# to accumulate the highest TRACK errors into the parents,
# or the highest FOLDER errors, or BOTH.
#
# Folder errors include things like missing folder.jpg files, etc.
# Track errors include things like missing metadata, etc.
#
# This default UI setting is a UI preference, and is overriden
# by the webUI on a per-call basis. It works.


my $SHOW_TRACK_HIGH = 0;
	# Accumulate the highest TRACK error into the icon
my $SHOW_FOLDER_HIGH = 1;
	# Accumluate the highest FOLDER error into the icon
my $SHOW_BOTH_HIGH = 2;
	# Accumulate both TRACK and FOLDER errors into the icon.

my $SHOW_HIGH = $SHOW_FOLDER_HIGH;
	# THE EXPLORER MODE SETTING
	


sub explorer_request
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
	elsif ($path eq 'get_track')
	{
		my $dbh = db_connect();
		my $rec = get_record_db($dbh,'SELECT * FROM tracks WHERE ID=?',[$params->{id}]);
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
		my $track = get_track($dbh,$params->{track_id});
		my $parent_id = $track->{parent_id};
		while (my $folder = get_folder($dbh,$parent_id))
		{
			# jquery doesn't want the 0th element
			push @parts,$folder->{id} if $folder->{id};
			$parent_id = $folder->{parent_id};
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


sub explorer_dir
	# Return the json for the list of children of the directory
	# given by params->{id}. albums are leaf nodes (in explorer) 
{
	my ($params) = @_;
	my $id = $params->{id} || 0;
	display($dbg_webui,0,"explorer_dir($id)");

	# sublimate id(0) to id(1)
	
	my $use_id = $id; # ? $id : 1;

	# collect the child folders
	
	my $dbh = db_connect();
	my $results = get_subitems($dbh, 'folders', $use_id, 0, 99999);
	db_disconnect($dbh);
	
	my $started = 0;
	my $response = json_header();
	$response .= '[';
	for my $rec (@$results)
	{
		next if (!$rec->{id});
		$response .= ',' if ($started);
		$started = 1;
		$response .= explorer_dir_element($params,$rec);
	}
	$response .= ']';
	
	display($dbg_webui+1,0,"dir response=$response");
	return $response;
}



		
sub explorer_dir_element
	# return the json for one subfolder element.
	# Return lazy=1 and folder=1 for parents to be load-on-expand
{
	my ($params,$rec) = @_;
	
	$rec->{key} = $rec->{id};	# required
	my $title = $rec->{title};

	if ($rec->{dirtype} ne 'album')
	{
		$rec->{folder} = '1';
		$rec->{lazy} = '1';
	}
		
	if ($rec->{dirtype} eq 'album' &&
		$rec->{path} !~ /\/dead/i)
	{
		$title = "$rec->{artist} - $title"
			if $rec->{artist};
		$title =~ s/_/-/g;	# fix my use of underscores for dashes
	}
	
	$rec->{title} = $title;	# required
	$rec->{art_uri} = "http://$server_ip:$server_port/get_art/$rec->{id}/folder.jpg";			
	
	my $mode = defined($params->{mode}) ? $params->{mode} : $SHOW_HIGH;

	my $use_high =
		$mode == $SHOW_TRACK_HIGH ? $$rec{highest_track_error} :
		$mode == $SHOW_FOLDER_HIGH ? $$rec{highest_folder_error} :
		$$rec{highest_error} > $$rec{highest_folder_error} ?
		$$rec{highest_error} : $$rec{highest_folder_error};

	$rec->{icon} = "/webui/icons/error_$use_high.png";
	
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
	# associated with a directory.
{
	my ($params) = @_;
	my $id = $params->{id} || 0;
	display($dbg_webui,0,"explorer_items($id)");

	my $dbh = db_connect();
	my $response = json_header();

	$response .= '[';
	my $started = 0;
	my $results = get_subitems($dbh, 'tracks', $id, 0, 99999);
	for my $rec (@$results)
	{
		next if (!$rec->{id});
		
		# note that the 'title' of the fancytree 0th td is the tracknum
		# prh - should the title just be the tile ? 
		
		$rec->{key} = $rec->{id};
		display(0,1,"rec->{title}=$rec->{title}");
		$rec->{TITLE} = $rec->{title};
			# lc title appears to conflict with jquery-ui
			# so we send upercase 
		$rec->{icon} = "/webui/icons/error_$rec->{highest_error}.png";

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
{
	my ($params) = @_;
	my $id = $params->{id} || 0;
	display($dbg_webui,0,"explorer_item_tags($id)");
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
	db_disconnect($dbh);

	$sections .= add_tag_section(0,\$use_id,'Database',0,$rec);

	# a section that shows the resolved "mediaFile"
	# section(s) that shows the low level tags

	my $info = MediaFile->new($rec->{path});
	if (!$info)
	{
		error("no mediaFile($rec->{path}) in item_tags request!");
		# but don't return error (show the database anyways)
	}
	else
	{
		# the errors get their own section
		
		my $merrors = $info->get_errors();
		delete $info->{errors};
		
		$sections .= add_tag_section(1,\$use_id,'mediaFile',0,$info,'^raw_tags$');
		
		# show any mediaFile warnings or errors
		# we need err_num to keep the keys separate to call json()
		
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
	$rval = "" if !defined($rval);
	
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
		display($dbg_webui+2,0,"icon($lval)=$icon");
		$response .= add_tag_item(\$started,$use_id,$lval,$rval,$icon);
	}		
	$response .= "]}\n";
	return $response;
	
}	





1;
