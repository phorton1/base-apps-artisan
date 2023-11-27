#!/usr/bin/perl
#---------------------------------------
# Renderer.pm
#---------------------------------------

package Renderer;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Device;
use base qw(Device);

my $dbg_ren = 1;

our $RENDERER_STATE_NONE 		= 'NONE';
our $RENDERER_STATE_INIT		= 'INIT';
our $RENDERER_STATE_STOPPED		= 'STOPPED';
our $RENDERER_STATE_TRANSIT		= 'TRANSIT';
our $RENDERER_STATE_PLAYING		= 'PLAYING';
our $RENDERER_STATE_PAUSED		= 'PAUSED';
our $RENDERER_STATE_ERROR		= 'ERROR';


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		$RENDERER_STATE_NONE
		$RENDERER_STATE_INIT
		$RENDERER_STATE_STOPPED
		$RENDERER_STATE_TRANSIT
		$RENDERER_STATE_PLAYING
		$RENDERER_STATE_PAUSED
		$RENDERER_STATE_ERROR
	);
};



sub new
{
	my ($class,$params) = @_;
	$params->{deviceType} ||= $DEVICE_TYPE_RENDERER;
	display($dbg_ren,0,"Renderer::new()");
	my $this = $class->SUPER::new($params);
		# $is_local,
		# $DEVICE_TYPE_RENDERER,
		# $uuid,
		# $friendlyName);
	bless $this,$class;

	mergeHash($this, shared_clone({
		maxVol 		=> 0,
		canMute		=> 0,
		canLoud		=> 0,
		maxBal 		=> 0,
		maxFade		=> 0,
		maxBass		=> 0,
		maxMid 		=> 0,
		maxHigh		=> 0,

		state 		=> $RENDERER_STATE_NONE,

		muted       => 0,
		volume      => 0,
		balance     => 0,
		fade        => 0,
		bassLevel   => 0,
		midLevel    => 0,
		highLevel   => 0,

		position 	=> 0,
		duration 	=> 0,

		playlist	=> '',
		metadata    => shared_clone({
			artist      => '',
			album_title => '',
			genre       => '',
			title       => '',
			track_num   => '',
			type        => '',
			year_str    => '',
			art_uri     => '',		# gotten from parent folder for webUI
			pretty_size => '', 		# built in memory for webUI
		}),

	}));

	return $this;
}


1;