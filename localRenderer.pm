#!/usr/bin/perl
#---------------------------------------
# localRenderer.pm
#---------------------------------------
# See https://learn.microsoft.com/en-us/windows/win32/wmp/player-object
#
# Playing the Queue vs Playlist(s)
#
# A Renderer is playing on or the other of the current Queue
# and a potential Playlist. The Queue can end, Playlists wrap.s
#
# As currently implemented, an 'immediate' play (single song)
# has the effect of replacing the item in the current Queue/Playlist.
# if the song ends, or if they they hit >> forward from there, they go to
# the next song in the Queue/Playlist. If they hit << they play the song
# that was previously playing.  This behavior is 'ok', as is the fact
# that we start songs from the beginning when a playlist is interrupted
# and then restarted ... minor details for another day.

package localRenderer;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
# use mpWin on windows
use if is_win, 'mpWin';
# use mpMPG123 on Linux
use if !is_win, 'mpMPG123';
# unused mpHTML on linux
# use if !is_win, 'mpHTML';
use Renderer;
use Device;
use DeviceManager;
use artisanPrefs;
use Queue;
use base qw(Renderer);

my $dbg_lren = 0;
my $dbg_hren = 0;
	# html renderer specific


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


sub running
	# returns $mp_running as exported by mpXXX.pm
{
	my ($this) = @_;
	return $mp_running;
}


sub checkMPStart
	# called from mpXXX.pm in idle loop to see
	# if a new song needs to start playing
{
	my ($this,$mp,$stopped) = @_;
	my $queue = Queue::getQueue($this->{uuid});

	# in all cases start playing the queue if
	# needs_start changes

	if ($this->{q_needs_start} != $queue->{needs_start})
	{
		$this->{q_needs_start} = $queue->{needs_start};
		$this->{playing} = $RENDERER_PLAY_QUEUE;
		my $track = $queue->{tracks}->[$queue->{track_index}];
		if ($track)
		{
			display(0,0,"queue needs_start($this->{q_needs_start}} ($queue->{track_index}) $track->{title}");
			$this->play_track($track->{library_uuid},$track->{id});
		}
		else
		{
			stopMP($this,$mp);
		}
	}
	elsif ($stopped)
	{
		if ($this->{state} eq $RENDERER_STATE_PLAYING)
		{
			if ($this->{playing} == $RENDERER_PLAY_PLAYLIST)
			{
				$this->playlist_song($PLAYLIST_RELATIVE,1);
			}
			else
			{
				my $rslt = Queue::queueCommand('next',{renderer_uuid=>$this->{uuid}});
				stopMP($this,$mp) if $rslt->{error};
			}
		}

		# called without $mp from HTML_RENDERER, this prevents
		# us from clearing the meta data on a restart ...
		elsif ($mp)
		{
			stopMP($this,$mp);
		}
	}
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
		name  => $program_name,
		ip    => $server_ip,		# unused, added for consistency
		port  => $server_port, });
	bless $this,$class;

	mergeHash($this, shared_clone({
		state   => $RENDERER_STATE_INIT,
        maxVol  => 100,
        canMute => 1,
        maxBal  => 100,
		transportURL => "http://$server_ip:$server_port/AVTransport",
        controlURL   => "http://$server_ip:$server_port/control",
		playing => $RENDERER_PLAY_QUEUE,
	}));

	my $queue = Queue::getQueue($this->{uuid});
	$this->{q_needs_start} = $queue->{needs_start};

	my $thread = threads->create(\&mpThread,$this);
	$thread->detach();

	$this->{volume} = getPreference($PREF_RENDERER_VOLUME);
	$this->{muted} = getPreference($PREF_RENDERER_MUTE);

	doMPCommand($this,$this->{muted} ? 'mute' : 'unmute');
	doMPCommand($this,"volume,$this->{volume}");

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
	#   seek
	#		position => ms
	#
	#   play_song =>
	#		library_uuid => uuid
	#		track_id => id
	#
	#	set_playing
	#		playing=$RENDERER_PLAY_XXX
	#
	#   next
	#   prev
	#	next_album
	#	prev_album
	#
	#   set_playlist
	#		library_uuid => uuid
	#       id => playlist_id
	#	playlist_song
	#		index => index to use
	#	shuffle
	#		how => $SHUFFLE_XXX  (0,1,2)
	#
	#	toggle_mute
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

