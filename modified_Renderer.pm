#!/usr/bin/perl
#---------------------------------------
# Can just Ping the WD to see if it's there.
# Need fast method? for other renderers?

# 
# Renderer.pm
#
# Provides an abstracted API to a "Now Playing Device",
# that has the concept of a stack of currently playing
# things including
#
#     A single Song
#     The Current Songlist
#     A Station or a Saved Songlist
#
# The class includes static methods to find a list of
# current renderers, and to select (activate) one.
#
# By default, the list of available renders are the
# DLNA Renderer found by an SSDP Search, but there is
# the possibility for the UI to crete a Local Renderer
# register, and set it, as the current renderer.
#
# The Renderer includes a thread loop that keeps the
# renderer playing, advances tracks, etc, regardless
# of any UI interaction.  The general UI model is to
# poll this Renderer from the UI and to present it's
# results, or to modify it's behavior, then resume
# polling it, including upon the SelectRenderer event.
#
#    read_renderer_cache()
#        static initialization to be called before usage
#        reads the last list of DLNA renders into memory
# 
#    getRenderers()
#       returns a list of the current renderers known to the system
#       May invalidate the current renderer if it is not found online.
#    
#    selectRenderer($id)
#       From the list of known renderers, the UI can select one.
#       If playback is occuring, it will be transferred to the new renderer.
#       Returns the getSelectedRenderer()
#
#    getSelectedRenderer()
#       Returns the currently selected renderer, or undef.
#       Most other methods are instance methods on the renderer object.
#
# STATIC RENDERER METHODS
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
#    not_implemented_yet:   playSong($song_id)
#       push the given song onto the "stack" and play it.
#       when it is finished, or upon << or >> out of it,
#       the stack will be popped, and whatever was playing
#       will resume.
#
#    not_implemented_yet:  playCurrentSonglist([$track_num])
#       play the Current Songlist, if there is one,
#       track_num is optional, and specifies where to start playing the songList
#       When the current songlist is finished, or upon << or >> out of it,
#       the stack will be popped and the underlying Station or Saved SongList
#       will start playing.  If $track_num is not provided, the last
#       value (as maintained by the Current Songlist) will be played.
#
#    setStation($station_num)  0==off
#       This renderer can, at the bottom, either be playing a Station,
#       or a Saved Songlist.  Stations loop automatically, whereas
#       Songlists stop when they finish. The station must have some
#       songs.  Stations, by default, start off where they left off.
#
#    not_implemented_yet: setSavedSonglist($list_name)  ""=off
#       The alternative to setStation, play a named saved songlist.
#       Songlists start at the first track.
#       Songlists may be explicitly "shuffled" and retain that state,
#       and can be played in "Shuffle" or "Native" order.
#
# The following methods correspond directly to UI Transport Controls
#    stop() 
#       This will stop the renderer, and any song, songlist,
#       or station it might be playing. Correspon
#       be playing.
#    
#    play_next_song()
#    play_prev_song()
#       These will play the next or previous song in the station,
#       if any.  They will return false if there is an error, of
#       if the renderer is not playing a station.
#
#    set_position($pct)
#       Takes an integer from 0..100 and moves the renderer there.
#
# The following methods *SHOULD* be implemented
#
#    pause_play()
#    is_paused()   - or whatever add'l state needed for ui
#
#    It should have setXXX and getXXXMax methods for the following:
#    		setVol     getVolMax
#    		setBal     getBalMax
#    		setFade    getFadeMax
#    		setBass    getBassMax
#    		setMid     getMidMax
#    		setHigh    getHighMax
#           setMute    canMute
#           setLoud    canLoud


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
# on the most recent song we enqueued with the reltime not changing on
# two subsequent calls, in which case we issue a stop().
#
# (2) If we ever detect a different song than we are expecting, then
# it means that the user has manually played a song on the device,
# and so we give up control.
#
# (2) I would like that pressing the STOP button on the renderer
# causes the song list to stop playing. NOT IMPLEMENTED YET.
# Could use a window of like 5 seconds from the end of the song,
# to determine if the song stopped 'naturally', or by user intervention.
#
# NOTES
#
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
use HTTPXML;
use SSDPSearch;
use Library;
use Database;
use Utils;
# use Station;

# Want explicit API References
# 
# BEGIN
# {
#  	use Exporter qw( import );
# 	our @EXPORT = qw (
#         getRenderers
#         selectRenderer
#         getSelectedRenderer
#     );
# }
# 


#-----------------------------
# CONSTANTS
#-----------------------------


# getDLNARenderers() returns records consisting
# of the following fields. All are inited, although
# DLNA only supports some of 

