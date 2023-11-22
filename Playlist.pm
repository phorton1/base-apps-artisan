#!/usr/bin/perl
#---------------------------------------
# Playlist.pm
#---------------------------------------
# A Playlist is contained in a playlists.db file, and
# has the following members:
#
#	id				- playlist id within library(uuid)
#   uuid			- uuid of the library holding the playlist
# 	name			- playlist title
# 	shuffle			- shuffle mode
#   num_tracks		- number of tracks in the playlist
#   track_index		- current track index within the playlist
#   {tracks}		- the 'tracks' in the playlist may be loaded into memory
#
# The Tracks in a playlist (pl_tracks) are contained in database file called
# "name.db" in a 'playlists' subdirectory relative to the playlists.db file.
# A pl_track has sufficient information to sort/shuffle the playlist, and to
# return the track_id within the library.
#
#	id			- id of the track
#	album_id    - a useful ID for sorting the tracks in the playlist by random album
#	position    - unsorted position within the playlilst
#
# MASTER COPY
#
# 	Each library has a 'master' set of database files represnting its playlists.
#	for the localLibrary, the playlists.db file is in the $data_directory (/mp3s/_data),
#   and the named.db files are in $data_directory/playlists.
#
#   The master copy is constructed during the library ctor for remoteLibraries, or
#   via a call to localPlaylist::initPlaylists(); for the localLibrary.
#
# RENDERER PLAYLISTS
#
# 	The state of a playlist is particular to a particular renderer.
#	Each Renderer gets a COPY of each playlists.db file, on which it can
#   modify the state variables.  These copies are compared by timestamp,
#   and will be re-copied if the underlying playlists.db file changes.
#
# 	For this discussion, say there are two renderer uuids involved
#   at this time:  local_renderer->{uuid} and 'html_renderer' from the
#   webUI. For the example we will use the uuid's 'local_renderer' and
#   'local_library' for local devices.
#
#   $library->getPlaylist($renderer_uuid,$playlist_id)
#
#		Creates a COPY of the master playlists.db.
#		These copies are kept in the 'temp' directory under a subfolder
#       named 'Renderers', with the uuid of the library in the filename.
#
#       So, for example, the localRenderer getting a playlist named 'work'
#       from the localLibrary would result in the following directory structure:
#
#		/base_data/temp/artisan/				$temp_dir
#			Renderers/							$temp_dir/Renderers
#       		local_renderer/					$temp_dir/Renderers/xxxx-feed/
#					playlist.local_library.db	$temp_dir/Renderers/xxxx-feed/playlist.xxxx-feed.db
#
#       When the 'tracks' are needed for a playlist, they are always gotten from
#       the named.db files in the master.
#
# DERIVED CLASSES
#
#	Derived classes do whatever they need to do during startup (or on
#   first access, to build the master playlist.db and named.db files.
#
#		$library->dataDir()
#			implemented in derived classes, this returns
#           the master directory from which the playlist.db
#           will be copied.
#		$library->playlistDir()
#			usually $library->dataDir()/playlists
#
#
# API to Library
#
#	getPlaylists($library,$renderer_uuid)
#
# 		implemented here generically, creates the renderer copy
#       and, creates blessed in memory cache of the playlists,
#       from its playlists.db, and returns it to the caller.
#		Always called before getPlaylist()!!
#
#	getPlaylist($library,$renderer_uuid,$playlist_id)
#
#		implemented here generically,
#		returns the blessed playlist
#		which is cached in memory
#
#	$playlist->getTrackId($library,$renderer_uuid, $mode,$index)
#   $playlist->sortPlaylist(shuffle) returns 1 on success
#
#		A Playlist gotten from a Library for a particular Renderer
#   	provides exactly two entry points, one to get the TrackID
#   	of a track (based on $PLAYLIST_ABSOLUTE/RELATIVE and $index),
#   	or to sortThe playlist resetting the index to 1 and returning
#
#   	The playlist itself will already be cached in memory due
#       to a previous call to getPlaylists().
#
#       The 'tracks' will be loaded into memory if they have not
#       already been, as they are need for both calls.
#
#       Both calls are write-thru to the copy of the database, updating
#       the state of the particular Renderer's version of the
#       playlist.
#
# ISSUES
#
#	At this time, the playlist tracks are always sorted in memory.
#   So, for example, if dead is sorted randomly by album, and I play it for while,
#   then shut down Artisan, when I restart it, it will create a new random order
#   for the albums.   That's not really the behavior I wanted.
#
#   To fix it means that I would have to
#
#		(a) denormalize the named.db files as well, a whole nuther layer of work
#		(b) re-insert the sorted pl_tracks into the denormalized named.db files
#			after sorting, like I used to, which means that the sort itself will
#           take longer.
#
#	I am going to defer this issue until (a) I have gotten the remoteLibrary
#   playlists working withing this scheme, and have implemented the HTML Renderer
#   playlist behavior.  But I think I will want to go back and retain the
#   sort order in the databases for my own actual preferred personal use.
#
# SUPPORT FOR $library->getSubItems()
#
# 	Remember that, at this time, NONE of this has anything to do with
# 	Artisan as a DLNA MediaServer.   WMP has its own sort/shuffle capabilites
# 	and gets all the tracks for a given playlist from the localLibrary directly
# 	via getSubItems()
#
#	To support $library->getSubItems() which only works
#   off the master database, a fake renderer id of 'default'
#   is used to create a separate cache.


