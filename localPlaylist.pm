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
use Database;
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
# The 'count' member will be added during init_playlists()


my $playlists_by_name = {};
	# built during init_playlists();

my $playlists = [

	# Working folders

	{
		name => 'test',
		query => [
			"albums/Productions/Originals/Forgotten Space" ]
	},

	{
		name => 'work',
		query => [
			"albums/Work" ]
	},

	# Special Classes

    {
		name => 'favorite',
		query => [
			"albums/Favorite",
			"singles/Favorite" ]
	},
	{
		name => 'dead',
		query => [
			"albums/Dead",
			"singles/Dead" ]
	},
	{
		name => 'beatles',
		query => [
			"albums/Beatles" ]
	},

	# Main Classes

    {
		name => 'blues',
		query => [
			"albums/Blues",
			"singles/Blues" ]
	},
    {
		name => 'classical',
		query => [
			"albums/Classical minus /Baroque",
			"singles/Classical minus /Baroque" ]
	},
    {
		name => 'country',
		query => [
			"albums/Country",
			"singles/Country" ]
	},
    {
		name => 'folk',
		query => [
			"albums/Folk",
			"singles/Folk" ]
	},
    {
		name => 'jazz',
		query => [
			"albums/Jazz/Old",
			"albums/Jazz/Soft",
			"albums/Jazz/Swing",
			"singles/Jazz" ]
	},
	{
		name => 'orleans',
		query => [
			"albums/NewOrleans",
			"albums/Zydeco" ]
	},
    {
		name => 'RandB',
		query => [
			"albums/R&B",
			"singles/R&B" ]
	},
    {
		name => 'reggae',
		query => [
			"albums/Reggae",
			"singles/Reggae" ]
	},
	{
		name => 'rock',
		query => [
			"albums/Rock",
			"albums/SanDiegoLocals",
			"singles/Rock" ]
	},
    {
		name => 'world',
		query => [
			"albums/World minus /Tipico",
			"singles/World" ]
	},

	# Personal

	{
		name => 'originals',
		query => [
			"albums/Productions/Originals" ]
	},
	{
		name => 'bands',
		query => [
			"albums/Productions/Bands",
			"albums/Productions/Other",
			"albums/Productions/Theo"]
	},
    {
		name => 'friends',
		query => [
			"albums/Productions minus Sweardha Buddha",
			"albums/Friends" ]
	},


	# Other

    {
		name => 'xmas',
		query => [
			"albums/Christmas",
			"singles/Christmas" ]
	},
    {
		name => 'compilations',
		query => [
			"albums/Compilations",
			"singles/Compilations" ]
	},
    {
		name => 'soundtrack',
		query => [
			"albums/Soundtracks" ]
	},
    {
		name => 'other',
		query => [
			"albums/Other",
			"singles/Other" ]
	},

];	# $playlists




#-----------------------------
# support for localLibrary
#-----------------------------


sub getPlaylists
{
	return $playlists;
}


sub getPlaylistByName
{
	my ($name) = @_;
	return $playlists_by_name->{$name};
}



sub getTracks
{
	my ($desc,$start,$count) = @_;
	my $name = $desc->{name};
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



sub updatePlaylist
	# create named.db file if it doesn't exist
	# else set $desc->{count} from existing database
{
	my ($desc) = @_;
	my $name = $desc->{name};
	my $query = $desc->{query};
	my $named_db = "$playlist_dir/$name.db";

	$playlists_by_name->{$name} = $desc;

	display($dbg_create+1,0,"updatePlaylist($desc->{name})");

	if (-f $named_db)
	{
		my $named_dbh = db_connect($named_db);
		return if !$named_dbh;
		my $recs = get_records_db($named_dbh,"SELECT id FROM tracks");
		db_disconnect($named_dbh);

		my $count = @$recs;
		display($dbg_create+1,1,"found count($count) recs in existing $name.db");
		$desc->{count} = $count;
	}
	else	# Create it
	{
		# connect to the main database

		my $artisan_dbh = db_connect();

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

		# disconnect from the databases

		db_disconnect($artisan_dbh);

		# create the new database and it's tracks table

		display($dbg_create+1,1,"creating $name.db with ".scalar(@$tracks)." tracks");

		my $named_dbh = db_connect($named_db);
		return if !$named_dbh;

		create_table($named_dbh,"tracks");

		my $position = 1;
		for my $track (sort {default_sort($a,$b)} @$tracks)
		{
			$track->{position} = $position++;
			if (!insert_record_db($named_dbh,'tracks',$track))
			{
				error("Could not insert track($track->{id}==$track->{title}) into $name.db database");
				return;
			}
		}

		db_disconnect($named_dbh);
		$desc->{count} = @$tracks;
	}

	display($dbg_create+1,0,"updatePlaylist($name) finished");
	return 1;
}



sub initPlaylists
{
	display($dbg_create,0,"initPlaylists() started ...");
	for my $desc (@$playlists)
	{
		updatePlaylist($desc);
	}
	display($dbg_create,0,"initPlaylists() finished");
}




1;