my @cache_fields qw(
    id
    name
    ip
    port
    transportURL
    controlURL
	maxVol
	canMute
	canLoud
	maxBal
	maxFade
	maxBass
	maxMid
	maxHigh
);

    
my $renderer_cachefile = "$temp_dir/renderer_cache.txt";


#---------------------------
# VARIABLES
#---------------------------
# list of the current renderers by id
# and the current renderer

my %g_renderers : shared;
my $g_renderer : shared;

my $ua = LWP::UserAgent->new();
	# a global $ua for speed


# a hash containing the state of the renderer
# is combined with the renderer object for
# returning a single big record for the webUI

my %g_state : shared = (
	state 			=> '',
	station 		=> undef,
	song_id 		=> '',
	
	duration 		=> '',
	type        	=> '',
	uri 			=> '',
	metadata 		=> '',

	reltime 		=> '',
	stall_count 	=> 0,
	pending_song	=> '',
	pending_timer 	=> 0,
	
	vol				=> 0,
	mute			=> 0,
	loud			=> 0,
	bal				=> 0,
	fade			=> 0,
	bass			=> 0,
	mid				=> 0,
	high			=> 0
);







#------------------------------------------
# Construction
#------------------------------------------

sub new
    # required params are
	#    id
    #    friendlyName
    #    ip
    #    port
    #    avControlURL
{
    my ($class,$params) = @_;
    my $id = $params->{id};
    display($dbg_ren,0,"Renderer::new($id)");
    my $this = shared_clone($params);
    bless $this,$class;
    $this->{online} = 0;
    $g_renderers{$id} = $this;
    return $this;
}



sub static_init_renderer
    # level 0 = init everything
    # level 1 = turn off station
    # level 2 = init for new song
{
    my ($level) = @_;
    $level ||= 0;
    
    display($dbg_ren,0,"init_renderer($level)");

    if ($level <= 2)
    {
        $song_id = "";		# the currently playing song
        $metadata = undef;
        $reltime = '';
        $duration = '';
        $stall_count = 0;
    }
    
    if ($level <= 1)
    {
        $station = undef;

    }
    
    if (!$level)
    {
        $state = '';
    }

    display($dbg_ren,0,"init_renderer($level) finished");
}    
    
    


#------------------------------------------
# accessors
#------------------------------------------

sub getState 	{ return $state; }
sub getStation 	{ return $station; }
sub getSongID   { return $song_id; }
sub getMetaData { return $metadata; }
sub getReltime  { return $reltime; }
sub getDuration { return $duration; }
sub getPlayPct  { return calc_play_pct($reltime,$duration); }
	
sub getSelectedRenderer
{
    return $g_renderer;
}

sub getRenderer
{
    my ($id) = @_;
    return $g_renderers{$id};
}

sub calc_play_pct
	# private
{
    my ($reltime,$duration) = @_;
    my $relsecs = time_to_secs($reltime);
    my $dursecs = time_to_secs($duration);
    my $pct = $dursecs ? int(100 * ($relsecs/$dursecs)) : 0;
    return $pct;
}


sub time_to_secs
	# private
{
    my ($time) = @_;
    my @parts = split(/:/,$time);
    my $secs = 0;
    while (@parts)
    {
        my $part = shift(@parts);
        $secs = ($secs * 60) + $part;
    }
    return $secs;
}


sub secs_to_time
	# private
{
    my ($secs) = @_;
    my $time = '';
    for (0..2)
    {
        my $part = $secs % 60;
        $time = ':'.$time if ($time);
        $time = pad2($part).$time;
        $secs = int($secs / 60);
    }
    return $time;
}






#-------------------------------------------
# renderer cache file
#-------------------------------------------

