#!/usr/bin/perl
#---------------------------------------
# mpHTML.pm
#---------------------------------------
# A kludgy way to implement the localRenderer on linux.
# Requires a browser session to be running or nothing happens.
# Interacts closely with localRenderer.
#
# I'm not really sure what I gained by this. At this time there
# is no way to control a remote artisan's renderer.
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

package mpHTML;
use strict;
use warnings;
use threads;
use threads::shared;
# use Audio::Play::MPG123;
use myMPG123;
use Time::HiRes qw(sleep);
use artisanUtils;
use Renderer;


my $dbg_mp = -1;


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


our $mp_running:shared = 0;

# A command is set into the HTMLRenderer at a certain version number,
# 	and then 'sent' (returned) to the JS via an update() call.
# When it gets the command, it 'acknowledges' it, by passing the
#   version number back to the Perl in the next update() call,
#   which then clears the command so that it doesn't get sent again.

sub doMPCommand
{
	my ($renderer,$command) = @_;
	$renderer->{html_audio}->{version}++;
	$renderer->{html_audio}->{command} = $command;
	$renderer->{state} = $RENDERER_STATE_TRANSIT;
	display($dbg_mp,0,"doMPCommand($command) at version($renderer->{html_audio}->{version})");
}


sub stopMP
{
	my ($renderer,$mp) = @_;
	display($dbg_mp,0,"stopMP()");
	$renderer->{state} = $RENDERER_STATE_STOPPED
		if $renderer->{state} ne  $RENDERER_STATE_INIT;
	$renderer->{position} = 0;
	$renderer->{duration} = 0;
	delete $renderer->{metadata};
	# doMPCommand($renderer,'stop');
}


sub mpThread
	# not really a thread, or if it is, one that
	# returns immediately
{
	my ($renderer) = @_;
	my $mp = shared_clone({
		state => 0,
		version => 0,
		command => '',
	});
	$renderer->{html_audio} = $mp;
	$mp_running = 1;
}



1;
