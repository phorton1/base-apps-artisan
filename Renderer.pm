#!/usr/bin/perl
#---------------------------------------
# Renderer.pm
#
# This object provides an abstracted API to a "Now Playing Device"
# that has the concept of a stack of currently playing things including
#
#     A single Song
#     The Current Playlist
#
# The general UI model is to call methods that do things as needed,
# and separately to call update() from a loop from the UI, and to use the
# current renderer to display/return the results in either case.
# The case of no existing renderer (getSelectedRenderer() returns undef)
# is important, and must be known and handled by the client code.
#
#----------------------------------------------------
# STATIC METHODS
#----------------------------------------------------
#
# The class includes a static methods to find the list of current
# DNLA renderers:
#
#    getRenderers()
#       returns a list of the current DLNA renderers known to the system
#       May invalidate the current Renderer if it is not found online.
#
# to select one:
#
#    selectRenderer($id)
#       From the list of known renderers, the UI can select one.
#       If playback is occuring, it will be transferred to the new renderer.
#       Returns the selected Renderer.
#
# and to determine if there is one selected:
#
#    getSelectedRenderer()
#       Returns the currently selected Renderer, or undef.
#
# There is one other static method, called by the main application
# via a thread, that starts an update loop:
#
#     auto_update_thread()
#         calls g_renderer->update() in a timer loop
#         to keep the transport working headlessly
#
# ALL THE OTHER METHODS ARE OBJECT METHODS ON g_renderer.
# The client should not cache renderers.
# The client should only call these methods on a defined
# result from getSelectedRenderer()
#
#----------------------------------------------------
# RENDERER OBJECT METHODS
#----------------------------------------------------
#
# After sucessfully selecting a renderer, the client may call
# these methods. They are protected against re-entrancy using
# threads::shared::lock() on the %g_renderers hash.
#
#    update() - can be called explicitly by client code for
#       more granularity, called automatically from the Renderer
#       Monitor Thread.  This method hits the selected renderer,
#       get's its state, checks it, detecting stops and stalls,
#       and advances the song/track as necessary.
#
#    setPlaylist($playlist_name)  ""
#       This renderer can, at the bottom, either be playing a Playlist,
#       or a Saved Songlist.  Playlists loop automatically, whereas
#       Songlists stop when they finish. The playlist must have some
#       songs.  Playlists, by default, start off where they left off.
#
# The following methods correspond directly to UI Transport Controls
#
#    stop()
#       This will stop the renderer, and any song, songlist,
#       or playlist it might be playing. Correspon
#       be playing.
#
#    play_next_song()
#    play_prev_song()
#       These will play the next or previous song in the playlist,
#       if any.  They will return false if there is an error, of
#       if the renderer is not playing a playlist.
#
#    set_position($pct)
#       Takes an integer from 0..100 and moves the renderer there.
#
#----------------------------------------------------
# ENVISIONED METHODS / FUNCTIONALITY
#----------------------------------------------------
# The following methods *SHOULD* be implemented
#
#    playSong($song_id)
#       push the given song onto the "stack" and play it.
#       when it is finished, or upon << or >> out of it,
#       the stack will be popped, and whatever was playing
#       will resume.
#
#    playCurrentSonglist([$track_num])
#       play the Current Songlist, if there is one,
#       track_num is optional, and specifies where to start playing the songList
#       When the current songlist is finished, or upon << or >> out of it,
#       the stack will be popped and the underlying Playlist or Saved SongList
#       will start playing.  If $track_num is not provided, the last
#       value (as maintained by the Current Songlist) will be played.
#
#    setSavedSonglist($list_name)  ""=off
#       The alternative to setPlaylist, play a named saved songlist.
#       Songlists start at the first track.
#       Songlists may be explicitly "shuffled" and retain that state,
#       and can be played in "Shuffle" or "Native" order.
#
#
#    pause_play()
#    is_paused()
#       or whatever add'l state needed for ui
#
#    and there should be setXXX and getXXXMax methods for the following:
#    	setVol     getVolMax
#    	setBal     getBalMax
#    	setFade    getFadeMax
#    	setBass    getBassMax
#    	setMid     getMidMax
#    	setHigh    getHighMax
#       setMute    canMute
#       setLoud    canLoud
#
#------------------------------------------
# POLLING HEURISTICS
#------------------------------------------
# There is only nominal control over the bubbuleUp renderer,
# so we have to use some heuristics to determine who has control.
#
# In general, if we see a "STOPPED" renderer, we take that to mean
# that the last song we played has finished, and it is time to
# enqueue the next one.
#
# (1) Due to the fact that some songs have a longer "duration" than
# they actually play, the renderer will hang on them and never stop.
# We deteect this special case of the renderer being in PLAYING mode
# on the most recent song we enqueued with the position not changing on
# two subsequent calls, in which case we issue a stop().
#
# (2) If we ever detect a different song than we are expecting, then
# it means that the user has manually played a song on the device,
# and so we give up control.
#
# (3) I would like that pressing the STOP button on the renderer
# causes the song list to stop playing. NOT IMPLEMENTED YET.
# Could use a window of like 5 seconds from the end of the song,
# to determine if the song stopped 'naturally', or by user intervention.
#
#------------------------------------------
# OTHER NOTES
#------------------------------------------
# There used to be a thread/timer to do SSDP discovery, but it would
# turn off the current renderer sometimes.  Therefore, we allow attempts
# to hit any renderer, but put the renderer in a clearable error state
# if contact fails.


