#!/usr/bin/perl
#---------------------------------------
# localRenderer.pm
#---------------------------------------
# See https://learn.microsoft.com/en-us/windows/win32/wmp/player-object

package localRenderer;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::OLE;
use artisanUtils;
use Renderer;
use Device;
use DeviceManager;
use base qw(Renderer);

my $dbg_lren = 0;
my $dbg_com_object = 1;


# field that get moved from a track to the renderer
# art_uri will be gotten from parent if not available
# pretty_size is built for each request

my @track_fields_to_renderer = qw(
	artist
	album_title
	duration
	genre
	title
	track_num
	year_str);


# Media Player COM object

my $mp = Win32::OLE->new('WMPlayer.OCX');
my $controls = $mp->{controls};
my $settings = $mp->{settings};
$settings->{autoStart} = 0;

if ($dbg_com_object <= 0)
{
	display_hash(0,0,"mp",$mp);
	display_hash(0,0,"controls",$controls);
	display_hash(0,0,"settings",$controls);
}

# $mp->{playState}
#
my $MP_STATE_STOPPED 		= 1; 	# Playback of the current media item is stopped.
my $MP_STATE_PAUSED 		= 2; 	# Playback of the current media item is paused. When a media item is paused, resuming playback begins from the same location.
my $MP_STATE_PLAYING 		= 3; 	# The current media item is playing.
my $MP_STATE_SCANFORWARD 	= 4; 	# The current media item is fast forwarding.
my $MP_STATE_SCANREVERSE 	= 5; 	# The current media item is fast rewinding.
my $MP_STATE_BUFFERING 		= 6; 	# The current media item is getting additional data from the server.
my $MP_STATE_WAITING 		= 7; 	# Connection is established, but the server is not sending data. Waiting for session to begin.
my $MP_STATE_MEDIAENDED 	= 8; 	# Media item has completed playback.
my $MP_STATE_TRANSITIONING	= 9; 	# Preparing new media item.
my $MP_STATE_READY 			= 10; 	# Ready to begin playing.
my $MP_STATE_RECONNECTING 	= 11; 	# Reconnecting to stream.


#------------------------------------
# methods
#--------------------------------------


sub new
{
	my ($class) = @_;
	display($dbg_lren,0,"localRenderer::new()");
	my $this = $class->SUPER::new({
		local => 1,
		uuid  => $this_uuid,
		name  => $program_name });
	bless $this,$class;

	mergeHash($this, shared_clone({
		state   => $RENDERER_STATE_INIT,
        maxVol  => 100,
        canMute => 1,
        maxBal  => 100,
		transportURL => "http://$server_ip:$server_port/AVTransport",
        controlURL   => "http://$server_ip:$server_port/control",
		playlist => '',
	}));

	return $this;
}


sub checkParam
{
	my ($error,$command,$params,$field) = @_;
	my $value = $params->{$field};
	$value = undef if defined($value) && $value eq '';
	$$error = error("localRenderer doCommand($command) param($field) not found in request")
		if !defined($value);
	return $value;
}


sub doCommand
	# returns '' for success, or an error message
	#
	# Supports the following commands and arguments
	#
	#   update
	#	stop
	#   play
	#	pause
	#   play_pause
	#   next
	#   prev
	#
	#	mute 0 or 1		- not implemented yet
	#	loud 0 or 1
	#	volume 0..100
	#	balance -100..+100
	#	fade -100..100
	#	bassLevel 0..100
	#	midLevel 0..100
	#	highLevel 0..100
	#		value =>
	#   seek
	#		position => ms
	#
	#   play_song =>    currently only supports local library
	#		library_uuid => uuid
	#		id => id
	#
	#   set_playlist
	#		plsource_uuid => uuid
	#       name => name
	#	playlist_song
	#		index => index to use
	#	shuffle_playlist
	#		value => 0,1,2
{
	my ($this,$command,$params) = @_;

	my $extra_dbg = $command eq 'update' ? 1 : 0;
    display_hash($dbg_lren + $extra_dbg,0,"doCommand($command)",$params);

	my $error = '';
	if ($command eq 'update')
	{
		$error = $this->update();
	}
	elsif ($command eq 'stop')
	{
		$controls->stop();
		warning(0,0,"doCommand(stop) in state $this->{state}")
			if $this->{state} eq $RENDERER_STATE_INIT;
		$this->{state} = $RENDERER_STATE_STOPPED;
	}
	elsif ($command eq 'pause')
	{
		if ($this->{state} eq $RENDERER_STATE_PLAYING)
		{
			$controls->pause();
			$this->{state} = $RENDERER_STATE_PAUSED;
		}
		else
		{
			warning(0,0,"doCommand(pause) while not $RENDERER_STATE_PLAYING");
		}
	}
	elsif ($command eq 'play_pause')
	{
		if ($this->{state} eq $RENDERER_STATE_PLAYING)
		{
			$controls->pause();
			$this->{state} = $RENDERER_STATE_PAUSED;
		}
		elsif ($this->{state} eq $RENDERER_STATE_PAUSED)
		{
			$controls->play();
			$this->{state} = $RENDERER_STATE_PLAYING;
		}
		else
		{
			warning(0,0,"doCommand(play_pause) in state $this->{state}");
		}
	}
	elsif ($command eq 'seek')
	{
		# convert seek in milliseconds to seconds

		if ($this->{state} eq $RENDERER_STATE_PLAYING ||
			$this->{state} eq $RENDERER_STATE_PAUSED)
		{
			my $ms = checkParam(\$error,$command,$params,'position');
			return $error if !defined($ms);
			$this->{position} = $ms;
			$controls->{currentPosition} = $ms / 1000;
		}
		else
		{
			warning(0,0,"doCommand(seek) in state $this->{state}");
		}
	}
	elsif ($command eq 'next')
	{
		$error = $this->playlist_song(1);
	}
	elsif ($command eq 'prev')
	{
		$error = $this->playlist_song(-1);
	}
	elsif ($command eq 'playlist_song')
	{
		my $index = checkParam(\$error,$command,$params,'index');
		return $error if !defined($index);
		my $playlist = $this->{playlist};
		return error("no playlist in doCommand($command)")
			if !$playlist;
		return error("doCommand($command) index($index) out of range 1..$playlist->{num_tracks}")
			if $index<1 || $index>$playlist->{num_tracks};
		$playlist->{track_index} = $index;	# intimate knowledge of localPlaylist
		$error = $this->playlist_song(0);
	}
	elsif ($command eq 'shuffle_playlist')
	{
		my $value = checkParam(\$error,$command,$params,'value');
		return $error if !defined($value);
		my $playlist = $this->{playlist};
		return error("no playlist in doCommand($command)")
			if !$playlist;
		$playlist->{shuffle} = $value;
		$playlist->sortPlaylist();
		$error = $this->playlist_song(0);
	}

	# currently only implemented for localLibrary and localPlaylist

	elsif ($command eq 'play_song')
	{
		my $library_uuid = checkParam(\$error,$command,$params,'library_uuid');
		return $error if !defined($library_uuid);

		my $track_id = checkParam(\$error,$command,$params,'track_id');
		return $error if !defined($track_id);

		return error("doCommand('play_song') library($library_uuid) not supported")
			if $library_uuid ne $local_library->{uuid};

		my $track = $local_library->getTrack($track_id);
		return error("doCommand('play_song') could not find track($track_id)")
			if !$track;

		$this->play_track($track);
	}

	elsif ($command eq 'set_playlist')
	{
		my $library_uuid = checkParam(\$error,$command,$params,'library_uuid');
		return $error if !defined($library_uuid);

		my $name = checkParam(\$error,$command,$params,'name');
		return $error if !defined($name);

		return error("doCommand('set_playlist') library($library_uuid) not supported")
			if $library_uuid ne $local_library->{uuid};

		$this->{playlist} = localPlaylist::getPlaylist($name);
		$error = $this->playlist_song(0);

	}
	else
	{
		return error("unknown doCommand($command)");
	}

	return $error;

}	# doCommand()




