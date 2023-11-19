#!/usr/bin/perl
#---------------------------------------
# localPlaylist.pm
#---------------------------------------
# A Playlist has the following members:
#
#	id				- playlist id within library(uuid)
#   uuid			- uuid of the library holding the playlist
# 	name			- playlist title
# 	shuffle			- shuffle mode
#   num_tracks		- number of tracks in the playlist
#   track_index		- current track index within the playlist
#   [track_ids]		- the ids of the tracks when loaded in memory
#
# And exists as a database file called playlists/name.db.
# which duplicates the Track records from the main local
# Artisan library.
#
# track_index and shuffle members are accessed directly from Renderers.
# which also call the API
#
#	getTrackEntry()
#	sortPlaylist
#
# Whereas the other API are generally pass-thrus via the Library
#
#	getPlaylist
#   getPlaylists


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


my $dbg_lpl = 0;
my $dbg_pl_create = 0;



my $pl_dbh;
	# this is a dangerous global non-rentrant database handle!

my $playlist_dir = "$data_dir/playlists";
mkdir $playlist_dir if (!(-d $playlist_dir));

my $playlists:shared = shared_clone([]);
my $playlists_by_id:shared = shared_clone({});




#-------------------------------------
# API passed-thru from localLibrary
#-------------------------------------

sub getPlaylist
{
	my ($id) = @_;
	my $playlist = $playlists_by_id->{$id};
	return $playlist;
}


sub getPlaylists()
	# returns a list of the names of the Playlists within this PLSource
{
	return $playlists;
}


#------------------------------------
# Renderer API
#------------------------------------

sub getTrackId
{
    my ($this,$inc) = @_;
    display($dbg_lpl,0,"getTrackId($this->{name},$this->{track_index}) inc=$inc");
    $this->{track_index} += $inc;
    $this->{track_index} = 1 if $this->{track_index} > $this->{num_tracks};
    $this->{track_index} = $this->{num_tracks} if $this->{track_index} < 1;
    $this->saveToPlaylists();

	if (!$this->{track_ids})
	{
		return '' if !$this->startDB();
		$this->{track_ids} = shared_clone([]);
		my $recs = get_records_db($pl_dbh,"SELECT id FROM tracks ORDER BY path");
		display($dbg_lpl+1,1,"getTrackEntry() found ".scalar(@$recs)." items in localPlaylist($this->{name})");

		for my $rec (@$recs)
		{
			push @{$this->{track_ids}},$rec->{id};
		}
		$this->stopDB();
		$this->{num_tracks} = scalar(@{$this->{track_ids}});
		$this->fix_track_index();
		$this->saveToPlaylists();
		$this->sortPlaylist();
	}

	my $track_index = $this->{track_index};
	my $track_id = ${$this->{track_ids}}[$track_index-1];
    display($dbg_lpl+1,0,"getTrackId($track_index) returning track_id==$track_id");
    return $track_id;
}



#------------------------------------
# ContentDirectory1 API
#------------------------------------

sub getTracks
	# Called by ContentDirectory1 for Artisan BEING a MediaServer
	# NOT called in a local context.
	# As far as the rest of the world is concerned, the playlist is
	# sorted our way, and it is upto them to shuffle it if they want.
{
	my ($this) = @_;
	return [] if !$this->startDB();

	# we get the records by path, which is close, then sort them
	# in our DEFAULT SORT ORDER using by_pathof_tracknum_title()

	my $tracks = get_records_db($pl_dbh,"SELECT * FROM tracks ORDER BY path");
	display($dbg_lpl+1,1,"getTracks() found ".scalar(@$tracks)." items in localPlaylist($this->{name})");
	$this->stopDB();

	$tracks = [sort {by_pathof_tracknum_title($a,$b)} @$tracks];
	return $tracks;
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
	display($dbg_lpl+1,0,"saveToPlaylists($this->{id}) $this->{name}");

	my $dbh = sqlite_connect("$data_dir/playlists.db",'playlists','');
	if (!$dbh)
	{
		error("Could not connect to playlist.db database");
		return;
	}
	if (!update_record_db($dbh,'playlists',$this,'id'))
	{
		error("Could not update playlist.db database");
		return;
	}
	db_disconnect($dbh);
}


