#!/usr/bin/perl
#---------------------------------------
# Renderer.pm
#
# prh - next/prev could be more responsive if they created
# the metadata in advance of the actual renderer update ...
#
# A one sided control point that works within the artisan webUI.
# By default, this code is inactive in artisan, until a webUI is
# opened up to it.
#
# There usage model suports two modes for a given renderer.
#
# The default, passive mode is that the client, the
# javascript on a webpage, calls the webUI perl, which
# in turn calls the renderer->update() method, which
# polls the given device, and returns it's state to the UI.
#
# A renderer may also be in a 'playing' mode, playing
# a given 'station', in which case a separate thread
# here polls the device every second (and manages the
# device to play the station's songlist), and the webui
# notices the differene, and just returns the renderer
# from memory.
#
# In addition to the two modes, there is the concept
# of a selected renderer. if !$PREF_MULTIPLE_RENDERERS,
# then the webUI will return the currently selected
# renderer, regardless of the one the UI asks for,
# and selecting a new one will transfer playback,
# if any, from the previous to the new renderer.
#
# Therefore the UI always shows, and selects, the
# renderer returned by the server, as it may change
# out from under the UI.  
# 
#    getRenderers($refresh)
#    
#       returns a list of the current renderers known to the system.
#       the system caches and remembers all renderers it has found
#    
#       refresh == 0  returns the list of cached renderers
#       refresh == 1  do an SSDP scan for renderers and add them to list
#       refresh == 2  clear the list and do an SSDP scan
#    
#       a renderer is marked as 'online' if it found during an SSDP scan.
#       however, this is unreliable, and so we allow for attempts to select,
#       and monitor, any known renderer. The online bit is not used for anything.
#    
#       If refresh==2, and there is a currently selected renderer, if
#       that renderer is not found in the subsequent list, the current
#       renderer will be set to undef.
#    
#    selectRenderer($id)
#    
#       From the list of known renderers, the UI can select one.
#       The UI should call this in any case to do the first update
#       and to test if the renderer is only, although technically
#       it need not, and may just call update() with an id to see
#       what happens.
#    
#       This is absolutely required if !$PREF_MULTIPLE_RENDERERS,
#       as this is the method that transfers the playing renderer
#       state to a new renderer.
#    
#    getRenderer(id)
#    
#       return the given renderer by id
#    
#    getSelectedRenderer()
#    
#       Returns the currently selected renderer, or undef.
#       Most other methods are instance methods on the renderer object.
#    
# RENDERER METHODS
#
# After getting a renderer, the client may call these methods on it.
# These methods are protected against re-entrancy using
# threads::shared::lock() on the %g_renderers hash.
#
#    update() - called via a polling loop from the webUI, or
#       automatically for renderers with a station number,
#       this method hits the selected renderer and checks its state.
#    
#       The internal behaviour of update() is somewhat complicated,
#       but essentially it monitors the renderer for it's own UI events,
#       detecting stops and stalls, and, if playing a station, enqueues
#       songs as appropriate.
#    
#    setStation($station_num)  0==off
#    
#       A renderer that has a staion number is automatically
#       polled and managed. Setting the station to 0 is the
#       equivilant of calling stop() on it.
#    
#    stop()
#    
#       This will stop the renderer, and any station it migh
#       be playing.
#    
#    play_next_song()
#    play_prev_song()
#    
#       These will play the next or previous song in the station,
#       if any.  They will return false if there is an error, of
#       if the renderer is not playing a station.
#
#    set_position($pct)
#
#       Takes an integer from 0..100 and moves the renderer there.
#
# POLLING HEURISTICS
#
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
# (3) If we ever detect a different song than we are expecting, then
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
use Library;
use Database;
use Utils;
use Station;
use uiPrefs;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
        getRenderer
        getSelectedRenderer
        getRenderers
        selectRenderer
    );
}


#-----------------------------
# CONSTANTS
#-----------------------------
# ssdp constants

my $ssdp_port = 1900;
my $ssdp_group = '239.255.255.250';

# cachefile constants

my @cache_fields = qw(
    friendlyName
    ip
    port
    avControlURL
    rendererControlURL
    volMax
    supportsMute );
    
my $renderer_cachefile = "$cache_dir/renderer_cache.txt";


#---------------------------
# VARIABLES
#---------------------------
# list of the current renderers by id
# the current renderer, and the current songlist.

