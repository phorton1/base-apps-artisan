#!/usr/bin/perl
#---------------------------------------
# remoteLibrary.pm
#---------------------------------------
# API
#	getTrack
#	getFolder
#	getSubitems
#   getPlaylist
#	getPlaylists
#	getTrackMetadata
#	getFolderMetadata
#
# The main entry point from the webUI is getSubitems().
# The cache/database scheme is built around this fact.
# 'Tracks' and 'Folders' in the remoteLibrary are always
# 'built' as the children of a folder (or playlist) via a
# call to getSubitems() which subsequently calls
# BrowseDirectChildren for some parent_id.
#
# The webUI may be asking for folders or tracks, but
# the result may contain either, so getSubItems always
# creates (sub) 'Folders' for 'containers' it finds, and
# (non-unique) 'Tracks' for any 'items' it finds in the
# returned result.
#
# getSubItems then returns the correct type of child things,
# for example, returning 0 items when asked to find folders,
# but finding a bunch of tracks (items).
#
# remotePlaylist separately caches the result of its
# SEARCH for playlists, which takes a long time.
#
# The presence of a cachefile means that we have already
# gotten the children of the given ID and the results
# are in the database.  There is currently no 'updating'
# of the database based on (event) UpdateID or partial
# removal of cachefiles.  Remove them all, or none.


package remoteLibrary;
use strict;
use warnings;
use threads;
use threads::shared;
use IO::Socket::INET;
use XML::Simple;
use artisanUtils;
use Library;
use Database;
use Track;
use Folder;
use Playlist;
use remotePlaylist;
use base qw(Library);


my $dbg_rlib = 0;
	#  0 = main
	# -1 == remoteFolders and Tracks
	# -2 == remoteFolder selection criteria



sub new
	# receives a $dev containing ip,port,services, etc
{
	my ($class,$params) = @_;
	display($dbg_rlib,0,"remoteLibrary::new()");
	my $this = $class->SUPER::new($params);
	bless $this,$class;

	$this->startDatabase();
	remotePlaylist::initPlaylists($this);

	return $this;
}




sub startDatabase
	# if the database doesn't exist, create it,
	# and update it from any existing cache files.
{
	my ($this) = @_;
	my $db_path = $this->dbPath();
	if (!-f $db_path)
	{
		display($dbg_rlib,0,"Creating new database");
		db_initialize($db_path);
		my $dbh = db_connect($this->dbPath());
		return if !$dbh;

		my $cache_dir = $this->subDir('cache');
		if (!opendir(DIR,$cache_dir))
		{
			error("Could not opendir $cache_dir");
			return;
		}
		while (my $entry=readdir(DIR))
		{
			my $filename = "$cache_dir/$entry";
			if ($entry =~ /^(.*)\.didl\.txt$/ && -f $filename)
			{
				my $dbg_name = $1;
				my $params = $this->getParseParams($dbg_rlib,$dbg_name);
				$params->{dbh} = $dbh;

				# by virtue of the fact that the cachefile exists,
				# the underlying didlRequest() will use the cachefile,
				# not call the serviceRequest, and hence does not
				# need 'service', 'action', or 'args' parameters.

				last if !$this->getAndParseDidl($params);
			}
		}
		db_disconnect($dbh);
		closedir DIR;
	}
}


sub dbPath
{
	my ($this) = @_;
	my $device_dir = $this->deviceDir();
	my $db_path = "$device_dir/remote_library.db";
	return $db_path;
}


sub subDir
{
	my ($this,$what) = @_;
	my $device_dir = $this->deviceDir();
	my $subdir = "$device_dir/$what";
	mkdir $subdir if !-f $subdir;
	return $subdir;
}


sub getParseParams
{
	my ($this,$dbg,$dbg_name,) = @_;
	my $cache_dir = $this->subDir('cache');
	my $parse_params = {
		dbg => $dbg_rlib,
		dbg_name => "$dbg_name",
		cache_file => "$cache_dir/$dbg_name.didl.txt",
		dump_dir => $this->subDir('dump'),
		raw => 0,
		pretty => 1,
		my_dump => 0,
		dumper => 1, };
	return $parse_params;
}


#-------------------------------------------------------
# API
#-------------------------------------------------------