package Playlist;
use strict;
use warnings;
use threads;
use threads::shared;
use File::Copy;
use Database;
use artisanUtils;
use DeviceManager;


my $dbg_pl = 0;
my $dbg_sort = 0;



my $all_playlists:shared = shared_clone({});
my $all_playlists_by_id:shared = shared_clone({});
	# hashes by library_uuid - renderer_uuid containing
	# a list of playlists, or hash of playlists_by_id
	# that have been 'gotten'



sub playlistMem
{
	my ($library,$renderer_uuid,$dont_create) = @_;
	my $library_uuid = $library->{uuid};

	my $lib_playlists = $all_playlists->{$library_uuid};
	return if !$lib_playlists && $dont_create;
	$lib_playlists = $all_playlists->{$library_uuid} = shared_clone({}) if !$lib_playlists;

	my $lib_playlists_by_id = $all_playlists_by_id->{$library_uuid};
	return if !$lib_playlists_by_id && $dont_create;
	$lib_playlists_by_id = $all_playlists_by_id->{$library_uuid} = shared_clone({}) if !$lib_playlists_by_id;

	my $playlists = $lib_playlists->{$renderer_uuid};
	return if !$playlists && $dont_create;
	$playlists = $lib_playlists->{$renderer_uuid} = shared_clone([]) if !$playlists;

	my $playlists_by_id = $lib_playlists_by_id->{$renderer_uuid};
	return if !$playlists_by_id && $dont_create;
	$playlists_by_id = $lib_playlists_by_id->{$renderer_uuid} = shared_clone({}) if !$playlists_by_id;

	return ($playlists,$playlists_by_id);
}



sub getPlaylists
{
	my ($library,$renderer_uuid) = @_;
	display($dbg_pl,0,"getPlaylists($library->{name},$renderer_uuid)");

	# create the in-memory cache early in case there are errors

	my ($playlists,$playlists_by_id) = playlistMem($library,$renderer_uuid);

	my $library_uuid = $library->{uuid};
	my $play_dir = "$temp_dir/Renderers/$renderer_uuid/$library_uuid";
	my $play_db_name = "$play_dir/playlists.db";
	my_mkdir($play_dir) if !-f $play_dir;

	my $master_dir = $library->dataDir();
	my $master_db_name = "$master_dir/playlists.db";

	my $play_ts = getTimestamp($play_db_name);
	my $master_ts = getTimestamp($master_db_name);
	display($dbg_pl,1,"master_ts($master_ts) play_ts($play_ts)");

	if ($master_ts gt $play_ts)
	{
		unlink $play_db_name;
		my $master_dir = $library->dataDir();
		my $master_db_name = "$master_dir/playlists.db";
		display($dbg_pl,1,"Copying playlists.db from $master_dir to $play_db_name");
		if (!File::Copy::copy($master_db_name,$play_db_name))
		{
			error("Could not copy from '$master_db_name' to '$play_db_name' : $!");
			return [];
		}
	}


	display($dbg_pl,1,"getting records from $play_db_name");
	my $dbh = db_connect($play_db_name);
	return [] if !$dbh;
	my $recs = get_records_db($dbh,"SELECT * FROM playlists ORDER BY id") || [];
	db_disconnect($dbh);
	display($dbg_pl,1,"found ".scalar(@$recs)." records");

	# create the cache

	for my $rec (@$recs)
	{
		my $playlist = shared_clone($rec);
		bless $playlist,'Playlist';
		$playlist->{needs_write} = 0;

		my $exists = $playlists_by_id->{$playlist->{id}};
		if (!$exists)
		{
			push @$playlists,$playlist;
			$playlists_by_id->{$playlist->{id}} = $playlist;
		}
	}

	display($dbg_pl,0,"getPlaylists() returning ".scalar(@$playlists)." playlists");
	return $playlists || [];
}