sub read_renderer_cache
{
    if (-f $renderer_cachefile)
    {
        my $lines = getTextLines($renderer_cachefile);
        for my $line (@$lines)
        {
            chomp($line);
            my %params;
            @params{@cache_fields} = split(/\t/,$line);
            Renderer->new(\%params);
        }
    }
    my $num = keys(%g_renderers) || 0;
    display($dbg_ren,0,"found $num renderers in cache");
}


    
sub write_renderer_cache
{
    my $text;
    for my $name (sort(keys(%g_renderers)))
    {
        display($dbg_ren,0,"write_renderer_cache($name)");
        my $renderer = $g_renderers{$name};
        my $line = join("\t",@$renderer{@cache_fields});
        $text .= $line."\n";
    }
    if (!printVarToFile(1,$renderer_cachefile,$text))
    {
        error("Could not write to renderer cachefile '$renderer_cachefile'");
    }
}




    
sub getRenderers
    # fleshes out, and invariantly returns the
    # global list of renderers.
    # 0 = return the current cache
	# 1 = rescan, and update the cache
	# 2 = clear, and rebuild the cache
	# 1 and 2 may invalidate current renderer
{
    my ($refresh) = @_;
    if ($refresh)
    {
        display($dbg_ren,0,"getRenderers($refresh)");
		my $dlna_renderers = SSDPSearch::getDLNARenderers($ua);
        display($dbg_ren,1,"found ".scalar(keys(%$dlna_renderers))." DLNA Renderers");
		for my $id (sort(keys(%$dlna_renderers)))
		{
			my $dlna = $dlna_renderers->{$id};
	        display($dbg_ren,1,"doing $id = $dlna->{friendlyName}");
			
			# The avControlURL is the important one, that we use for most stuff.
			# We only use the renderingControlURL for the volume control.
			# If we do not find an avControlURL, then we will not wipe out an
			# existing one, but will not create a new renderer object from it.
			# rendererControlURL is just along for the ride.

			my $renderer = $g_renderers{$id};
			if ($renderer)
			{
				$renderer->{avControlURL} = $dlna->{avControlURL}
					if ($dlna->{avControlURL});
				$renderer->{rendererControlURL} = $dlna->{rendererControlURL}
					if ($dlna->{rendererControlURL});

				# take these params in case we are updating an
				# existing renderer cache text file with new fields.
				
				$renderer->{volMax} = $dlna->{volMax};
				$renderer->{supportsMute} = $dlna->{supportsMute};
			}
			elsif ($dlna->{avControlURL})
			{
				$renderer = Renderer->new($dlna);
			}
			else
			{
				error("Cannot create a Renderer object without a avControlURL");
			}
			
			$renderer->{online} = 2 if ($renderer);

        }   # for every dlna renderer
                
        # reset the online status and/or remove stale entries
        
        for my $id (keys(%g_renderers))
        {
            my $renderer = $g_renderers{$id};
            $renderer->{online} ||= 0;
            $renderer->{online} = $renderer->{online}==2 ? 1 : 0;
            
            # remove stale entries if refresh==2
            
            if ($refresh == 2 && !$renderer->{online})
            {
                if ($g_renderer && $g_renderer->{id} eq $renderer->{id})
                {
                    display($dbg_ren,0,"invalidating current renderer");
                    $g_renderer = undef;
                }
                delete $g_renderers{$id};
            }
        }
        
        # write it out
        
        write_renderer_cache();
		
    }	# if $refresh
    
    return \%g_renderers;
	
}                



#-------------------------------------------------------------
# selectRenderer
#-------------------------------------------------------------

sub selectRenderer
{
    my ($id) = @_;
    my $state;
    
    display($dbg_ren,0,"selectRenderer($id)");
    lock(%g_renderers);
    display($dbg_ren,1,"selectRenderer($id) got lock");

    # find it
	# prh - could use a quick "ping" or other "online" test here
    
    my $renderer = $g_renderers{$id};
    if (!$renderer)
    {
        error("Could not get renderer($id) in selectRenderer()");
		return;
    }
	
	# Halt the old one if it's playing
	# (without modifying state)
	
	if ($g_renderer)
	{
		display($dbg_ren,1,"selectRenderer($id) halting old renderer $g_renderer->{frindlyName}");
		stop();
	}
	
	# Assign the new one
	
	$g_renderer = $renderer;
	display($dbg_ren,1,"selectRenderer($id) assigning new renderer");

	# Start new one playing if there was a station playing
	
	if ($station)
	{
		display($dbg_ren,0,"starting station($g_renderer->{station}->{name}) on new renderer. reltime="._def($g_renderer->{reltime}));
		if (!play($song_id))
		{
			display($dbg_ren,1,"Renderer::play($g_renderer->{song_id}) returned false");
			static_init_renderer(0);
			$g_renderer = undef;
		}
		elsif ($reltime && $reltime gt '00:00:05')
		{
			# attempts to seek before doAction(play) seem to fail
			# we could sleep but that cause song to stop, then jump to position
			# we try to get better timing by waiting for transport to reach PLAYING state.

			display($dbg_ren,1,"waiting for PLAYING ..");
	
			my $count = 5;
			my $state = getState();
			while ($state ne 'PLAYING' && --$count > 0)
			{
				sleep(1);
				$state = getState();
			}

			display($dbg_ren,1,"finished waiting with count=$count and state=$state");
			display($dbg_ren,1,"seeking to $reltime ..");
			
			if (!doAction(0,'Seek',{
				Unit => 'REL_TIME',
				Target => $reltime }))
			{
				warning(0,0,"selectRenderer($id) seek to $g_renderer->{reltime} failed");
			}
			
	   }    # seeking in new renderer
	}   # active station
    
    display($dbg_ren,0,"selectRenderer returning ".($g_renderer?$g_renderer->{friendlyName}:'undef'));
    return $g_renderer;
}




