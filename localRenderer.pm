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
use Time::HiRes qw(sleep);
use artisanUtils;
use Renderer;
use Device;
use DeviceManager;
use base qw(Renderer);

my $dbg_lren = 0;
my $dbg_mp = 0;


# field that get moved from a track to the renderer
# art_uri will be gotten from parent if not available
# pretty_size is built for each request

my @track_fields_to_renderer = qw(
	artist
	album_title
	duration
	genre
	title
	type
	track_num
	year_str);


#------------------------------------------------------------------
# Media Player COM object
#------------------------------------------------------------------
# Has to be wrapped in it's own thread and communicated with
# via shared memory variables

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


my $mp_running:shared = 0;
my $mp_command:shared = '';
	# stop
	# pause
	# play,optional_url
	# set_position,millis
my $mp_state:shared		= 0;		# out
my $mp_position:shared	= '';		# out
my $mp_duration:shared	= '';		# out

sub running
{
	my ($this) = @_;
	return $mp_running;
}


sub doMPCommand
{
	my ($command) = @_;
	display($dbg_mp+1,0,"doMPCommand($command) starting");
	while ($mp_command)
	{
		sleep(0.01);
	}
	display($dbg_mp,0,"doMPCommand($command)");
	$mp_command = $command;
}


sub mpThread
{
	my $mp = Win32::OLE->new('WMPlayer.OCX');
	my $controls = $mp->{controls};
	my $settings = $mp->{settings};
	$settings->{autoStart} = 0;
	display($dbg_mp,0,"mpThread() started");
	$mp_running = 1;
	while (1)
	{
		if (!$quitting)
		{
			if ($mp_command)
			{
				display($dbg_mp+1,1,"doing command '$mp_command'");
				$controls->stop() if $mp_command eq 'stop';
				$controls->pause() if $mp_command eq 'pause';
				$controls->play() if $mp_command eq 'play';
				if ($mp_command =~ /^set_position,(.*)$/)
				{
					my $mp_position = $1;
					display($dbg_mp+1,2,"doing set_position($mp_position)");
					$controls->{currentPosition} = $mp_position/1000;
				}
				if ($mp_command =~ /^play,(.*)$/)
				{
					my $url = $1;
					display($dbg_mp+1,2,"doing play($url)");
					$mp->{URL} = $url;
					$controls->play();
				}
				$mp_command = '';
			}
			else
			{
				$mp_state = $mp->{playState} || 0;
				$mp_position = $controls->{currentPosition} * 1000 || 0;
				my $media = $mp->{currentMedia};
				$mp_duration = $media ? $media->{duration} * 1000 : 0;
			}
			sleep(0.1);
		}
		elsif ($mp_running)
		{
			display($dbg_mp,0,"suspending mpThread");
			$mp->close();
			$controls = undef;
			$settings = undef;
			$mp = undef;
			$mp_running = 0;
			display($dbg_mp,0,"mpThread suspended");
		}
		else
		{
			sleep(1);
		}
	}

	# never gets here
	$mp->close();
	$controls = undef;
	$settings = undef;
	$mp = undef;
	display($dbg_mp,0,"mpThread() ended");
}


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

	my $thread = threads->create(\&mpThread);
	$thread->detach();

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
		doMPCommand('stop');	# $controls->stop();
		warning(0,0,"doCommand(stop) in state $this->{state}")
			if $this->{state} eq $RENDERER_STATE_INIT;
		$this->{state} = $RENDERER_STATE_STOPPED;
	}
	elsif ($command eq 'pause')
	{
		if ($this->{state} eq $RENDERER_STATE_PLAYING)
		{
			doMPCommand('pause');	# $controls->pause();
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
			doMPCommand('pause');	# $controls->pause();
			$this->{state} = $RENDERER_STATE_PAUSED;
		}
		elsif ($this->{state} eq $RENDERER_STATE_PAUSED)
		{
			doMPCommand('play');	# $controls->play();
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
			doMPCommand('set_position,'.$ms);	# $controls->{currentPosition} = $ms / 1000;
		}
		else
		{
			warning(0,0,"doCommand(seek) in state $this->{state}");
		}
	}

	elsif ($command eq 'play_song')
	{
		my $library_uuid = checkParam(\$error,$command,$params,'library_uuid');
		return $error if !defined($library_uuid);
		my $track_id = checkParam(\$error,$command,$params,'track_id');
		return $error if !defined($track_id);
		$error = $this->play_track($library_uuid,$track_id);
		return $error;
	}


	#-------------------------------------
	# playlist commands
	#-------------------------------------
	# next and prev

	elsif ($command eq 'next')
	{
		$error = $this->playlist_song(1);
	}
	elsif ($command eq 'prev')
	{
		$error = $this->playlist_song(-1);
	}

	# start a playlist on the current index of the playlist

	elsif ($command eq 'set_playlist')
	{
		my $library_uuid = checkParam(\$error,$command,$params,'library_uuid');
		return $error if !defined($library_uuid);

		my $playlist_id = checkParam(\$error,$command,$params,'id');
		return $error if !defined($playlist_id);

		return error("doCommand('set_playlist') library($library_uuid) not supported")
			if $library_uuid ne $local_library->{uuid};

		$this->{playlist} = localPlaylist::getPlaylist($playlist_id);
		$this->{playlist}->{library_name} = $local_library->{name};
		$error = $this->playlist_song(0);
	}

	# play a song by index within the current playlist

	elsif ($command eq 'playlist_song')
	{
		my $index = checkParam(\$error,$command,$params,'index');
		return $error if !defined($index);

		my $playlist = $this->{playlist};
		return error("no playlist in doCommand($command)")
			if !$playlist;

		return error("doCommand($command) index($index) out of range 1..$playlist->{num_tracks}")
			if $index<1 || $index>$playlist->{num_tracks};

		# intimate knowledge of playlists!!!

		$playlist->{track_index} = $index;
		$error = $this->playlist_song(0);
	}

	# sort/shuffle the playlist

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




	else
	{
		return error("unknown doCommand($command)");
	}

	return $error;

}	# doCommand()




