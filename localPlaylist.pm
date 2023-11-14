#!/usr/bin/perl
#---------------------------------------
# localPlaylist.pm
#---------------------------------------
# A Playlist has the following members:
#
#   [uuid]			- uuid of the PLSource hosting the playlist
#	num				- playlist number (id) within PLSource
# 	name			- playlists have, and are accessed by unique names
# 	shuffle			- shuffle mode
#   num_tracks		- number of tracks in the playlist
#   track_index		- current track index within the playlist
#
# And exists as a database file called playlists/name.db.
# which currently duplicates the Track records from the main local
# Artisan library.  This will be changed so that the playlist entry
# consists of the following fields:
#
#   [uuid]			- uuid of the Library holding the track
#	index		    - sorted position within playlist
#   track_id		- id of Track within parent library
#   track_num		- track number within parent album
#	path			- path to the track, implying folder structure for sorting by album name
#
# of which, only the first three are returned by the API.

package localPlaylist;
use strict;
use warnings;
use threads;
use threads::shared;
use SQLite;
use Database;
use artisanUtils;
use DeviceManager;
	# temporary? kludge to support new API
	# by using $local_library


my $dbg_lpl = 1;


our $SHUFFLE_NONE = 0;
our $SHUFFLE_TRACKS = 1;
our $SHUFFLE_ALBUMS = 2;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		$playlist_dir
		$SHUFFLE_NONE
		$SHUFFLE_TRACKS
		$SHUFFLE_ALBUMS
    );
}


my $pl_dbh;
	# this is a dangerous global non-rentrant database handle!

our $playlist_dir = "$data_dir/playlists";
mkdir $playlist_dir if (!(-d $playlist_dir));


#------------------------------------
# single client entry point
#------------------------------------

sub getTrackEntry
{
    my ($this,$inc) = @_;
    display($dbg_lpl,0,"getTrackEntry($this->{name},$this->{track_index}) inc=$inc");
    $this->{track_index} += $inc;
    $this->{track_index} = 1 if $this->{track_index} > $this->{num_tracks};
    $this->{track_index} = $this->{num_tracks} if $this->{track_index} < 1;
    $this->saveToPlaylists();

	if (!$this->{track_ids})
	{
		return '' if !$this->startDB();
		my $ids = shared_clone([]);
		my $tracks = get_records_db($pl_dbh,"SELECT id FROM tracks ORDER BY position");
		display($dbg_lpl+1,1,"getTrackEntry() found ".scalar(@$tracks)." items in localPlaylist($this->{name})");

		for my $track (@$tracks)
		{
			push @$ids,$track->{id};
		}
		$this->stopDB();
		$this->{track_ids} = $ids;
		$this->{num_tracks} = scalar(@$ids);
		$this->fix_track_index();
		$this->saveToPlaylists();
	}

	my $track_index = $this->{track_index};
	my $track_id = ${$this->{track_ids}}[$track_index-1];
	my $track = $local_library->getTrack($track_id);
    if (!$track)
    {
        error("getTrackEntry($track_index) could not get kluge track($track_id}");
        return;
    }

	# temporary kludge to support new API

	my $entry = {
		index => $track_index,		# index of track within playlist
		id    => $track_id,			# id of track within library
		uuid  => $local_library->{uuid} };	# Library uuid

    display($dbg_lpl+1,0,"getTrackEntry($track_index) returning local ($track_index,$track_id)");
    return $entry;
}


#------------------------------------
# Database Operations
#------------------------------------

sub stopDB
{
	my ($this) = @_;
	db_disconnect($pl_dbh) if $pl_dbh;
	$pl_dbh = undef;
}


sub startDB
{
	my ($this) = @_;
	my $db_path = "$playlist_dir/$this->{name}.db";
	$pl_dbh = sqlite_connect($db_path,'tracks','');
	if (!$pl_dbh)
	{
		error("Could not connect to localPlaylist($this->{name}) at $db_path");
		return;
	}
	return $this;
}


sub insert_track
{
	my ($this,$track) = @_;
	# display($dbg_lpl+1,2,"insert_track($track->{id},$track->{title})");
	return insert_record_db($pl_dbh,'tracks',$track);
}


sub fix_track_index
{
	my ($this) = @_;
	$this->{track_index} = 0 if !$this->{num_tracks};
	$this->{track_index} = 1 if !$this->{track_index} && $this->{num_tracks};
}


sub saveToPlaylists
{
	my ($this) = @_;
	display($dbg_lpl+1,0,"saveToPlaylists($this->{name})");

	my $dbh = sqlite_connect("$data_dir/playlists.db",'playlists','');
	if (!$dbh)
	{
		error("Could not connect to playlist.db database");
		return;
	}
	if (!update_record_db($dbh,'playlists',$this,'name'))
	{
		error("Could not update playlist.db database");
		return;
	}
	db_disconnect($dbh);
}


#--------------------------------------------------
# sort and shuff
#--------------------------------------------------


sub sortPlaylist
{
	my ($this) = @_;
	my $name = $this->{name};

	display($dbg_lpl,0,"sortPlaylist($name)");

	return if !$this->startDB();
	my $tracks = get_records_db($pl_dbh,"SELECT * FROM tracks");
	db_do($pl_dbh,"DELETE FROM tracks");
	$tracks = $this->sort_shuffle_tracks($tracks);
	my $position = 1;
	$this->{track_ids} = shared_clone([]);
	for my $track (@$tracks)
	{
		$track->{position} = $position++;
		return if !$this->insert_track($track);
		push @{$this->{track_ids}},$track->{id};
	}
	$this->stopDB();
	$this->{track_index} = 1;
	$this->fix_track_index();
	$this->saveToPlaylists();

	display($dbg_lpl,0,"sortPlaylist($name) finished");
}