sub getPlaylist
	# The UI never starts with a call chain to getPlaylist.
	#
	# It CAN start with a renderer that already has a playlist,
	# but that's ok, as that's whats used in the webUI playlist pane.
	# Otherwise, they have to press the button to get to this method.
	#
	# However, $library->getSubitems() doesn't know that, and yet
	# calls getPlaylist() before getPlaylists.
	#
	# Therefore, there is a parameter $dont_create on playlistMem()
	# that will not spuriouisly create the memory cache if it doesnt
	# already exit, so that we can return undef for that case.
{
	my ($library,$renderer_uuid,$id) = @_;
	display($dbg_pl,0,"getPlaylist($library->{name},$renderer_uuid,$id)");

	my ($playlists,$playlists_by_id) = playlistMem($library,$renderer_uuid,1);
		# dont create caches if they don't already exist
	if (!$playlists)
	{
		display($dbg_pl,0,"getPlaylist() returning undef!!");
		return;
	}

	my $playlist = $playlists_by_id->{$id} || '';

	display($dbg_pl,0,"getPlaylist() returning ".($playlist?
		"playlist($playlist->{name},$playlist->{num_tracks},$playlist->{track_index})":
		'undef'));
	return $playlist;
}




sub getTrackId
{
    my ($this,$renderer_uuid,$mode,$orig_index) = @_;
    display($dbg_pl,0,"getTrackId($this->{name},$mode,$orig_index) num($this->{num_tracks} cur($this->{track_index})");
    display($dbg_pl,1,"library($this->{uuid}) renderer($renderer_uuid)");

	# if tracks are not in memory, call sortPlaylist to get them.

	if (!$this->{tracks})
	{
		my $ok = $this->sortPlaylist($renderer_uuid);
		return '' if !$ok;
	}

	my $index = $orig_index;
	if ($mode == $PLAYLIST_RELATIVE)
	{
		$index = $this->{track_index} + $index;
		$index = 1 if $index > $this->{num_tracks};
    	$index = $this->{num_tracks} if $index < 1;
	}

	$index = 1 if $index < 1;
	$index = $this->{num_tracks} if $index>$this->{num_tracks};
	$index = 0 if !$this->{num_tracks};

	if ($this->{track_index} != $index)
	{
		$this->{needs_write} = 1;
		$this->{track_index} = $index;
	}

	$this->saveToPlaylists($renderer_uuid) if $this->{needs_write};

	my $track_id = $index ? $this->{tracks}->[$index-1]->{id} : '';
    display($dbg_pl,0,"getTrackId($mode,$orig_index) returning track($index)=$track_id");
	return $track_id;
}



