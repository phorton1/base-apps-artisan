#!/usr/bin/perl
#---------------------------------------
# remoteArtisan.pm
#---------------------------------------
# A pass through reference to a remote instance
# of an Artisan locaLibrary.
#
# library requests to remote_artisan libraries
# are already diverted to the other instance of
# Artisan by using the js library_url() method
#
# So this object only supports the following APIs
# needed by the localRenderer:
#
#	getTrack($track_id)
#	#	// getPlaylists()
#	#	getPlaylist($id)
#	#	getPlaylistTrack(
#
# I needed to move the Playlist APIs upto the library
# to support this (no-one should be calling $playlist->
# methods directly).


package remoteArtisan;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use LWP::UserAgent;
use base qw(Library);


my $dbg_alib = 0;


sub new
	# receives a $dev containing ip,port,services, etc
{
	my ($class,$params) = @_;
	display($dbg_alib,0,"remoteArtisan::new()");
	my $this = $class->SUPER::new($params);
	bless $this,$class;
	$this->{remote_artisan} = 1;
	$this->{state} = $DEVICE_STATE_READY;
	return $this;
}



sub getTrack
{
	my ($this,$id) = @_;
	display($dbg_alib,0,"getTrack($id)");
	my $obj = $this->remoteRequest("get_track?id=$id");
	bless $obj,'Track' if $obj;
	return $obj;
}


#	sub unused_getPlaylists
#	{
#		my ($this) = @_;
#		display($dbg_alib,0,"getPlaylists()");
#		return $this->remoteRequest("get_playlists");
#	}
#
#
#	sub getPlaylist
#		# pass thru
#	{
#		my ($this,$id) = @_;
#		display($dbg_alib,0,"getPlaylist($id)");
#		my $obj = $this->remoteRequest("get_playlist?id=$id");
#		bless $obj,'Playlist' if $obj;
#		return $obj;
#	}
#
#
#	sub getPlaylistTrack
#	{
#	    my ($this,$id,$version,$mode,$index) = @_;
#		display($dbg_alib,0,"getPlaylistTrack($id,$version,$mode,$index)");
#		my $obj = $this->remoteRequest("get_playlist_track?id=$id&version=$version&mode=$mode&index=$index");
#		bless $obj,'Playlist' if $obj;
#		return $obj;
#	}
#
#
#	sub sortPlaylist
#	{
#	    my ($this,$id,$shuffle) = @_;
#		display($dbg_alib,0,"sortPlaylist($id,$shuffle)");
#		my $obj = $this->remoteRequest("shuffle_playlist?id=$id&shuffle=$shuffle");
#		bless $obj,'Playlist' if $obj;
#		return $obj;
#	}
#

use JSON;
use Error qw(:try);



sub remoteRequest
{
	my ($this,$command) = @_;
	display($dbg_alib,0,"remoteRequest($command)");
	my $url = "http://$this->{ip}:$this->{port}/webui/library/$this->{uuid}/$command";
	display($dbg_alib,1,"url=$url");
	my $ua = LWP::UserAgent->new();
	my $response = $ua->get($url);
	return json_error("No response from get($url)") if !$response;
	my $content = $response->content();
	my $json = '';
	try
	{
		$json = decode_json($content);
	}
	catch Error with
	{
		my $ex = shift;   # the exception object
		error("Could not decode json: $ex");
	};

	display($dbg_alib,0,"remoteRequest returning json($json)");
	return shared_clone($json);
}


1;