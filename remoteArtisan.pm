#!/usr/bin/perl
#---------------------------------------
# remoteArtisan.pm
#---------------------------------------
# A pass through reference to a remote instance
# of an Artisan locaLibrary.
#
# Reworked for queues, I started with getFolder()
# Needs to be reworked again for HTML Renderers
#
# API
#
#	getTrack
#	getFolder
#	- getTrackMetadata
#	- getFolderMetadata
#	getSubitems

#   getPlaylist
#	getPlaylists



package remoteArtisan;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use httpUtils;
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


#---------------------------------------------
# support for direct calls from webUI
#---------------------------------------------

sub getTrack
{
	my ($this,$id) = @_;
	display($dbg_alib,0,"getTrack($id)");
	my $rec = $this->remoteRequest("get_track?id=$id");
	my $track = Track->newFromHash($rec);
	return $track;
}

sub getFolder
{
	my ($this,$id) = @_;
	display($dbg_alib,0,"getFolder($id)");
	my $rec = $this->remoteRequest("get_folder?id=$id");
	my $track = Folder->newFromHash($rec);
	return $track;
}




#	sub unused_getPlaylists
#	{
#		my ($this) = @_;
#		display($dbg_alib,0,"getPlaylists()");
#		return $this->remoteRequest("get_playlists");
#	}
#
#


sub getPlaylist
	# pass thru
{
	my ($this,$id) = @_;
	display($dbg_alib,0,"getPlaylist($id)");
	my $obj = $this->remoteRequest("get_playlist?id=$id");
	bless $obj,'Playlist' if $obj;
	return $obj;
}


sub getPlaylistTrack
{
    my ($this,$id,$version,$mode,$index) = @_;
	display($dbg_alib,0,"getPlaylistTrack($id,$version,$mode,$index)");
	my $obj = $this->remoteRequest("get_playlist_track?id=$id&version=$version&mode=$mode&index=$index");
	bless $obj,'Playlist' if $obj;
	return $obj;
}


sub sortPlaylist
{
    my ($this,$id,$shuffle) = @_;
	display($dbg_alib,0,"sortPlaylist($id,$shuffle)");
	my $obj = $this->remoteRequest("shuffle_playlist?id=$id&shuffle=$shuffle");
	bless $obj,'Playlist' if $obj;
	return $obj;
}


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
	my $json = my_json_decode($content);
	display($dbg_alib,0,"remoteRequest returning json($json)");
	return shared_clone($json);
}


1;