sub sortPlaylist
{
	my ($this,$renderer_uuid,$shuffle) = @_;
	display($dbg_pl,0,"sortPlaylist($this->{name},"._def($shuffle).") cur=$this->{shuffle}");

	my $from_ui = defined($shuffle) ? 1 : 0;
	if ($from_ui && $this->{track_index} != 1)
	{
		$this->{needs_write} = 1;
		$this->{track_index} = 1
	}

	$shuffle = $this->{shuffle} if !defined($shuffle);

	if (!$this->{tracks})
	{
		display($dbg_pl,1,"loading tracks using shuffle($shuffle) (setting this->{shuffle}=$SHUFFLE_NONE)");
		$this->{shuffle} = $SHUFFLE_NONE;
		$this->{tracks} = shared_clone([]);
			# in case of errors

		# get the master named.db filename

		my $library_uuid = $this->{uuid};
		my $library = findDevice($DEVICE_TYPE_LIBRARY,$library_uuid);
		if (!$library)
		{
			error("Could not find library $library_uuid");
			return 0;
		}
		my $playlist_dir = $library->playlistDir();
		my $db_name = "$playlist_dir/$this->{name}.db";

		# connect to the named.db file
		# and get the records

		my $dbh = db_connect($db_name);
		return 0 if !$dbh;
		my $recs = get_records_db($dbh,"SELECT * FROM pl_tracks ORDER BY position");
		db_disconnect($dbh);
		return if !$recs;

		# push the records on this->{tracks}

		warning($dbg_pl,0,"EMPTY PLAYLSIT $this->{name} lib($this->{uuid})")
			if !@$recs;
		for my $rec (@$recs)
		{
			push @{$this->{tracks}},shared_clone($rec);
		}
	}

	display($dbg_pl,1,"after tracks from_ui($from_ui) shuffle($shuffle) this_shuffle($this->{shuffle})");
	if ($from_ui || $this->{shuffle} != $shuffle)
	{
		$this->{needs_write} = 1;
		$this->{shuffle} = $shuffle;
		$this->sort_shuffle_tracks();
	}

	$this->saveToPlaylists($renderer_uuid)
		if $from_ui && $this->{needs_write};
	return 1;
}




sub random_album
	# sorting within a random index of albums
	# then, if a tracknum is provided, by that, and
	# finally by the track title.
{
    my ($albums,$a,$b) = @_;
    my $cmp = $albums->{$a->{album_id}} <=> $albums->{$b->{album_id}};
    return $cmp if $cmp;
    return $a->{position} <=> $b->{position};
}


sub sort_shuffle_tracks
{
	my ($this) = @_;
    # sort them according to shuffle

   	display($dbg_pl,0,"sort_shuffle_tracks($this->{name},$this->{shuffle})");

	my $old_tracks = $this->{tracks};
	$this->{tracks} = shared_clone([]);

    if ($this->{shuffle} == $SHUFFLE_TRACKS)
    {
		# temp_position is an in-memory only variable
		# the TRACKS will be re-written to the database
		# in a random order

        for my $track (@$old_tracks)
        {
            $track->{temp_position} = 1 + int(rand($this->{num_tracks} + 1));
			# display($dbg_sort,1,"setting old_track($track->{position}) temp_position=$track->{temp_position}");
	    }
        for my $track (sort {$a->{temp_position} <=> $b->{temp_position}} @$old_tracks)
        {
			# display($dbg_sort,1,"pushing old_track($track->{position}) at temp_position=$track->{temp_position}");
            push @{$this->{tracks}},$track;
        }
    }
    elsif ($this->{shuffle} == $SHUFFLE_ALBUMS)
    {
        my %albums;
        for my $track (@$old_tracks)
        {
			my $album_id = $track->{album_id};
			if (!$albums{$album_id})
			{
				$albums{ $album_id} = int(rand($this->{num_tracks} + 1));
				# display($dbg_sort,1,"setting albums($album_id}) to $albums{$album_id}");
			}
		}
        for my $track (sort {random_album(\%albums,$a,$b)} @$old_tracks)
        {
			# display($dbg_sort,1,"pushing track album_id($track->{album_id}) position($track->{position})");
            push @{$this->{tracks}},$track;
		}
    }

	# sort the records by the DEFAULT SORT ORDER

    else	# proper default sort order
    {
        for my $track (sort {$a->{position} <=> $b->{position}} @$old_tracks)
        {
			# display($dbg_sort,1,"pushing track($track->{position})");
            push @{$this->{tracks}},$track;
        }
    }

   	display($dbg_pl,0,"sort_shuffle_tracks($this->{name}) finished");
}




sub saveToPlaylists
{
	my ($this,$renderer_uuid) = @_;
	display($dbg_pl,0,"saveToPlaylists($this->{id}) $this->{name}");

	my $library_uuid = $this->{uuid};
	my $play_dir = "$temp_dir/Renderers/$renderer_uuid/$library_uuid";
	my $play_db_name = "$play_dir/playlists.db";

	my $dbh = db_connect($play_db_name);
	return if !$dbh;

	if (!update_record_db($dbh,'playlists',$this,'id'))
	{
		error("Could not update playlist.db database");
		return;
	}
	db_disconnect($dbh);
}






1;
