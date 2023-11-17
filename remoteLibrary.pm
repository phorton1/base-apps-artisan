#!/usr/bin/perl
#---------------------------------------
# remoteLibrary.pm
#---------------------------------------
# API
#	getTrack
#	getFolder
#	getSubitems
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
use base qw(Library);


my $dbg_rlib = 0;


my $folder_cache:shared = shared_clone({});
my $track_cache:shared = shared_clone({});


sub new
	# receives a $dev containing ip,port,services, etc
{
	my ($class,$params) = @_;
	display($dbg_rlib,0,"remoteLibrary::new()");
	my $this = $class->SUPER::new($params);
	bless $this,$class;
	return $this;
}



sub getTrack
{
    my ($this,$id) = @_;
	display($dbg_rlib,0,"getTrack($id)");
	my $tcache = $track_cache->{$this->{uuid}};
	my $track = $tcache ? $tcache->{$id} : '';
	error("could not getTrack($id)") if !$track;
	return $track;
}


sub getFolder
{
    my ($this,$id) = @_;
	display($dbg_rlib,0,"getFolder($id)");
	my $fcache = $folder_cache->{$this->{uuid}};
	my $folder = $fcache ? $fcache->{$id} : '';
	error("could not getFolder($id)") if !$folder;
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
			RequestedCount => 100,
			SortCriteria => '', ]);
		# WMP Media Server is fucking sensitive to the
		# order of arguments!  I was struggling just to
		# get it working ... and this order, from
		# DLNA Browser' made it go ...


	return [] if !$didl;

	# we only get tracks from folders of type 'album',
	# and only get folders from 'sections' (and 'root').
	# Artisan does not support music albums that contain
	# subfolders, indeed, the presence of a track in a folder
	# DEFINES an an album.

	my $rslt = [];

	if ($table eq 'tracks')
	{
		my $container = {};
			# for building track_numbers, etc

		my $items = $didl->{item};
		for my $item (@$items)
		{
			my $remote_track = $this->remoteTrack($item,$container);
			push @$rslt,$remote_track if $remote_track;
		}
	}
	else	# table eq 'folders'
	{
		my $containers = $didl->{container};
		for my $container (@$containers)
		{
			my $remote_folder = $this->remoteFolder($container);
			push @$rslt,$remote_folder if $remote_folder;
		}
	}

	return $rslt;

}   # get_subitems



sub remoteFolder
{
	my ($this,$container) = @_;
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
		print "checking class $content\n";

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

	my $is_album = $class_name eq 'object.container.album.musicAlbum' ? 1 : 0;
	my $artist = getArtist($container);


	my $folder = shared_clone({
		# 0 is not false (if blah) in js is_local 		=> 0,
		id 				=> $id,
		title			=> $title,
		parent_id		=> $container->{parentID} || 0,
		dirtype 		=> $is_album ? 'album' : 'section',
		num_elements    => $num_elements,

		# quick and dirty for now

	    has_art     	=> 0,
        path	 		=> '',
		art_uri			=> '',

		# presented via DNLA ...
		# mostly specific to albums


		artist   		=> getArtist($container),
        genre		    => $container->{'upnp:genre'} || '',
        year_str        => '',
		folder_error          => 0,
		highest_folder_error  => 0,
		highest_track_error   => 0,
	});

	my $fcache = $folder_cache->{$this->{uuid}};
	$fcache = $folder_cache->{$this->{uuid}} = shared_clone({})
		if !$fcache;
	$fcache->{$id} = $folder;

	return $folder;
}