my %g_renderers : shared;
my $g_renderer : shared;

# working vars

my $ua = LWP::UserAgent->new();


#------------------------------------------
# Construction
#------------------------------------------

sub getSelectedRenderer
{
    return $g_renderer;
}

sub getRenderer
{
    my ($id) = @_;
    return $g_renderers{$id};
}



sub id_from_ip_port
{
    my ($ip,$port) = @_;
    my $id =  "$ip.$port";
    $id =~ s/\./_/g;
    return $id;
}


sub id_of
{
    my ($this) = @_;
    return id_from_ip_port($this->{ip},$this->{port});
}




sub new
    # required params are
    #    friendlyName
    #    ip
    #    port
    #    avControlURL
{
    my ($class,$params) = @_;
    my $id = id_of($params);
    display($dbg_ren,0,"Renderer::new($id)");
    my $this = shared_clone($params);
    bless $this,$class;
    
    $this->{id} = $id;
    
    $this->init_renderer();

    $this->{online} = 0;

    $g_renderers{$id} = $this;
    return $this;
}


sub init_renderer
    # level 0 = init everything
    # level 1 = turn off station
    # level 2 = init for new song
{
    my ($this,$level) = @_;
    $level ||= 0;
    
    display($dbg_ren,0,"init_renderer($level) - $this->{friendlyName}");

    if ($level <= 2)
    {
        $this->{song_num} = 0;
        $this->{metadata} = undef;
        $this->{reltime} = '';
        $this->{duration} = '';
        $this->{play_pct} = 0;
        $this->{stall_count} = 0;
    }
    
    if ($level <= 1)
    {

        $this->{station} = undef;
        delete $this->{station};

    }
    
    if (!$level)
    {
        $this->{state} = '';
    }

    display($dbg_ren,0,"init_renderer($level) finished");
}    
    
    
sub inherit
{
    my ($this,$that) = @_;
    for my $field (qw(station metadata song_num reltime duration play_pct))
    {
        $this->{$field} = $that->{$field};
    }
}


sub calc_play_pct
{
    my ($reltime,$duration) = @_;
    my $relsecs = time_to_secs($reltime);
    my $dursecs = time_to_secs($duration);
    my $pct = $dursecs ? int(100 * ($relsecs/$dursecs)) : 0;
    return $pct;
}


sub time_to_secs
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