sub set_position
	# returns undef on error
{
    my ($pct) = @_;
    
	if (!$g_renderer)
	{
		warning(0,0,"No renderer in set_position()");
		return;
		
	}
    display($dbg_ren,0,"set_position($pct)");
    lock(%g_renderers);
    display($dbg_ren,1,"set_position($pct) got lock");
    
    if (!$duration)
    {
        error("No duration in set_position($pct)");
        return;
    }
    else
    {
        my $dursecs = time_to_secs($duration);
        my $relsecs = int(($pct + 0.5) * $dursecs / 100);
        display($dbg_ren,1,"set_position($pct) dursecs=$dursecs relsecs=$relsecs");
        
        my $settime = secs_to_time($relsecs);
        display($dbg_ren,1,"set_position($pct) seeking to '$settime'");
        if (!doAction(0,'Seek',{
            Unit => 'REL_TIME',
            Target => $settime }))
        {
            error("set_position($pct) could not seek to '$settime'");
            return;
        }
		
		$reltime = $settime;
	}

    display($dbg_ren,1,"set_position($pct) returning 1");
    return 1;
}




#----------------------------------------------------
# update
#----------------------------------------------------
# The update method does the bulk of the work.
# It gets the status/state of the renderer,
# and if playing, the current duration, time,
# and metadata from the device.
#
# It then uses these for it's heuristics for
# controlling the behavior of the renderer.
#
# In the end, it sets static variables on the
# renderer which will are available by call to the UI
#
# It reports errors and returns undef if there are problems.
# If the problem was in a call to doAction(), the renderer
# will also be ERROR.
#
# Tried to use lock() selectively but still ran into problems.


sub update
    # Get the status of the renderer.
    # If it is playing, get the position and
    # metainfo and do heuristics.  The error
	# code 
{
	if (!$g_renderer)
	{
		static_init_renderer(0);
		return 1;
	}
    
    display($dbg_ren+1,0,"update($g_renderer->{friendlyName})");
    lock(%g_renderers);
    display($dbg_ren+1,1,"update($g_renderer->{friendlyName}) got lock");

    # if there is a pending song,
    # if pending_timer==0, spin around again
    # to let button presses settle, then play the song
    
    if ($pending_song)
    {
        if (!$pending_timer)
        {
            $pending_timer = 1;
            return 1;
        }
        
        display($dbg_ren,0,"playing pending song($pending_song)");
        play($pending_song);
        $pending_song = '';
		$pending_timer = 0;
        return 1;
    }
    
    # and spin around one more time to let the
    # renderer catch up, so that we return the
    # new song's metadata on the next call
    
    elsif ($pending_timer)
    {
        $pending_timer = 0;
        return 1;
    }
    
    
    # If getState returns undef, it is synonymous with
    # the renderer being offline. We will return 0,
    # and, if called from the webUI, it will return an
    # xml result with an error to the browser.
    
    $state = get_update_state();
	
    if (!defined($state))
    {
        error("call to get_update_state() failed");
        static_init_renderer(0);
        $g_renderer = undef;
        return;
    }

    # We continue thru the loop in state ERROR
    # and return the renderer with the ERROR state
    # to the UI
    
    elsif ($state eq 'PLAYING')
    {
        display($dbg_ren+2,1,"update() - renderer PLAYING");
        my $data = get_device_data();

        if (!$data)
        {
            error("call to get_device_data() failed");
            static_init_renderer(0);
			$g_renderer = undef;
			return;
        }    
        elsif (!defined($data->{reltime}))
        {
            warning(0,0,"update() ignoring PLAYING renderer with undefined reltime");
        }
        else
        {
            # if the song_id is "" it's not from us
            # if the song_id doesn't agree with the current songlist
            # it's not from us.  In either case, we turn off {station}
            # optimized to not check if pending song
            
            if ($station && !$pending_song)
            {
                if (!$data->{song_id} || $data->{song_id} ne $song_id)
                {
                    LOG(0,"detected song change on renderer ... stopping station");
                    setStation(undef);
                }
            }
            
            # if we are still in control, then check for stalled renderer
            
            if ($station)
            {
                if ($data->{reltime} eq $reltime)
                {
                    $stall_count++;
                    display($dbg_ren,0,"stalled renderer count=$stall_count");
                    if ($stall_count > 4)
                    {
                        LOG(0,"detected stalled renderer .. stopping");
                        return if !stop();
                    }
                }
                else
                {
                    $stall_count = 0;
                }
            }
    
            $state = 'PLAYING_STATION' if $station;
    
            # update the members for the UI
            # @$this{keys %$data} = values %$data;

			$duration = $data->{duration};
			$reltime = $data->{reltime};
			$metadata = $data->{metadata};
			
			# needed?
			
			my $type = $data->{type};
			my $uri = $data->{uri};
        
        }   # got a valid reltime
    }   # state == PLAYING
    
    # if we are playing the songlist and the renderer
    # is stopped, enqueue the next song.
    # optimized to not stop if pending song
    
    elsif ($station && $state eq 'STOPPED' && !$pending_song)
    {
        display($dbg_ren,1,"update() calling play_next_song()");
        if (!play_next_song(1))
        {
            display($dbg_ren,0,"play_next_song() returned false in update()");
            return;
        }
        display($dbg_ren,1,"update() back from play_next_song()");
    }
    
    display($dbg_ren+1,1,"update($g_renderer->{friendlyName}) returning 1");
    return 1;
}



