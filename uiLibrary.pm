#!/usr/bin/perl
#---------------------------------------
# uiLibrary.pm
#
# The dispatch handler for /webui/library requests.


package uiLibrary;
use strict;
use warnings;
use artisanUtils;
use Device;
use DeviceManager;
use Database;
use MediaFile;
use Library;

use httpUtils;

my $dbg_uilib = 0;
	# 0 == shows calls
	# -1 == show results
	# -2 == show icons
my $dbg_uipls = 0;
	# 'Local Playlist Source'


#---------------------------------
# EXPLORER ERROR MODE
#---------------------------------
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




sub library_request
{
	my ($path,$params) = @_;
	display($dbg_uilib,0,"library_request($path)");

	return json_error("could not find library uuid in '$path'")
		if $path !~ s/^(.*?)\///;
	my $uuid = $1;

	# Get the Library

	my $library = findDevice($DEVICE_TYPE_LIBRARY,$uuid);
	return json_error("could not find library '$uuid'") if !$library;

	# handle request

	if ($path eq 'dir')
	{
		return library_dir($library,$params);
	}
	elsif ($path eq 'tracklist')
	{
		return library_tracklist($library,$params);
	}
	elsif ($path eq 'get_track')
	{
		my $id = $params->{id} || '';
		my $track = $library->getTrack($id);
		return json_error("could not find track '$id'") if !$track;
		my $json = json($track);
		return json_header().$json;
	}

	# following two currently require a previously
	# cached remoteTrack/Folder in remoteLibrary

	elsif ($path eq 'track_metadata')
	{
		my $id = $params->{id} || 0;
		display($dbg_uilib,0,"library_track_metadata($id)");
		my $metadata = $library->getTrackMetadata($id);
		my $json = json($metadata);
		return json_header().$json;
	}
	elsif ($path eq 'folder_metadata')
	{
		my $id = $params->{id} || 0;
		display($dbg_uilib,0,"library_folder_metadata($id)");
		my $metadata = $library->getFolderMetadata($id);
		my $json = json($metadata);
		return json_header().$json;
	}

	# following only used in webUI context menu
	# which are not re-implemented yet ...

	elsif ($path eq 'get_id_path')
	{
		# needs to be library agnostic

		my @parts;
		push @parts,'track_'.$params->{track_id};
		my $track = $library->getTrack($params->{track_id});
		my $parent_id = $track->{parent_id};
		while (my $folder = $library->getFolder($parent_id))
		{
			# jquery doesn't want the 0th element
			push @parts,$folder->{id} if $folder->{id};
			$parent_id = $folder->{parent_id};
		}

		return json_header().json({id_path=>join('/',reverse @parts)});
	}

	#-----------------------------
	# Playlists
	#-----------------------------

	elsif ($path eq 'get_playlists')
	{
		my $renderer_uuid = $params->{renderer_uuid} || '';
		return json_error("no renderer_uuid in get_playiists")
			if !$renderer_uuid;

		my $playlists = $library->getPlaylists($renderer_uuid);
		my $html = html_header();
		for my $playlist (@$playlists)
		{
			$html .= getPlaylistMenuHTML($playlist);
		}
		# display(0,0,"get_playlists returning $html");
		return $html;
	}
	elsif ($path eq 'get_playlist')
	{
		my $id = $params->{id} || '';
		return json_error("no playlist id in get_playiist")
			if !$id;
		my $renderer_uuid = $params->{renderer_uuid} || '';
		return json_error("no renderer_uuid in get_playiist")
			if !$renderer_uuid;

		my $playlist = $library->getPlaylist($renderer_uuid,$id);
		return json_error("could not find playlist '$id'") if !$playlist;
		my $json = json($playlist);
		return json_header().$json;
	}

	#-----------------------------
	# unknown
	#-----------------------------

	else
	{
		return json_error("unknown library_request: $path");
	}
}



#-----------------------------------------------
# directory requests
#-----------------------------------------------

