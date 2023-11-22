#!/usr/bin/perl
#---------------------------------------
# localPlaylist.pm
#---------------------------------------
# Builds the master playlists for the localLibrary.
# Note that this is NOT a derived class.
# It merely builds the database(s).


package localPlaylist;
use strict;
use warnings;
use threads;
use threads::shared;
use SQLite;
use Database;
use artisanUtils;
use Playlist;


my $dbg_pl_create = 0;
	#  0 == show init_playlists header
	# -1 == show playlist creation
	# -2 == show playlist creation details



my $playlist_dir = "$data_dir/playlists";
mkdir $playlist_dir if (!(-d $playlist_dir));


#----------------------------------
# support for base Playlist
#----------------------------------

sub playlistDir
{
	return $playlist_dir;
}


#---------------------------
# DEFAULT PLAYLISTS
#---------------------------
# The master playlists all start as un-shuffled.
# The shuffle state is retained in the per-library-renderer copies.


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
		query =>
			"albums/Work" },
	'003' => {
		name => 'dead',
		query =>
			"albums/Dead\t".
			"singles/Dead" },
    '004' => {
		name => 'favorite',
		query =>
			"albums/Favorite\t".
			"singles/Favorite" },
    '005' => {
		name => 'jazz',
		query =>
			"albums/Jazz/Old\t".
			"albums/Jazz/Soft\t".
			"albums/Jazz/Swing\t".
			"singles/Jazz" },
    '006' => {
		name => 'blues',
		query =>
			"albums/Blues\t".
			"singles/Blues" },
	'007' => {
		name => 'bands',
		query =>
			"albums/Productions/Bands\t".
			"albums/Productions/Other\t".
			"albums/Productions/Theo"},
	'008' => {
		name => 'originals',
		query =>
			"albums/Productions/Originals" },
    '009' => {
		name => 'world',
		query =>
			"albums/World minus /Tipico\t".
			"singles/World" },
	'010' => {
		name => 'orleans',
		query =>
			"albums/NewOrleans\t".
			"albums/Zydeco" },
    '011' => {
		name => 'reggae',
		query =>
			"albums/Reggae\t".
			"singles/Reggae" },
	'012' => {
		name => 'rock',
		query =>
			"albums/Rock\t".
			"albums/SanDiegoLocals\t".
			"singles/Rock" },
     '013' => {
		name => 'RandB',
		query =>
			"albums/R&B\t".
			"singles/R&B" },
    '014' => {
		name => 'country',
		query =>
			"albums/Country\t".
			"singles/Country" },
    '015' => {
		name => 'classical',
		query =>
			"albums/Classical minus /Baroque\t".
			"singles/Classical minus /Baroque" },
    '016' => {
		name => 'xmas',
		query =>
			"albums/Christmas\t".
			"singles/Christmas" },
    '017' => {
		name => 'friends',
		query =>
			"albums/Productions minus Sweardha Buddha\t".
			"albums/Friends" },
    '018' => {
		name => 'folk',
		query =>
			"albums/Folk\t".
			"singles/Folk" },
    '019' => {
		name => 'compilations',
		query =>
			"albums/Compilations\t".
			"singles/Compilations" },
    '020' => {
		name => 'soundtrack',
		query =>
			"albums/Soundtracks" },
    '021' => {
		name => 'other',
		query =>
			"albums/Other\t".
			"singles/Other" },


);	# %default_playlists




#------------------------------------------
# Pseudo Constructors
#------------------------------------------

sub updateFromRecQuery
	# the record already exists, and we need to create the
	# table from the query ...
{
	my ($rec) = @_;
	display($dbg_pl_create+2,1,"updateFromRecQuery($rec->{id}) $rec->{name}");
	return if !create_tracks_from_query($rec);
	display($dbg_pl_create+2,1,"updateFromRecQuery($rec->{id}) finished");
	return 1;
}


sub newFromDefault
	# create a playlist from the default definition
	# wipes out and recreates the tracks.db by calling
	# create_tracks_from_query. The record will be
	# inserted into the main database by caller.
{
	my ($id,$desc) = @_;
	display($dbg_pl_create+2,1,"newFromDefault($id) $desc->{name}");

	my $rec = {
		id => '',
		uuid => $this_uuid,
		name => '',
		query => '',
		shuffle => 0,
		num_tracks => 0,
		track_index => 0,
	};

	mergeHash($rec,$desc);
	$rec->{id} = $id;

	return if !create_tracks_from_query($rec);

	display($dbg_pl_create+2,1,"newFromDefault($desc->{name}) finished");
	return $rec;
}