package Renderer;
use strict;
use warnings;
use threads;
use threads::shared;
use IO::Select;
use IO::Socket::INET;
use XML::Simple;
use LWP::UserAgent;
use Time::HiRes qw(sleep);
use SSDPSearch;
use Library;
use Database;
use artisanUtils;
use Playlist;
use DLNARenderer;


#---------------------------
# CONSTRUCTION (private)
#---------------------------

my %locker : shared;
	# a variable for locking
my $g_renderer : shared = undef;
	# The current selected Renderer

my $ALLOW_STOP_FROM_REMOTE = 1;
my $STOP_FROM_REMOTE_THRESHOLD = 9000;
	# we detect a stop on the remote if we
	# find a stopped renderer and the last
	# song position was less than THRESHOLD
	# milliseconds from the end of the song.
	# We pass the bit as a variable, and
	# clear it during asynch_play_next(),
	# which is only called from >> and <<,
	# so that >> and << don't stop the playlist.

my $REFRESH_TIME = 500;	# milliseconds
my $STALL_COUNT = 10;
	# how many updates at same position
	# constitute a stalled renderer

sub new
{
	my ($class,$id) = @_;
	display($dbg_ren,0,"new Renderer($id)");
	my $dlna = DLNARenderer::getDLNARenderer($id);
	if (!$dlna)
	{
		error("Attempt to create Renderer with unknown ID: $id");
		return;
	}
	my $this = shared_clone({
		id 	 => $dlna->{id},
		name => $dlna->{name} });
	bless $this,$class;

	$this->init_renderer(0);
	return $this;
};



sub init_renderer
	# private
    # level 0 = init state, playlist, and song
    # level 1 = init playlist,
    # level 2 = init for new song
{
    my ($this,$level) = @_;
    $level ||= 0;

    display($dbg_ren,0,"init_renderer($this->{name},$level)");

    if ($level <= 2)
    {
        $this->{song_id}  = "";
		$this->{uri}      = "";
		$this->{type}     = "";
        $this->{metadata} = shared_clone({});
        $this->{position}  = 0;
        $this->{duration} = 0;
        $this->{play_pct} = 0;
        $this->{stall_count} = 0;
		$this->{pending_seek} = 0;
		$this->{allow_stop_from_remote} = $ALLOW_STOP_FROM_REMOTE;
		$this->{last_position} = 0;
    }

    if ($level <= 1)
    {
		$this->{pending_song} = '';
		$this->{pending_timer} = 0;
        $this->{playlist} = undef;
    }

    if (!$level)
    {
        $this->{state} = '';
		$this->{vol}   = 0;
		$this->{mute}  = 0;
		$this->{loud}  = 0;
		$this->{bal}   = 0;
		$this->{fade}  = 0;
		$this->{bass}  = 0;
		$this->{mid}   = 0;
		$this->{high}  = 0;

    }

    display($dbg_ren,0,"init_renderer($level) finished");
}



