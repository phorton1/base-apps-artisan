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
# Implemented in terms of xml POST requests to a remote
# DLNA MediaServer ContentDirectory service


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
use remotePlaylist;
use base qw(Library);


my $REINIT_REMOTE_DBS = 0;


my $dbg_rlib = 0;


# my $folder_cache:shared = shared_clone({});
# my $track_cache:shared = shared_clone({});


sub dbPath
{
	my ($this) = @_;
	my $cache_dir = $this->cacheDir();
	my $db_path = "$cache_dir/_remote_library.db";
	return $db_path;
}


sub new
	# receives a $dev containing ip,port,services, etc
{
	my ($class,$params) = @_;
	display($dbg_rlib,0,"remoteLibrary::new()");
	my $this = $class->SUPER::new($params);
	bless $this,$class;

	# create or open the database

	my $db_path = $this->dbPath();
	unlink $db_path if $REINIT_REMOTE_DBS;
	$this->{new_db} = -f $db_path ? 0 : 1;
	db_initialize($db_path);

	return $this;
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
	# Called by DLNA and webUI to return the list
	# of items in a folder given by ID.  If the
	# folder type is an 'album', $table will be
	# TRACKS, to get the tracks in an album.
	# An album may not contain subfolders.
	#
	# Otherwise, the $table will be FOLDERS and
	# we are finding the children folders of the
	# given ID (which is also a leaf "class" or "genre).
	# We sort the list so that subfolders (sub-genres)
	# show up first in the list.
{
	my ($this,$table,$id,$start,$count) = @_;
    $start ||= 0;
    $count ||= 999999;
    display($dbg_rlib,0,"get_subitems($table,$id,$start,$count)");

	my $didl = $this->didlRequest(
		'ContentDirectory',
		'Browse',[
			ObjectID => $id,
			BrowseFlag => 'BrowseDirectChildren',
			Filter => '*',
			StartingIndex => 0,
			RequestedCount => $count,
			SortCriteria => '', ]);
		# WMP Media Server is fucking sensitive to the
		# order of arguments!  I was struggling just to
		# get it working ... and this order, from
		# DLNA Browser' made it go ...

	my $rslt = shared_clone([]);
	return $rslt if !$didl;

	my $dbh = db_connect($this->dbPath());
	return $rslt if !$dbh;

	# I currently always use 0 and 99999 ...
	# may need to change this a bit in the future
	# to use $start and $count

	my $from_cache = $didl->{from_cache};
	display($dbg_rlib,1,"get_subitems() from_cache=$from_cache");;
	if ($from_cache && !$REINIT_REMOTE_DBS)
	{
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

	# Regardless of the $table requested, we scan the result
	# for any folders or tracks, but only return the type of
	# thing requested.

	else
	{
		my $position = 1;
		my $items = $didl->{item} || [];
		for my $item (@$items)
		{
			my $remote_track = $this->remoteTrack($dbh,\$position,$item);
			push @$rslt,$remote_track
				if $remote_track && $table eq 'tracks';
		}

		my $containers = $didl->{container} || [];
		for my $container (@$containers)
		{
			my $remote_folder = $this->remoteFolder($dbh,$container);
			push @$rslt,$remote_folder
				if $remote_folder && $table eq 'folders';
		}
	}

	db_disconnect($dbh);
	display($dbg_rlib,0,"get_subitems() returning ".scalar(@$rslt)." $table recs ".($from_cache?'from cache':''));
	return $rslt;

}   # get_subitems




sub getPlaylist
	# pass thru
{
	my ($this,$id) = @_;
	return remotePlaylist::getPlaylist($this,$id);
}

sub getPlaylists
	# pass through
{
	my ($this) = @_;
	return remotePlaylist::getPlaylists($this);
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

sub remoteFolder
{
	my ($this,$dbh,$container) = @_;
	my $id = $container->{id};
	my $class_name = $container->{'upnp:class'}->{content} || '';
	my $title = $container->{'dc:title'} || '';
	my $num_elements = $container->{childCount} || 0;

	display($dbg_rlib,0,"remoteFolder($id,$class_name) $title $num_elements");

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
			display($dbg_rlib,1,"accepting container($id) based on class($content)");
			$accept = 1;
			last;
		}
	}
	if (!$accept)
	{
		display($dbg_rlib,1,"skipping container($id)");
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

	display($dbg_rlib,0,"remoteTrack($id) $title");

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