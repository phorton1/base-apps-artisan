#!/usr/bin/perl
#---------------------------------------
# remoteArtisanLibrary.pm
#---------------------------------------
# A Artisan Library running on another machine.
#
# This object is predicated on the fact that we encode the ip:port into
# the $this_uuid in artisanUtils.pm.
#
#		Artisan Perl-$server_ip-$server_port-($MACHINE_NAME)
#
# Then the webUI can call only the desired server for Library
# requests.
#
# I used to process uiLibrary.pm requests to THIS artisan (/library/uuid/blah)
# through to the other library, but that is no longer necessary.
#
# The webUI 'knows' that a library is a remoteArtisan and instead of
# even calling THIS Artisan at all, it calls directly to the OTHER
# artisan for any library/ requests.
#
# The most important thing that is important is that we register the device,
# keep track of it, and feed it back to the UI. We also map folder.jpg
# urls for these, like we do for localLibrary, in localRenderer.pm.

package remoteArtisanLibrary;
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
	display($dbg_alib,0,"remoteArtisanLibrary::new()");
	my $this = $class->SUPER::new($params);
	bless $this,$class;
	$this->{remote_artisan} = 1;
	$this->{state} = $DEVICE_STATE_READY;
	return $this;
}


#---------------------------------------------
# support for direct calls from Queue
#---------------------------------------------
# To the degree that the Queue lives on THIS machine, and
# the library *may* be a remoteArtisanLibrary, at least one
# call through to the remote library MUST be supported.

sub getQueueTracks
{
	my ($this,$rslt,$post_params) = @_;
	display($dbg_alib,0,"getQueueTracks($this->{name}) at $this->{ip}:$this->{port}");
	my $url = "http://$this->{ip}:$this->{port}/webui/library/$this->{uuid}/get_queue_tracks";
	display($dbg_alib,1,"url=$url");
	my $ua = LWP::UserAgent->new();
	my $response = $ua->post($url,$post_params);
	return json_error("No response from get($url)") if !$response;
	my $content = $response->content();
	my $json = my_decode_json($content);
	if (!$json)
	{
		$rslt->{error} = "getQueueTracks() Could not decode json result";
	}
	elsif ($json->{error})
	{
		error($json->{error});
		$rslt->{error} = $json->{error};
		$json = '';
	}
	display_hash($dbg_alib,0,"getQueueTracks returning",$json);
	return $json;
}





#	sub getTrack
#	{
#		my ($this,$id) = @_;
#		display($dbg_alib,0,"getTrack($id)");
#		my $rec = $this->remoteRequest("get_track?id=$id");
#		my $track = Track->newFromHash($rec);
#		return $track;
#	}
#
#	sub getFolder
#	{
#		my ($this,$id) = @_;
#		display($dbg_alib,0,"getFolder($id)");
#		my $rec = $this->remoteRequest("get_folder?id=$id");
#		my $track = Folder->newFromHash($rec);
#		return $track;
#	}
#
#
#
#
#	#	sub unused_getPlaylists
#	#	{
#	#		my ($this) = @_;
#	#		display($dbg_alib,0,"getPlaylists()");
#	#		return $this->remoteRequest("get_playlists");
#	#	}
#	#
#	#
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
#
#	sub remoteRequest
#	{
#		my ($this,$command) = @_;
#		display($dbg_alib,0,"remoteRequest($command)");
#		my $url = "http://$this->{ip}:$this->{port}/webui/library/$this->{uuid}/$command";
#		display($dbg_alib,1,"url=$url");
#		my $ua = LWP::UserAgent->new();
#		my $response = $ua->get($url);
#		return json_error("No response from get($url)") if !$response;
#		my $content = $response->content();
#		my $json = my_decode_json($content);
#		display($dbg_alib,0,"remoteRequest returning json($json)");
#		return shared_clone($json);
#	}


1;