#--------------------------------------------------
# sort and shufffle
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
	# my $position = 1;
	$this->{track_ids} = shared_clone([]);
	for my $track (@$tracks)
	{
		# $track->{position} = $position++;
		return if !$this->insert_track($track);
		push @{$this->{track_ids}},$track->{id};
	}
	$this->stopDB();
	$this->{track_index} = 1;
	$this->fix_track_index();
	$this->saveToPlaylists();

	display($dbg_lpl,0,"sortPlaylist($name) finished");
}




sub by_pathof_tracknum_title
	# proper DEFAULT SORT ORDER is to sort by 'album',
	# as given by the pathOf($path) then, if a tracknum
	# is provided, by that, and finally by the track title.
{
    my ($a,$b) = @_;
    my $cmp = pathOf($a->{path}) cmp pathOf($b->{path});
    return $cmp if $cmp;
    $cmp = ($a->{tracknum} || 0) <=> ($b->{tracknum} || 0);
    return $cmp if $cmp;
    return $a->{title} cmp $b->{title};
}


sub within_random_album
	# sorting within a random index of albums
	# then, if a tracknum is provided, by that, and
	# finally by the track title.
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
		# position is an in-memory only variable
		# the TRACKS will be re-written to the database
		# in a random order

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
        for my $rec (sort {within_random_album(\%albums,$a,$b)} @$recs)
        {
            push @result,$rec;
        }
    }

	# sort the records by the DEFAULT SORT ORDER

    else	# proper default sort order
    {
        for my $rec (sort {by_pathof_tracknum_title($a,$b)} @$recs)
        {
            push @result,$rec;
        }
    }

   	display($dbg_lpl,0,"sort_shuffle_tracks($this->{name}) finished");
	return \@result;
}




#---------------------------
# DEFAULT PLAYLISTS
#---------------------------

