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


#-------------------------------------------------
# FancyTree Notes
#-------------------------------------------------
# We add the following fields to the directory entries (folders)
# and tracklist items (tracks) data-records we return to the UI
# for fancytree:
#
#		key = is set to the id of the Folder/Track
#       icon = retrievable url for an error icon
#			i.e. "/webui/icons/error_3.png"
#
# For Explorer Tree we pass 'title' to fancytree (it is removed from
# the data-record by fancytree). We also add the following fields for
# for non-terminal nodes (not playlists or albums)
#
# 		folder => 1
#		lazy => 1
#
# The following fields in our Track records CONFLICT with fancytree.
# Fancytree USES these identifiers itself and removes them from the
# data record.  therefore we UPPERCASE these normal field names
# from the database Tracks that we return to the UI as fancytree
# data records:
#
#	title		=> TITLE
#	type		=> TYPE
#
# Other 'reserved words" we that fancytree will interpret include:
# (example is from Track)
#
#	_error: null
#	_isLoading: false
#	checkbox: undefined
#	children: null
#	data: {…}									<-- OUR RECORD is in here
#	expanded: undefined
#	extraClasses: undefined
#	folder: undefined
#	icon: "/webui/icons/error_3.png"			<-- WE ADDED THIS
#	iconTooltip: undefined						<-- WE SET THIS for non-terminal ExplorerTree nodes
#	key: "c04b4dc0c522241edfbecf916be2ee03"		<-- WE ADDED THIS
#	lazy: undefined								<-- WE SET THIS for non-terminal ExplorerTree nodes
#	li: null
#	parent: {…}
#	partsel: undefined
#	radiogroup: undefined
#	refKey: undefined
#	selected: undefined
#	span: span.fancytree-node
#	statusNodeType: undefined
#	title: undefined
#	tooltip: undefined
#	tr: tr.fancytree-lastsib.fancytree-exp-nl.fancytree-ico-c??
#	tree: {…}
#	type: undefined
#	ul: null
#	unselectable: undefined
#	unselectableIgnore: undefined
#	unselectableStatus: undefined


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
	# library requests to remote_artisan libraries
	# are already diverted to the other instance of
	# Artisan by using the js library_url() method
{
	my ($path,$params) = @_;
	display($dbg_uilib,0,"library_request($path)");

	return json_error("could not find library uuid in '$path'")
		if $path !~ s/^(.*?)\///;
	my $uuid = $1;

	# Get the Library

	my $library = findDevice($DEVICE_TYPE_LIBRARY,$uuid);
	return json_error("could not find library '$uuid'") if !$library;

	# Remote request for another Artisan library
    # To become supported in remoteArtisan as standard Library API

	if ($library->{remote_artisan})
	{
		return remoteArtisanRequest($library,$path,$params);
	}

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
		return json_header().json($track);
	}

	# following two currently require a previously
	# cached remoteTrack/Folder in remoteLibrary

	elsif ($path eq 'track_metadata')
	{
		my $id = $params->{id} || 0;
		display($dbg_uilib,0,"library_track_metadata($id)");
		my $metadata = $library->getTrackMetadata($id);
		return json_header().json($metadata);
	}
	elsif ($path eq 'folder_metadata')
	{
		my $id = $params->{id} || 0;
		display($dbg_uilib,0,"library_folder_metadata($id)");
		my $metadata = $library->getFolderMetadata($id);
		return json_header().json($metadata);
	}


	#-----------------------------
	# Playlists
	#-----------------------------

	elsif ($path eq 'get_playlists')
	{
		my $playlists = $library->getPlaylists();
		my $result = [];
		for my $playlist (@$playlists)
		{
			push @$result,{
				id => $playlist->{id},
				name => $playlist->{name},
				uuid => $playlist->{uuid}, };
		}
		return json_header().json($result);
	}

	# command that need a playlist

	elsif ($path =~ /^(get_playlist|get_playlist_track|shuffle_playlist)$/)
	{
		my $id = $params->{id} || '';
		return json_error("no playlist id in get_playiist")
			if !$id;

		my $playlist = $library->getPlaylist($id);
		return json_error("could not find playlist '$id'") if !$playlist;

		if ($path eq 'get_playlist_track')
		{
			my $version = $params->{version} || 0;
			my $mode = $params->{mode} || 0;
			my $index = $params->{index} || 0;
			$playlist = $playlist->getPlaylistTrack($version,$mode,$index);
			return json_error("uiLibrary($library->{name}) could not getPlaylistTrack($mode,$index)")
				if !$playlist;
		}
		elsif ($path eq 'shuffle_playlist')
		{
			my $shuffle = $params->{shuffle} || 0;
			$playlist = $playlist->sortPlaylist($shuffle);
			return json_error("uiLibrary($library->{name}) could not sortPlaylist($shuffle)")
				if !$playlist;
		}

		return json_header().json($playlist);
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
	my $start = $params->{start} || 0;
	my $count = $params->{count} || 0;
		# count==0 means get all of em
	display($dbg_uilib,0,"library_dir($id,$start,$count)");

	# sublimate id(0) to id(1)

	my $use_id = $id; # ? $id : 1;

	# collect the child folders

	my $results = $library->getSubitems('folders', $use_id, $start, $count);

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

	# key and title are required for explorer_tree (fancyTree)
	# folder=1 is apparently meaningless
	# lazy=1 is what drives having an expander before it is loaded

	$rec->{key} = $rec->{id};
	my $title = $rec->{title};

	# I have sections, classes, albums, and playlists

	if ($rec->{dirtype} ne 'album' &&
		$rec->{dirtype} ne 'playlist')
	{
		$rec->{folder} = '1';
		$rec->{lazy} = '1';
	}

	# title optimized for local library
	# I should probably build this into it

	if ($library->{uuid} eq $this_uuid &&
		$rec->{dirtype} eq 'album' &&
		$rec->{path} !~ /\/dead/i &&
		$rec->{path} !~ /\/beatles/i)
	{
		$title = "$rec->{artist} - $title"
			if $rec->{artist};
		$title =~ s/_/-/g;	# fix my use of underscores for dashes
	}

	$rec->{title} = $title;	# required
	$rec->{TITLE} = $title;	# for consistency with Track convention


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
	my $start = $params->{start} || 0;
	my $count = $params->{count} || 0;
	display($dbg_uilib,0,"library_tracklist($id,$start,$count)");
	my $results = $library->getSubitems('tracks', $id, $start, $count);

	my $started = 0;
	my $response = json_header().'[';
	for my $rec (@$results)
	{
		next if (!$rec->{id});

		# add fancy tree fields

		$rec->{key} = $rec->{id};
		$rec->{icon} = "/webui/icons/error_$rec->{highest_error}.png";

		# map fancy tree conflict fields

		$rec->{TITLE} = $rec->{title};
		$rec->{TYPE} = $rec->{type};
		delete $rec->{title};
		delete $rec->{type};


		$response .= ',' if ($started);
		$started = 1;
		$response .= json($rec);
	}
	$response .= ']';
	return $response;
}


#-------------------------------------------------------
# remoteArtisanRequest
#-------------------------------------------------------

use LWP::UserAgent;


my $dbg_remote = 0;

sub remoteArtisanRequest
{
 	my ($library,$path,$params) = @_;
 	my $args = '';
 	for my $key (keys %$params)
 	{
 		$args .= $args ? '&' : '?';
 		$args .= "$key=$params->{$key}";
 	}
 	my $url = "http://$library->{ip}:$library->{port}/webui/library/$library->{uuid}/$path$args";
 	display($dbg_remote,0,"remoteArtisanRequest($url)");
 	my $ua = LWP::UserAgent->new();
 	my $response = $ua->get($url);
 	return json_error("No response from get($url)") if !$response;
 	display($dbg_remote,0,"response=".length($response->as_string())." bytes");
 	return $response->as_string();
}






1;