sub remoteTrack
{
	my ($this,$item,$container) = @_;
	my $id = $item->{id};
	my $title = $item->{'dc:title'};

	display($dbg_rlib,0,"remoteTrack($id) $title");

	my $album_artist = $item->{'dc:creator'};

	my $art_uri = getBestArtUri($item);
	my $res = getBestRes($item);
	my $duration = $res && $res->{duration} ?
		duration_to_millis($res->{duration}) : 0;
	my $path = $res ? $res->{content} : '';

	# I think you need the streaming info and a different protocol
	# to use different resolutions, so, after finding the best one
	# we remove any query params, and that seems to work ...

	$path =~ s/\?.*$//;

	my $date = $item->{'dc:date'} || '';
	my $year_str = $date =~ /^(\d\d\d\d)/ ? $1 : '';
	my $track_num = $item->{'upnp:originalTrackNumber'} || '';

	my $track = shared_clone({
		position 		=> 0, 		# unused playlist position
		# 0 is not a false value in js !  is_local       	=> 0,
		id             	=> $id,
		parent_id    	=> $item->{parent_id},
		has_art        	=> $art_uri ? 1 : 0,
		path			=> $path,
		art_uri			=> $art_uri,
		duration     	=> $duration,
		size         	=> 0,
		type         	=> '',
        title		  	=> $title,
        artist		  	=> getArtist($container),
        album_title  	=> $item->{'upnp:album'} || '',
        album_artist 	=> '',
        tracknum  	  	=> $track_num,
        genre		  	=> $item->{'upnp:genre'} || '',
		year_str     	=> $year_str,
		timestamp      	=> 0,
		file_md5       	=> '',
		error_codes 	=> '',
		highest_error   => 0,
	});

	# cache it
	my $tcache = $track_cache->{$this->{uuid}};
	$tcache = $track_cache->{$this->{uuid}} = shared_clone({})
		if !$tcache;
	$tcache->{$id} = $track;

	return $track;
}



#----------------------------------------
# methods to sort thru the morass of
# fields offered and try to find
# usable values
#----------------------------------------


sub getArtist
{
	my ($cont) = @_;
	my $artist = getField($cont,'dc:creator');
	$artist ||= getField($cont,'upnp:actor');
	$artist ||= getField($cont,'upnp:actor');
	return $artist || '';
}


sub getField
	# returns the referred to field,
	# the 0th element of an array,
	# or the first alphabetically keyed item of a hash
{
	my ($cont,$field) = @_;

	my $retval = '';
	my $obj = $cont->{$field};

	while (ref($obj))
	{
		if ($obj =~ /ARRAY/)
		{
			$obj = $obj->[0];
		}
		elsif ($obj =~ /HASH/)
		{
			$obj = (values %$obj)[0];
		}

		# if it's still a hash, return the content member

		if ($obj =~ /HASH/ && $obj->{content})
		{
			$obj = $obj->{content};
		}
	}

	return $obj || '';
}


sub getBestRes
{
	my ($item) = @_;
	my $bit_rate = 0;

	my $best_res;
	my $resources = $item->{res};
	if ($resources)
	{
		for my $res (@$resources)
		{
			if (!$best_res || ($res->{bitrate} > $best_res->{bitrate}))
			{
				$best_res = $res;
			}
		}
	}
	return $best_res;
}


sub getBestArtUri
{
	my ($item) = @_;

	# The sizes of the the images are, ahem, as follows
	#
	# 	PNG/JPEG_TN,	160x160
	# 	PNG/JPEG_SM,	640x480
	# 	PNG/JPEG_MED    ??
	# 	PNG/JPEG_LRG	??
	#
	# There may be times where we want the larger ones,
	# but for right now I will optimize to the smaller ones

	my $art_uri = '';
	my $uris = $item->{'upnp:albumArtURI'};
	if ($uris)
	{
		for my $uri (@$uris)
		{
			$art_uri = $uri->{content};
			last if $uri->{'dlna:profileID'} =~ /_TN/;
		}
	}

	# they have comma delimited params?
	# $art_uri =~ s/,/&/g;
	$art_uri =~ s/,*.$//;
	return $art_uri;
}



#-------------------------------------------------------
# metadata - for displaying in the details section
#-------------------------------------------------------

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



sub get_metafield
    # look for &lt/&gt bracketed value of id
    # massage it as necessary
    # and set it into hash as $field
{
    my ($data,$hash,$field,$id) = @_;
    my $value = '';
    $value = $1 if ($data =~ /&lt;$id&gt;(.*?)&lt;\/$id&gt/s);
    $hash->{$field} = $value;
}





1;