#!/usr/bin/perl
#---------------------------------------
# remoteRenderer.pm
#---------------------------------------

package remoteRenderer;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Renderer;
use base qw(Renderer);

my $dbg_rlib = 0;


sub new
{
	my ($class,$params) = @_;
	display($dbg_rlib,0,"remoteRenderer::new()");
	my $this = $class->SUPER::new($params);
	bless $this,$class;
	return $this;
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
	return "not supported";
}

1;