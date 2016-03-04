#!/usr/bin/perl
#---------------------------------------
# Playlist.pm
#
# The name of the songlist is the name of the file
#
# ArtisanWin currently can only create and use track.xml
# files that contain LOCAL_ID tracks.  It cannot handle
# playlists created on the Android.
#
# This module maintains a set of playlists of songs that
# can be played by the renderer.
#
# Each playlist has a name, and optionally, a number.
#
# The number is used to sort it in the list of
# songlists in a user defined order.  By default there is a
# playlist "", with number 0.  Playlists with negative numbers
# -1 will be sorted to the left of numbered stations. Playlists
# with the same number will be sorted by name.
#
# Playlists are kept in _data/playlists, in files called
# name.xml, and name.tracks.xml.
#
# This module has a set of default playlists that will be
# created if they are not found during startup.  They have
# queries associated with them that will select the initial
# items.  Some are called StationNN and have empty, but
# existing, queries. Playlists with queries can be compared
# to the database to detect differences, and recreate them.
#
# We *used* to keep a bit in the database for the songs that
# were in "stations" 1 thru 32, which allowed for a nice
# hiearchial folder approach to editing the playlist.
# What we need now, perhaps, is to use a single bit,
# temporarilily, and, aghast, reset it from the list of
# ids and files each time we change playlists.
# THIS IS A MAJOR WEIRDNESS and I want a fast hierarchial
# folder approach to playlists.
#
# static methods
#
#	static_init_playlists() - read existing, create default stations
#   getPlaylists() - returns a list of all the available playlist
#   getPlaylist(station_name) - returns the particular playlist
#      "" returns the temporary playlist which is never written
#
# instance methods
#
#   Shuffle - re-order the items by track, album, or native
#      order of Class (Genre), Artist, Album, track.
#      Writes the changed name.tracks.xml
#
#   getNumTracks() - number of tracks in the stationList
#   getTrackIndex() - the currently playing song, 1 based
#   setTrackIndex(track_index) - set the currently playing song
#        Writes the changed name.xml
#
#   getTrackID(track_index)
#      Returns the trackID of the song at the given track_index
#      within the station. 0 means that no trackID (song) was found
#   getNextTrackID()
#   getPrevTrackID()
#       return the next/previous trackID with wrapping
#   getIncTrackID(inc == -1 or 1)
#       an alternative method to calling getNext/Prev
#       Writes teh changed name.xml

package Playlist;
use strict;
use warnings;
use threads;
use threads::shared;
use Library;
use Database;
use Utils;
use XML::Simple;
use HTTPXML;

our $SHUFFLE_NONE = 0;
our $SHUFFLE_TRACKS = 1;
our $SHUFFLE_ALBUMS = 2;

our $dbg_pl = 2;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
    );
}


#-----------------------------
# CONSTANTS
#-----------------------------

my $NUM_DEFAULT_PLAYLISTS = 32;
    # Number of default playlists.
	# Ones with queries will be created first,
	# then gaps will be filled in with empty
	# StationXX playlists.
	

my $playlist_dir = "$cache_dir/playlists";
mkdir $playlist_dir if (!(-d $playlist_dir));


#---------------------------
# VARIABLES
#---------------------------

my %g_playlists:shared;
    # a global hash, by station_num, of Station objects.
        