sub getTrack
{
    my ($this,$id) = @_;
	display($dbg_rlib,0,"getTrack($id)");

	my $dbh = db_connect($this->dbPath());
	return if !$dbh;
	my $rec = get_record_db($dbh,"SELECT * FROM tracks WHERE id='$id'");
	db_disconnect($dbh);

	return !error("Could not find track($id)") if !$rec;
	my $track = Track->newFromHash($rec);
	return $track;
}


sub getFolder
{
    my ($this,$id) = @_;
	display($dbg_rlib,0,"getFolder($id)");

	my $dbh = db_connect($this->dbPath());
	return if !$dbh;
	my $rec = get_record_db($dbh,"SELECT * FROM folders WHERE id='$id'");
	db_disconnect($dbh);

	return !error("Could not find track($id)") if !$rec;
	my $folder = Folder->newFromHash($rec);
	return $folder;
}


sub getSubitems
	# Called by DLNA and webUI to return the list of items in a
	# folder given by ID.  If $table is 'folders', we return only
	# Folders, and if table is 'tracks' we return only Tracks.
	#
	# If the cache_file is present, we return results from the databae,
	# otherwise, we make the request, parse the results for both
	# both containers (Folders) and items (Tracks), adding them
	# to the database, and then return only the specified things.
	#
	# I currently always ask for everything, and this method does
	# not return partial results.
{
	my ($this,$table,$id,$start,$count) = @_;
    $start ||= 0;
    $count ||= 999999;
    display($dbg_rlib,0,"get_subitems($table,$id,$start,$count)");

	my $rslt = shared_clone([]);
	my $dbh = db_connect($this->dbPath());
	return $rslt if !$dbh;

	# by convention, didlRequest will add '.didl.txt' to the filenames,
	# and deviceRequest() will add '.txt'

	my $from_database = 0;
	my $dbg_name = "Browse($id)";
	my $cache_dir = $this->subDir('cache');
	my $cache_file = "$cache_dir/$dbg_name.didl.txt";

	# if the cache_file exists, get records from the database

	if (-f $cache_file)
	{
		$from_database = 1;
		my $order_field = $table eq 'tracks' ? 'position' : 'path';
		my $recs = get_records_db($dbh,"SELECT * FROM $table WHERE parent_id = '$id' ORDER BY $order_field");
		if ($recs && @$recs)
		{
			for my $rec (@$recs)
			{
				push @$rslt, $table eq 'tracks' ?
					Track->newFromHash($rec) :
					Folder->newFromHash($rec);
			}
		}
	}
	else
	{
		my $params = $this->getParseParams($dbg_rlib,$dbg_name);

		$params->{dbh} = $dbh;
		$params->{service} = 'ContentDirectory';
		$params->{action} = 'Browse';
		$params->{args} = [
			ObjectID => $id,
			BrowseFlag => 'BrowseDirectChildren',
			Filter => '*',
			StartingIndex => 0,
			RequestedCount => $count,
			SortCriteria => '', ];

		$rslt = $this->getAndParseDidl($params,$table);
	}

	db_disconnect($dbh);
	display($dbg_rlib,0,"get_subitems() returning ".scalar(@$rslt)." $table recs ".($from_database?'from database':''));
	return $rslt;

}   # get_subitems



sub getPlaylist
	# pass thru
{
	my ($this,$renderer_uuid,$id) = @_;
	return Playlist::getPlaylist($this,$renderer_uuid,$id);
}

sub getPlaylists
	# pass through
{
	my ($this,$renderer_uuid) = @_;
	return Playlist::getPlaylists($this,$renderer_uuid);
}


sub getFolderMetadata
{
	my ($this,$id) = @_;
	display($dbg_rlib,0,"getFolderMetadata($id)");
	my $folder = $this->getFolder($id);
	return [] if !$folder;

	my $use_id = 0;
	my $sections = [];
	push @$sections, meta_section(\$use_id,'Database',1,$folder);
	return $sections;
}


sub getTrackMetadata
{
	my ($this,$id) = @_;
	display($dbg_rlib,0,"getTrackMetadata($id)");
	my $track = $this->getTrack($id);
	return [] if !$track;

	my $use_id = 0;
	my $sections = [];
	push @$sections, meta_section(\$use_id,'Database',1,$track);
	return $sections;
}


#--------------------------------------------------------
# Implementation
#--------------------------------------------------------

