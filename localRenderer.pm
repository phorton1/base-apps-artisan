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
use Queue;
use base qw(Renderer);

my $dbg_lren = 0;
my $dbg_mp = 0;

Win32::OLE::prhSetThreadNum(1);
	# I found this old fix in my own build, under /src/wx/Win32_OLE.
	# This prevents threads from crashing on return (i.e. in HTTPServer
	# 	connections) by setting a flag into my version of Win32::OLE
	# 	that causees it to short return from it's AtExit() method,
	# 	not deleting anything. Otherwise threads get messed up.
	# Presumably everytinng is deleted when the main Perl interpreter
	# 	realy exits.
	# I *may* not have needed to enclose $mp in a loop, but it's
	#	done now so I'm not changing it!


# fields that get moved from a track to the renderer
# art_uri will be gotten from parent if not available
# pretty_size is built for each request

my @track_fields_to_renderer = qw(
	artist
	album_title
	duration
	genre
	title
	type
	tracknum
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
my $mp_command_queue:shared = shared_clone([]);
	# stop
	# pause
	# play,optional_url
	# set_position,millis


sub running
{
	my ($this) = @_;
	return $mp_running;
}


sub doMPCommand
{
	my ($command) = @_;
	display($dbg_mp,0,"doMPCommand($command)");
	push @$mp_command_queue,$command;
}


sub stopMP
	# When the queue reaches the end it 'stops', and
	# the renderer goes to RENDERER_STATE_STOPPED.
	# It can be 'restarted' by navigating to a previous
	# track or album, or via the Play button which will
	# start it over from the beginning.
{
	my ($this,$mp) = @_;
	$mp->close() if $mp;
	$this->{state} = $RENDERER_STATE_STOPPED;
	$this->{position} = 0;
	$this->{duration} = 0;
	delete $this->{metadata};
}


sub mpThread
	# handles all state changes
{
	my ($this) = @_;
	my $mp = Win32::OLE->new('WMPlayer.OCX');
	my $controls = $mp->{controls};
	my $settings = $mp->{settings};
	$settings->{autoStart} = 0;
	display($dbg_mp,0,"mpThread() started");
	$mp_running = 1;

	my $queue = Queue::getQueue($this->{uuid});
	my $last_update_time = time();

	while (1)
	{
		if (!$quitting)
		{
			my $mp_command = shift @$mp_command_queue;
			if ($mp_command)
			{
				display($dbg_mp,1,"doing command '$mp_command'");

				# there is no $controls->stop() method
				# instead you 'close()' the current media file

				if ($mp_command eq 'stop')
				{
					$this->stopMP($mp);
					$this->{state} = $RENDERER_STATE_INIT;
				}
				elsif ($mp_command eq 'pause')
				{
					$controls->pause();
					$this->{state} = $RENDERER_STATE_PAUSED;
				}
				elsif ($mp_command eq 'play')
				{
					$controls->play();
					$this->{state} = $RENDERER_STATE_PLAYING;
				}
				elsif ($mp_command =~ /^set_position,(.*)$/)
				{
					my $mp_position = $1;
					display($dbg_mp+1,2,"doing set_position($mp_position)");
					$controls->{currentPosition} = $mp_position/1000;
				}
				elsif ($mp_command =~ /^play,(.*)$/)
				{
					my $url = $1;
					display($dbg_mp+1,2,"doing play($url)");
					$mp->{URL} = $url;
					$controls->play();
					$this->{state} = $RENDERER_STATE_PLAYING;
				}
			}
			else
			{
				my $mp_state = $mp->{playState} || 0;

				display($dbg_mp+1,0,"mp_state($mp_state) state($this->{state})");

				if ($this->{state} eq $RENDERER_STATE_PLAYING)
				{
					my $media = $mp->{currentMedia};
					my $position = $controls->{currentPosition};
					my $duration = $media ? $media->{duration} : 0;
					$position ||= 0;
					$duration ||= 0;
					$this->{position} = $position * 1000;
					$this->{duration} = $duration * 1000;
				}

				# in all cases start playing the queue if it needs_start

				if ($queue->{needs_start})
				{
					$queue->{needs_start} = 0;
					my $track = $queue->getNextTrack();
					if ($track)
					{
						display(0,0,"starting queue(0) $track->{title}");
						$this->play_track($track->{library_uuid},$track->{id});
					}
					else
					{
						$this->stopMP($mp);
					}
				}

				elsif ($mp_state == $MP_STATE_STOPPED)
				{
					if ($this->{state} eq $RENDERER_STATE_PLAYING)
					{
						my $track = $queue->getNextTrack();
						if ($track)
						{
							display(0,0,"next queue() $track->{title}");
							$this->play_track($track->{library_uuid},$track->{id});
						}
						elsif ($this->{playlist}) 	# playlists currently wrap and never end
						{
							$this->playlist_song($PLAYLIST_RELATIVE,1);
						}
						else
						{
							$this->stopMP($mp);
						}
					}
					else
					{
						$this->stopMP($mp);
					}
				}
			}

			sleep($dbg_mp < 0 ? 1 : 0.1);
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
	}));

	if (1)
	{
		my $thread = threads->create(\&mpThread,$this);
		$thread->detach();
	}

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


sub copyQueue
{
	my ($this,$queue) = @_;
	$this->{queue} = shared_clone({});
	for my $key (keys %$queue)
	{
		next if $key eq 'tracks';
		$this->{queue}->{$key} = $queue->{$key};
	}
}


sub doCommand
	# returns '' for success, or an error message
	#
	# Supports the following commands and arguments
	#
	#   update
	#	stop
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
	#   play_song =>
	#		library_uuid => uuid
	#		track_id => id
	#
	#   set_playlist
	#		library_uuid => uuid
	#       id => playlist_id
	#	playlist_song
	#		index => index to use
	#	shuffle_playlist
	#		shuffle => 0,1,2
{
	my ($this,$command,$params) = @_;
	my $extra_dbg = $command eq 'update' ? 1 : 0;
    display_hash($dbg_lren + $extra_dbg,0,"doCommand($command)",$params);
	my $queue = Queue::getQueue($this->{uuid});

	my $error = '';
	if ($command eq 'update')
	{
		$this->copyQueue($queue);
	}
	elsif ($command eq 'stop')
	{
		if ($this->{state} eq $RENDERER_STATE_INIT)
		{
			warning(0,0,"doCommand(stop) in state $this->{state}")
		}
		else
		{
			# the 'stop' command clears the renderer,
			# clearing the queue, metadata, and setting
			# it back to RENDERER_STATE_INIT. The call
			# to doMPCommand() will call stopMP() again
			# in a few MS.

			$queue->clear();
			$this->copyQueue($queue);
			$this->stopMP();
			$this->{state} = $RENDERER_STATE_INIT;
			doMPCommand('stop');
		}
	}

	elsif ($command eq 'pause')
	{
		if ($this->{state} eq $RENDERER_STATE_PLAYING)
		{
			doMPCommand('pause');
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
			doMPCommand('pause');
		}
		elsif ($this->{state} eq $RENDERER_STATE_PAUSED)
		{
			doMPCommand('play');
		}
		elsif ($this->{state} eq $RENDERER_STATE_STOPPED)
		{
			$queue->restart();
			$this->copyQueue($queue);
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
			doMPCommand('set_position,'.$ms);
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
    #
	# elsif ($command eq 'next')
	# {
	# 	$error = $this->playlist_song($PLAYLIST_RELATIVE,1);
	# }
	# elsif ($command eq 'prev')
	# {
	# 	$error = $this->playlist_song($PLAYLIST_RELATIVE,-1);
	# }

	# start a playlist on the current index of the playlist
	# this command will trigger the creation of the
	# base_data/temp/Renderer/renderer_id/library_id/playlists.db file

	elsif ($command eq 'set_playlist')
	{
		my $library_uuid = checkParam(\$error,$command,$params,'library_uuid');
		return $error if !defined($library_uuid);

		my $playlist_id = checkParam(\$error,$command,$params,'id');
		return $error if !defined($playlist_id);

		my $library = findDevice($DEVICE_TYPE_LIBRARY,$library_uuid);
		return error("Could not find library($library_uuid)")
			if !$library;

		$this->{playlist} = $library->getPlaylist($playlist_id);
		$error = $this->playlist_song($PLAYLIST_RELATIVE,0);
	}

	# play a song by index within the current playlist

	elsif ($command eq 'playlist_song')
	{
		my $index = checkParam(\$error,$command,$params,'index');
		return $error if !defined($index);

		my $playlist = $this->{playlist};
		return error("no playlist in doCommand($command)")
			if !$playlist;

		$error = $this->playlist_song($PLAYLIST_ABSOLUTE,$index);
	}

	# sort/shuffle the playlist

	elsif ($command eq 'shuffle_playlist')
	{
		my $shuffle = checkParam(\$error,$command,$params,'shuffle');
		return $error if !defined($shuffle);

		my $playlist = $this->{playlist};
		return error("no playlist in doCommand($command)")
			if !$playlist;

		my $library_uuid = $playlist->{uuid};
		my $library = findDevice($DEVICE_TYPE_LIBRARY,$library_uuid);
		return error("Could not find library($library_uuid)")
			if !$library;

		my $pl_id = $playlist->{id};
		display($dbg_lren,1,"calling library::sortPlaylist($library_uuid,$pl_id,$shuffle) name=$playlist->{name}");
		my $new_pl = $library->sortPlaylist($pl_id,$shuffle);

		if (!$new_pl)
		{
			$error = "Could not sort playlist $playlist->{name}";
		}
		else
		{
			display($dbg_lren,1,"new_playlist".Playlist::dbg_info($new_pl,2));
			$this->{playlist} = $new_pl;
			$error = $this->playlist_song($PLAYLIST_ABSOLUTE,1);
		}

	}
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
	$this->{metadata} = shared_clone({});
	for my $field (@track_fields_to_renderer)
	{
		$this->{metadata}->{$field} = $track->{$field};
	}
	$this->{metadata}->{pretty_size} = prettyBytes($track->{size});

	# special handling for local library
	# get the art from the parent folder

	my $path = $track->{path};
	if ($library->{local} || $library->{remote_artisan})
	{
		my $library_ip = $library->{ip};
		my $library_port = $library->{port};
		$this->{metadata}->{art_uri} = "http://$library_ip:$library_port/get_art/$track->{parent_id}/folder.jpg";
		$path = "http://$library_ip:$library_port/media/$track->{id}.$track->{type}";
		# $path = "$mp3_dir/$track->{path}";		direct file access
	}
	else
	{
		$this->{metadata}->{art_uri} = $track->{art_uri};
	}

	$this->{position} = 0;

	doMPCommand('play,'.$path);
	return '';
}



sub playlist_song
	# starts a playlist on a particular index
	# note that the localRenderer keeps actual playlists, which
	# contain queries and will be written to the database!!
{
	my ($this,$mode,$index) = @_;
	my $playlist = $this->{playlist};
	return error("no playlist!")
		if !$playlist;


	my $library_uuid = $playlist->{uuid};
	my $library = findDevice($DEVICE_TYPE_LIBRARY,$library_uuid);
	return error("Could not find library($library_uuid)")
		if !$library;

	display($dbg_lren,0,"playlist_song($mode,$index) on".$playlist->dbg_info(2));

	my $pl_id = $playlist->{id};
	my $new_pl = $library->getPlaylistTrack($pl_id,$playlist->{version},$mode,$index);
	return error("No playlist returned by getPlaylistTrack($library_uuid,$pl_id)")
		if !$new_pl;

	display($dbg_lren,0,"new_playlist".Playlist::dbg_info($new_pl,2));

	$this->{playlist} = $new_pl;
	if ($new_pl->{track_id})
	{
		$this->play_track($new_pl->{uuid},$new_pl->{track_id});
	}
	else
	{
		return error("No {track_id} in new_playlist".Playlist::dbg_info($new_pl,2));
	}
	return '';
}




1;