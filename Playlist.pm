#!/usr/bin/perl
#---------------------------------------
# Playlist.pm
#
# This module creates and/or maintains a collection of
# playlists, each of which consists of a header record
# and a database of tracks.
#
# Each playlist has a name, and optionally, a number.
#
# Playlists will be sorted for the client based on
# the number, and if the number is the same, the name.
#
# The list of playlists is kept in _data/playlists.db,
# and the tracks in a given playlist are kept in
# _data/playlists/name.db.
#
# This module has a set of default playlists that will be
# created if they are not found during startup.  Removing
# the playlists/track.db file will cause it to be regenerated
# from an SQL query. Removing the main playlists.db file
# will cause all default playlists to be regenerated, and
# main playlist records to be created for any other track
# database files that happen to be found.
#
# In addition to well known playlists like dead, and blues,
# the module currently creates a number of empty playlists
# called StationNN.
#
# There is currently only one entry point, static_init_playlists()
# that does everything.
#
# Current clients work with IDs and get the underlying tracks themselves


package Playlist;
use strict;
use warnings;
use threads;
use threads::shared;
use Library;
use Database;
use artisanUtils;
use SQLite;

our $SHUFFLE_NONE = 0;
our $SHUFFLE_TRACKS = 1;
our $SHUFFLE_ALBUMS = 2;

our $dbg_pl = 0;

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
        getPlaylist
        getPlaylists
    );
}


#-----------------------------
# VARIABLES
#-----------------------------

my $playlist_dir = "$cache_dir/playlists";
mkdir $playlist_dir if (!(-d $playlist_dir));

my $g_playlists = shared_clone([]);
my $g_playlists_by_name = shared_clone({});

my $track_dbh = undef;



#----------------------------------------
# Playlist API
#----------------------------------------

sub getPlaylists
{
	return $g_playlists;
}


sub getPlaylist
{
	my ($name) = @_;
	return $g_playlists_by_name->{$name};
}



sub start
{
	my ($this) = @_;
	my $db_path = "$playlist_dir/$this->{name}.db";
	display(0,0,"Playlist.start($this->{name}) path=$db_path");
	
	$track_dbh = sqlite_connect($db_path,'tracks','');
	if (!$track_dbh)
	{
		error("Could not connect to playlist tracks database: $this->{name}.db at\n$db_path");
		return;
	}
	return $this;
}


sub stop
{
	my ($this) = @_;
	if ($track_dbh)
	{
		db_disconnect($track_dbh);
	}
	$track_dbh = undef;
}



sub getNumTracks
{
    my ($this) = @_;
    return $this->{num_tracks};
}

sub getTrackIndex
{
    my ($this) = @_;
    return $this->{track_index};
}

sub setTrackIndex
{
    my ($this,$track_index) = @_;
    if ($track_index < 0 || $track_index > $this->{num_tracks})
    {
        error("setTrackIndex($track_index) out of range($this->{num_tracks})");
        return;
    }
    $this->{track_index} = $track_index;
}


sub getTrackID
	# Get the TrackID that corresponds to the track_index within the playlist.
	# Implemented as a write-thru cache in conjunction with save()
{
    my ($this,$track_index) = @_;
	return "" if $track_index == 0;
    if ($track_index <= 0 || $track_index > $this->{num_tracks})
    {
        error("getTrackID($track_index) out of range($this->{num_tracks})");
        return "";
    }
	
	# read cache
	
	if (!$this->{track_ids})
	{
		$this->start();
		my @ids;
		my $tracks = get_records_db($track_dbh,"SELECT id FROM tracks");
		display(0,0,"getTrackID() found ".scalar(@$tracks)." items in Playlist($this->{name})");
		
		for my $track (@$tracks)
		{
			push @ids,$track->{id};
		}
		$this->stop();
		$this->{track_ids} = shared_clone(\@ids);
		$this->{num_tracks} = scalar(@ids);
		$this->fix_track_index();
		$this->save();
	}
	
	my $track_id = ${$this->{track_ids}}[$track_index-1];
    display($dbg_pl,0,"getTrackID($track_index) returning $track_id");
    return $track_id;
}


    
sub getIncTrackID
{
    my ($this,$inc) = @_;
    
    $this->{track_index} += $inc;
    $this->{track_index} = 1 if $this->{track_index} > $this->{num_tracks};
    $this->{track_index} = $this->{num_tracks} if $this->{track_index} < 1;
    
    $this->save();
    
    return $this->getTrackID($this->{track_index});
}