sub get_update_state
    # This method called on every time slice.
    #
    # If !$data, the renderer state will be ERROR,
    # and we will return undef immediately. This is
    # synonymous with the renderer being unreachable.
    #
    # On the other hand, if we got valid xml from the renderer,
    # but it's state is not OK, we return a state of 'ERROR',
    # a subtle distinction.
{
    my $data = doAction(0,'GetTransportInfo');
    return if !$data;
    
    display($dbg_ren+2,0,"Status Info\n$data");
    
    my $status = $data =~ /<CurrentTransportStatus>(.*?)<\/CurrentTransportStatus>/s ? $1 : '';
    my $state = $data =~ /<CurrentTransportState>(.*?)<\/CurrentTransportState>/s ? $1 : '';
    
    $state = 'ERROR' if ($status ne 'OK');
    display($dbg_ren+1,0,"getState=$state");
    return $state;
}




sub get_device_data
    # issue the GetPositionInfo action, and return
    # a hash with the results.
{
    my $data = doAction(0,'GetPositionInfo');
    return if !$data;

    display($dbg_ren+2,0,"Position Info\n$data");
    
    my %retval;
    $retval{duration} = $data =~ /<TrackDuration>(.*?)<\/TrackDuration>/s ? $1 : '';
    $retval{reltime} = $data =~ /<RelTime>(.*?)<\/RelTime>/s ? $1 : '';

    # Get the file type from the file extensionin the TrackURI
    # This will be incorrect except for MP3 due to kludge in
    # get_item_meta_didl().
    
    $retval{uri} = $data =~ /<TrackURI>(.*?)<\/TrackURI>/s ? $1 : '';
    $retval{type} = $retval{uri} =~ /.*\.(.*?)$/ ? uc($1) : '';

    # song number
    
    $retval{song_id} = "";
    if ($retval{uri} =~ /http:\/\/$server_ip:$server_port\/media\/(.*?)\.mp3/)
    {
        $retval{song_id} = $1;
        display($dbg_ren+2,0,"getSongNum() found song_id=$retval{song_id}");
    }

    # metadata
    
    $retval{metadata} = shared_clone({});
    get_metafield($data,$retval{metadata},'title','dc:title');
    get_metafield($data,$retval{metadata},'artist','upnp:artist');
    get_metafield($data,$retval{metadata},'artist','dc:creator') if !$retval{metadata}->{artist};
    get_metafield($data,$retval{metadata},'albumArtURI','upnp:albumArtURI');
    get_metafield($data,$retval{metadata},'genre','upnp:genre');
    get_metafield($data,$retval{metadata},'date','dc:date');
    get_metafield($data,$retval{metadata},'album','upnp:album');
    get_metafield($data,$retval{metadata},'track_num','upnp:originalTrackNumber');

    $retval{metadata}->{size} = ($data =~ /size="(\d+)"/) ? $1 : 0;
    $retval{metadata}->{pretty_size} = $retval{metadata}->{size} ?
        pretty_bytes($retval{metadata}->{size}) : '';

    # Get a better version of the 'type' from the DLNA info
    # esp. since we ourselves sent the wrong file extension
    # in the kludge in get_item_meta_didl()
    
    $retval{type} = 'WMA' if ($data =~ /audio\/x-ms-wma/);
    $retval{type} = 'WAV' if ($data =~ /audio\/x-wav/);
    $retval{type} = 'M4A' if ($data =~ /audio\/x-m4a/);

    display($dbg_ren+1,0,"getPosition()=$retval{reltime},$retval{duration},$retval{song_id}");
    display($dbg_ren+2,1,"uri='$retval{uri}' type='$retval{type}'");
    
    # VOLUME DOES NOT WORK ON BUBBLEUP CAR STEREO

    if (0)
    {
        $vol--;
        display($dbg_ren,0,"SetVolume($vol)");
        
        use Data::Dumper;
        $data = doAction(1,'SetVolume',{DesiredVolume=>$vol});
        if ($data)
        {
            display($dbg_ren,0,"SET VOLUME:\n".Dumper($data));
        }
    
        $data = doAction(1,'GetVolume');
        if ($data)
        {
            display($dbg_ren,0,"GOT VOLUME:\n".Dumper($data));
        }
        
        if (0)
        {
            $data = doAction(1,'GetMute');
            if ($data)
            {
                display($dbg_ren,0,"GOT MUTE:\n".Dumper($data));
            }
        }
    }    

    return \%retval;
}