my %default_playlists = (

	# playlist names may have spaces
	# but since they get sent along as parts of
	# urls, etc, they cannot have any special characters
	# except maybe dash and dot (certainly not ampersand)
	# which does not work unencoded in xml

	'001' => {
		id => '001',
		name => 'test',
		query =>
			"albums/Productions/Originals/Forgotten Space" },
	'002' => {
		name => 'work',
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Work" },
	'003' => {
		name => 'dead',
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Dead\t".
			"singles/Dead" },
    '004' => {
		name => 'favorite',
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Favorite\t".
			"singles/Favorite" },
    '005' => {
		name => 'jazz',
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Jazz/Old\t".
			"albums/Jazz/Soft\t".
			"albums/Jazz/Swing\t".
			"singles/Jazz" },
    '006' => {
		name => 'blues',
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Blues\t".
			"singles/Blues" },
	'007' => {
		name => 'bands',
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Productions/Bands\t".
			"albums/Productions/Other\t".
			"albums/Productions/Theo"},
	'008' => {
		name => 'originals',
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Productions/Originals" },
    '009' => {
		name => 'world',
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/World minus /Tipico\t".
			"singles/World" },
	'010' => {
		name => 'orleans',
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/NewOrleans\t".
			"albums/Zydeco" },
    '011' => {
		name => 'reggae',
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Reggae\t".
			"singles/Reggae" },
	'012' => {
		name => 'rock',
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Rock\t".
			"albums/SanDiegoLocals\t".
			"singles/Rock" },
     '013' => {
		name => 'RandB',
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/R&B\t".
			"singles/R&B" },
    '014' => {
		name => 'country',
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Country\t".
			"singles/Country" },
    '015' => {
		name => 'classical',
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Classical minus /Baroque\t".
			"singles/Classical minus /Baroque" },
    '016' => {
		name => 'xmas',
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Christmas\t".
			"singles/Christmas" },
    '017' => {
		name => 'friends',
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Productions minus Sweardha Buddha\t".
			"albums/Friends" },
    '018' => {
		name => 'folk',
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Folk\t".
			"singles/Folk" },
    '019' => {
		name => 'compilations',
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Compilations\t".
			"singles/Compilations" },
    '020' => {
		name => 'soundtrack',
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Soundtracks" },
    '021' => {
		name => 'other',
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Other\t".
			"singles/Other" },


);	# %default_playlists




#------------------------------------------
# Constructors
#------------------------------------------

sub new
{
	my ($class) = @_;
	my $this = shared_clone({
		id => '',
		uuid => $this_uuid,
		name => '',
		query => '',
		shuffle => 0,
		num_tracks => 0,
		track_index => 0,
	});
	bless $this,$class;
	return $this;
}


sub newFromRec
	# assumes the database already exists
	# and everything in rec is correct
{
	my ($class,$rec) = @_;
	display($dbg_lpl,1,"newFromRec($rec->{id}) $rec->{name}");
	my $this = $class->new();
	mergeHash($this,$rec);
	return $this;
}


sub newFromRecQuery
	# the record already exists, and we need to create the
	# table from the query ...
{
	my ($class,$rec) = @_;
	display($dbg_lpl,1,"newFromRecQuery($rec->{id}) $rec->{name}");
	my $this = $class->new();
	mergeHash($this,$rec);
	return if !$this->create_tracks_from_query();
	$this->saveToPlaylists();
	display($dbg_lpl,1,"newFromRecQuery($rec->{name}) finished");
	return $this;
}


sub newFromDefault
	# create a playlist from the default definition
	# wipes out and recreates the tracks.db by calling
	# create_tracks_from_query. The record will be
	# inserted into the main database by caller.
{
	my ($class,$id,$desc) = @_;
	display($dbg_lpl,1,"newFromDefault($id) $desc->{name}");

	my $this = $class->new();
	mergeHash($this,$desc);
	$this->{id} = $id;

	return if !$this->create_tracks_from_query();

	display($dbg_lpl,1,"newFromDefault($desc->{name}) finished");
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
		$query .= " ORDER BY path";
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

	# my $position = 1;
	for my $track (@$tracks)
	{
		# $track->{position} = $position++;
		return if !$this->insert_track($track);
	}
	$this->stopDB();

	warning(0,0,"CREATED EMPTY TRACKLIST($this->{name}) FROM QUERY!!")
		if (!@$tracks);

	display($dbg_lpl,1,"create_tracks_from_query($name) finished");
	return $this;
}


#-----------------------------------------
# initPlaylists
#-----------------------------------------

sub initPlaylists
{
	display($dbg_pl_create,0,"initPlaylists() started ...");

	my $main_db_name = "$data_dir/playlists.db";
	my $new_database = !-f $main_db_name;
	my $dbh = sqlite_connect($main_db_name,'playlists','');
	create_table($dbh,"playlists") if $new_database;

	# create any missing default playlists
	# or update the track databases if not found
	# the default playlists are assumed to be in the correct order.

	for my $id (sort {$a cmp $b} keys(%default_playlists))
	{
		my $desc = $default_playlists{$id};
		my $name = $desc->{name};

		my $exists = -f "$playlist_dir/$name.db" ? 1 : 0;
		my $rec = get_record_db($dbh, "SELECT * FROM playlists WHERE id='$id'");

		display($dbg_pl_create,1,"got($name) exists=$exists rec="._def($rec));

		# if record does not exist, we recreate the playlist from scratch
		# if the table doesnt exist, then we create it from the query
		# otherwise, we assume it is correct

		my $playlist;
		if (!$rec)
		{
			display($dbg_pl_create,2,"creating new playlist($name) from default");
			$playlist = localPlaylist->newFromDefault($id,$desc);
			next if !$playlist;
			if (!insert_record_db($dbh,'playlists',$playlist))
			{
				error("Could not insert playlist($name) into database");
				next;
			}

		}
		elsif (!$exists)
		{
			display($dbg_pl_create,2,"updating playlist($name) from rec's query");
			$playlist = localPlaylist->newFromRecQuery($rec);
			next if !$playlist;
		}
		else
		{
			display($dbg_pl_create,2,"using existing playlist ".pad($name,20)." num_tracks=$rec->{num_tracks}");
			$playlist = localPlaylist->newFromRec($rec);
				# cannot fail
		}

		$playlists_by_id ->{$id} = $playlist;
		push @$playlists,$playlist;
	}

	# finished

	display($dbg_pl_create,0,"static_init_playlists finished");
}



1;