sub getNextTrackID
{
    my ($this) = @_;
    return $this->getIncTrackID(1);
}


sub getPrevTrackID
{
    my ($this) = @_;
    return $this->getIncTrackID(-1);
}



sub sortPlaylist
{
	my ($this) = @_;
	my $name = $this->{name};
	
	display(0,0,"sortPlaylist($name)");
	
	$this->start();
	my $tracks = get_records_db($track_dbh,"SELECT * FROM tracks");
	db_do($track_dbh,"DELETE FROM tracks");
	$tracks = $this->sort_shuffle_tracks($tracks);
	my $position = 1;
	$this->{track_ids} = shared_clone([]);
	for my $track (@$tracks)
	{
		# display(0,0,"after sorting position($position)=$track->{title}");
		
		$track->{position} = $position++;
		return if !$this->insert_track($track);
		push @{$this->{track_ids}},$track->{id};
	}
	$this->stop();
	$this->{track_index} = 1;
	$this->fix_track_index();
	$this->save();

	display(0,0,"sortPlaylist($name) finished");
}



sub save
{
	my ($this) = @_;
	display(0,0,"save Playlist($this->{name})");
	
	my $dbh = sqlite_connect("$cache_dir/playlists.db",'playlists','');
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



sub insert_track
{
	my ($this,$track) = @_;
	return insert_record_db($track_dbh,'tracks',$track);
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
	station7 => { num => 7, query => "" },
	station8 => { num => 8, query => "" },
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
    'RandB' => {
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


    

#------------------------------------------
# Construction
#------------------------------------------


sub create_table
{
	my ($dbh,$table) = @_;
	display(0,0,"create_table($table)");
	my $def = join(',',@{$artisan_field_defs{$table}});
	$def =~ s/\s+/ /g;
	$dbh->do("CREATE TABLE $table ($def)");
}


sub fix_track_index
{
	my ($this) = @_;
	$this->{track_index} = 0 if !$this->{num_tracks};
	$this->{track_index} = 1 if !$this->{track_index} && $this->{num_tracks};
}

	
sub new_from_default
	# add a playlist from a default definition
	# wipes out and recreates the tracks.db
	# not a shared memory guy
{
	my ($class,$dbh,$name,$def) = @_;
	display($dbg_pl,0,"new_from_default($name) ...");

	$def->{name} = $name;
	my $this = {};
	mergeHash($this,$def);
	bless $this,$class;

	$this->{shuffle} ||= 0;
	$this->{track_index} = 0;
	
	$this->create_tracks_from_query();
	$this->fix_track_index();

	# add the record to the database
	
	if (!insert_record_db($dbh,'playlists',$this))
	{
		$this = undef;
		error("Could not insert record into database");
	}
	
	display($dbg_pl,0,"new_from_default($name) finished");
	return $this;
}	




sub tracks_from_db
	# given an existing tracks.db file
	# read in, and count the tracks in it
	# set num_tracks and
	# set track_index to 0 / 1 as needed
{
	my ($this) = @_;
	my $name = $this->{name};
	display($dbg_pl,0,"tracks_from_db $name ...");

	$this->start();
	my $tracks = get_records_db($track_dbh,"SELECT * FROM tracks ORDER BY position");
	$this->stop();
	
	$this->{num_tracks} = @$tracks;
	display(0,1,"found $this->{num_tracks} tracks");
	$this->fix_track_index();

	display($dbg_pl,0,"tracks_from_db $name finished");
}




sub create_tracks_from_query
	# Creates the database (and 'tracks' table)
	# for the playlist and populates it from the query.
	# Wipes out the tracks.db file if it exists,
	# which it should not in my initial usage.
{
    my ($this) = @_;
	my $name = $this->{name};
	my $query = $this->{query};
	
	display($dbg_pl,0,"create_tracks_from_query($name) ...");
	display($dbg_pl,1,"query=$query");
	
	$this->{num_tracks} = 0;
	$this->{track_index} = 0;
	
	# connect to the Library database

    my $library_dbh = db_connect();

	# get the records by path
	
	my $tracks = [];
	my @paths = split("\t",$this->{query});
    for my $path (@paths)
    {
		display($dbg_pl,1,"path=$path");
		
		my $query = "SELECT * FROM tracks WHERE instr(path,?) > 0";
		my $exclude = ($path =~ s/\s+minus\s+(.*)$//) ? $1 : '';
		my $args = [ $path ]; # ."/" ];
		if ($exclude)
		{
			display(0,2,"exclude='$exclude'");
			push @$args,$exclude;
			$query .= " AND instr(path,?) <= 0";
		}
		$query .= " ORDER BY position";
			# "genre,album_artist,album_title,tracknum,title";
		my $recs = get_records_db($library_dbh,$query,$args);
		display($dbg_pl,2,"found ".scalar(@$recs)." tracks from query path=$path");
		$this->{num_tracks} += @$recs;
		push @$tracks,@$recs;
	}

	# disconnect from the databases

	display($dbg_pl,1,"disconnecting ...");
    db_disconnect($library_dbh);
	$this->fix_track_index();
	
	# wipe out and recreate the tracks.db database

	display(0,0,"inserting ".scalar(@$tracks)." items in new Playlist($this->{name})");
	
	# unlink "$playlist_dir/$name.db";
	$this->start();
	create_table($track_dbh,"tracks");
	$tracks = $this->sort_shuffle_tracks($tracks);
	
	my $position = 1;
	for my $track (@$tracks)
	{
		$track->{position} = $position++;
		return if !$this->insert_track($track);
	}
	$this->stop();

	warning(0,0,"CREATED EMPTY TRACKLIST($this->{name}) FROM QUERY!!")
		if (!@$tracks);

	display($dbg_pl,0,"create_tracks_from_query($name) finished");
}


sub sort_shuffle_tracks
{
	my ($this,$recs) = @_;
    # sort them according to shuffle

   	display($dbg_pl,0,"sort_shuffle_tracks($this->{name})");

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

   	display($dbg_pl,0,"sort_shuffle_tracks($this->{name}) finished");
	return \@result;
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
    



sub update_db_counts
{
	my ($this,$dbh) = @_;
	$dbh->do("UPDATE playlists SET ".
		"num_tracks=$this->{num_tracks},".
		"track_index=$this->{track_index} ".
		"WHERE name='$this->{name}'");
}



sub static_init_playlists
{
	display(0,0,"static_init_playlists started ...");
	my $new_database = ! -f "$cache_dir/playlists.db";
	my $dbh = sqlite_connect("$cache_dir/playlists.db",'playlists','');
	
	if ($new_database)
	{
		create_table($dbh,"playlists");
	}
	
	# create any missing default playlists
	# or update the track databases if not found

	display(0,1,"check/create default playlists");
	for my $name (keys(%default_playlists))
	{
		my $playlist = get_record_db($dbh,
			"SELECT * FROM playlists WHERE name='$name'");
		
		display(0,1,"got($name)="._def($playlist));
		
		if (!$playlist)
		{
			display(0,1,"creating new playlist($name) from the default");
			$playlist = Playlist->new_from_default(
				$dbh,
				$name,
				$default_playlists{$name});
		}
		elsif (-f "$playlist_dir/$name.db")
		{
			bless $playlist,"Playlist";
			
			# record and tracks database exist
			# we asume this means everythings good
			# this code would reset the header num_tracks
			# from the actual database.

			if (0)	
			{
				display(0,1,"getting playlist($name) from existing databse");
				$playlist->tracks_from_db();
				$playlist->update_db_counts($dbh);
			}
		}
		elsif (1)	
		{
			display(0,1,"recreating playlist($name) tracks from query");
			bless $playlist,"Playlist";
			$playlist->create_tracks_from_query();
			$playlist->update_db_counts($dbh);
		}
	}
	
	# now do the query and add the playlists to memory
	
	my $recs = get_records_db($dbh,"SELECT * FROM playlists ORDER BY num,name");
	display(0,1,"got ".scalar(@$recs)." playlists");
	for my $rec (@$recs)
	{
		my $playlist = shared_clone($rec);
		bless $playlist,"Playlist";
		push @{$g_playlists},$playlist;
		$g_playlists_by_name->{$rec->{name}} = $playlist;
	}
	
	# finished
	
	display(0,0,"static_init_playlists finished");
}


     


#---------------------------------------
# testing
#---------------------------------------

if (0)
{
	static_init_playlists();
}


1;