sub get_metafield
    # look for &lt/&gt bracketed value of id
    # massage it as necessary
    # and set it into hash as $field
{
    my ($data,$hash,$field,$id) = @_;
    my $value = '';
    $value = $1 if ($data =~ /&lt;$id&gt;(.*?)&lt;\/$id&gt/s);
    $hash->{$field} = $value;
}



#--------------------------------------------------------
# doAction - do one avTransport action to the renderer
#--------------------------------------------------------
# The only method on the actual renderer object
# returns undef or !$data in error cases, setting
# $state to ERROR.

sub doAction
{
    my ($rv,$action,$args) = @_;
    display($dbg_ren+1,0,"doAction($rv,$action)");
	
	if (!$g_renderer)
	{
		warning(0,0,"No renderer in doAction($rv,$action)");
		return;
	}
	

    my $sock = IO::Socket::INET->new(
        PeerAddr => $g_renderer->{ip},
        PeerPort => $g_renderer->{port},
        Proto => 'tcp',
        Type => SOCK_STREAM,
        Blocking => 1);
    if (!$sock)
    {
        error("Could not open socket to $g_renderer->{ip}:$g_renderer->{port}");
        $state = 'ERROR';
        return;
    }


    my $service = $rv ? 'RenderingControl' : 'AVTransport';
    my $url = $rv ? $g_renderer->{rendererControlURL} : $g_renderer->{avControlURL};

    # build the body    

    my $body = '<?xml version="1.0" encoding="utf-8"?>'."\r\n";
    $body .= "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">";
    $body .= "<s:Body>";
    $body .= "<u:$action xmlns:u=\"urn:schemas-upnp-org:service:$service:1\">";
    $body .= "<InstanceID>0</InstanceID>";
    $body .= "<Channel>Master</Channel>" if ($rv);
    
    if ($args)
    {
        for my $k (keys(%$args))
        {
            $body .= "<$k>$args->{$k}</$k>";        
        }
    }
    
    $body .= "</u:$action>";
    $body .= "</s:Body>";
    $body .= "</s:Envelope>\r\n";

    # build the header and request
    
    my $request = '';
    $request .= "POST $url HTTP/1.1\r\n";
    $request .= "HOST: $g_renderer->{ip}:$g_renderer->{port}\r\n";
    $request .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
    $request .= "Content-Length: ".length($body)."\r\n";
    $request .= "SOAPACTION: \"urn:schemas-upnp-org:service:$service:1#$action\"\r\n";
    $request .= "\r\n";
    $request .= $body;

    # send the action

    display($dbg_ren+2,1,"sending action($action) request");
    display($dbg_ren+2,1,"--------------- request --------------------");
    display($dbg_ren+2,1,$request);
    display($dbg_ren+2,1,"--------------------------------------------");
    
    if (!$sock->send($request))
    {
        error("Could not send message to renderer socket");
        $state = 'ERROR';
        return;
    }

    # get the response
    
    display($dbg_ren+1,1,"getting action($action) response");
    
    my %headers;
    my $first_line = 1;
    my $line = <$sock>;
    while (defined($line) && $line ne "\r\n")
    {
        chomp($line);
        $line =~ s/\r|\n//g;
        display($dbg_ren+2,2,"line=$line");
        if ($line =~ /:/)
        {
			my ($name, $value) = split(':', $line, 2);
			$name = lc($name);
            $name =~ s/-/_/g;
			$value =~ s/^\s//g;
			$headers{$name} = $value;
        }
        $line = <$sock>;
    }
    
    # WDTV puts out chunked which I think means that
    # the length is on a the next line, in hex
    
    my $length = $headers{content_length};
    if (!$length && $headers{transfer_encoding} eq 'chunked')
    {
        my $hex = <$sock>;
        $hex =~ s/^\s*//g;
        $hex =~ s/\s*$//g;
        $length = hex($hex);
        display($dbg_ren+1,0,"using chunked transfer_encoding($hex) length=$length");
    }

    # continuing ...
    
    if (!$length)
    {
        error("No content length returned by response");
        $state = 'ERROR';
        return;
    }
    
    my $data;
    my $rslt = $sock->read($data,$length);
    if (!$rslt || $rslt != $length)
    {
        error("Could not read $length bytes from socket");
        $state = 'ERROR';
        return;
    }
    if (!$data)
    {
        error("No data found in action response");
        $state = 'ERROR';
        return;
    }
    
    
    display($dbg_ren+1,1,"got "._def($rslt)." bytes from socket");
    
    display($dbg_ren+2,1,"--------------- response --------------------");
    display($dbg_ren+2,1,"'$data'");
    display($dbg_ren+2,1,"--------------------------------------------");
    
    # return to caller
    
    $sock->close();
    return $data;

}   # doAction



