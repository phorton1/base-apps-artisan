#!/usr/bin/perl
#---------------------------------------
# remmotePlaylist.pm
#---------------------------------------
# A Playlist has the following members:
#
#	id				- playlist id within the library
#   uuid			- uuid of the library
# 	name			- playlist title
# 	shuffle			- shuffle mode
#   num_tracks		- number of tracks in the playlist
#   track_index		- current track index within the playlist


package remmotePlaylist;
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


my $dbg_rpl = 1;


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


my $all_playlists:shared = shared_clone({});
my $all_playlists_by_id:shared = shared_clone({});



#------------------------------------------
# Constructors
#------------------------------------------

sub new
{
	my ($class,$params) = @_;
	display($dbg_rpl,0,"remotePlaylist::new($params->{uuid},$params->{id}) $params->{name}");

	my $this = shared_clone({
		id => '',
		uuid => '',
		name => '',
		query => '',
		shuffle => 0,
		num_tracks => 0,
		track_index => 0,
	});
	bless $this,$class;
	mergeHash($this,$params);

	my $uuid = $this->{uuid};
	my $playlists = $all_playlists->{$uuid};
	my $playlists_by_id = $all_playlists_by_id->{$uuid};
	$playlists = $all_playlists->{$uuid} = shared_clone([]) if !$playlists;
	$playlists_by_id = $all_playlists_by_id->{$uuid} = shared_clone({}) if !$playlists_by_id;

	push @$playlists,$this;
	$playlists_by_id->{$this->{id}} = $this;
	return $this;
}


sub getPlaylist
{
	my ($uuid,$id) = @_;
	my $playlists_by_id = $all_playlists_by_id->{$uuid};
	my $playlist = $playlists_by_id ? $playlists_by_id->{$id} : '';
	display($dbg_rpl,0,"getPlaylist($uuid,$id)=".($playlist?$playlist->{name}:'not found'));
	return $playlist;
}


sub getPlaylists()
{
	my ($uuid) = @_;
	my $playlists = $all_playlists->{$uuid};
	my $num = $playlists ? @$playlists : 0;
	display($dbg_rpl,0,"getPlaylists($uuid) returning $num playlists");
	return $playlists;
}


sub getTrackEntry
{
    my ($this,$inc) = @_;
    display($dbg_rpl,0,"getTrackEntry($this->{name},$this->{track_index}) inc=$inc");
    $this->{track_index} += $inc;
    $this->{track_index} = 1 if $this->{track_index} > $this->{num_tracks};
    $this->{track_index} = $this->{num_tracks} if $this->{track_index} < 1;
	return '';
}


sub sortPlaylist
{
	my ($this) = @_;
	my $name = $this->{name};
	display($dbg_rpl,0,"sortPlaylist($name)");

}




1;