sub by_album_tracknum
{
    my ($albums,$a,$b) = @_;
    my $cmp = $albums->{$a->{parent_id}} <=> $albums->{$b->{parent_id}};
    return $cmp if $cmp;
    $cmp = ($a->{tracknum} || 0) <=> ($b->{tracknum} || 0);
    return $cmp if $cmp;
    return $a->{title} cmp $b->{title};
}


sub sort_shuffle_tracks
{
	my ($this,$recs) = @_;
    # sort them according to shuffle

   	display($dbg_lpl,0,"sort_shuffle_tracks($this->{name})");

    my @result;
    if ($this->{shuffle} == $SHUFFLE_TRACKS)
    {
        for my $rec (@$recs)
        {
            $rec->{position} = 1 + int(rand($this->{num_tracks} + 1));
        }
        for my $rec (sort {$a->{position} <=> $b->{position}} @$recs)
        {
            push @result,$rec;
        }
    }
    elsif ($this->{shuffle} == $SHUFFLE_ALBUMS)
    {
        my %albums;
        for my $rec (@$recs)
        {
            $albums{ $rec->{parent_id} } = int(rand($this->{num_tracks} + 1));
        }
        for my $rec (sort {by_album_tracknum(\%albums,$a,$b)} @$recs)
        {
            push @result,$rec;
        }
    }
    else	# the default sort order is by path
    {
        # @result = map($_,@$recs);
        for my $rec (sort {$a->{path} cmp $b->{path}} @$recs)
        {
            push @result,$rec;
        }
    }

   	display($dbg_lpl,0,"sort_shuffle_tracks($this->{name}) finished");
	return \@result;
}



#------------------------------------------
# Constructors
#------------------------------------------

sub new
{
	my ($class) = @_;
	my $this = shared_clone({
		num => 0,
		name => '',
		query => '',
		shuffle => 0,
		num_tracks => 0,
		track_index => 0,
	});
	bless $this,$class;
	return $this;
}


sub newFromRecAndTable
	# assumes the database already exists
	# and everything in rec is correct
{
	my ($class,$rec) = @_;
	display($dbg_lpl,1,"newFromRecAndTable($rec->{name})");
	my $this = $class->new();
	mergeHash($this,$rec);
	return $this;
}


sub newFromQuery
	# the record already exists, and we need to create the
	# table from the query ...
{
	my ($class,$rec) = @_;
	display($dbg_lpl,1,"newFromQuery($rec->{name})");
	my $this = $class->new();
	mergeHash($this,$rec);
	return if !$this->create_tracks_from_query();
	$this->saveToPlaylists();
	return $this;
}



sub newFromDefault
	# create a playlist from the default definition
	# wipes out and recreates the tracks.db by calling
	# create_tracks_from_query. The record will be
	# inserted into the main database by caller.
{
	my ($class,$name,$def) = @_;
	display($dbg_lpl,1,"newFromDefault($name) ...");

	my $this = $class->new();
	mergeHash($this,$def);
	$this->{name} = $name;

	return if !$this->create_tracks_from_query();

	display($dbg_lpl,1,"newFromDefault($name) finished");
	return $this;
}




sub create_tracks_from_query
	# Creates the database playlists/name.db, with
	# 	a 'tracks' table
	# and populates it with records from the main library
	#   using the query.
	# Wipes out the tracks.db file if it exists,
	# which it should not in my initial usage.
{
    my ($this) = @_;
	my $name = $this->{name};
	my $query = $this->{query};

	display($dbg_lpl,1,"create_tracks_from_query($name) ...");
	display($dbg_lpl,2,"query=$query");

	$this->{num_tracks} = 0;
	$this->{track_index} = 0;

	# connect to the local Artisan (Library) database

    my $artisan_dbh = db_connect();

	# get the records by path

	my $tracks = [];
	my @paths = split("\t",$this->{query});
    for my $path (@paths)
    {
		display($dbg_lpl,1,"path=$path");

		my $query = "SELECT * FROM tracks WHERE instr(path,?) > 0";
		my $exclude = ($path =~ s/\s+minus\s+(.*)$//) ? $1 : '';
		my $args = [ $path ]; # ."/" ];
		if ($exclude)
		{
			display($dbg_lpl,3,"exclude='$exclude'");
			push @$args,$exclude;
			$query .= " AND instr(path,?) <= 0";
		}
		$query .= " ORDER BY position";
			# "genre,album_artist,album_title,tracknum,title";
		my $recs = get_records_db($artisan_dbh,$query,$args);
		display($dbg_lpl,3,"found ".scalar(@$recs)." tracks from query path=$path");
		$this->{num_tracks} += @$recs;
		push @$tracks,@$recs;
	}

	# disconnect from the databases

	display($dbg_lpl,2,"disconnecting ...");
    db_disconnect($artisan_dbh);
	$this->fix_track_index();

	# wipe out and recreate the tracks.db database

	display($dbg_lpl,1,"inserting ".scalar(@$tracks)." items in new Playlist($this->{name})");

	# create new table

	unlink "$playlist_dir/$name.db";
	$this->startDB();
	create_table($pl_dbh,"tracks");
	$tracks = $this->sort_shuffle_tracks($tracks);

	my $position = 1;
	for my $track (@$tracks)
	{
		$track->{position} = $position++;
		return if !$this->insert_track($track);
	}
	$this->stopDB();

	warning(0,0,"CREATED EMPTY TRACKLIST($this->{name}) FROM QUERY!!")
		if (!@$tracks);

	display($dbg_lpl,1,"create_tracks_from_query($name) finished");
	return $this;
}




1;