sub default_sort
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


sub create_tracks_from_query
	# Creates the database playlists/name.db, with
	# 	a 'tracks' table
	# and populates it with records from the main library
	#   using the query.
	# Wipes out the tracks.db file if it exists,
	# which it should not in my initial usage.
{
    my ($rec) = @_;
	my $name = $rec->{name};
	my $query = $rec->{query};

	display($dbg_pl_create+2,1,"create_tracks_from_query($name) ...");
	display($dbg_pl_create+2,2,"query=$query");

	$rec->{num_tracks} = 0;
	$rec->{track_index} = 0;

	# connect to the local Artisan (Library) database

    my $artisan_dbh = db_connect();

	# get the records by path

	my $tracks = [];
	my @paths = split("\t",$rec->{query});
    for my $path (@paths)
    {
		display($dbg_pl_create+2,1,"path=$path");

		my $query = "SELECT * FROM tracks WHERE instr(path,?) > 0";
		my $exclude = ($path =~ s/\s+minus\s+(.*)$//) ? $1 : '';
		my $args = [ $path ]; # ."/" ];
		if ($exclude)
		{
			display($dbg_pl_create+2,3,"exclude='$exclude'");
			push @$args,$exclude;
			$query .= " AND instr(path,?) <= 0";
		}
		$query .= " ORDER BY path";
			# "genre,album_artist,album_title,tracknum,title";
		my $recs = get_records_db($artisan_dbh,$query,$args);
		display($dbg_pl_create+2,3,"found ".scalar(@$recs)." tracks from query path=$path");
		$rec->{num_tracks} += @$recs;
		push @$tracks,@$recs;
	}

	# disconnect from the databases

    db_disconnect($artisan_dbh);

	# fix the track_index

	$rec->{track_index} = 0 if !$rec->{num_tracks};
	$rec->{track_index} = 1 if !$rec->{track_index} && $rec->{num_tracks};

	# wipe out and recreate the tracks.db database

	display($dbg_pl_create+2,1,"inserting ".scalar(@$tracks)." items in new Playlist($rec->{name})");

	# create new table

	my $db_name = "$playlist_dir/$name.db";
	unlink $db_name;
	my $dbh = db_connect($db_name);
	return if !$dbh;

	create_table($dbh,"pl_tracks");

	my $position = 1;
	for my $track (sort {default_sort($a,$b)} @$tracks)
	{
		my $pl_track = {
			id => $track->{id},
			album_id => $track->{parent_id},
			position => $position++ };
		if (!insert_record_db($dbh,'pl_tracks',$pl_track))
		{
			error("Could not insert pl_track($track->{id}==$track->{title}) into $rec->{name}.db database");
			return;
		}
	}
	db_disconnect($dbh);

	warning(0,0,"CREATED EMPTY TRACKLIST($rec->{name}) FROM QUERY!!")
		if !@$tracks;

	display($dbg_pl_create+2,1,"create_tracks_from_query($name) finished");
	return 1;
}




#-----------------------------------------
# initPlaylists
#-----------------------------------------

sub initPlaylists
{
	display($dbg_pl_create,0,"initPlaylists() started ...");

	my $main_db_name = "$data_dir/playlists.db";
	my $new_database = !-f $main_db_name;
	my $dbh = db_connect($main_db_name);
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

		display($dbg_pl_create+2,1,"got($name) exists=$exists rec="._def($rec));

		# if record does not exist, we recreate the playlist from scratch
		# if the table doesn't exist, then we create it from the query
		# otherwise, we assume it is correct and do nothing

		if (!$rec)
		{
			display($dbg_pl_create+1,2,"creating new playlist($name) from default");
			$rec = newFromDefault($id,$desc);
			next if !$rec;
			if (!insert_record_db($dbh,'playlists',$rec))
			{
				error("Could not insert playlist($name) into database");
				next;
			}
		}
		elsif (!$exists)
		{
			display($dbg_pl_create+1,2,"updating playlist($name) from rec's query");
			next if !updateFromRecQuery($rec);
			if (!update_record_db($dbh,'playlists',$rec,'id'))
			{
				error("Could not update playlist.db database");
				return;
			}
		}
	}

	# finished

	display($dbg_pl_create,0,"initPlaylists() finished");
}



1;
