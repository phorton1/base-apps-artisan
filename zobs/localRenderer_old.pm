#!/usr/bin/perl
#------------------------------------------------------------
# localRenderer.pm
#------------------------------------------------------------
# 2023-11-07 - moved from artisanWin to artisan.
#   Wooo hooo - I got a headless media player!!
# 	See https://learn.microsoft.com/en-us/windows/win32/wmp/player-object
# 	Basics:
#     create the OLE object $mp
#     set the file to play using $mp->{URL}
#     get or set the position within the stream with $mp->{controls}->{currentPosition};
#     get or set the volume with $mp->{settings}->{volume}
#     get or set the balance with $mp->{settings}->{balance}
#
# First try, direct calls to global $mp object created at started.


#------------------------------------------------------
# Overview
#------------------------------------------------------
# An object that can be registered with the pure perl
# DLNARenderer class as a local renderer.
#
# This object must be created in SHARED MEMORY and
# contain all the necessary member fields:
#
#       id
#       name
#       maxVol
#       canMute
#       canLoud
#       maxBal
#       maxFade
#       maxBass
#       maxMid
#       maxHigh
#
# By convention it should probably also provide
# blank values for the following:
#
#       ip
#       port
#       transportURL
#       controlURL
#
# It must provide the following APIs
#
#    getState()
#
#        Returns undef if renderer is not online or there
#            is a problem with the return value (no status)
#        Otherwise, returns the state of the DLNA renderer
#            PLAYING, TRANSITIONING, ERROR, etc
#
#    getDeviceData()
#
#        If getState() returns 'PLAYING' this method may be called.
#        Returns undef if renderer is not online.
#        Otherwise, returns a $data hash with interesting fields:
#
#			duration
#           reltime
#           vol			- 0 (not supported)
#           mute		- 0 (not supported)
#           uri			- that the renderer used to get the song
#           song_id     - our song_id, if any, by RE from the uri
#           type        - song "type" from RE on the uri, or metadata mime type
#			metadata    - hash containing
#				artist
#				title
#				album
#			    track_num
#  				albumArtURI
#				genre
#				date
#				size
#				pretty_size
#
#    public doCommand(command,args)
#		 'stop'
#        'set_song', song_id
#        'play'
#        'seek', reltime
#        'pause'
#


use lib '/base/apps/artisan';

package localRenderer;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Database;
use Library;
use Pub::Utils;


my $dbg_lr = 0;
my $dbg_com_object = 1;



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



BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
    );
}



sub new
{
    my ($class) = @_;
    my $this = shared_clone({

        # basic state variables
        # and returned in getState() and getDeviceData()

        state   => 'INIT',      # state of this player
        song_id => '',          # currently playing song, if any

        # these are returned in getDeviceData()
        # and are set in the named mediaPlayerWindow method

        duration => 0,          # milliseconds
        position => 0,

        # these are the normal DLNAServer member variables
        # that a derived class must provide, and which are
        # returned returned directly to the ui as a hash of
        # this object.

        id      => 'local_renderer',
        name    => 'Local Renderer',

        maxVol  => 100,
        canMute => 1,
        canLoud => 0,
        maxBal  => 100,
        maxFade => 0,
        maxBass => 0,
        maxMid  => 0,
        maxHigh => 0,

        # there are unused normal DLNARenderer fields
        # that are set for safety

        ip      => '',
        port    => '',
        transportURL => '',
        controlURL => '',
    });

    bless $this, $class;
    return $this;

}


sub getState
{
    my ($this) = @_;
	display($dbg_lr+1,0,"getState() returning $this->{state}");
    return $this->{state};
}



sub getDeviceData()
{
    my ($this) = @_;
    my $song_id = $this->{song_id};
    $song_id ||= '';

    my $track = $song_id ? get_track(undef,$song_id) : undef;
    if ($song_id && !$track)
    {
        error("Could not get track($song_id)");
    }
	if ($track)
	{
		$track->{pretty_size} = $track ? bytesAsKMGT($track->{size}): '';
		$track->{art_uri} = $track->getPublicArtUri();
	}

	my $media = $mp->{currentMedia};
	$this->{position} = $controls->{currentPosition} * 1000 || 0;
	$this->{duration} = $media ? $media->{duration} * 1000 : 0;
	display($dbg_lr,0,"getDeviceData() position=$this->{position} duration=$this->{duration}");
	$this->{state} = 'STOPPED' if !$this->{position};

    my $data = shared_clone({
        song_id     => $song_id,
        position    => $this->{position},
        duration    => $this->{duration},

        uri			=> $track ? $track->{path}    : '',
        type        => $track ? $track->{type}    : '',
        vol			=> 0,
        mute		=> 0,
        metadata    => $track,
    });

    return $data;

}



sub doCommand
    # This code can runs on a thread from the HTTP Server,
{
    my ($this,$command,$arg) = @_;
    $arg ||= '';

    display($dbg_lr,0,"localRenderer::command($command,"._def($arg).")");

	if ($command eq 'stop')
	{
		$controls->stop();
		$this->{state} = 'STOPPED';
		return 1;
	}
	elsif ($command eq 'pause')
	{
		$controls->pause();
		$this->{state} = 'PAUSED';
		return 1;
	}
	elsif ($command eq 'seek')
	{
		# convert seek in milliseconds to seconds
		$arg /= 1000;
		$controls->{currentPosition} = $arg;
		return 1;
	}
	elsif ($command eq 'play')
	{
		$controls->play();
		$this->{state} = 'PLAYING';
		return 1;
	}
	elsif ($command eq 'set_song')
	{
		if ($arg)
		{
			my $track = get_track(undef,$arg);
			if (!$track)
			{
				error("Could not get track($arg)");
				return;
			}

			my $path = "$mp3_dir/$track->{path}";
			$path =~ s/\//\//g;
			display($dbg_lr,1,"set_song($arg) path($path) duration=$track->{duration}");

			$this->{duration} = $track->{duration};
			$this->{song_id} = $arg;
			$this->{state} = 'LOADED';

			$mp->{URL} = $path;
			# $controls->stop();		# stop it JIC
		}
		else
		{
			$mp->{URL} = '';
			$controls->stop();		# stop it JIC
			$this->{song_id} = '';
			$this->{state} = 'STOPPED';
		}
		return 1;
	}

	error("Unknown command $command arg=$arg in onIdle::command()");
	return 0;

}	# doCommand()







1;