{
	my ($this,$command,$params) = @_;
	my $extra_dbg = $command eq 'update' ? 1 : 0;
    display_hash($dbg_lren + $extra_dbg,0,"doCommand($command) playing($this->{playing})",$params);
	my $queue = Queue::getQueue($this->{uuid});

	my $error = '';
	if ($command eq 'update')
	{
		# Special Handling for HTML Audio 'device'

		my $mp = $this->{html_audio};
		if ($mp)
		{
			my $state = $params->{html_audio_state} || '';
			my $version = $params->{html_audio_version} || 0;
			my $position = $params->{html_audio_position} || 0;
			my $duration = $params->{html_audio_duration} || 0;

			display($dbg_hren+1,0,"HTML_AUDIO UPDATE($state) V($version) pos($position) dur($duration)");

			# the position and duration are relatively
			# intelligently handled, so, at least for now,
			# we just set em'

			$this->{position} = $position;
			$this->{duration} = $duration;

			# We clear the command and updazte the renderer's state
			# after a given command once the version number is 'acknowledged'.
			# This handles all state changes EXCEPT if a song ends in the JS.

			if ($mp->{command} && $version >= $mp->{version})	# command ACK
			{
				display($dbg_hren,1,"clearing command $mp->{command}");
				$mp->{command} = '';
				$this->{state} = $state;
			}

			# The tricky part is understanding the difference between
			# the JS stopping from a stop command, versus stopping from
			# a end event.  Therefore we only checkMPStart() on the ELSE
			# from a command.

			else
			{
				$this->checkMPStart(undef,$state eq $RENDERER_STATE_STOPPED ? 1 : 0);
			}
		}

		# if they just added tracks, then we go from INIT to STOPPED

		$this->{state} = $RENDERER_STATE_STOPPED
			if $queue->{num_tracks} && $this->{state} eq $RENDERER_STATE_INIT;

		$this->copyQueue($queue);
	}
	elsif ($command eq 'stop')
	{
		if ($this->{state} eq $RENDERER_STATE_INIT)
		{
			warning(0,0,"doCommand(stop) in state $this->{state}")
		}
		elsif ($this->{state} eq $RENDERER_STATE_STOPPED)
		{
			# 2nd press of button clears the renderer,
			# clearing the queue, metadata, and setting
			# it back to RENDERER_STATE_INIT. The call
			# to doMPCommand() will call stopMP() again
			# in a few MS.

			delete $this->{playlist};
			$this->{playing} = $RENDERER_PLAY_QUEUE;
			Queue::queueCommand('clear',{renderer_uuid=>$this->{uuid}});
				# never fails
			$this->copyQueue($queue);
			$this->{state} = $RENDERER_STATE_INIT;
			stopMP($this);
			doMPCommand($this,'stop');
		}
		else
		{
			stopMP($this);
			doMPCommand($this,'stop');
		}
	}

	elsif ($command eq 'pause')
	{
		if ($this->{state} eq $RENDERER_STATE_PLAYING)
		{
			doMPCommand($this,'pause');
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
			doMPCommand($this,'pause');
		}
		elsif ($this->{state} eq $RENDERER_STATE_PAUSED)
		{
			doMPCommand($this,'play');
		}
		elsif ($this->{playing} == $RENDERER_PLAY_PLAYLIST)
		{
			$error = $this->playlist_song($PLAYLIST_RELATIVE,0);
		}
		elsif ($this->{state} eq $RENDERER_STATE_STOPPED)
		{
			Queue::queueCommand('restart',{renderer_uuid=>$this->{uuid}});
				# never fails
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
			doMPCommand($this,'set_position,'.$ms);
		}
		else
		{
			warning(0,0,"doCommand(seek) in state $this->{state}");
		}
	}

	# Play song immediate outside of Queue/Playlist framework

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
	# volume commands
	#-------------------------------------

	elsif ($command eq 'toggle_mute')
	{
		$this->{muted} = $this->{muted} ? 0 : 1;
		doMPCommand($this,$this->{muted} ? 'mute' : 'unmute');
		setPreference($PREF_RENDERER_MUTE,$this->{muted});
	}
	elsif ($command eq 'set_volume')
	{
		my $volume = checkParam(\$error,$command,$params,'volume');
		return $error if !defined($volume);
		$this->{muted} = 0;
		$this->{volume} = $volume;
		doMPCommand($this,"volume,$volume");
		setPreference($PREF_RENDERER_VOLUME,$this->{volume});
	}

	#-------------------------------------
	# transport commands
	#-------------------------------------
	# The Renderer can be playing the Queue AND/OR a Playlist.
	# The following transport commands apply to the current
	# thing that is playing.
	#
	# The Queue can End, but Playlists wrap.

	elsif ($command eq 'set_playing')
	{
		my $playing = $params->{playing} || 0;
		if ($this->{playing} != $playing)
		{
			$this->{playing} = $playing;
			if ($playing == $RENDERER_PLAY_PLAYLIST)
			{
				$this->playlist_song($PLAYLIST_RELATIVE,0);
			}
			else
			{
				$queue->{needs_start}++;
			}
		}

	}


	elsif ($command eq 'next')
	{
		if ($this->{playing} == $RENDERER_PLAY_PLAYLIST)
		{
			$error = $this->playlist_song($PLAYLIST_RELATIVE,1);
		}
		else
		{
			my $rslt = Queue::queueCommand($command,{renderer_uuid=>$this->{uuid}});
			$error = $rslt->{error};
		}
	}
	elsif ($command eq 'prev')
	{
		if ($this->{playing} == $RENDERER_PLAY_PLAYLIST)
		{
			$error = $this->playlist_song($PLAYLIST_RELATIVE,-1);
		}
		else
		{
			my $rslt = Queue::queueCommand($command,{renderer_uuid=>$this->{uuid}});
			$error = $rslt->{error};
		}
	}
	elsif ($command eq 'next_album')
	{
		if ($this->{playing} == $RENDERER_PLAY_PLAYLIST)
		{
			$error = $this->playlist_song($PLAYLIST_ALBUM_RELATIVE,1);
		}
		else
		{
			my $rslt = Queue::queueCommand($command,{renderer_uuid=>$this->{uuid}});
			$error = $rslt->{error};
		}
	}
	elsif ($command eq 'prev_album')
	{
		if ($this->{playing} == $RENDERER_PLAY_PLAYLIST)
		{
			$error = $this->playlist_song($PLAYLIST_ALBUM_RELATIVE,-11);
		}
		else
		{
			my $rslt = Queue::queueCommand($command,{renderer_uuid=>$this->{uuid}});
			$error = $rslt->{error};
		}
	}


	#-------------------------------------
	# playlist commands
	#-------------------------------------
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

		$this->{playing} = $RENDERER_PLAY_PLAYLIST;
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

	elsif ($command eq 'shuffle')
	{
		my $how = checkParam(\$error,$command,$params,'how');
		return $error if !defined($how);

		if ($this->{playing} == $RENDERER_PLAY_PLAYLIST)
		{
			my $playlist = $this->{playlist};
			return error("no playlist in doCommand($command)")
				if !$playlist;

			my $library_uuid = $playlist->{uuid};
			my $library = findDevice($DEVICE_TYPE_LIBRARY,$library_uuid);
			return error("Could not find library($library_uuid)")
				if !$library;

			my $pl_id = $playlist->{id};
			display($dbg_lren,1,"calling library::sortPlaylist($library_uuid,$pl_id,$how) name=$playlist->{name}");
			my $new_pl = $library->sortPlaylist($pl_id,$how);

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
			my $rslt = Queue::queueCommand('shuffle',{
				renderer_uuid=>$this->{uuid},
				how=>$how});
			$error = $rslt->{error};
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
	$this->{metadata}->{library_uuid} = $library_uuid;

	# special handling for Artisan servers
	# get the art from the parent folder by fully qualified ip:port

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

	doMPCommand($this,'play,'.$path);
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
