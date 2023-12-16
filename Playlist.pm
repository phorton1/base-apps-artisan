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
#   query			- my SQL query, blank for remotePlaylists
# 	shuffle			- shuffle mode
#   num_tracks		- number of tracks in the playlist
#   track_index		- current track index within the playlist or 0 if no tracks
#   track_id		- track_id corresponding to the track_index or '' if no tracksid
#	version		    - version number is bumped on every sort and getPlaylistTrack index change.
#
# The Tracks are kept in a named.db file a 'playlists' subdirectory relative to
# the playlists.db file with an additional 'pl_idx' integer indicating its sorted
# position within the current shuffle mode.
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
	#  0 = function heaaders
	# -1 = big steps
	# -2 = gruesome details
my $dbg_sort = 0;
	# display() calls currently commented out
	# 0 == gruesome details


sub getPlaylists
{
	my ($library) = @_;
	display($dbg_pl+1,0,"getPlaylists($library->{name})");

	my $master_dir = $library->dataDir();
	my $master_db_name = "$master_dir/playlists.db";

	display($dbg_pl+2,1,"getting records from $master_db_name");

	my $dbh = db_connect($master_db_name);
	return [] if !$dbh;

	my $recs = get_records_db($dbh,"SELECT * FROM playlists ORDER BY id") || [];
	db_disconnect($dbh);
	display($dbg_pl+1,1,"found ".scalar(@$recs)." records");

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


sub dbg_info
{
	my ($this,$extra_dbg) = @_;
	$extra_dbg ||= 0;

	return "("._def($this).")" if !$this;

	my $name = "($this->{uuid}:$this->{name}" ;
	$name .= ",V_$this->{version},$this->{track_index},$this->{num_tracks}"
		if $dbg_pl < $extra_dbg;
	$name .= ",S_$this->{shuffle},$this->{track_id}"
		if $dbg_pl < $extra_dbg-1;
	$name .= ")";
	return $name;
}


sub getPlaylist
{
	my ($library,$id,$no_error) = @_;
	display($dbg_pl+1,0,"getPlaylist($library->{name},$id)");

	my $master_dir = $library->dataDir();
	my $playlist_db = $library->dataDir() . "/playlists.db";
	display($dbg_pl+1,1,"playlist_db=$playlist_db");

	my $playlist_dbh = db_connect($playlist_db);
	return if !$playlist_dbh;

	my $rec = get_record_db($playlist_dbh,"SELECT * FROM playlists WHERE id='$id'");
	db_disconnect($playlist_dbh);
	display($dbg_pl+1,1,"found rec="._def($rec));

	# clone the record and bless it

	my $playlist;
	if ($rec)
	{
		$playlist = shared_clone($rec);
		bless $playlist,'Playlist';
		$playlist->{library_name} = $library->{name};
	}
	elsif (!$no_error)
	{
		error("Could not find playlist($library->{name},$id)");
	}

	display($dbg_pl,0,"getPlaylist() returning".dbg_info($playlist,2));
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

	display($dbg_pl,0,"getPlaylistTrack($version,$mode,$orig_index) caled on".dbg_info($this));

    display($dbg_pl+1,1,"library($this->{uuid})");	# renderer($renderer_uuid)");
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
			display($dbg_pl+1,1,"getting index($index) from $named_db");
			my $dbh = db_connect($named_db);
			return if !$dbh;

			my $rec = get_record_db($dbh,"SELECT * FROM tracks WHERE pl_idx='$index'");
			db_disconnect($dbh);
			display($dbg_pl+1,1,"found rec="._def($rec));

			$this->{track_index} = $index;
			$this->{track_id} = $rec ? $rec->{id} : '';
			$this->{version}++;

			$this->saveToPlaylists();

			display($dbg_pl,0,"getPlaylistTrack() returning".dbg_info($this,2));
		}
		else
		{
			display($dbg_pl,0,"getPlaylistTrack() no_change".dbg_info($this,2));
		}
	}
	else
	{
		warning($dbg_pl,0,"getPlaylistTrack() skipping request".dbg_info($this,2));
	}
	return $this;
}



sub sortPlaylist
	# used to be used to read the cache into memory, but that is no longer the case.
	# always provided with $shuffle parameter from UI and we always re-sort the list
	# and it always needs writing

{
	my ($this,$shuffle) = @_;				# $renderer_uuid
	display($dbg_pl,0,"sortPlaylist($shuffle) on playlist".dbg_info($this));
	my $playlists_dir = getLibraryPlaylistsDir($this->{uuid});
	return if !$playlists_dir;

	my $db_name = "$playlists_dir/$this->{name}.db";

	# connect to the named.db file
	# and get the records

	my $dbh = db_connect($db_name);
	return 0 if !$dbh;
	my $recs = get_records_db($dbh,"SELECT * FROM tracks ORDER BY position");

	$this->{shuffle} = $shuffle;

	my $first_track_id = '';
	if ($recs)
	{
		# sort em

		my $new_recs = $this->sort_shuffle_tracks($recs);

		# delete the old ones
		# and insert the new ones

		if (db_do($dbh,"DELETE FROM tracks"))
		{
			my $index = 1;
			for my $rec (@$new_recs)
			{
				$first_track_id = $rec->{id} if $index == 1;

				$rec->{pl_idx} = $index++;
				if (!insert_record_db($dbh,'tracks',$rec))
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

	display($dbg_pl,0,"sortPlaylist() returning".dbg_info($this,2));

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
	display($dbg_pl,0,"saveToPlaylists".dbg_info($this));

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