#---------------------------
# UTILITIES
#---------------------------

sub invalidate_renderer
{
    display($dbg_ren,0,"invalidating current renderer");
	$g_renderer = undef;
}





#---------------------------------------------------------
# STATIC PUBLIC API
#---------------------------------------------------------


sub getSelectedRenderer
	# public
{
    return $g_renderer;
}


sub getRenderers
    # Call getDLNARenderers()
	# Invalidate g_renderer if it's not found anymore
{
    my ($refresh) = @_;
    display($dbg_ren,0,"getRenderers($refresh)");
	my $dlna_renderers = DLNARenderer::getDLNARenderers($refresh);
	if ($g_renderer && (
		!$dlna_renderers ||
		!$dlna_renderers->{$g_renderer->{id}}))
	{
		invalidate_renderer();
	}
    display($dbg_ren,0,"getRenderers($refresh) returning $dlna_renderers");
	return $dlna_renderers;
}


sub auto_update_thread
{
	My::Utils::setOutputToSTDERR();
	# My::Utils::set_alt_output(1);
    LOG(0,"starting auto_update_thread");

    while (!$quitting)
    {
        if ($g_renderer)  # && $g_renderer->{playlist})
        {

            # issue the call to update()
            # the thread will block and wait
            # if there is a UI method call in progress

            display($dbg_ren+1,0,"auto_update '$g_renderer->{id}'");
            $g_renderer->update();
        }

        sleep($REFRESH_TIME/1000);
    }
}



sub selectRenderer
{
    my ($id) = @_;

    display($dbg_ren,0,"selectRenderer($id)");
    lock(%locker);
    display($dbg_ren,1,"selectRenderer($id) got lock");

	# invalidate the renderer if no id passed in
	# i.e. Turn off the renderer with no error

	if (!$id)
	{
		if ($g_renderer)
		{
			display($dbg_ren,0,"deselecting Renderer");
			$g_renderer->command('stop');
		}
		invalidateRenderer();
		return;
	}

    # find the dlna renderer

    my $new_dlna = DLNARenderer::getDLNARenderer($id);
    if (!$new_dlna)
    {
        error("Could not find DLNARenderer($id) in selectRenderer()");
		return;
    }

    # try to get the state to test if the renderer is online
    # return an error, without changing the state, if not.

    my $state = $new_dlna->getState();
	if (!$state)
	{
		error("No state in selectRenderer($id)");
		return;
	}

    # short ending if its the same renderer

    if ($g_renderer && $id eq $g_renderer->{id})
	{
		$g_renderer->{state} = $state;
        display($dbg_ren,1,"selectRenderer(same renderer)");
		return $g_renderer;
	}

	# PROCEED TO CHANGE RENDERERS
	# Stop the playlist on the old renderer if it's playing

    LOG(0,"selectRenderer($id)");
	if ($g_renderer && $g_renderer->{playlist})
	{
		display($dbg_ren,1,"selectRenderer($id) stopping old renderer");
		$g_renderer->command('stop');
	}

	# create the new renderer if needed

	if (!$g_renderer)
	{
		$g_renderer = Renderer->new($id);
		return if !$g_renderer;
	}

	# assign the new id and name

	display($dbg_ren,1,"selectRenderer($id) assigning new renderer $new_dlna->{name}");
	$g_renderer->{id} = $new_dlna->{id};
	$g_renderer->{name} = $new_dlna->{name};

	# Start the playlist on the new renderer if needed

	if ($g_renderer->{playlist})
	{
		display($dbg_ren,0,"starting playlist($g_renderer->{playlist}->{name}) on new renderer. position="._def($g_renderer->{position}));
		if (!$g_renderer->play($g_renderer->{song_id}))
		{
			display($dbg_ren,1,"renderer->play($g_renderer->{song_id}) returned false");
			invalidate_renderer();
			return;
		}

		# seek to the correct position
		# it's not worth it less than 5 seconds in
		# we set pending_seek, and let the update() loop do the actual seek
		# we used to loop here until getState() got PLAYING but that didn't
		# seem to work reliably

		elsif ($g_renderer->{position} && $g_renderer->{position} > 5000)
		{
			display($dbg_ren,1,"setting pending_seek=$g_renderer->{position}");
			$g_renderer->{pending_seek} = $g_renderer->{position};
		}

	}   # new renderer has a playlist

    display($dbg_ren,0,"selectRenderer returning $g_renderer->{name}");
    return $g_renderer;
}