my %default_playlists = (
	
	# playlist names may have spaces
	# but since they get sent along as parts of
	# urls, etc, they cannot have any special characters
	# except maybe dash and dot (certainly not ampersand)
	# which does not work unencoded in xml
	
	test => {
		num => 1,
		query => [
			"albums/Productions/Originals/Forgotten Space" ]},
	work => {
		num => 2,
		query => [
			"albums/Work" ]},
	dead => {
		num => 3,
		shuffle => $SHUFFLE_ALBUMS,
		query => [
			"albums/Dead",
			 "singles/Dead"]},
    favorite => {
		num => 4,
		shuffle => $SHUFFLE_ALBUMS,
		query => [
			"albums/Favorite",
			"singles/Favorite"]},
    jazz => {
		num => 5,
		shuffle => $SHUFFLE_TRACKS,
		query => [
			"albums/Jazz/Old",
			"albums/Jazz/Soft",
			"albums/Jazz/Swing",
			"singles/Jazz"]},
    blues => {
		num => 6,
		shuffle => $SHUFFLE_TRACKS,
		query => [
			"albums/Blues",
			"singles/Blues"]},
	station7 => { num => 7, query => [] },
	station8 => { num => 8, query => [] },
    world => {
		num => 9,
		shuffle => $SHUFFLE_ALBUMS,
		query => [
			"albums/World minus /Tipico",
			"singles/World"]},
	orleans => {
		num => 10,
		shuffle => $SHUFFLE_TRACKS,
		query => [
			"albums/NewOrleans",
			"albums/Zydeco"]},
    reggae => {
		num => 11,
		shuffle => $SHUFFLE_TRACKS,
		query => [
			"albums/Reggae",
			"singles/Reggae"]},
	rock => {
		num => 12,
		shuffle => $SHUFFLE_TRACKS,
		query => [
			"albums/Rock",
			"albums/SanDiegoLocals",
			"singles/Rock" ]},
    'RandB' => {
		num  => 13,
		shuffle => $SHUFFLE_TRACKS,
		query => [
			"albums/R&B",
			"singles/R&B"]},
    country => {
		num  => 14,
		shuffle => $SHUFFLE_TRACKS,
		query => [
			"albums/Country",
			"singles/Country"]},
    classical => {
		num  => 15,
		shuffle => $SHUFFLE_ALBUMS,
		query => [
			"albums/Classical minus /Baroque",
			"singles/Classical minus /Baroque"]},
    xmas => {
		num  => 16,
		shuffle => $SHUFFLE_TRACKS,
		query => [
			"albums/Christmas",
			"singles/Christmas"]},
    friends => {
		num  => 17,
		shuffle => $SHUFFLE_ALBUMS,
		query => [
			"albums/Productions minus Sweardha Buddha",
			"albums/Friends"]},
    folk => {
		num  => 18,
		shuffle => $SHUFFLE_TRACKS,
		query => [
			"albums/Folk",
			"singles/Folk"]},
    compilations => {
		num  => 19,
		shuffle => $SHUFFLE_ALBUMS,
		query => [
			"albums/Compilations",
			"singles/Compilations"]},
    soundtrack => {
		num  => 20,
		shuffle => $SHUFFLE_ALBUMS,
		query => [
			"albums/Soundtracks"]},
    other => {
		num  => 21,
		shuffle => $SHUFFLE_TRACKS,
		query => [
			"albums/Other",
			"singles/Other"]},
	station22 => { num => 22, query => [] },
	station23 => { num => 23, query => [] },
	station24 => { num => 24, query => [] },
	station25 => { num => 25, query => [] },
	station26 => { num => 26, query => [] },
	station27 => { num => 27, query => [] },
	station28 => { num => 28, query => [] },
	station29 => { num => 29, query => [] },
	station30 => { num => 30, query => [] },
	station31 => { num => 31, query => [] },
	station32 => { num => 32, query => [] },
	
	
);	# %default_playlists


    

#------------------------------------------
# Construction
#------------------------------------------


sub new_from_file
	# from an xml file
{
	my ($class,$entry) = @_;
	my $name:shared = $entry;
	$name =~ s/\.xml$//;
	display(0,0,"new_from_file $entry");
	my $xml = get_xml_from_file($entry);
	if (!$xml)
	{
		error("No XML found in $entry");
		return;
	}
	my $this = shared_clone($xml);
	bless $this,$class;
	$this->{name} = $name;
	$this->{dirty} = 0;
	$this->{tracks} = shared_clone([]);
	if ($this->{query})
	{
		my $paths = $this->{query}->{path};
		$paths = [ $paths ] if (!ref($paths));
		$this->{query} = shared_clone([]);
		for my $path (@$paths)
		{
			next if !$path;
			my $decoded = decode_xml($path);
			push @{$this->{query}},$decoded;
			display(0,2,"query_path($path)=$decoded");
		}
		
	}
	if (!-f "$playlist_dir/$name.tracks.xml")
	{
		$this->{dirty} |= 2;
		$this->create_tracks_from_query()
			if ($this->{query} && @{$this->{query}});
	}
	display(0,1,"name=$this->{name}");
	return $this;
}
	
	
sub new_from_default
	# from a default definition (done first)
{
	my ($class,$name,$def) = @_;
	display(0,0,"new_from_default($name) ...");
	$def->{name} = $name;
	$def->{shuffle} = 0;
	my $this = shared_clone($def);
	bless $this,$class;
	
	# Read the existing trackfile in if it exists.
	# Otherwise create the tracklist from a query
	
	$this->{dirty} = 1;
	my $xml = get_xml_from_file("$this->{name}.tracks.xml");
	if ($xml)
	{
		my $tracks = $xml->{tracklist}->{tracks};
		if ($tracks)
		{
			display(0,0,"found ".scalar(@$tracks)." tracks $this->{name}.tracks.xml");
			$this->{tracks} = shared_clone($tracks);
		}
		else
		{
			display(0,0,"no tracks in tracklist!!");
		}
	}
	
	if (!$this->{tracks})
	{
		display(0,0,"no tracks found in $this->{name}.tracks.xml .. creating from query");
		$this->create_tracks_from_query();
		$this->{dirty} |= 2;	  # the TRACKS are dirty
	}
	$this->{num_tracks} = @{$this->{tracks}};
	$this->{track_index} = $this->{num_tracks} ? 1 : 0;
	display(0,0,"new_from_default($def->{name}) finished");
	return $this;
}
	