sub play_track
{
	my ($this,$library_uuid,$track_id) = @_;
	display($dbg_lren,1,"play_track($library_uuid,$track_id)");

	my $library = findDevice($DEVICE_TYPE_LIBRARY,$library_uuid);
	return error("Could not find library($library_uuid)")
		if !$library;

	my $track = $library->getTrack($track_id);
	return error("Could not find track($track_id)")
		if !$track;

	display($dbg_lren,1,"play_track($track->{path}) duration=$track->{duration}");

	for my $field (@track_fields_to_renderer)
	{
		$this->{metadata}->{$field} = $track->{$field};
	}
	$this->{metadata}->{pretty_size} = bytesAsKMGT($track->{size});

	# special handling for local library
	# get the art from the parent folder

	my $path = $track->{path};
	if ($library->{local})
	{
		$this->{metadata}->{art_uri} = "http://$server_ip:$server_port/get_art/$track->{parent_id}/folder.jpg";
		$path = "http://$server_ip:$server_port/media/$track->{id}.$track->{type}";
		# $path = "$mp3_dir/$track->{path}";		direct file access
	}
	else
	{
		$this->{metadata}->{art_uri} = $track->{art_uri};
	}

	$this->{position} = 0;
	doMPCommand('play,'.$path);
	$this->{state} = $RENDERER_STATE_PLAYING;
	return '';
}



sub playlist_song
	# starts a playlist on a particular index
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
	my $track_id = $playlist->getTrackId($inc);
	return error("Could not get getTrackId($inc) from playlist($name)")
		if !$track_id;

	$this->play_track($playlist->{uuid},$track_id);
	return '';

	# # temporary startup code
    #
	# my $library = findDevice($DEVICE_TYPE_LIBRARY,$playlist->{uuid});
	# return error("Could not get library($playlist->{uuid}) for playlist($name)")
	# 	if !$library;
    #
	# my $track = $library->getTrack($track_id);
	# return error("Could not get track($track_id} from library($playlist->{uuid}) for index($playlist->{track_index}) from playlist($name)")
	# 	if !$track;
    #
	# $this->play_track($track);
	# return '';
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
		# my $media = $mp->{currentMedia};
		$this->{position} = $mp_position;	# $controls->{currentPosition} * 1000 || 0;
		$this->{duration} = $mp_duration;	# $media ? $media->{duration} * 1000 : 0;
		display($dbg_lren+1,1,"position=$this->{position} duration=$this->{duration}");

		# we stop the player and move to the next playlist song

		my $play_state = $mp_state;		# $mp->{playState};
		display($dbg_lren+1,0,"play_state=$play_state");

		if ($play_state == $MP_STATE_STOPPED)
		{
			doMPCommand('stop');	# $controls->stop();
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