#----------------------------------------------------
# update
#----------------------------------------------------
# The update method does the bulk of the work.
# It gets the status/state of the renderer,
# and if playing, the current duration, time,
# and and the metadata from the device.
#
# It then uses these for it's heuristics for
# controlling the behavior of the renderer.
#
# In the end, it sets member variables on the
# renderer which will be passed to the UI.
#
# It reports errors and returns undef if
# there are problems.



sub update
    # Get the status of the renderer.
    # If it is playing, get the position and
    # metainfo and do heuristics.
{
    my ($this) = @_;

    display($dbg_ren+1,0,"update($this->{name})");
    lock(%locker);
    display($dbg_ren+1,1,"update($this->{name}) got lock");

    # if there is a pending song,
    # if pending_timer==0, spin around again
    # to let button presses settle, then play the song

    if ($this->{pending_song})
    {
        if (!$this->{pending_timer})
        {
            $this->{pending_timer}++;
            return 1;
        }

        my $song_id = $this->{pending_song};
        display($dbg_ren,0,"playing pending song($song_id)");
        $this->play($song_id);
        $this->{song_id} = $song_id;
        $this->{pending_song} = 0;
        return 1;
    }

    # and spin around one more time to let the
    # renderer catch up, so that we return the
    # new track

    elsif ($this->{pending_timer} && $this->{pending_timer} == 1)
    {
        $this->{pending_timer} = 0;
        return 1;
    }


    # If getState returns undef, it is synonymous with
    # the renderer being offline. We will return 0,
    # and, if called from the webUI, it will return an
    # xml result with an error to the browser.

	my $dlna = DLNARenderer::getDLNARenderer($this->{id});
	if (!$dlna)
	{
		error("Could not get DLNARenderer for $this->{id}");
		invalidate_renderer;
		return 0;
	}

    my $state = $dlna->getState();
    if (!defined($state))
    {
        error("call to getState() failed");
		invalidate_renderer();
        return 0;
    }

    # We continue thru the loop in state ERROR
    # and return the renderer with the ERROR state
    # to the UI

    elsif ($state =~ 'PLAYING')
    {
        display($dbg_ren+2,1,"update() - renderer PLAYING");

		if ($this->{pending_seek})
		{
	        display($dbg_ren,1,"PLAYING processing pending_seek to $this->{pending_seek}");
			$this->command('seek',$this->{pending_seek});
			$this->{position} = $this->{pending_seek};
			$this->{pending_seek} = 0;
			return 1;
		}
        my $data = $dlna->getDeviceData();

        if (!$data)
        {
            error("Could not get device data from $dlna->{name}");
			invalidate_renderer();
			return 0;
        }

		$this->{metadata} = $data->{metadata};
			# pass the metadata (fields just like a track) onto the client

		if (!defined($data->{position}))
        {
            warning(0,0,"update() ignoring PLAYING renderer with undefined position");
        }
        else
        {
			$this->{last_position} = $data->{position};
				# save off the last time for detecting $ALLOW_STOP_FROM_REMOTE

            # if the song_id is "" it's not from us
            # if the song_id doesn't agree with the current songlist
            # it's not from us.  In either case, we turn off {playlist}
            # optimized to not check if pending song

            if ($this->{playlist} && !$this->{pending_song})
            {
                if (!$data->{song_id} || $data->{song_id} ne $this->{song_id})
                {
                    LOG(0,"detected song change on renderer ... stopping playlist");
                    # $this->setPlaylist(0);
			        $this->init_renderer(1);

                }
            }

            # if we are still in control, then check for stalled renderer

            if ($this->{playlist})
            {
                if ($data->{position} == $this->{position})
                {
                    $this->{stall_count}++;
                    display($dbg_ren+1,0,"stalled renderer count=$this->{stall_count}");
                    if ($this->{stall_count} > $STALL_COUNT)
                    {
                        LOG(0,"detected stalled renderer .. stopping");
                        if (!$this->stop())
						{
							error("Could not stop stalled renderer");
							invalidate_renderer();
							return 0;
						}
                    }
                }
                else
                {
                    $this->{stall_count} = 0;
                }
            }

            $state = 'PLAYING_PLAYLIST' if $this->{playlist};

            # update the members for the UI

            $this->{state} = $state;
            @$this{keys %$data} = values %$data;

        }   # got a valid position
    }   # state == PLAYING


    # if we are playing the songlist and the renderer
    # is stopped, enqueue the next song.
    # optimized to not stop if pending song

    elsif ($this->{playlist} && $state =~ 'STOPPED' && !$this->{pending_song})
    {
		my $advance = 1;
		display($dbg_ren,0,"Advancing .. allow_stop_from_remote=$this->{allow_stop_from_remote}");
		if ($this->{allow_stop_from_remote})
		{
			display($dbg_ren,0,"Checking STOP_FROM_REMOTE: $this->{last_position} < $this->{duration} - $STOP_FROM_REMOTE_THRESHOLD");
			if ($this->{last_position} > $STOP_FROM_REMOTE_THRESHOLD &&
				$this->{last_position} < $this->{duration} - $STOP_FROM_REMOTE_THRESHOLD)
			{
				$this->init_renderer(1);
				$this->{state} = $state;
				$advance = 0;
			}
		}

		if ($advance)
		{
			display($dbg_ren,1,"update() calling play_next_song()");
			if (!$this->play_next_song(1))
			{
				display($dbg_ren,0,"play_next_song() returned false in update()");
				invalidate_renderer();
				return 0;
			}
			display($dbg_ren,1,"update() back from play_next_song()");
		}

    }

    # otherwise, just set the state member

    elsif ($state ne $this->{state})
    {
        $this->{state} = $state;
    }

    display($dbg_ren+1,1,"update($this->{name}) returning 1");
    return 1;
}




