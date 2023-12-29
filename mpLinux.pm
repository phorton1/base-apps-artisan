#!/usr/bin/perl
#---------------------------------------
# mpLinux.pm
#---------------------------------------
# See https://metacpan.org/pod/Audio::Play::MPG123 and
# /zip/_rpi/_setup/rpi_Setup.docx
#
# Abstract the linux MPG123 Media Player for localRenderer.
# Counterpart to mpWin.pm for the rPi.
#
# Had to add special handling to HTTPServer for mpg123 to
# serve the entire file (not just headers).
#
# PROBLEMS:
#
# (1) There's a SERIOUS PROBLEM with this thread. It stops
#     sometimes, maybe coincident with trying to resolve
#     a remote library, or the end of another thread.
#     Output to STDOUT?
#
# (2) frame->[3] is never returning non-zero, so we can't
#     calc the duration correctly and use the track's metadata
#     duration as a kludge. Might have to do with HTTP Server
#     and non-ranged requests.
#
# (3) Can seek forward, but not backwards. mpg123 jump() method
#     acts funny.
#
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

package mpLinux;
use strict;
use warnings;
use threads;
use threads::shared;
# use Audio::Play::MPG123;
use myMPG123;
use Time::HiRes qw(sleep);
use artisanUtils;
use Renderer;


my $dbg_mp = 0;


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


my $MPG123_STATE_STOPPED 		= 0; 	# Playback of the current media item is stopped.
my $MPG123_STATE_PAUSED 		= 1; 	# Playback of the current media item is paused.
my $MPG123_STATE_PLAYING 		= 2; 	# The current media item is playing.


our $mp_running:shared = 0;
my $mp_command_queue:shared = shared_clone([]);
	# stop
	# pause
	# play,optional_url
	# set_position,millis


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
	my ($renderer,$mp) = @_;
	$mp->stop() if $mp;
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
	# my $mp = Audio::Play::MPG123->new();
	my $mp = myMPG123->new();
	display($dbg_mp,0,"mpThread() started");
	$mp_running = 1;

	my $last_weird = 0;

	while (1)
	{
		if (!$quitting)
		{
			$mp->poll(0);
			my $mp_command = shift @$mp_command_queue;
			if ($mp_command)
			{
				display($dbg_mp,1,"doing command '$mp_command'");

				if ($mp_command eq 'stop')
				{
					stopMP($renderer,$mp);
				}
				elsif ($mp_command eq 'pause')
				{
					if ($renderer->{state} eq $RENDERER_STATE_PLAYING)
					{
						$mp->pause();
						$renderer->{state} = $RENDERER_STATE_PAUSED;
					}
				}
				elsif ($mp_command eq 'play')
				{
					if ($renderer->{state} eq $RENDERER_STATE_PAUSED)
					{
						$mp->pause();
						$renderer->{state} = $RENDERER_STATE_PLAYING;
					}
				}
				elsif ($mp_command =~ /^set_position,(.*)$/)
				{
					my $mp_position = $1;
					my $seconds = $mp_position/1000;
					# my $secs_per_frame = $mp->tpf;
					# 	# seconds per frame, for some reason, is off by factor of 2
					# my $frame = 2 * $seconds / $secs_per_frame;
					# display($dbg_mp+1,2,"doing set_position($mp_position)=frame($frame)");
					# $mp->jump($frame);
					$mp->jump($seconds."s");
					# $mp->poll(1);
				}
				elsif ($mp_command =~ /^play,(.*)$/)
				{
					my $url = $1;
					display($dbg_mp+1,2,"doing play($url)");
					$mp->load($url);
					$renderer->{state} = $RENDERER_STATE_PLAYING;
					# while (!$mp->state)
					# {
					#	$mp->poll(1);
					# }
				}
			}
			else
			{
				# $mp->poll(0);
				my $mp_state = $mp->{state};

				display($dbg_mp+1,0,"mp_state($mp_state) state($renderer->{state})")
					if defined($mp_state);	# not available at init

				if ($renderer->{state} eq $RENDERER_STATE_PLAYING)
				{
					my $frame_data = $mp->{frame};
						# frames_played, frames_remaining, secs_played, secs_remaining

					if ($frame_data)
					{
						my $secs = $frame_data->[2];
						my $remain = $frame_data->[3];
						$renderer->{position} = $secs * 1000;

						# WEIRDNESS: for some mp3s, $remain is always '0.00'
						# in which case we revert to use the metadata duration ..

						if (defined($remain) && $remain ne '0.00')
						{
							# how I expect it to work
							my $total = $secs + $remain;
							$renderer->{duration} = $total * 1000;
						}
						elsif (time() ne $last_weird)	# kludge
						{
							$last_weird = time();
							$frame_data ||= ['undef'];
							display($dbg_mp,0,"weirdness frame_data(".
								join(',',@$frame_data).")");
							$renderer->{duration} = $renderer->{metadata}->{duration}
								if $renderer->{metadata};
						}
					}
				}

				$renderer->checkMPStart($mp,$mp_state == $MPG123_STATE_STOPPED ? 1 : 0)
					if defined($mp_state);
			}

			sleep($dbg_mp < 0 ? 1 : 0.1);
		}
		elsif ($mp_running)
		{
			display($dbg_mp,0,"suspending mpThread");
			$mp->stop();
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
	$mp->stop();
	$mp = undef;
	display($dbg_mp,0,"mpThread() ended");
}



1;
