#!/usr/bin/perl
#---------------------------------------
# remotePlaylist.pm
#---------------------------------------
# A remotePlaylist has the following members:
#
#	id				- playlist id within the library
#   uuid			- uuid of the library
# 	name			- playlist title
# 	shuffle			- shuffle mode
#   num_tracks		- number of tracks in the playlist
#   track_index		- current track index within the playlist
#	[tracks]		- added if the playlist is 'gotten'
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


package remotePlaylist;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;


my $dbg_rpl = 0;


my $all_playlists:shared = shared_clone({});
my $all_playlists_by_id:shared = shared_clone({});



#------------------------------------------
# Constructors
#------------------------------------------

# sub new
# {
# 	my ($class,$params) = @_;
# 	display($dbg_rpl,0,"remotePlaylist::new($params->{uuid},$params->{id}) $params->{name}");
#
# 	my $this = shared_clone({
# 		id => '',
# 		uuid => '',
# 		name => '',
# 		query => '',
# 		shuffle => 0,
# 		num_tracks => 0,
# 		track_index => 0,
# 	});
# 	bless $this,$class;
# 	mergeHash($this,$params);
#
# 	my $uuid = $this->{uuid};
# 	my $playlists = $all_playlists->{$uuid};
# 	my $playlists_by_id = $all_playlists_by_id->{$uuid};
# 	$playlists = $all_playlists->{$uuid} = shared_clone([]) if !$playlists;
# 	$playlists_by_id = $all_playlists_by_id->{$uuid} = shared_clone({}) if !$playlists_by_id;
#
# 	push @$playlists,$this;
# 	$playlists_by_id->{$this->{id}} = $this;
# 	return $this;
# }


#------------------------------------
# API to Renderers
#------------------------------------

sub getTrackId
{
    my ($this,$inc) = @_;
    display($dbg_rpl,0,"getTrackId($this->{name},$this->{track_index}) inc=$inc");
    $this->{track_index} += $inc;
    $this->{track_index} = 1 if $this->{track_index} > $this->{num_tracks};
    $this->{track_index} = $this->{num_tracks} if $this->{track_index} < 1;
	return $this->{tracks}->[$this->{track_index}]->{id};
}


sub sortPlaylist
{
	my ($this) = @_;
	my $name = $this->{name};
	display($dbg_rpl,0,"sortPlaylist($name)");
}



#------------------------------------
# pass thru API to remoteLibrary
#------------------------------------

sub getPlaylist
{
	my ($library,$id) = @_;
	display($dbg_rpl,0,"getPlaylist($library->{name},$id)");
	my $playlists_by_id = $all_playlists_by_id->{$library->{uuid}};
	if (!$playlists_by_id)
	{
		error("getPlaylist($library->{uuid}) accessed before getPlaylists()!");
		return '';
	}
	my $playlist = $playlists_by_id->{$id} || '';
	if (!$playlist)
	{
		error("playist($library->{name},$id) not found!");
	}
	else
	{
		display($dbg_rpl,1,"getPlaylist($library->{name},$id) returning pl with $playlist->{num_tracks} tracks");
	}

	# initialize the tracks in the playlist
	# unlike the localLibrary, we're gonna cache the entire tracks records

	if (!$playlist->{tracks})
	{
		display($dbg_rpl,1,"initializing playlist tracks ($library->{name},$id)");
		$playlist->{tracks} = $library->getSubitems('tracks',$playlist->{id});
		display($dbg_rpl,1,"initializing playlist found ".scalar(@{$playlist->{tracks}})." tracks");
	}

	return $playlist;
}


sub getPlaylists
{
	my ($library) = @_;
	display($dbg_rpl,0,"getPlaylists($library->{name})");
	my $playlists = $all_playlists->{$library->{uuid}};

	$playlists = initPlaylists($library) if !$playlists;

	my $num = @$playlists;
	display($dbg_rpl,0,"getPlaylists($library->{name}) returning $num playlists");
	return $playlists;
}


sub initPlaylists
{
	my ($library) = @_;
	display($dbg_rpl,0,"initPlaylists($library->{name})");

	# initialize the in-memory cache
	# to prevent retrying on errors

	my $playlists = $all_playlists->{$library->{uuid}} = shared_clone([]);
	my $playlists_by_id = $all_playlists_by_id->{$library->{uuid}} = shared_clone({});

	# Do the device request to search for all playlist containers
	# We call didlRequest() directly as there are no records to insert in database

	my $dbg_name = 'Search(playlists)';
	my $params = $library->getParseParams($dbg_rpl,$dbg_name);

	$params->{service} = 'ContentDirectory';
	$params->{action} = 'Search';
	$params->{args} = [
		ContainerID => 0,
		SearchCriteria =>  'upnp:class derivedfrom "object.container.playlistContainer"',
		Filter => '*',
		StartingIndex => 0,
		RequestedCount => 9999,
		SortCriteria => '', ];

	my $didl = $library->didlRequest($params);

	if ($didl)
	{
		# The problem is that WMP returns the same playlist as a child of
		# multiple different containers, with no way to tell they are the same,
		# therefore WE WILL TAKE ONLY UNIQUE NAMES as given by the first
		# container->{dc:title}

		my $first_by_title = {};
		my $containers = $didl->{container};
		for my $container (@$containers)
		{
			my $id = $container->{id};
			my $title = $container->{'dc:title'};
			my $exists = $first_by_title->{$title};
			if ($exists)
			{
				display($dbg_rpl,1,"skiping duplicate title($id,$title) from previous($exists->{id})");
				next;
			}

			display($dbg_rpl,1,"adding playlist($id,$title)");
			my $playlist = shared_clone({
				id => $id,
				uuid => $library->{uuid},
				name => $title,
				num_tracks => $container->{childCount},
				shuffle => 0,
				track_index => 1, });
			bless $playlist,'remotePlaylist';

			$first_by_title->{$title} = $playlist;
			push @$playlists,$playlist;
			$playlists_by_id->{$id} = $playlist;

		}	# for each container
	}	# got didl

	my $num = @$playlists;
	display($dbg_rpl,0,"initPlaylists($library->{name}) returning $num playlists");
	return $playlists;

}	# initPlaylists




1;
