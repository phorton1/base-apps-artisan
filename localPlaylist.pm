#!/usr/bin/perl
#---------------------------------------
# localPlaylist.pm
#---------------------------------------
# A Playlist has the following members:
#
#	num				- playlist number (id) within PLSource
# 	name			- playlists have, and are accessed by unique names
# 	shuffle			- shuffle mode
#   num_tracks		- number of tracks in the playlist
#   track_index		- current track index within the playlist
#
# And exists as a database file called playlists/name.db.
# which duplicates the Track records from the main local
# Artisan library.


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
my $dbg_pl_create = 0;


our $SHUFFLE_NONE = 0;
our $SHUFFLE_TRACKS = 1;
our $SHUFFLE_ALBUMS = 2;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		$SHUFFLE_NONE
		$SHUFFLE_TRACKS
		$SHUFFLE_ALBUMS
    );
}


my $pl_dbh;
	# this is a dangerous global non-rentrant database handle!

my $playlist_dir = "$data_dir/playlists";
mkdir $playlist_dir if (!(-d $playlist_dir));

my $playlists:shared = shared_clone([]);
my $playlists_by_name:shared = shared_clone({});



#------------------------------------
# client entry points
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


sub getTracks
{
	my ($this) = @_;
	return [] if !$this->startDB();
	my $tracks = get_records_db($pl_dbh,"SELECT * FROM tracks ORDER BY position");
	display($dbg_lpl+1,1,"getTracks() found ".scalar(@$tracks)." items in localPlaylist($this->{name})");
	$this->stopDB();
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


#-----------------------------------------------------
# Aggregate APIs
#-----------------------------------------------------

sub getPlaylist
{
	my ($name) = @_;
	my $playlist = $playlists_by_name->{$name};
	return $playlist;
}


sub getPlaylistNames()
	# returns a list of the names of the Playlists within this PLSource
{
	my $retval = [];
	display($dbg_lpl,0,"getPlaylistNames(".scalar(@$playlists).")");

	for my $playlist (@$playlists)
	{
		display($dbg_lpl+1,0,"adding $playlist->{name}");
		push @$retval,$playlist->{name};
	}
	return $retval;
}


sub setPlaylistInfo
	# shuffle = 0,1, or 2 or
	# track_index = 1..num_tracks
	# Returns the json for the playlist on success,
	# or {error=>msg} json on a failure
{
	my ($name,$field,$value) = @_;
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

	test => {
		num => 1,
		query =>
			"albums/Productions/Originals/Forgotten Space" },
	work => {
		num => 2,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Work" },
	dead => {
		num => 3,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Dead\t".
			"singles/Dead" },
    favorite => {
		num => 4,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Favorite\t".
			"singles/Favorite" },
    jazz => {
		num => 5,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Jazz/Old\t".
			"albums/Jazz/Soft\t".
			"albums/Jazz/Swing\t".
			"singles/Jazz" },
    blues => {
		num => 6,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Blues\t".
			"singles/Blues" },
	bands => {
		num => 7,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Productions/Bands\t".
			"albums/Productions/Other\t".
			"albums/Productions/Theo"},
	originals => {
		num => 8,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Productions/Originals" },
    world => {
		num => 9,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/World minus /Tipico\t".
			"singles/World" },
	orleans => {
		num => 10,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/NewOrleans\t".
			"albums/Zydeco" },
    reggae => {
		num => 11,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Reggae\t".
			"singles/Reggae" },
	rock => {
		num => 12,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Rock\t".
			"albums/SanDiegoLocals\t".
			"singles/Rock" },
    RandB => {
		num  => 13,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/R&B\t".
			"singles/R&B" },
    country => {
		num  => 14,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Country\t".
			"singles/Country" },
    classical => {
		num  => 15,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Classical minus /Baroque\t".
			"singles/Classical minus /Baroque" },
    xmas => {
		num  => 16,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Christmas\t".
			"singles/Christmas" },
    friends => {
		num  => 17,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Productions minus Sweardha Buddha\t".
			"albums/Friends" },
    folk => {
		num  => 18,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Folk\t".
			"singles/Folk" },
    compilations => {
		num  => 19,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Compilations\t".
			"singles/Compilations" },
    soundtrack => {
		num  => 20,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Soundtracks" },
    other => {
		num  => 21,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Other\t".
			"singles/Other" },
	station22 => { num => 22, query => "" },
	station23 => { num => 23, query => "" },
	station24 => { num => 24, query => "" },
	station25 => { num => 25, query => "" },
	station26 => { num => 26, query => "" },
	station27 => { num => 27, query => "" },
	station28 => { num => 28, query => "" },
	station29 => { num => 29, query => "" },
	station30 => { num => 30, query => "" },
	station31 => { num => 31, query => "" },
	station32 => { num => 32, query => "" },


);	# %default_playlists




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

	for my $name (sort {$default_playlists{$a}->{num} <=> $default_playlists{$b}->{num}} keys(%default_playlists))
	{
		my $exists = -f "$playlist_dir/$name.db" ? 1 : 0;
		my $rec = get_record_db($dbh,
			"SELECT * FROM playlists WHERE name='$name'");

		display($dbg_pl_create,1,"got($name) exists=$exists rec="._def($rec));

		# if record does not exist, we recreate the playlist from scratch
		# if the table doesnt exist, then we create it from the query
		# otherwise, we assume it is correct

		my $playlist;
		if (!$rec)
		{
			display($dbg_pl_create,2,"creating new playlist($name) from default");
			$playlist = localPlaylist->newFromDefault(
				$name,
				$default_playlists{$name});
			next if !$playlist;
			if (!insert_record_db($dbh,'playlists',$playlist))
			{
				error("Could not insert playlist($name) into database");
				next;
			}

		}
		elsif (!$exists)
		{
			display($dbg_pl_create,2,"updating playlist($name) from its table");
			$playlist = localPlaylist->newFromQuery($rec);
			next if !$playlist;
		}
		else
		{
			display($dbg_pl_create,2,"using existing playlist ".pad($name,20)." num_tracks=$rec->{num_tracks}");
			$playlist = localPlaylist->newFromRecAndTable($rec);
				# cannot fail
		}

		$playlists_by_name->{$name} = $playlist;
		push @$playlists,$playlist;
	}

	# finished

	display($dbg_pl_create,0,"static_init_playlists finished");
}







1;