sub getAndParseDidl
{
	my ($this,$params,$table) = @_;
	$table ||= '';

	my $dbh = $params->{dbh};
	my $dbg = $params->{dbg};
	my $dbg_name = $params->{dbg_name};
    display($dbg,0,"getAndParseDidl($dbg_name) table($table)");

	my $rslt = shared_clone([]);
	my $didl = $this->didlRequest($params);
	return $rslt if !$didl;

	# Regardless of the $table requested, we scan the result
	# for any folders or tracks, but only return the type of
	# thing requested.

	my $position = 1;
	my $items = $didl->{item} || [];
	for my $item (@$items)
	{
		my $remote_track = $this->remoteTrack($dbh,\$position,$item);
		push @$rslt,$remote_track
			if $remote_track && (!$table || $table eq 'tracks');
	}

	my $containers = $didl->{container} || [];
	for my $container (@$containers)
	{
		my $remote_folder = $this->remoteFolder($dbh,$container);
		push @$rslt,$remote_folder
			if $remote_folder && (!$table || $table eq 'folders');
	}

	display($dbg_rlib,0,"getAndParseDidl() returning ".scalar(@$rslt)." $table recs ");
	return $rslt;
}



sub remoteFolder
{
	my ($this,$dbh,$container) = @_;
	my $id = $container->{id};
	my $class_name = $container->{'upnp:class'}->{content} || '';
	my $title = $container->{'dc:title'} || '';
	my $num_elements = $container->{childCount} || 0;

	display($dbg_rlib+1,0,"remoteFolder($id,$class_name) $title $num_elements");

	# we will only accept containers that contain music stuff

	my $accept = 0;
	my $classes = $container->{'upnp:searchClass'};
	for my $class (@$classes)
	{
		my $content = $class->{content};
		# print "checking class $content\n";

		if (
			$content =~ /audioItem/ ||
			$content =~ /musicTrack/ ||
			$content =~ /musicAlbum/ ||
			$content =~ /musicArtist/ ||
			$content =~ /audioBook/ ||
			# $content =~ /playlistContainer/ ||
			0
		)
		{
			display($dbg_rlib+2,1,"accepting container($id) based on class($content)");
			$accept = 1;
			last;
		}
	}
	if (!$accept)
	{
		display($dbg_rlib+2,1,"skipping container($id)");
		return;
	}

	# my $fcache = $folder_cache->{$this->{uuid}};
	# $fcache = $folder_cache->{$this->{uuid}} = shared_clone({})
	# 	if !$fcache;


	my $dir_type =
		($class_name eq 'object.container.album.musicAlbum') ? 'album' :
		($class_name eq 'object.container.playlistContainer') ? 'playlist' :
		'section';

	my $path = '';
	my $descs = $container->{desc};
	for my $desc (@$descs)
	{
		print "$desc->{id} --> $desc->{content}\n";

		if ($desc->{id} eq 'folderPath' &&
			$desc->{content} =~ /<microsoft:folderPath>(.*)<\/microsoft:folderPath>/)
		{
			$path = $1;
			$path =~ s/\\/\//g;
			last;
		}
	}

	if (!$path)
	{
		my @parts = ($title);
		my $parent_id = $container->{parentID};
		my $parent = get_record_db($dbh,"SELECT * FROM folders WHERE id = '$parent_id'");
		while ($parent)
		{
			push @parts,$parent->{title};
			$parent_id = $parent->{parent_id};
			$parent = get_record_db($dbh,"SELECT * FROM folders WHERE id = '$parent_id'");
		}
		$path = "/" . join("/",reverse @parts);
	}


	my $folder = shared_clone({
		id 				=> $id,
		title			=> $title,
		parent_id		=> $container->{parentID} || 0,
		dirtype 		=> $dir_type,
		num_elements    => $num_elements,

		# quick and dirty for now

	    has_art     	=> 0,
        path	 		=> $path,
		art_uri			=> getArtUri($container),

		# presented via DNLA ...
		# mostly specific to albums

		artist   		=> getArtist($container,1),
        genre		    => $container->{'upnp:genre'} || '',
        year_str        => '',
		folder_error          => 0,
		highest_folder_error  => 0,
		highest_track_error   => 0,
	});

	$folder->{has_art} = 1 if $folder->{art_uri};
	return !error("Could not insert folder($id) in database")
		if !insert_record_db($dbh,'folders',$folder);

	return $folder;
}