#--------------------------------------------------
# actions
#--------------------------------------------------

sub command
	# pass thru to DLNARenderer
{
	my ($this,$action,$arg) = @_;
	$arg ||= '';
    display($dbg_ren,0,"command($action,$arg)");
    lock(%locker);
    display($dbg_ren,1,"command($action,$arg) got lock");

	my $dlna = DLNARenderer::getDLNARenderer($this->{id});
	if (!$dlna)
	{
		error("Could not get DLNARenderer for $this->{id}=$this->{name} in command()");
		return;
	}
	return $dlna->doCommand($action,$arg);
}


sub rendererState
	# pass thru to DLNARenderer
{
	my ($this) = @_;
	my $dlna = DLNARenderer::getDLNARenderer($this->{id});
	if (!$dlna)
	{
		error("Could not get dlna for $this->{id}=$this->{name} in rendererState()");
		return;
	}
	return $dlna->getState();
}


sub stop
{
    my ($this) = @_;
    display($dbg_ren,0,"stop()");
    lock(%locker);
    display($dbg_ren,1,"stop() got lock");

    my $retval = $this->command('stop');
    display($dbg_ren,1,"stop($this->{name}) returning $retval");
    return $retval;
}


sub play
{
    my ($this,$song_id) = @_;
    $song_id ||= "";

	$this->{stall_count} = 0;

    display($dbg_ren,0,"play($song_id)");
    lock(%locker);
    display($dbg_ren,1,"play($song_id) got lock");

    my $retval = 1;
    if ($song_id)
    {
        if (!$this->stop())
        {
            $retval = 0;
        }
        else
        {
            $retval = $this->command('set_song',$song_id);

            # if ($retval)
            # {
            #     $this->{metadata} = get_track(undef,$song_id);
            # }
        }
    }

    if ($retval)
    {
        $retval = $this->command('play');
    }

    display($dbg_ren,1,"play($this->{name}) returning $retval");
    return $retval;
}


