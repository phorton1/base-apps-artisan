#!/usr/bin/perl
#---------------------------------------
# localPlaylist.pm
#---------------------------------------
# Builds the /playlists subdirectory and the databases
# for each Playlist.  The ID of a Playlist is it's NAME.
# The Ordering of Playlists within the virtual Playlists
# Folder is gotten by a call to the static default_playlists
# data structure.

package localPlaylist;
use strict;
use warnings;
use threads;
use threads::shared;
use File::Path;
use Database;
use Playlist;
use artisanUtils;



my $dbg_get = 0;
my $dbg_create = -2;
	#  0 == show init_playlists header
	# -1 == show playlist creation
	# -2 == show playlist creation details



my $playlist_dir = "$data_dir/playlists";
mkdir $playlist_dir if (!(-d $playlist_dir));



#---------------------------
# DEFAULT PLAYLISTS
#---------------------------

my $playlist_defs = [

	# Working folders

	{
		id => '001',
		name => 'test',
		query => [
			"albums/Productions/Originals/Forgotten Space" ]
	},

	{
		id => '002',
		name => 'work',
		query => [
			"albums/Work" ]
	},

	# Special Classes

    {
		id => '003',
		name => 'favorite',
		query => [
			"albums/Favorite",
			"singles/Favorite" ]
	},
	{
		id => '004',
		name => 'dead',
		query => [
			"albums/Dead",
			"singles/Dead" ]
	},
	{
		id => '005',
		name => 'beatles',
		query => [
			"albums/Beatles" ]
	},

	# Main Classes

    {
		id => '006',
		name => 'blues',
		query => [
			"albums/Blues",
			"singles/Blues" ]
	},
    {
		id => '007',
		name => 'classical',
		query => [
			"albums/Classical minus /Baroque",
			"singles/Classical minus /Baroque" ]
	},
    {
		id => '008',
		name => 'country',
		query => [
			"albums/Country",
			"singles/Country" ]
	},
    {
		id => '009',
		name => 'folk',
		query => [
			"albums/Folk",
			"singles/Folk" ]
	},
    {
		id => '010',
		name => 'jazz',
		query => [
			"albums/Jazz/Old",
			"albums/Jazz/Soft",
			"albums/Jazz/Swing",
			"singles/Jazz" ]
	},
	{
		id => '011',
		name => 'orleans',
		query => [
			"albums/NewOrleans",
			"albums/Zydeco" ]
	},
    {
		id => '012',
		name => 'RandB',
		query => [
			"albums/R&B",
			"singles/R&B" ]
	},
    {
		id => '013',
		name => 'reggae',
		query => [
			"albums/Reggae",
			"singles/Reggae" ]
	},
	{
		id => '014',
		name => 'rock',
		query => [
			"albums/Rock",
			"albums/SanDiegoLocals",
			"singles/Rock" ]
	},
    {
		id => '015',
		name => 'world',
		query => [
			"albums/World minus /Tipico",
			"singles/World" ]
	},

	# Personal

	{
		id => '016',
		name => 'originals',
		query => [
			"albums/Productions/Originals" ]
	},
	{
		id => '017',
		name => 'bands',
		query => [
			"albums/Productions/Bands",
			"albums/Productions/Other",
			"albums/Productions/Theo"]
	},
    {
		id => '018',
		name => 'friends',
		query => [
			"albums/Productions minus Sweardha Buddha",
			"albums/Friends" ]
	},


	# Other

    {
		id => '019',
		name => 'xmas',
		query => [
			"albums/Christmas",
			"singles/Christmas" ]
	},
    {
		id => '020',
		name => 'compilations',
		query => [
			"albums/Compilations",
			"singles/Compilations" ]
	},
    {
		id => '021',
		name => 'soundtrack',
		query => [
			"albums/Soundtracks" ]
	},
    {
		id => '022',
		name => 'other',
		query => [
			"albums/Other",
			"singles/Other" ]
	},

];	# $playlist_defs




sub getPlaylistDefs
{
	return $playlist_defs;
}


sub getPlaylistDefById
{
	my ($id) = @_;
	for my $def (@$playlist_defs)
	{
		return $def if $def->{id} eq $id;
	}
	return ''
}




#---------------------------------------------------
# support for localLibrary/ContentDirectory1
#---------------------------------------------------
# return them in their native original order


sub getTracks
{
	my ($def,$start,$count) = @_;
	my $name = $def->{name};
	display($dbg_get,0,"getTracks($name,$start,$count)");
	my $named_db = "$playlist_dir/$name.db";
	my $named_dbh = db_connect($named_db);
	return !error("Could not connect to local namedb $named_db")
		if !$named_dbh;

	my $last = $start + $count - 1;
	my $query = "SELECT * FROM tracks WHERE position>=$start AND position<=$last ORDER BY position";
	display($dbg_get,1,"query=$query");

	my $tracks = get_records_db($named_dbh,$query);

	db_disconnect($named_dbh);
	display($dbg_get,0,"getTracks($name) returning ".scalar(@$tracks)." Tracks");
	return $tracks;
}




#-----------------------------------------
# initPlaylists
#-----------------------------------------