sub remoteTrack
{
	my ($this,$dbh,$position,$item) = @_;
	my $id = $item->{id};
	my $title = $item->{'dc:title'};

	display($dbg_rlib+1,0,"remoteTrack($id) $title");

	my $path = '';
	my $size = 0;
	my $type = '';
	my $duration = 0;
	my $resources = $item->{res};
	my $res = $resources ? $resources->[0] : '';
	if ($res)
	{
		$size = $res->{size} || 0;
		$path = $res->{content};
		$path =~ s/\?.*$//;		# remove any ? query
		$type = lc($1) if $path =~ /\.(mp3|wma|m4a)$/;
		my $protocol = $res->{protocolInfo};
		if (!$type && $protocol)
		{
			$type ||= $protocol =~ /audio\/mpeg|DLNA\.ORG_PN=MP3/ ? 'mp3' : '';
			$type ||= $protocol =~ /audio\/x-ms-wma|DLNA\.ORG_PN=WM/ ? 'wma' : '';
			$type ||= $protocol =~ /audio\/x-m4a|DLNA\.ORG_PN=M4A/ ? 'm4a' : '';
		}
		$duration = duration_to_millis($res->{duration}) if $res->{duration};

	}

	my $date = $item->{'dc:date'} || '';
	my $year_str = $date =~ /^(\d\d\d\d)/ ? $1 : $date;

	my $track = shared_clone({
		position 		=> $$position++,
		# 0 is not a false value in js !  is_local       	=> 0,
		id             	=> $id,
		parent_id    	=> $item->{parentID},
		has_art        	=> 0,
		path			=> $path,
		art_uri			=> getArtUri($item),
		duration     	=> $duration,
		size         	=> $size,
		type         	=> $type,
        title		  	=> $title,
        artist		  	=> getArtist($item),
        album_title  	=> $item->{'upnp:album'} || '',
        album_artist 	=> getArtist($item,1),
        tracknum  	  	=> $item->{'upnp:originalTrackNumber'} || '',
        genre		  	=> $item->{'upnp:genre'} || '',
		year_str     	=> $year_str,
		timestamp      	=> 0,
		file_md5       	=> '',
		error_codes 	=> '',
		highest_error   => 0,
	});

	$track->{has_art} = 1 if $track->{art_uri};
	return !error("Could not insert track($id) in database")
		if !insert_record_db($dbh,'tracks',$track);
	return $track;
}



#----------------------------------------
# methods to sort thru the morass of
# fields offered and try to find
# usable values
#----------------------------------------
# I dicked around for quite a while trying to get Folder.jpg's
# from WMS.  I believe now that it ONLY sends JPGs embedded in
# mediaFiles, although WMP shows Folder.jpg happy as a clam.


sub getArtUri
	# takes the first uri found
	# minus any comma delimited params
{
	my ($item) = @_;
	my $uris = $item->{'upnp:albumArtURI'};
	my $art_uri = $uris && @$uris ? $uris->[0]->{content} : '';
	$art_uri =~ s/,*.$// if $art_uri =~ /,/;
	return $art_uri;
}



sub getArtist
{
	my ($cont,$album) = @_;

	my $creator = $cont->{'dc:creator'} || '';
	my $author = '';
	my $composer = '';
	my $performer = '';
	my $album_artist = '';

	my $entries = $cont->{'upnp:artist'};
	for my $entry (@$entries)
	{
		my $content = $entry->{content};
		$content =~ s/\[Unknown.*\]//;
		$author 	  ||= $entry->{role} =~ /Author/i         ? $content : '';
		$composer 	  ||= $entry->{role} =~ /Composer/i       ? $content : '';
		$performer 	  ||= $entry->{role} =~ /Performer/i      ? $content : '';
		$album_artist ||= $entry->{role} =~ /'AlbumArtist'/i  ? $content : '';
	}

	$album_artist ||= $creator;
	$album_artist ||= $author;
	$album_artist ||= $composer;
	$album_artist ||= $performer;

	$performer ||= $album_artist;

	return $album ? $album_artist : $performer;
}




#-------------------------------------------------------
# metadata - for displaying in the details section
#-------------------------------------------------------





1;