sub library_dir
	# Return the json for the list of children of the directory
	# given by params->{id}. albums are leaf nodes (in explorer)
{
	my ($library,$params) = @_;
	my $id = $params->{id} || 0;
	display($dbg_uilib,0,"library_dir($id)");

	# sublimate id(0) to id(1)

	my $use_id = $id; # ? $id : 1;

	# collect the child folders

	my $results = $library->getSubitems('folders', $use_id);

	my $started = 0;
	my $response = json_header();
	$response .= '[';
	for my $rec (@$results)
	{
		next if (!$rec->{id});
		$response .= ',' if ($started);
		$started = 1;
		$response .= library_dir_element($library,$params,$rec);
	}
	$response .= ']';

	display($dbg_uilib+1,0,"dir response=$response");
	return $response;
}


sub library_dir_element
	# return the json for one subfolder element.
	# Return lazy=1 and folder=1 for parents to be load-on-expand
{
	my ($library,$params,$rec) = @_;

	# required

	$rec->{key} = $rec->{id};
	my $title = $rec->{title};
	if ($rec->{dirtype} ne 'album')
	{
		$rec->{folder} = '1';
		$rec->{lazy} = '1';
	}

	# title optimized for local library
	# I should probably build this into it

	if ($library->{uuid} eq $this_uuid &&
		$rec->{dirtype} eq 'album' &&
		$rec->{path} !~ /\/dead/i)
	{
		$title = "$rec->{artist} - $title"
			if $rec->{artist};
		$title =~ s/_/-/g;	# fix my use of underscores for dashes
	}

	$rec->{title} = $title;	# required

	# art_uri build for localLibrary, and highest errors are
	# zero for remoteLibraries

	if ($library->{uuid} eq $this_uuid)
	{
		$rec->{art_uri} = "http://$server_ip:$server_port/get_art/$rec->{id}/folder.jpg";
	}

	my $mode = defined($params->{mode}) ? $params->{mode} : $SHOW_HIGH;

	my $use_high =
		$mode == $SHOW_TRACK_HIGH ? $$rec{highest_track_error} :
		$mode == $SHOW_FOLDER_HIGH ? $$rec{highest_folder_error} :
		$rec->{highest_error} > $rec->{highest_folder_error} ?
		$rec->{highest_error} : $rec->{highest_folder_error};

	$rec->{icon} = "/webui/icons/error_$use_high.png";

	return "\n".json($rec);
}


sub library_tracklist
	# Return the json for a list of of files (tracks)
	# associated with a directory.
{
	my ($library,$params) = @_;
	my $id = $params->{id} || 0;
	display($dbg_uilib,0,"library_tracklist($id)");
	my $results = $library->getSubitems('tracks', $id);

	my $started = 0;
	my $response = json_header().'[';
	for my $rec (@$results)
	{
		next if (!$rec->{id});

		# note that the 'title' of the fancytree 0th td is the tracknum
		# should the title just be the tile ?

		$rec->{key} = $rec->{id};
		display($dbg_uilib+1,1,"rec->{title}=$rec->{title}");
		$rec->{TITLE} = $rec->{title};
			# lc title appears to conflict with jquery-ui
			# so we send upercase
		$rec->{icon} = "/webui/icons/error_$rec->{highest_error}.png";

		$response .= ',' if ($started);
		$started = 1;
		$response .= json($rec);
	}
	$response .= ']';
	return $response;
}


sub getPlaylistMenuHTML
{
	my ($playlist) = @_;

	my $id = $playlist->{id};
	my $uuid = $playlist->{uuid};
	my $name = $playlist->{name};

	my $text = '';
	$text .= "<input type=\"radio\" ";
	$text .= "id=\"playlist_button_$id\" ";
	$text .= "class=\"playlist_button\" ";
	$text .= "onclick=\"javascript:set_playlist('$uuid','$id');\" ";
	$text .= "name=\"playlist_button_set\">";
	$text .= "<label for=\"playlist_button_$id\">";
	$text .= "$name</label>";
	$text .= "<br>";
	$text .= "\n";
	return $text;
}



1;