#--------------------------------------------------
# actions
#--------------------------------------------------

sub stop
{
	if (!$g_renderer)
	{
		warning(0,0,"No renderer in stop()");
		return;
	}
	display($dbg_ren,0,"stop()");
    lock(%g_renderers);
    display($dbg_ren,1,"stop() got lock");

    my $retval = $g_renderer->doAction(0,'Stop') ? 1 : 0;
    display($dbg_ren,1,"stop() returning $retval");
    return $retval;
}


sub play
{
    my ($set_song_id) = @_;
    $set_song_id ||= "";

	if (!$g_renderer)
	{
		warning(0,0,"No renderer in play($set_song_id)");
		return;
	}
    display($dbg_ren,0,"play($set_song_id)");
    lock(%g_renderers);
    display($dbg_ren,1,"play() got lock");
    
    return if !stop();
    $song_id = $set_song_id;
	my $retval = $g_renderer->doAction(0,'SetAVTransportURI',{
		CurrentURI => "http://$server_ip:$server_port/media/$song_id.mp3",
		CurrentURIMetaData => get_item_meta_didl($song_id) }) ? 1 : 0;
	$retval = $retval && $g_renderer->doAction(0,'Play',{ Speed => 1});
	$song_id = '' if !$retval;
	$metadata = metadata_from_item($song_id);
    display($dbg_ren,1,"play($set_song_id) returning $retval with song_id='$song_id'");
    return $retval;
}




sub setStation
{
    my ($set_station) = @_;

	if (!$g_renderer)
	{
		warning(0,0,"No renderer in setStation(".($set_station?$set_station->{name}:'undef').")");
		return;
	}
    display($dbg_ren,0,"setStation(".($set_station?$set_station->{name}:'undef').")");
    lock(%g_renderers);
    display($dbg_ren,1,"setStation() got lock");
    
    my $this_num = $station ? $station->{station_num} : 0;
    my $that_num = $set_station ? $set_station->{station_num} : 0;
    
    if ($this_num != $that_num)
    {
        return if $station && !stop();
        init_renderer(1);
		$station = $set_station;
        return if $station && !play_next_song();
    }
    
    display($dbg_ren,1,"setStation(".($set_station?$set_station->{name}:'undef').") returning 1");
    return 1;
}



sub play_next_song
{
	if (!$g_renderer)
	{
		warning(0,0,"No renderer in play_next_song()");
		return;
	}
	if (!$station)
	{
		warning(0,0,"No station in play_next_song()");
		return;
	}
	
    display($dbg_ren,0,"play_next_song() station=$station->{name}");
    lock(%g_renderers);
    display($dbg_ren,1,"play_next_song() got lock");
            
    my $a_song_id = $station->getNextTrackID();

    LOG(0,"playing next($station->{name},$station->{track_index},$a_song_id)");
    my $retval = play($a_song_id);
    display($dbg_ren,1,"play_next_song() returning $retval");
    return $retval;
}



sub play_prev_song
    # only called externally
{
    my ($this) = @_;
	if (!$g_renderer)
	{
		warning(0,0,"No renderer in play_prev_song()");
		return;
	}
	if (!$station)
	{
		warning(0,0,"No station in play_prev_song()");
		return;
	}

    display($dbg_ren,0,"play_prev_song() station=$station->{name}");
    lock(%g_renderers);
    display($dbg_ren,1,"play_prev_song() got lock");
            
    my $a_song_id = $station->getPrevTrackID();

    LOG(0,"playing prev($station->{name},$station->{track_index},$a_song_id)");
    my $retval = play($a_song_id);
    display($dbg_ren,1,"play_prev_song() returning $retval");
    return $retval;
}





sub async_play_song
    # an alternative to play_next/prev_song
    # for better responsiveness 
    # bump the track number, set the pending song number,
    # and return the metadata to the client right away.
    # The song will start playing on the next monitor loop.
{
    my ($inc) = @_;
	if (!$g_renderer)
	{
		warning(0,0,"No renderer in async_play_song()");
		return;
	}
	if (!$station)
	{
		warning(0,0,"No station in async_play_song()");
		return;
	}

    display($dbg_ren,0,"async_play_song() station=$station->{name} inc=$inc");

    lock(%g_renderers);
    $song_id = $station->getIncTrackID($inc);
    $pending_song = $song_id;
    $pending_timer = 0;
    $metadata = metadata_from_item($pending_song);
    return 1;
}




