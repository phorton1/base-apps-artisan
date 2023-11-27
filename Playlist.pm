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
#   track_index		- current track index within the playlist or 0 if no tracks
#   track_id		- track_id corresponding to the track_index or '' if no tracks
#	version		    - version number is bumped on every sort and getPlaylistTrack index change.
#
# The Tracks in a playlist (pl_tracks) are contained in database file called
# "name.db" in a 'playlists' subdirectory relative to the playlists.db file.
# A pl_track has sufficient information to sort/shuffle the playlist, and to
# return the track_id within the library.
#
#	id			- id of the track
#	album_id    - a useful ID for sorting the tracks in the playlist by random album
#	position    - 1..num_tracks original position within the playlilst
#   idx			- 1..num_tracks sorted position within the playist
#
# Each library has a set of database files representing its playlists.
# for the localLibrary, the playlists.db file is in the $data_directory (/mp3s/_data),
# and the named.db files are in $data_directory/playlists. For remoteLibraries
# they are in the /base_data/artisan/Library/UUID/ folder
#
# The database is constructed during the first usage for remoteLibraries, or
# at startup for the localLibrary via a call to localPlaylist::initPlaylists()
#
# THIS CLASS
#
# This class facilitates access to playlists by uiLibrary.pm and localRenderer
# Note that the localPlaylist and remotePlaylist are NOT classes.  They merely
# build the database files in given locations.  THIS is the generalic Playlist
# class the blesses these things as Playlists.  It supports the following methods
#
#	getPlaylists($library)
#	getPlaylist($library,$playlist_id)
#	$playlist->getPlaylistTrack($version,$mode,$index)
#   $playlist->sortPlaylist($shuffle)
#
# To provide orthogonal access to the library databases, each library
# provides a method to get to the path to the directory containing
# the playlists.db file.  The named.db files are always in a subdirectory
# /playists under that.
#
#    	$library->dataDir()


		$playlist->{track_index} = 0 if !$playlist->{num_tracks};
		$playlist->{track_index} = 1 if !$playlist->{track_index} && $playlist->{num_tracks};

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


sub getPlaylists
{
	my ($library) = @_;		# ,$renderer_uuid) = @_;
	display($dbg_pl,0,"getPlaylists($library->{name})");	# ,$renderer_uuid)");

	my $master_dir = $library->dataDir();
	my $master_db_name = "$master_dir/playlists.db";

	display($dbg_pl,1,"getting records from $master_db_name");

	my $dbh = db_connect($master_db_name);
	return [] if !$dbh;

	my $recs = get_records_db($dbh,"SELECT * FROM playlists ORDER BY id") || [];
	db_disconnect($dbh);
	display($dbg_pl,1,"found ".scalar(@$recs)." records");

	# create the list

	my $playlists = shared_clone([]);
	for my $rec (@$recs)
	{
		my $playlist = shared_clone($rec);
		bless $playlist,'Playlist';
		$playlist->{library_name} = $library->{name};  # NEW FOR CONSISTENCY
		push @$playlists,$playlist;
	}

	display($dbg_pl,0,"getPlaylists() returning ".scalar(@$playlists)." playlists");
	return $playlists || [];
}



sub getPlaylist
{
	my ($library,$id) = @_;
	display($dbg_pl,0,"getPlaylist($library->{name},$id)");

	my $master_dir = $library->dataDir();
	my $master_db_name = "$master_dir/playlists.db";
	display($dbg_pl,1,"getting $id from $master_db_name");

	my $dbh = db_connect($master_db_name);
	return if !$dbh;

	my $rec = get_record_db($dbh,"SELECT * FROM playlists WHERE id='$id'");
	db_disconnect($dbh);
	display($dbg_pl,1,"found rec="._def($rec));

	# clone the record and bless it

	my $playlist;
	if ($rec)
	{
		$playlist = shared_clone($rec);
		bless $playlist,'Playlist';
		$playlist->{library_name} = $library->{name};
	}

	display($dbg_pl,0,"getPlaylist() returning ".($playlist?
		"playlist($playlist->{name},V_$playlist->{version},$playlist->{num_tracks},$playlist->{track_index}) shuffle=$playlist->{shuffle} track_id=$playlist->{track_id}":
		'undef'));
	return $playlist;
}



sub getLibraryPlaylistsDir
{
	my ($library_uuid) = @_;
	my $library = findDevice($DEVICE_TYPE_LIBRARY,$library_uuid);
	return !error("Could not find Library($library_uuid)") if !$library;
	my $path = $library->dataDir()."/playlists";
	return $path;
}



sub getPlaylistTrack
{
    my ($this,$version,$mode,$orig_index) = @_;   # $renderer_uuid
    display($dbg_pl,0,"getPlaylistTrack($this->{name},V_$version,MODE_$mode,$orig_index) cur V_$this->{version} idx($this->{track_index}) num($this->{num_tracks})");
    display($dbg_pl,1,"library($this->{uuid})");	# renderer($renderer_uuid)");
	my $playlists_dir = getLibraryPlaylistsDir($this->{uuid});
	return if !$playlists_dir;

	# only the version holder can change the track number

	if ($version == $this->{version})
	{
		# determine the new index

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
			my $named_db = "$playlists_dir/$this->{name}.db";
			display($dbg_pl,1,"getting index($index) from $named_db");
			my $dbh = db_connect($named_db);
			return if !$dbh;

			my $rec = get_record_db($dbh,"SELECT * FROM pl_tracks WHERE idx='$index'");
			db_disconnect($dbh);
			display($dbg_pl,1,"found rec="._def($rec));

			$this->{track_index} = $index;
			$this->{track_id} = $rec ? $rec->{id} : '';
			$this->{version}++;

			$this->saveToPlaylists();

			display($dbg_pl,0,"getPlaylistTrack(V_$version,MODE_$mode,$orig_index) returning V_$this->{version} track($this->{track_index})=$this->{track_id}");
		}
		else
		{
			display($dbg_pl,0,"getPlaylistTrack(V_$version,MODE_$mode,$orig_index) no_change! V_$this->{version} track($this->{track_index})=$this->{track_id}");
		}
	}
	else
	{
		warning($dbg_pl,0,"getPlaylistTrack(V_$version,MODE_$mode,$orig_index) SKIPPING REQUEST FROM V_$this->{version} track($this->{track_index})=$this->{track_id}");
	}
	return $this;
}