sub fix_url
{
    my ($url) = @_;
    $url = '/'.$url if ($url && $url !~ /^\//);
    return $url;
}


#------------------------------------------------------------
# SSDP - getRenderers
#------------------------------------------------------------
    
sub getRenderers
    # Starting with a list of UPNP devices,
    # fleshes out, and invariantly returns the
    # global list of renderers.
{
    my ($refresh) = @_;
    if ($refresh)
    {
        display($dbg_ren,0,"getRenderers(1)");
        my @dev_list = getUPNPDeviceList();
        display($dbg_ren,1,"getRenderers() found ".scalar(@dev_list)." devices");
        for my $xml (@dev_list)
        {
            my $device = $xml->{device};
            my $type = $device->{deviceType};
            if ($type eq 'urn:schemas-upnp-org:device:MediaRenderer:1')
            {
                my $name = $device->{friendlyName};
                display($dbg_ren,1,"found renderer '$name'");

                # create a record for the parsed object
                
                my $params = {
                    friendlyName => $name,
                    ip => $xml->{ip},
                    port => $xml->{port},
                    avControlURL => '',
                    rendererControlURL => '',
                    volMax => 0,
                    supportsMute => 0
                };

                # loop thru the services to find the AVTransport and RenderingControl services
                # and save their urls into the params.
                
                my $service_list = $device->{serviceList};
                my $services = $service_list->{service};
                $services = [$services] if ref($services) !~ /ARRAY/;
                
                for my $service (@$services)
                {
                    my $type = $service->{serviceType};
                    if ($type eq 'urn:schemas-upnp-org:service:AVTransport:1')
                    {
                        $params->{avControlURL} = fix_url($service->{controlURL});
                    }
                    elsif ($type eq 'urn:schemas-upnp-org:service:RenderingControl:1')
                    {
                        $params->{rendererControlURL} = fix_url($service->{controlURL});
                        my $url = "http://$params->{ip}:$params->{port}";
                        $url .= "/" if ($service->{SCPDURL} !~ /^\//);
                        $url .= $service->{SCPDURL};
                        getVolMaxAndSupportsMute($params,$url);
                    }
                }

                # Done with loop, give error if either url is missing.
                
                if (!$params->{rendererControlURL})
                {
                    error("Could not find RenderingControl rendererControlURL for renderer($name)");
                }
                if (!$params->{avControlURL})
                {
                    error("Could not find AVTransport avControlURL for renderer($name)");
                }
                
                # The avControlURL is the important one, that we use for most stuff.
                # We only use the renderingControlURL for the volume control.
                # If we do not find an avControlURL, then we will not wipe out an
                # existing one, but will not create a new renderer object from it.
                # rendererControlURL is just along for the ride.

                my $id = id_of($params);
                my $renderer = $g_renderers{$id};
                if ($renderer)
                {
                    $renderer->{avControlURL} = $params->{avControlURL}
                        if ($params->{avControlURL});
                    $renderer->{rendererControlURL} = $params->{rendererControlURL}
                        if ($params->{rendererControlURL});

                    # take these params in case we are updating an
                    # existing renderer cache text file with new fields.
                    
                    $renderer->{volMax} = $params->{volMax};
                    $renderer->{supportsMute} = $params->{supportsMute};
                }
                elsif ($params->{rendererControlURL})
                {
                    $renderer = Renderer->new($params);
                }
                else
                {
                    error("Cannot create a Renderer object without a avControlURL");
                }
                
                
                $renderer->{online} = 2 if ($renderer);

            }   # for every MediaRenderer
        }   # for every device
                
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
    }
    
    return \%g_renderers;
}                



sub getVolMaxAndSupportsMute
{
    my ($params,$url) = @_;
    display($dbg_ren,2,"getVolMaxAndSupportsMute($url)");
    my $response = $ua->get($url);
    if (!$response->is_success())
    {
        error("Could not get RendererControl description xml from $url");
        return;
    }

    my $xml;
    my $content = $response->content();
    
    my $dbg_file = $url;
    $dbg_file =~ s/:|\//./g;
    printVarToFile(1,"/junk/$dbg_file",$content);

    my $xmlsimple = XML::Simple->new();
    eval { $xml = $xmlsimple->XMLin($content) };
    if ($@)
    {
        error("Unable to parse xml from $url:".$@);
        return;
    }
 
    # sanity checks
    
    if ($xml->{actionList}->{action}->{GetMute} &&
        $xml->{actionList}->{action}->{SetMute})
    {
        $params->{supportsMute} =
            $xml->{serviceStateTable}->{stateVariable}->{Mute} ? 1 : 0;
        display($dbg_ren,0,"got supportsMute=$params->{supportsMute}");
    }
 
    if ($xml->{actionList}->{action}->{GetVolume} &&
        $xml->{actionList}->{action}->{SetVolume})
    {
        my $volume =
            $xml->{serviceStateTable}->{stateVariable}->{Volume};
        $params->{volMax} = $volume->{allowedValueRange}->{maximum};
        display($dbg_ren,0,"got volmax=$params->{volMax}");
    }
}



sub getUPNPDeviceList
    # Send out a general UPNP root device request, then get the
    # service description from each device and return them
    # as a list of xml hashes, with url, ip, port, and path added.
{
    display($dbg_ren,0,"getUPNPDeviceList()");
    
    #------------------------------------------------
    # send the broadcast message
    #------------------------------------------------
    
    my $mx = 3;   # number of seconds window is open for replies
    my $mcast_addr = $ssdp_group . ':' . $ssdp_port;
    my $ssdp_header = <<"SSDP_SEARCH_MSG";
M-SEARCH * HTTP/1.1
Host: $mcast_addr
Man: "ssdp:discover"
ST: upnp:rootdevice
MX: $mx

SSDP_SEARCH_MSG

    $ssdp_header =~ s/\r//g;
    $ssdp_header =~ s/\n/\r\n/g;

    display($dbg_ren,1,"creating socket");

    my $sock = IO::Socket::INET->new(
        LocalAddr => $server_ip,
        LocalPort => 8679,
        PeerPort  => $ssdp_port,
        Proto     => 'udp',
        ReuseAddr => 1);
    if (!$sock)
    {
        error("Cannot create socket to send multicast $@");
        return;
    }

    # add the socket to the correct IGMP multicast group
    # and actually send the message. 
    
    _mcast_add( $sock, $mcast_addr );
    display($dbg_ren,1,"sending broadcast message");
    _mcast_send( $sock, $ssdp_header, $mcast_addr );

    #------------------------------------------------------
    # loop thru replies to get list of root devices
    #------------------------------------------------------
    
    my @device_replies;
    my $sel = IO::Select->new($sock);
    while ( $sel->can_read( $mx ) )
    {
        my $ssdp_res_msg;
        recv ($sock, $ssdp_res_msg, 4096, 0);

        display($dbg_ren+2,2,"DEVICE RESPONSE");
        for my $line (split(/\n/,$ssdp_res_msg))
        {
            $line =~ s/\s*$//;
            next if ($line eq '');
            display($dbg_ren+2,3,$line);
        }
        if ($ssdp_res_msg !~ m/LOCATION[ :]+(.*)\r/i)
        {
            error("no LOCATION found in SSDP message");
            next;
        }
        my $dev_location = $1;
        display($dbg_ren,2,"device_reply from '$dev_location'");
        push @device_replies,$dev_location;
    }
    
    #----------------------------------------------------------
    # for each found device, get it's device description
    #----------------------------------------------------------
    # and return if and when the target renderer is found.

    my @dev_list;
    display($dbg_ren,1,"getting device descriptions");
    for my $url (@device_replies)
    {
        display($dbg_ren,2,"getting $url");
        my $response = $ua->get($url);
        if (!$response->is_success())
        {
            error("Could not get device xml from $url");
            next;
        }

        my $xml;
        my $content = $response->content();
        
        my $dbg_file = $url;
        $dbg_file =~ s/:|\//./g;
        printVarToFile(1,"/junk/$dbg_file",$content);

        my $xmlsimple = XML::Simple->new();
        eval { $xml = $xmlsimple->XMLin($content) };
        if ($@)
        {
            error("Unable to parse xml from $url:".$@);
            my $response = http_header({
                statuscode   => 501,
                content_type => 'text/plain' });
        }
        else
        {
            # massage the ip, port, and path out of the location
            # and into the xml record
        
            if ($url !~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i)
            {
                error("ill formed device url: $url");
                next;
            }
            $xml->{ip} = $1;
            $xml->{port} = $2;
            $xml->{path} = $3;
            $xml->{url} = $url;
            push @dev_list,$xml;
            
            if (0)
            {
                display($dbg_ren+2,1,"------------- XML ------------------");
                use Data::Dumper;
                print Dumper($xml);
                display($dbg_ren+2,0,"------------- XML ------------------");
            }
            
            if (1)
            {
                for my $field (qw(
                    deviceType
                    friendlyName
                    manufacturer
                    manufacturerURL
                    modelDescription
                    modelName
                    modelNumber
                    serialNumber
                    UDN))
                {
                    my $val = $xml->{device}->{$field} || '';
                    display($dbg_ren,4,"$field=$val");
                }
            }
        }
    }

    close $sock;
    return @dev_list;
}


sub _mcast_add
{
    my ( $sock, $host ) = @_;
    my ( $addr, $port ) = split /:/, $host;
    my $ip_mreq = inet_aton( $addr ) . INADDR_ANY;

    if (!setsockopt(
        $sock,
        getprotobyname('ip') || 0,
        _constant('IP_ADD_MEMBERSHIP'),
        $ip_mreq  ))
    {
        error("Unable to add IGMP membership: $!");
        exit 1;
    }
}


sub _mcast_send
{
    my ( $sock, $msg, $host ) = @_;
    my ( $addr, $port ) = split /:/, $host;

    # Set a TTL of 4 as per UPnP spec
    if (!setsockopt(
        $sock,
        getprotobyname('ip') || 0,
        _constant('IP_MULTICAST_TTL'),
        pack 'I', 4 ))
    {
        error("Error setting multicast TTL to 4: $!");
        exit 1;
    };

    my $dest_addr = sockaddr_in( $port, inet_aton( $addr ) );
    my $bytes = send( $sock, $msg, 0, $dest_addr );
    # print "Sent $bytes bytes\n";
}


sub _constant
{
    my ($name) = @_;
    my %names = (
        IP_MULTICAST_TTL  => 0,
        IP_ADD_MEMBERSHIP => 1,
        IP_MULTICAST_LOOP => 0,
    );
    my %constants = (
        MSWin32 => [10,12],
        cygwin  => [3,5],
        darwin  => [10,12],
        default => [33,35],
    );

    my $index = $names{$name};
    my $ref = $constants{ $^O } || $constants{default};
    return $ref->[ $index ];
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
    
    my $renderer = $g_renderers{$id};
    if (!$renderer)
    {
        error("Could not get renderer($id) in selectRenderer()");
    }
    
    # try to get the state to test if the renderer is online
    # return an error if not.
    
    else
    {
        $state = $renderer->getState();
        if (!$state)
        {
            error("No state in selectRenderer($id)");
        }
    }
    
    
    # if we are not using a single selected renderer,
    # that's it, we're done.  Otherwise, do all the stuff
    # to inherit from the previous renderer, if any
    
    my $mult = getPreference($PREF_MULTIPLE_RENDERERS);
    LOG(0,"UNSUPPORTED PREF_MULTIPLE_RENDERERS") if $mult;
    
    if ($state) # && !$mult)
    {
        LOG(0,"selectRenderer(SINGLE,$id)");
        
        if ($g_renderer)
        {
            if (is_shared($renderer) == is_shared($g_renderer))
            {
                display($dbg_ren,1,"selectRenderer(same renderer)");
            }
            else
            {
                display($dbg_ren,1,"selectRenderer($id) inhereting from $g_renderer->{friendlyName}");

                $renderer->inherit($g_renderer);
                $g_renderer->init_renderer();
                
                if ($renderer->{station})
                {
                    display($dbg_ren,1,"selectRenderer() stopping previous renderer");
                    if (!$g_renderer->stop())
                    {
                        display($dbg_ren,1,"prev_renderer->stop() returned false in selectRenderer()");
                        $renderer = undef;
                    }
                }
            }
            $g_renderer = undef;
        }
    
        if ($renderer)
        {
            $g_renderer = $renderer;
            display($dbg_ren,1,"selectRenderer($id) assigning new renderer");
        
            # start new renderer playing if old one was
            
            if ($g_renderer->{station})
            {
                display($dbg_ren,0,"starting station($g_renderer->{station}->{name}) on new renderer. reltime="._def($g_renderer->{reltime}));
                if (!$g_renderer->play($g_renderer->{song_num}))
                {
                    display($dbg_ren,1,"renderer->play($g_renderer->{song_num}) returned false");
                    $renderer = undef;
                }
        
                elsif ($g_renderer->{reltime} && $g_renderer->{reltime} gt '00:00:05')
                {
                    # attempts to seek before doAction(play) seem to fail
                    # we could sleep but that cause song to stop, then jump to position
                    # we try to get better timing by waiting for transport to reach PLAYING state.
        
                    display($dbg_ren,1,"waiting for PLAYING ..");
            
                    my $count = 5;
                    my $state = $g_renderer->getState();
                    while ($state ne 'PLAYING' && --$count > 0)
                    {
                        sleep(1);
                        $state = $g_renderer->getState();
                    }
        
                    display($dbg_ren,1,"finished waiting with count=$count and state=$state");
                    display($dbg_ren,1,"seeking to $g_renderer->{reltime} ..");
                    
                    if (!$g_renderer->doAction(0,'Seek',{
                        Unit => 'REL_TIME',
                        Target => $g_renderer->{reltime} }))
                    {
                        warning(0,0,"selectRenderer($id) seek to $g_renderer->{reltime} failed");
                    }
                    
               }    # seking in new renderer
            }   # new renderer has a station
        }   # previous renderer stopped ok
    }   # SINGLE_RENDERER
    
    display($dbg_ren,0,"selectRenderer returning ".($renderer?$renderer->{friendlyName}:'undef'));
    return $renderer;
}



sub set_position
{
    my ($this,$pct) = @_;
    my $retval = 1;
    
    display($dbg_ren,0,"set_position($pct)");
    lock(%g_renderers);
    display($dbg_ren,1,"set_position($pct) got lock");
    
    if (!$this->{duration})
    {
        error("No duration in set_position($pct)");
        $retval = 0;
    }
    else
    {
        my $dursecs = time_to_secs($this->{duration});
        my $relsecs = int(($pct + 0.5) * $dursecs / 100);
        display($dbg_ren,1,"set_position($pct) dursecs=$dursecs relsecs=$relsecs");
        
        my $reltime = secs_to_time($relsecs);
        display($dbg_ren,1,"set_position($pct) seeking to '$reltime'");
        if (!$this->doAction(0,'Seek',{
            Unit => 'REL_TIME',
            Target => $reltime }))
        {
            error("set_position($pct) could not seek to '$reltime'");
            $retval = 0;
        }
        else
        {
            $this->{reltime} = $reltime;
            $this->{play_pct} = $pct;
        }
    }

    display($dbg_ren,1,"set_position($pct) returning $retval");
    return $retval;
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
# In the end, it sets member variables on the
# renderer which will be passed to the UI.
#
# It reports errors and returns undef if there are problems.
# If the problem was in a call to doAction(), the renderer
# will also be ERROR.
#
# Tried to use lock() selectively but still ran into problems.


sub update
    # Get the status of the renderer.
    # If it is playing, get the position and
    # metainfo and do heuristics.
{
    my ($this) = @_;
    my $retval = 1;
    
    display($dbg_ren+1,0,"update($this->{friendlyName})");
    lock(%g_renderers);
    display($dbg_ren+1,1,"update($this->{friendlyName}) got lock");

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
        
        my $song_num = $this->{pending_song};
        display($dbg_ren,0,"playing pending song($song_num)");
        $this->play($song_num);
        $this->{song_num} = $song_num;
        $this->{pending_song} = 0;
        return 1;
    }
    
    # and spin around one more time to let the
    # renderer catch up, so that we return the
    # new song's metadata on the next call
    
    elsif ($this->{pending_timer} && $this->{pending_timer} == 1)
    {
        $this->{pending_timer} = 0;
        return 1;
    }
    
    
    # If getState returns undef, it is synonymous with
    # the renderer being offline. We will return 0,
    # and, if called from the webUI, it will return an
    # xml result with an error to the browser.
    
    my $state = $this->getState();
    if (!defined($state))
    {
        error("call to getState() failed");
        $this->init_renderer();
        $g_renderer = undef if ($g_renderer && $this->{id} eq $g_renderer->{id});
        $retval = 0;
    }

    # We continue thru the loop in state ERROR
    # and return the renderer with the ERROR state
    # to the UI
    
    elsif ($state eq 'PLAYING')
    {
        display($dbg_ren+2,1,"update() - renderer PLAYING");
        my $data = $this->getDeviceData();

        if (!$data)
        {
            error("Could not get device data from $this->{friendlyName}");
            $this->init_renderer();
            $retval = 0;
        }    
        elsif (!defined($data->{reltime}))
        {
            warning(0,0,"update() ignoring PLAYING renderer with undefined reltime");
        }
        else
        {
            # if the song_number is zero or undefined, it's not from us
            # if the song_number doesn't agree with the current songlist
            # it's not from us.  In either case, we turn off {station}
            # optimized to not check if pending song
            
            if ($this->{station} && !$this->{pending_song})
            {
                if (!$data->{song_num} || $data->{song_num} != $this->{song_num})
                {
                    LOG(0,"detected song change on renderer ... stopping station");
                    $this->setStation(0);
                }
            }
            
            # if we are still in control, then check for stalled renderer
            
            if ($this->{station})
            {
                if ($data->{reltime} eq $this->{reltime})
                {
                    $this->{stall_count}++;
                    display($dbg_ren,0,"stalled renderer count=$this->{stall_count}");
                    if ($this->{stall_count} > 4)
                    {
                        LOG(0,"detected stalled renderer .. stopping");
                        $retval = $this->stop();
                    }
                }
                else
                {
                    $this->{stall_count} = 0;
                }
            }
    
            $state = 'PLAYING_STATION' if $this->{station};
    
            # update the members for the UI

            $this->{state} = $state;
            @$this{keys %$data} = values %$data;
            $this->{play_pct} = calc_play_pct($data->{reltime},$data->{duration});
        
        }   # got a valid reltime
    }   # state == PLAYING
    
    # if we are playing the songlist and the renderer
    # is stopped, enqueue the next song.
    # optimized to not stop if pending song
    
    elsif ($this->{station} && $state eq 'STOPPED' && !$this->{pending_song})
    {
        display($dbg_ren,1,"update() calling play_next_song()");
        if (!$this->play_next_song(1))
        {
            display($dbg_ren,0,"play_next_song() returned false in update()");
            return;
        }
        display($dbg_ren,1,"update() back from play_next_song()");
    }
    
    # otherwise, just set the state member
    
    elsif ($state ne $this->{state})
    {
        $this->{state} = $state;
    }
    
    display($dbg_ren+1,1,"update($this->{friendlyName}) returning $retval");
    return 1;
}



sub getState
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
    my ($this) = @_;
    my $data = $this->doAction(0,'GetTransportInfo');
    return if !$data;
    
    display($dbg_ren+2,0,"Status Info\n$data");
    
    my $status = $data =~ /<CurrentTransportStatus>(.*?)<\/CurrentTransportStatus>/s ? $1 : '';
    my $state = $data =~ /<CurrentTransportState>(.*?)<\/CurrentTransportState>/s ? $1 : '';
    
    $state = 'ERROR' if ($status ne 'OK');
    display($dbg_ren+1,0,"getState=$state");
    return $state;
}




my $vol:shared = 100;


sub getDeviceData
    # issue the GetPositionInfo action, and return
    # a hash with the results.
{
    my ($this) = @_;
    my $data = $this->doAction(0,'GetPositionInfo');
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
    
    $retval{song_num} = 0;
    if ($retval{uri} =~ /http:\/\/$server_ip:$server_port\/media\/(.*?)\.mp3/)
    {
        $retval{song_num} = $1;
        display($dbg_ren+2,0,"getSongNum() found song_num=$retval{song_num}");
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

    display($dbg_ren+1,0,"getPosition()=$retval{reltime},$retval{duration},$retval{song_num}");
    display($dbg_ren+2,1,"uri='$retval{uri}' type='$retval{type}'");
    
    # VOLUME DOES NOT WORK ON BUBBLEUP CAR STEREO

    if (0)
    {
        $vol--;
        display($dbg_ren,0,"SetVolume($vol)");
        
        use Data::Dumper;
        $data = $this->doAction(1,'SetVolume',{DesiredVolume=>$vol});
        if ($data)
        {
            display($dbg_ren,0,"SET VOLUME:\n".Dumper($data));
        }
    
        $data = $this->doAction(1,'GetVolume');
        if ($data)
        {
            display($dbg_ren,0,"GOT VOLUME:\n".Dumper($data));
        }
        
        if (0)
        {
            $data = $this->doAction(1,'GetMute');
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
# returns undef or !$data in error cases, setting
# this->{state} to ERROR.

sub doAction
{
    my ($this,$rv,$action,$args) = @_;
    display($dbg_ren+1,0,"doAction($rv,$action)");

    my $sock = IO::Socket::INET->new(
        PeerAddr => $this->{ip},
        PeerPort => $this->{port},
        Proto => 'tcp',
        Type => SOCK_STREAM,
        Blocking => 1);
    if (!$sock)
    {
        error("Could not open socket to $this->{ip}:$this->{port}");
        $this->{state} = 'ERROR';
        return;
    }



    my $service = $rv ? 'RenderingControl' : 'AVTransport';
    my $url = $rv ? $this->{rendererControlURL} : $this->{avControlURL};

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
    $request .= "HOST: $this->{ip}:$this->{port}\r\n";
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
        $this->{state} = 'ERROR';
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
        $this->{state} = 'ERROR';
        return;
    }
    
    my $data;
    my $rslt = $sock->read($data,$length);
    if (!$rslt || $rslt != $length)
    {
        error("Could not read $length bytes from socket");
        $this->{state} = 'ERROR';
        return;
    }
    if (!$data)
    {
        error("No data found in action response");
        $this->{state} = 'ERROR';
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
    my ($this) = @_;
    display($dbg_ren,0,"stop($this->{friendlyName})");
    lock(%g_renderers);
    display($dbg_ren,1,"stop($this->{friendlyName}) got lock");

    my $retval = $this->doAction(0,'Stop') ? 1 : 0;

    display($dbg_ren,1,"stop($this->{friendlyName}) returning $retval");
    return $retval;
}


sub play
{
    my ($this,$song_number) = @_;
    my $retval = 1;
    $song_number ||= 0;

    display($dbg_ren,0,"play($this->{friendlyName}) song_number=$song_number");
    lock(%g_renderers);
    display($dbg_ren,1,"play($this->{friendlyName}) got lock");
    
    if ($song_number)
    {
        if (!$this->stop())
        {
            $retval = 0;
        }
        else
        {
            $retval = $this->doAction(0,'SetAVTransportURI',{
                CurrentURI => "http://$server_ip:$server_port/media/$song_number.mp3",
                CurrentURIMetaData => get_item_meta_didl($song_number) }) ? 1 : 0;
            
            if ($retval)
            {
                $this->{metadata} = metadata_from_item($song_number);
            }
        }
    }
    
    if ($retval)
    {
        $retval = $this->doAction(0,'Play',{ Speed => 1}) ? 1 : 0;
    }
    
    display($dbg_ren,1,"play($this->{friendlyName}) returning $retval");
    return $retval;
}




sub setStation
{
    my ($this,$station) = @_;
    my $retval = 1;

    display($dbg_ren,0,"setStation($this->{friendlyName}) station=".($station?$station->{name}:'undef'));
    lock(%g_renderers);
    display($dbg_ren,1,"setStation($this->{friendlyName}) got lock");
    
    my $this_num = $this->{station} ? $this->{station}->{station_num} : 0;
    my $that_num = $station ? $station->{station_num} : 0;
    
    if ($this_num != $that_num)
    {
        if ($this->{station})
        {
            $retval = 0 if !$this->stop();
        }

        $this->init_renderer(1);
        
        if ($retval && $station)
        {
            $this->{station} = $station;
            $retval = 0 if !$this->play_next_song();
        }
    }
    
    display($dbg_ren,1,"setStation($this->{friendlyName}) returning $retval");
    return $retval;
}



sub play_next_song
{
    my ($this) = @_;

    display($dbg_ren,0,"play_next_song($this->{friendlyName}) station=$this->{station}->{name}");
    lock(%g_renderers);
    display($dbg_ren,1,"play_next_song($this->{friendlyName}) got lock");
            
    $this->{song_num} = $this->{station}->getNextTrackID();

    LOG(0,"playing next($this->{station}->{station_num}.".
        "$this->{station}->{name})".
        "song($this->{station}->{track_index}) = $this->{song_num}");

    my $retval = $this->play($this->{song_num});
    display($dbg_ren,1,"play_next_song($this->{friendlyName}) returning $retval");
    return $retval;
}




sub async_play_song
    # an alternative to play_next/prev_song
    # for better responsiveness 
    # bump the track number, set the pending song number,
    # and return the metadata to the client right away.
    # The song will start playing on the next monitor loop.
{
    my ($this,$inc) = @_;

    display($dbg_ren,0,"async_play_song($this->{friendlyName}) station=$this->{station}->{name} inc=$inc");

    lock(%g_renderers);
    $this->{song_num} = $this->{station}->getIncTrackID($inc);
    $this->{pending_song} = $this->{song_num};
    $this->{pending_timer} = 0;
    $this->{metadata} = metadata_from_item($this->{pending_song});
    return 1;
}




sub play_single_song
    # play a single song id.
	# uses pending mechanism.
	# should *not* stop the radio station,
	# which *should* continue when the song is done.
{
    my ($this,$song_number) = @_;

    display($dbg_ren,0,"play_single_song($this->{friendlyName}) id=$song_number");

    lock(%g_renderers);
    $this->{song_num} = $song_number;
    $this->{pending_song} = $song_number;
    $this->{pending_timer} = 0;
    $this->{metadata} = metadata_from_item($song_number);
    return 1;
}



sub play_prev_song
    # only called externally
{
    my ($this) = @_;

    display($dbg_ren,0,"play_prev_song($this->{friendlyName}) station=$this->{station}");
    lock(%g_renderers);
    display($dbg_ren,1,"play_prev_song($this->{friendlyName}) got lock");
            
    $this->{song_num} = $this->{station}->getPrevTrackID();

    LOG(0,"playing prev($this->{station}->{station_num}.".
        "$this->{station}->{name})".
        "song($this->{station}->{track_index}) = $this->{song_num}");

    my $retval = $this->play($this->{song_num});
    display($dbg_ren,1,"play_prev_song($this->{friendlyName}) returning $retval");
    return $retval;
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
    
    while (1)
    {
        for my $id (sort(keys(%g_renderers)))
        {
            next if (!getPreference($PREF_MULTIPLE_RENDERERS) && (
                !$g_renderer || $g_renderer->{id} ne $id));
            my $renderer = $g_renderers{$id};
            next if !$renderer->{station};
            
            # issue the call to update()
            # the thread will block and wait
            # if there is a UI method call in progress
            
            display($dbg_ren+1,0,"auto_update '$renderer->{id}'");
            $renderer->update();
        }        

        sleep(1);
    }
}


#--------------------------------------------
# main
#--------------------------------------------
# static initialization

read_renderer_cache();


1;