sub static_init_playlists
{
	display(0,0,"static_init_playlists started ...");
	# read the existing playlists
	
	if (!opendir(DIR,$playlist_dir))
	{
		error("Could not opendir $playlist_dir");
		return;
	}
	else
	{
		my @entries;
		while (my $entry = readdir(DIR))
		{
			display(0,1,"checking entry: $entry");
			next if $entry !~ /\.xml$/;
			next if $entry =~ /\.tracks\.xml$/;
			push @entries,$entry;
		}
		closedir DIR;
		
		for my $entry (@entries)
		{
			my $pl = Playlist->new_from_file($entry);
			return if !$pl;
			$g_playlists{$pl->{name}} = $pl;
		}
	}
	
	
    # create default playlists

	display(0,0,"check/create default playlists");
	for my $name (keys(%default_playlists))
	{
		if (!$g_playlists{$name})
		{
			$g_playlists{$name} = Playlist->new_from_default(
				$name,$default_playlists{$name});
		}
	}
	
	# finished
	
	write_playlists();
	display(0,0,"static_init_playlists finished");
}




sub create_tracks_from_query
{
    my ($this) = @_;
	$this->{tracks} = shared_clone([]);
	my $paths = $this->{query};
	$paths ||= [];
	
	display(0,0,"create_tracks_from_query ...");
	
    my $dbh = db_connect();
    for my $path (@$paths)
    {
		my $query = "SELECT ID FROM TRACKS WHERE instr(FULLNAME,?) > 0";
		my $exclude = ($path =~ s/\s+minus\s+(.*)$//) ? $1 : '';
		my $args = [ $path ]; # ."/" ];
		if ($exclude)
		{
			display(0,2,"exclude='$exclude'");
			push @$args,$exclude;
			$query .= " AND instr(FULLNAME,?) <= 0";
		}
		$query .= " ORDER BY ALBUM_ARTIST,ALBUM,TRACKNUM,TITLE";
		my $recs = get_records_db($dbh,$query,$args);
		display(0,1,"found ".scalar(@$recs)." tracks from query path=$path");
		for my $rec (@$recs)
		{
			push @{$this->{tracks}},shared_clone({ local_id => $rec->{ID} });
		}
	}
    
	warning(0,0,"CREATED EMPTY TRACKLIST($this->{name}) FROM QUERY!!")
		if (!@{$this->{tracks}});
	display(0,0,"create_tracks_from_query finished");
    db_disconnect($dbh);
}


#-------------------------------------------
# Utilities
#-------------------------------------------

sub by_num
{
	my ($a,$b) = @_;
	my $cmp = $a->{num} <=> $b->{num};
	return $cmp if $cmp;
	return $a->{name} cmp $b->{name};
}



sub get_xml_from_file
{
	my ($playlist_file) = @_;
	my $filename = "$playlist_dir/$playlist_file";
	
	if (!-f $filename)
	{
		warning(0,0,"no xml file: $filename");
		return;
	}
	my $text = getTextFile($filename);
	if (!$text)
	{
		warning(0,0,"No text in $filename");
		return;
	}

	my $xml;
	my $xmlsimple = XML::Simple->new();
	eval { $xml = $xmlsimple->XMLin($text) };
	if ($@)
	{
		error("Unable to parse xml $text:".$@);
		return;
	}

	display(0,0,"get_xml_from_file($playlist_file)");
	for my $key (sort(keys(%$xml)))
	{
		display(0,1,"$key=$xml->{$key}");
	}

	return $xml;
	
}


#-----------------------------------------
# save
#-----------------------------------------


sub write_playlists
{
	display(0,0,"write_playlists()");
	
	for my $list (sort {by_num($a,$b)} (values(%g_playlists)))
	{
		# write dirty playlists
	
		next if !$list->{dirty};
		display(0,1,"writing $list->{name}.xml");
		my $text = "<playlist>\n";
		for my $field qw(num num_tracks track_index shuffle)
		{
			$text .= "    <$field>$list->{$field}</$field>\n";
		}
		if ($list->{query})
		{
			$text .= "    <query>\n";
			for my $path (@{$list->{query}})
			{
				$text .= "       <path>";
				$text .= encode_xml($path);
				$text .= "</path>\n"
			}
			$text .= "    </query>\n";
		}
		$text .= "</playlist>\n";
		printVarToFile(1,"$playlist_dir/$list->{name}.xml",$text);
		
		# write dirty track lists
		
		next if $list->{dirty} < 2;
		display(0,1,"writing $list->{name}.tracks.xml");
		$text = "<tracklist>\n";
		for my $track (@{$list->{tracks}})
		{
			$text .= "<track>\n";
			for my $key (sort(keys(%$track)))
			{
				$text .= "    <$key>$track->{$key}</$key>\n";
			}
			$text .= "</track>\n";
		}
		$text .= "</tracklist>\n";
		printVarToFile(1,"$playlist_dir/$list->{name}.tracks.xml",$text);
	}
}





#---------------------------------------
# testing
#---------------------------------------

if (1)
{
	static_init_playlists();
}


1;