sub setPlaylist
{
    my ($this,$playlist) = @_;
    my $retval = 1;

    display($dbg_ren,0,"setPlaylist(".($playlist?$playlist->{name}:'undef').")");
    lock(%locker);
    display($dbg_ren,1,"setPlaylist() got lock");

    my $this_name = $this->{playlist} ? $this->{playlist}->{name} : "";
    my $that_name = $playlist ? $playlist->{name} : "";

    if ($this_name ne $that_name)
    {
        if ($this->{playlist})
        {
            $retval = 0 if !$this->stop();
        }

        $this->init_renderer(1);
        $this->{playlist} = $playlist;

        if ($retval && $playlist)
        {
            $retval = 0 if !$this->play_next_song();
        }
    }

    display($dbg_ren,1,"setPlaylist(".($playlist?$playlist->{name}:'undef').") returning $retval");
    return $retval;
}


sub play_next_song
	# only called internally .. not from webUI
{
    my ($this) = @_;

    display($dbg_ren,0,"play_next_song()");
    lock(%locker);
    display($dbg_ren,1,"play_next_song() got lock");

    $this->{song_id} = $this->{playlist}->getNextTrackID();
    LOG(0,"playing next($this->{playlist}->{name}) song($this->{playlist}->{track_index}) = $this->{song_id}");

    my $retval = $this->play($this->{song_id});
    display($dbg_ren,1,"play_next_song() returning $retval");
    return $retval;
}


sub play_prev_song
{
    my ($this) = @_;

    display($dbg_ren,0,"play_prev_song()");
    lock(%locker);
    display($dbg_ren,1,"play_prev_song() got lock");

    $this->{song_id} = $this->{playlist}->getPrevTrackID();
    LOG(0,"playing next($this->{playlist}->{name}) song($this->{playlist}->{track_index}) = $this->{song_id}");

    my $retval = $this->play($this->{song_id});
    display($dbg_ren,1,"play_prev_song() returning $retval");
    return $retval;
}


sub async_play_song
	# only called by webUI (not on advance)
	# so it can reset the allow_stop_from_remote bit
	# to prevent stopping on >>

    # an alternative to play_next/prev_song
    # for better responsiveness
    # bump the track number, set the pending song number,
    # and return the track to the client right away.
    # The song will start playing on the next monitor loop.
{
    my ($this,$inc) = @_;
    display($dbg_ren,0,"async_play_song($this->{name}) playlist=$this->{playlist}->{name} inc=$inc");
    lock(%locker);
    display($dbg_ren,1,"async_play_song($inc) got lock");

	$this->{allow_stop_from_remote} = 0;
    $this->{song_id} = $this->{playlist}->getIncTrackID($inc);
    $this->{pending_song} = $this->{song_id};
    $this->{pending_timer} = 0;
    # $this->{metadata} = get_track(undef,$this->{pending_song});
    display($dbg_ren,1,"async_play_song() returning 1");
    return 1;
}


sub play_single_song
    # play a single song id.
	# uses pending mechanism.
	# should *not* stop the playlist,
	# which *should* continue when the song is done.
{
    my ($this,$song_id) = @_;
    display($dbg_ren,0,"play_single_song($song_id)");
    lock(%locker);
    display($dbg_ren,1,"play_single_song($song_id) got lock");

    $this->{song_id} = $song_id;
    $this->{pending_song} = $song_id;
    $this->{pending_timer} = 0;
    # $this->{metadata} = get_track(undef,$song_id);
    display($dbg_ren,1,"play_single_song() returning 1");
    return 1;
}


sub set_position
	# pct = 0..100
{
    my ($this,$new_position) = @_;
    my $retval = 1;

    display($dbg_ren,0,"set_position($new_position)");
    lock(%locker);
    display($dbg_ren,1,"set_position() got lock");

    if (!$this->{duration})
    {
        error("No duration in set_position($new_position)");
        $retval = 0;
    }
    else
    {
        display($dbg_ren,1,"set_position($new_position)");
        if (!$this->command('seek',$new_position))
        {
            error("could not seek set_position($new_position)");
            $retval = 0;
        }
        else
        {
            $this->{position} = $new_position;
        }
    }

    display($dbg_ren,1,"set_position($new_position) returning $retval");
    return $retval;
}



1;