sub play_track
{
	my ($this,$track) = @_;

	display($dbg_lren,1,"play_track($track->{path}) duration=$track->{duration}");

	for my $field (@track_fields_to_renderer)
	{
		$this->{metadata}->{$field} = $track->{$field};
	}
	$this->{metadata}->{pretty_size} = bytesAsKMGT($track->{size});
	my $ext = $track->{path} =~ /\.(.*?)$/ ? uc($1) : '';
	$this->{metadata}->{type} = $ext;

	# get the art from the parent folder

	$this->{metadata}->{art_uri} = "http://$server_ip:$server_port/get_art/$track->{parent_id}/folder.jpg";
	if (!$this->{metadata}->{art_uri})
	{
		my $folder = $local_library->getFolder($track->{parent_id});
		$this->{metadata}->{art_uri} = $folder->{art_uri};
	}

	$this->{position} = 0;

	my $path = "$mp3_dir/$track->{path}";
	$path =~ s/\//\//g;

	# use streaming url versus local file path ...
	# turned off for now, but it definitely worked
	# with the localRender on 2023-11-14 at 3:44pm

	if (1)
	{
		$path = "http://$server_ip:$server_port/media/$track->{id}.mp3";
		display($dbg_lren,2,"using url='$path'");
	}

	$mp->{URL} = $path;
	$controls->play();
	$this->{state} = $RENDERER_STATE_PLAYING;
}



sub playlist_song
{
	my ($this,$inc) = @_;
	my $playlist = $this->{playlist};
	return error("no playlist!")
		if !$playlist;

	my $name = $playlist->{name};
	if (!$playlist->{num_tracks})
	{
		$this->{playlist} = '';
		return error('empty playlist($name)!');
	}
	my $entry = $playlist->getTrackEntry($inc);
	return error("Could not get entry(1) from playlist($name)")
		if !$entry;

	# temporary startup code

	my $library = findDevice($DEVICE_TYPE_LIBRARY,$entry->{uuid});
	return error("Could not get library($entry->{uuid}) for index($entry->{index}) from playlist($name)")
		if !$library;

	my $track = $library->getTrack($entry->{id});
	return error("Could not get track($entry->{id} from library($entry->{uuid}) for index($entry->{index}) from playlist($name)")
		if !$track;

	$this->play_track($track);
	return '';
}



sub update
    # update the status of the renderer
	# and if playing, handle playlist transitions

    # If it is playing, get the position and
    # metainfo and do heuristics.
{
    my ($this) = @_;

    display($dbg_lren+1,0,"update($this->{name})");

	if ($this->{state} eq $RENDERER_STATE_PLAYING)
	{
		my $media = $mp->{currentMedia};
		$this->{position} = $controls->{currentPosition} * 1000 || 0;
		$this->{duration} = $media ? $media->{duration} * 1000 : 0;
		display($dbg_lren+1,1,"position=$this->{position} duration=$this->{duration}");

		# we stop the player and move to the next playlist song

		my $play_state = $mp->{playState};
		display($dbg_lren+1,0,"play_state=$play_state");

		if ($play_state == $MP_STATE_STOPPED)
		{
			$controls->stop();
			$this->{state} = $RENDERER_STATE_STOPPED;
			if ($this->{playlist})
			{
				display($dbg_lren,2,"update() playing next playlist song ...");
				my $error = $this->playlist_song(1);
				return $error if $error;
			}
		}
	}

	return '';
}



1;