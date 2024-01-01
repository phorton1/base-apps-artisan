#!/usr/bin/perl
#---------------------------------------
# mpWin.pm
#---------------------------------------
# See https://learn.microsoft.com/en-us/windows/win32/wmp/player-object
#
# Abstract the Win32::OLE Windows Media Player for localRenderer.
# Counterpart to mpLinux.pm for rPi.
#
# EXPORTS
#	$mp_running boolean
#
# API:
#
#   mpThread($renderer)
#		starts the thread
#
#	stopMP($renderer,[$mp])
#	    stops the player if $mp passed in
#		sets renderer->position to 0
#		sets renderer->duration to 0
#		deletes renderer->metadata
#		sets renderer->state to $RENDERER_STATE_STOPPED
#			if renderer->state is not $RENDERER_STATE_INIT
#	doMPCommand()
#		mute
#		unmute
#			mutes or unmutes sound
#			state maintained by local renderer
#		stop
#			calls stopMP()
#   	pause
#			pauses the player
#			sets renderer->state to $RENDERER_STATE_PAUSED
#   	play
#			starts the (paused) player
#			sets renderer->state to $RENDERER_STATE_PLAYING
#   	set_position,MS
#			sets the position to the given milliseconds
#			renderer->position will be updated in loop
#   	play,URL
#			starts playing the song given by the URL
#			sets renderer->state to $RENDERER_STATE_PLAYING
#
# Loop
#
#	in $RENDERER_STATE_PLAYING
#		updates renderer->position
#		updates renderer->duration
#	calls renderer->checkMPStart($mp,$stopped)
#		which can then check the queue for needed restarts
#       and/or advance the song in playlist/queue if $stopped



# Constructed in the context of a localRenderer, it calls methods
# to advance songs automatically. Otherwise

package mpWin;
use strict;
use warnings;
use threads;
use threads::shared;
use Win32::OLE;
use Time::HiRes qw(sleep);
use artisanUtils;
use Renderer;


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


BEGIN
{
 	use Exporter qw( import );

	# our constants

	our @EXPORT = qw (
		$mp_running
		mpThread
		stopMP
		doMPCommand
	);
}




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


our $mp_running:shared = 0;
my $mp_command_queue:shared = shared_clone([]);
	# stop
	# pause
	# play,optional_url
	# set_position,millis



sub doMPCommand
{
	my ($renderer,$command) = @_;
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
	my ($renderer,$mp) = @_;
	$mp->close() if $mp;
	$renderer->{state} = $RENDERER_STATE_STOPPED
		if $renderer->{state} ne  $RENDERER_STATE_INIT;
	$renderer->{position} = 0;
	$renderer->{duration} = 0;
	delete $renderer->{metadata};
}


sub mpThread
	# handles all state changes
{
	my ($renderer) = @_;
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
			my $mp_command = shift @$mp_command_queue;
			if ($mp_command)
			{
				display($dbg_mp,1,"doing command '$mp_command'");

				# there is no $controls->stop() method
				# instead you 'close()' the current media file

				if ($mp_command eq 'stop')
				{
					stopMP($renderer,$mp);
				}
				elsif ($mp_command eq 'pause')
				{
					$controls->pause();
					$renderer->{state} = $RENDERER_STATE_PAUSED;
				}
				elsif ($mp_command eq 'play')
				{
					$controls->play();
					$renderer->{state} = $RENDERER_STATE_PLAYING;
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
					$renderer->{state} = $RENDERER_STATE_PLAYING;
				}
				elsif ($mp_command eq 'mute')
				{
					$settings->{mute} = 1;
				}
				elsif ($mp_command eq 'unmute')
				{
					$settings->{mute} = 0;
				}

			}
			else
			{
				my $mp_state = $mp->{playState} || 0;

				display($dbg_mp+1,0,"mp_state($mp_state) state($renderer->{state})");

				if ($renderer->{state} eq $RENDERER_STATE_PLAYING)
				{
					my $media = $mp->{currentMedia};
					my $position = $controls->{currentPosition};
					my $duration = $media ? $media->{duration} : 0;
					$position ||= 0;
					$duration ||= 0;
					$renderer->{position} = $position * 1000;
					$renderer->{duration} = $duration * 1000;
				}

				$renderer->checkMPStart($mp,$mp_state == $MP_STATE_STOPPED ? 1 : 0);
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


1;