sub normalizedPath
	# Used to sort the original positions for tracks.
	# Takes a local track's 'path', removes the filename portion,
	# removes leading /albums and /singles and returns the result.
	# This effectively groups my playlists by Genre - Artist - Album_Title
	# to the degree that all child directories until a dirtype==album
	# are the Genres and, apart from the dead, all the folder names
	# are Artist - Album_Title.
{
	my ($path) = @_;
	$path = pathOf($path);
	$path =~ s/^(albums|singles)\///;
	return $path;
}


sub default_sort
	# proper DEFAULT SORT ORDER is to sort by 'album',
	# as given by the pathOf($path) then, if a tracknum
	# is provided, by that, and finally by the track title.
	#
	# I remove /albums and /singles from the path before comparing
{
    my ($a,$b) = @_;
    my $cmp = normalizedPath($a->{path}) cmp normalizedPath($b->{path});
    return $cmp if $cmp;
    $cmp = ($a->{tracknum} || 0) <=> ($b->{tracknum} || 0);
    return $cmp if $cmp;
    return $a->{title} cmp $b->{title};
}



sub createPlaylist
	# create named.db file
{
	my ($artisan_dbh,$def) = @_;
	my $name = $def->{name};
	my $query = $def->{query};
	my $named_db = "$playlist_dir/$name.db";

	display($dbg_create,0,"createPlaylist($def->{name})");

	# get the records by path

	my $tracks = [];
	for my $path (@$query)
	{
		display($dbg_create+2,1,"query path=$path");

		my $query = "SELECT * FROM tracks WHERE instr(path,?) > 0";
		my $exclude = ($path =~ s/\s+minus\s+(.*)$//) ? $1 : '';
		my $args = [ $path ]; # ."/" ];
		if ($exclude)
		{
			display($dbg_create+2,1,"exclude='$exclude'");
			push @$args,$exclude;
			$query .= " AND instr(path,?) <= 0";
		}
		$query .= " ORDER BY path";
			# "genre,album_artist,album_title,tracknum,title";
		my $recs = get_records_db($artisan_dbh,$query,$args);
		display($dbg_create+2,1,"found ".scalar(@$recs)." tracks from query path=$path");
		push @$tracks,@$recs;
	}

	# create the new database and it's tracks table

	my $num_tracks = scalar(@$tracks);
	display($dbg_create,1,"creating $name.db with $num_tracks tracks");

	my $named_dbh = db_connect($named_db);
	return if !$named_dbh;

	create_table($named_dbh,"tracks");

	my $position = 1;
	my $first_track;
	for my $track (sort {default_sort($a,$b)} @$tracks)
	{
		$first_track ||= $track;
		$track->{position} = $position++;
		$track->{pl_idx} = $track->{position};
		if (!insert_record_db($named_dbh,'tracks',$track))
		{
			error("Could not insert track($track->{id}==$track->{title}) into $name.db database");
			return;
		}
	}

	db_disconnect($named_dbh);

	my $rec = {
		id		 	 => $def->{id},
		uuid         => $this_uuid,
		name		 => $name,
		num_tracks   => $num_tracks,
		shuffle	 	 => $SHUFFLE_NONE,
		track_index  => $num_tracks ? 1 : 0,
		track_id	 => $first_track ? $first_track->{id} : '',
		version	 	 => 1,
		data_version => 1,
	};

	display($dbg_create,0,"createPlaylist($name) finished");
	return $rec;
}


sub initPlaylists
	# if the playlists.db file is removed, all
	# 	playlists will be recreated.
	# if a namedb.file or record is missing, that playlist
	#   will be recreated
	# if a record exists and a named.db file exists,
	#   they are assumed to be correct.

{
	display($dbg_create,0,"initPlaylists() started ...");

	my $playlist_db = "$data_dir/playlists.db";
	my $new_database = !-f $playlist_db;

	if ($new_database)
	{
		rmtree($playlist_dir);
		my_mkdir($playlist_dir);
	}

	my $artisan_dbh = db_connect();
	return if !$artisan_dbh;

	my $playlist_dbh = db_connect($playlist_db);
	if (!$playlist_dbh)
	{
		db_disconnect($artisan_dbh);
		return;
	}

	create_table($playlist_dbh,"playlists")
		if $new_database;

	for my $def (@$playlist_defs)
	{
		my $name = $def->{name};
		my $exists = -f "$playlist_dir/$name.db" ? 1 : 0;
		my $rec = get_record_db($playlist_dbh, "SELECT * FROM playlists WHERE id='$def->{id}'");

		display($dbg_create,0,"checking($name) exists=$exists  rec="._def($rec));
		if (!$rec || !$exists)
		{
			my $new_rec = createPlaylist($artisan_dbh,$def);
			last if !$new_rec;
			if (!$rec)
			{
				if (!insert_record_db($playlist_dbh,'playlists',$new_rec))
				{
					error("Could not insert playlist($name) into playlists.db");
					last;
				}
			}
			else
			{
				if (!update_record_db($playlist_dbh,'playlists',$new_rec,'id'))
				{
					error("Could not update playlist($name) in playlists.db");
					last;
				}
			}
			$rec = $new_rec;
		}
		$def->{count} = $rec->{num_tracks};
	}

	# finished

	db_disconnect($playlist_dbh);
	db_disconnect($artisan_dbh);

	display($dbg_create,0,"initPlaylists() finished");
}


1;