sub play_single_song
    # play a single song id.
	# uses pending mechanism.
	# should *not* stop the radio station,
	# which *should* continue when the song is done.
{
    my ($set_song_id) = @_;
	if (!$g_renderer)
	{
		warning(0,0,"No renderer in play_single_song()");
		return;
	}

    display($dbg_ren,0,"play_single_song($set_song_id)");

    lock(%g_renderers);
    $song_id = $set_song_id;
    $pending_song = $song_id;
    $pending_timer = 0;
    $metadata = metadata_from_item($song_id);
    return 1;
}





#----------------------------------------------------
# Fake little library for meta data xml
#----------------------------------------------------

sub didl_header
{
    my $xml = filter_lines(1,undef,<<EOXML);
<DIDL-Lite
    xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
    xmlns:sec="http://www.sec.co.kr/dlna"
    xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" >
EOXML
	return $xml;
}


sub didl_footer
{
    my $xml = filter_lines(1,undef,<<EOXML);
</DIDL-Lite>
EOXML
    return $xml;
}


sub get_item_meta_didl
{
    my ($item_num) = @_;

    my $dbh = db_connect();

    display($dbg_ren+1,0,"get_item_meta_didl($item_num)");
    my $item = get_track($dbh,$item_num);
    display($dbg_ren+1,1,"item="._def($item)." parent_id=".($item?$item->{PARENT_ID}:'undef'));
    my $parent = get_folder($dbh,$item->{PARENT_ID});
    display($dbg_ren+1,1,"parent="._def($parent)." parent_id=".($item?$item->{PARENT_ID}:'undef'));
    display($dbg_ren,1,"($item_num) == $item->{FULLNAME}");
 
    db_disconnect($dbh);
   
    # The Kludge.
    # for some fucking reason, Bup does not display the metainfo
    # if the FILEEXT is WMA, wma, M4a, m4a, etc, so, the only thing
    # I found that work was to send mp3 as the type. Thus later,
    # when bup returns the metadata to us, we extract the
    # actual type from the metadata protocolinfo.

    display($dbg_ren+1,0,"sending bogus 'mp3' type for '$item->{FILEEXT}'")
        if ($item->{FILEEXT} !~ /mp3/i);
    $item->{FILEEXT} = 'mp3';

    # debugging when renderer doees't show correct stuff
    # selectively add lines to see what happens
    
    if (0)
    {
         $item->{TITLE} = 'THIS IS THE TITLE blah';
         $item->{ARTIST} = 'THIS IS THE ARTIST';
         $item->{ALBUM}  = 'THIS IS THE ALBUM';
         $item->{GENRE}  = 'THIS IS THE GENRE';
         $item->{FILEEXT} = 'mp3';
    }
    
    my $meta_didl =
        didl_header() .
        xml_item($item,$parent) .
        didl_footer();
        
    display(9,0,"meta_didle=$meta_didl");
        
    return $meta_didl;
}


sub metadata_from_item
    # Usually the renderer get's the metadata from the device.
    # This routine stuffs the metadata member directly, ahead
    # of the next poll of the device, to make prev/next more
    # responsive (by setting the metadata right away)
{
    my ($item_num) = @_;

    display($dbg_ren+1,0,"metadata_from_item($item_num)");

    my $dbh = db_connect();
    my $item = get_track($dbh,$item_num);
    my $parent = get_folder($dbh,$item->{PARENT_ID});
    db_disconnect($dbh);
 
    my $metadata = shared_clone({});
    $metadata->{title} = $item->{TITLE};
    $metadata->{artist} = $item->{ARTIST};
    $metadata->{genre} = $item->{GENRE};
    $metadata->{date} = $item->{YEAR};
    $metadata->{track_num} = $item->{TRACKNUM};
    $metadata->{album} = $item->{ALBUM};
    $metadata->{albumArtURI} = $parent->{HAS_ART} ? 
		"http://$server_ip:$server_port/get_art/$parent->{ID}/folder.jpg" :
        '';

    $metadata->{size} = $item->{SIZE};
    $metadata->{pretty_size} = pretty_bytes($metadata->{size});

    return $metadata;
}


#------------------------------------------------
# auto-monitoring
#------------------------------------------------


sub auto_update_thread
{
	appUtils::set_alt_output(1);
    LOG(0,"starting auto_update_thread");
    
    while (!$quitting)
    {
		if ($g_renderer)
		{
            display($dbg_ren,0,"auto_update '$g_renderer->{id}'");
            $g_renderer->update();
        }        

        sleep(1);
    }
}




if (0)	# test
{
	my @devices = getUPNPDeviceList();
}




1;