sub sortPlaylist
	# used to be used to read the cache into memory, but that is no longer the case.
	# always provided with $shuffle parameter from UI and we always re-sort the list
	# and it always needs writing

{
	my ($this,$shuffle) = @_;				# $renderer_uuid
	display($dbg_pl,0,"sortPlaylist($this->{name},V_$this->{version},"._def($shuffle).") cur=$this->{shuffle}");
	my $playlists_dir = getLibraryPlaylistsDir($this->{uuid});
	return if !$playlists_dir;

	my $db_name = "$playlists_dir/$this->{name}.db";

	# connect to the named.db file
	# and get the records

	my $dbh = db_connect($db_name);
	return 0 if !$dbh;
	my $recs = get_records_db($dbh,"SELECT * FROM pl_tracks ORDER BY position");

	$this->{shuffle} = $shuffle;

	my $first_track_id = '';
	if ($recs)
	{
		# sort em

		my $new_recs = $this->sort_shuffle_tracks($recs);

		# delete the old ones
		# and insert the new ones

		if (db_do($dbh,"DELETE FROM pl_tracks"))
		{
			my $index = 1;
			for my $rec (@$new_recs)
			{
				$first_track_id = $rec->{id} if $index == 1;

				$rec->{idx} = $index++;
				if (!insert_record_db($dbh,'pl_tracks',$rec))
				{
					error("Could not insert rec($rec->{idx}) pos($rec->{position}} id($rec->{id}) album_id($rec->{album_id}) ".
						  "into $this->{name}.db database");
					last;
				}
			}
		}
	}

	db_disconnect($dbh);

	# write the new shuff and index

	$this->{track_index} = @$recs ? 1 : 0;
	$this->{track_id} = $first_track_id;
	$this->{version}++;

	display($dbg_pl,0,"sortPlaylist() returning($this->{name},V_$this->{version},$this->{track_index},$this->{num_tracks}) track_id=$this->{track_id}");

	$this->saveToPlaylists();
	return $this;
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
	my ($this,$old_recs) = @_;
    # sort them according to shuffle

   	display($dbg_pl,0,"sort_shuffle_tracks($this->{name},$this->{shuffle})");

	my $new_recs = [];

    if ($this->{shuffle} == $SHUFFLE_TRACKS)
    {
		# temp_position is an in-memory only variable
		# the TRACKS will be re-written to the database
		# in a random order

        for my $rec (@$old_recs)
        {
            $rec->{temp_position} = 1 + int(rand($this->{num_tracks} + 1));
			# display($dbg_sort,1,"setting old_track($track->{position}) temp_position=$track->{temp_position}");
	    }
        for my $rec (sort {$a->{temp_position} <=> $b->{temp_position}} @$old_recs)
        {
			# display($dbg_sort,1,"pushing old_track($track->{position}) at temp_position=$track->{temp_position}");
            push @$new_recs,$rec;
        }
    }
    elsif ($this->{shuffle} == $SHUFFLE_ALBUMS)
    {
        my %albums;
        for my $rec (@$old_recs)
        {
			my $album_id = $rec->{album_id};
			if (!$albums{$album_id})
			{
				$albums{ $album_id} = int(rand($this->{num_tracks} + 1));
				# display($dbg_sort,1,"setting albums($album_id}) to $albums{$album_id}");
			}
		}
        for my $rec (sort {random_album(\%albums,$a,$b)} @$old_recs)
        {
			# display($dbg_sort,1,"pushing track album_id($track->{album_id}) position($track->{position})");
            push @$new_recs,$rec;
		}
    }

	# sort the records by the DEFAULT SORT ORDER

    else	# proper default sort order
    {
        for my $rec (sort {$a->{position} <=> $b->{position}} @$old_recs)
        {
			# display($dbg_sort,1,"pushing track($track->{position})");
            push @$new_recs,$rec;
        }
    }

   	display($dbg_pl,0,"sort_shuffle_tracks($this->{name}) finished");
	return $new_recs;
}




sub saveToPlaylists
{
	my ($this) = @_;
	display($dbg_pl,0,"saveToPlaylists($this->{id}) $this->{name}");

	my $library = findDevice($DEVICE_TYPE_LIBRARY,$this->{uuid});
	return !error("Could not find Library($this->{uuid})") if !$library;
	my $master_db_name = $library->dataDir()."/playlists.db";
	my $dbh = db_connect($master_db_name);
	return if !$dbh;

	if (!update_record_db($dbh,'playlists',$this,'id'))
	{
		error("Could not update playlist.db database");
		return;
	}
	db_disconnect($dbh);
}






1;
