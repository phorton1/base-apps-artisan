#!/usr/bin/perl
#------------------------------------------------
# DLNARenderer.pm
#
# This module contains, and depends on the low level
# routine getUPNPDeviceList() which is a candidate
# for a separate PM file.  Otherwise, it's all about
# DLNA Renderrs
#
#    static_init_dlna_renderer_cache()
#
#        static method called from the main app to
#        read the last available list of DLNA renderers
#        into  memory.
#
#    static getDLNARenderers(refresh)
#
#		 	0 = return existing list
#           1 = add new items to, or change modified items in, the list
#           2 = rebuild list from scratch
#
#	     Possibly refresh, and returns a list of DLNARenderers
#        known to the system. Generally clients use this list
#        directly to populate a list of selectable renderers.
#
#    static getDLNARenderer(id)
#
#        Returns the DLNA renderer of the given ID, if any.
#        This is an object that supports the following object
#        methods which make use of the control URLs.
#
# A (local) renderer object may be registered with this module
# and will be available to the rest of the system.  If it is
# it must provide these methods (which are already on the
# base DLNA renderer):
#
#    getState()
#
#        Returns undef if renderer is not online or there
#            is a problem with the return value (no status)
#        Otherwise, returns the state of the DLNA renderer
#            PLAYING, STOPPED, TRANSITIONING, ERROR, etc
#        The PLAYING.* and STOPPED states are checked in
#            the main Renderer update() and set_playlist()
#            methods.
#
#            STOPPED is used in update() to advance to the
#            next track if there is a playlist active, and
#            PLAYING is the state in which getDeviceData()
#            will be called from update()
#            PLAYING is also used in set_playlist() when
#            switching to a new renderer, it must be
#            acheived before advancing the new renderer
#            to position
#
#    getDeviceData()
#
#        If getState() returns 'PLAYING' this method may be called.
#        Returns undef if renderer is not online.
#        Otherwise, returns a $data hash with interesting fields:
#
#			duration	- milliseconds
#           position	- milliseconds
#           vol			- 0 (not supported)
#           mute		- 0 (not supported)
#           uri			- that the renderer used to get the song
#           song_id     - our song_id, if any, by RE from the uri
#           type        - song "type" from RE on the uri, or metadata mime type
#			metadata    - hash containing
#				artist
#				title
#				album_title
#				album_artist
#			    track_num
#  				art_uri
#				genre
#				date
#				size
#				pretty_size
#
#    public doCommand(command,args)
#		 'stop'
#        'set_song', song_id
#        'play'
#        'seek', position
#        'pause'
#
#------------------------------------------------------------------
# LOCAL RENDERER
#------------------------------------------------------------------
# A Local Renderer may be created and registered with this class.
# It will then be returned first in the list of available renders,
# and may be given out to clients by calls to getDLNARenderer.
#
# It must provide member variables id and name, and might as
# well provide useful values for maxVol, canMute, etc.
#
#
# Client calls setLocalRenderer(obj) which must
# provide getState(), getDeviceData, and doCommand()
# methods.
#
# These will be called directly on the object by
# clients.
#
#------------------------------------------------------------------
# private implementation methods
#------------------------------------------------------------------
#
#    private_doAction(action,args)
#
#        Previously Public available actions:
#
#			0,'Stop'
#			0,'SetAVTransportURI',
#				CurrentURI => "http://$server_ip:$server_port/media/$song_id.mp3",
#               CurrentURIMetaData => get_item_meta_didl($song_id) }) ? 1 : 0;
#			0,'Play',{ Speed => 1}
#			0,'Seek',{Unit => 'REL_TIME',target => millis_to_duration($g_renderer->{position})}
#			0,'Pause'
#           	was called directly by uiRenderer
#
#
#        Internal Low Level (DLNA only) actions
#
#  			0,'GetTransportInfo'
#			0,'GetPositionInfo'
#			1,'GetVolume'
#			1,'GetMute'
#
#------------------------------------------------------------------
#
#    getUPNPDeviceList()
#
#       low level method to do a generic M_SEARCH and return
#       a list of matching devices, and the descriptive XML
#       generally considered private, as it requires a knowledgable
#       client to parse the Device XML that is returned.
#       Candidate for another module.


package DLNARenderer;
use strict;
use warnings;
use threads;
use threads::shared;
use IO::Select;
use IO::Socket::INET;
use XML::Simple;
use LWP::UserAgent;
use Utils;
use Database;
use Library;


my $dbg_dlna = 0;
my $dbg_ssdp_search = 0;

my $ssdp_port = 1900;
my $ssdp_group = '239.255.255.250';


# all but ip, port, and URLS required by derived classes

my @renderer_fields : shared = qw(
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

my $local_renderer : shared;
my %g_renderers : shared;
my $renderer_cachefile = "$temp_dir/renderer_cache.txt";


sub setLocalRenderer
{
	my ($obj) = @_;
	display(0,0,"setLocalRenderer("._def($obj).")");
	if ($local_renderer)
	{
		delete $g_renderers{$local_renderer->{id}};
		$local_renderer = undef;
	}
	if ($obj)
	{
		$local_renderer = $obj;
		$g_renderers{$obj->{id}} = $obj;
	}
}



#-------------------------------------------
# construction and cache file
#-------------------------------------------


sub new
{
	my ($class) = @_;
	my $this = shared_clone({});
	bless $this,$class;
	return $this;
}


sub getDLNARenderer
{
	my ($id) = @_;
	return $g_renderers{$id};
}


sub static_init_dlna_renderer_cache
	# static initialization by client code!!
{
	display(0,0,"static_init_dlna_renderer_cache()");
    if (-f $renderer_cachefile)
    {
        my $lines = getTextLines($renderer_cachefile);
        for my $line (@$lines)
        {
            chomp($line);
            my $renderer = DLNARenderer->new();
            @$renderer{@renderer_fields} = split(/\t/,$line);
			$g_renderers{$renderer->{id}} = $renderer;
			display($dbg_dlna,1,"adding cached renderer($renderer->{id})=$renderer->{name}")
        }
    }
    my $num = keys(%g_renderers) || 0;
    display($dbg_dlna,0,"found $num dlna renderers in cache");
}



sub write_dlna_renderer_cache
{
    my $text = '';
    display($dbg_dlna,0,"write_dlna_renderer_cache");
    for my $id (sort(keys(%g_renderers)))
    {
        my $renderer = $g_renderers{$id};
        display($dbg_dlna,1,"writing $id=$renderer->{name}");
        my $line = join("\t",@$renderer{@renderer_fields});
        $text .= $line."\n";
    }
    if (!printVarToFile(1,$renderer_cachefile,$text))
    {
        error("Could not write to renderer cachefile '$renderer_cachefile'");
    }
}




#==================================================================
# PUBLIC API
#==================================================================


sub doCommand
	# Supports the following commands and arguments
	#
	#	'stop'
	#   'set_song', track_id
	#   'play'
	#   'seek', position
	#   'pause'
{
	my ($this,$command,$arg) = @_;
	display($dbg_ren,0,"doCommand($command,$arg)");

	if ($command eq 'stop')
	{
		return $this->private_doAction(0,'Stop') ? 1 : 0;
	}
	elsif ($command eq 'set_song')
	{
		my $track = get_track(undef,$arg);

		if (!$track)
		{
			error("Could not get track($arg)in doCoommand()");
			return 0;
		}
		return $this->private_doAction(0,'SetAVTransportURI',{
			CurrentURI => "http://$server_ip:$server_port/media/$arg.mp3",
            CurrentURIMetaData => $track->getDidl() });
	}
	elsif ($command eq 'play')
	{
		return $this->private_doAction(0,'Play',{ Speed => 1}) ? 1 : 0;
	}
	elsif ($command eq 'seek')
	{
		my $time_str = millis_to_duration($arg,1);
		return $this->private_doAction(0,'Seek',{
			Unit => 'REL_TIME',
			Target => $time_str})  ? 1 : 0;
	}
	elsif ($command eq 'pause')
	{
		return $this->private_doAction(0,'Pause') ? 1 : 0;
	}

	error("Unknown command $command in doCoommand()");
	return 0;
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
    my $data = $this->private_doAction(0,'GetTransportInfo');
    return if !$data;

    display($dbg_ren+2,0,"Status Info\n$data");

    my $status = $data =~ /<CurrentTransportStatus>(.*?)<\/CurrentTransportStatus>/s ? $1 : '';
    my $state = $data =~ /<CurrentTransportState>(.*?)<\/CurrentTransportState>/s ? $1 : '';

    $state = 'ERROR' if ($status ne 'OK');
    display($dbg_ren+2,0,"getState=$state");
    return $state;
}



sub getDeviceData
    # issue the GetPositionInfo action, and return
    # a hash with the results.
{
    my ($this) = @_;
    my $data = $this->private_doAction(0,'GetPositionInfo');
    return if !$data;

    display($dbg_ren+2,0,"Position Info\n$data");

    my %retval;
	my $dur_str = $data =~ /<TrackDuration>(.*?)<\/TrackDuration>/s ? $1 : '';
    my $pos_str = $data =~ /<RelTime>(.*?)<\/RelTime>/s ? $1 : '';

    $retval{duration} = duration_to_millis($dur_str);
    $retval{position} = duration_to_millis($pos_str);

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
    get_metafield($data,$retval{metadata},'art_uri','upnp:albumArtURI');
    get_metafield($data,$retval{metadata},'genre','upnp:genre');
    get_metafield($data,$retval{metadata},'year_str','dc:date');
    get_metafield($data,$retval{metadata},'album_title','upnp:album');
    get_metafield($data,$retval{metadata},'album_artist','upnp:albumArtist');
    get_metafield($data,$retval{metadata},'track_num','upnp:originalTrackNumber');
    $retval{metadata}->{size} = ($data =~ /size="(\d+)"/) ? $1 : 0;
	$retval{metadata}->{pretty_size} = pretty_bytes($retval{metadata}->{size});

    # Get a better version of the 'type' from the DLNA info
    # esp. since we ourselves sent the wrong file extension
    # in the kludge in get_item_meta_didl()

    $retval{type} = 'WMA' if ($data =~ /audio\/x-ms-wma/);
    $retval{type} = 'WAV' if ($data =~ /audio\/x-wav/);
    $retval{type} = 'M4A' if ($data =~ /audio\/x-m4a/);

    display($dbg_ren+1,0,"GOT_POSITION: position=$retval{position} duration=$retval{duration} id=$retval{song_id}");
    display($dbg_ren+2,1,"uri='$retval{uri}' type='$retval{type}'");

    # VOLUME DOES NOT WORK ON BUBBLEUP CAR STEREO

    if (1)
	{
		$retval{vol} = 0;
		$retval{mute} = 0;
	}
	else
    {
        $data = $this->private_doAction(1,'GetVolume');
        if ($data)
        {
            display($dbg_ren,0,"GOT VOLUME:\n".Dumper($data));
        }
		$data = $this->private_doAction(1,'GetMute');
		if ($data)
		{
			display($dbg_ren,0,"GOT MUTE:\n".Dumper($data));
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


my $call_num = 0;


sub private_doAction
	# do one avTransport action to the renderer
	# returns undef in error cases
{
    my ($this,$rv,$action,$args) = @_;

	display(0,0,"$action($args->{Target})") if $action =~ /Seek/;

	display($dbg_ren+1,0,"private_doAction($rv,$action)");

    my $sock = IO::Socket::INET->new(
        PeerAddr => $this->{ip},
        PeerPort => $this->{port},
        Proto => 'tcp',
        Type => SOCK_STREAM,
        Blocking => 1);
    if (!$sock)
    {
        error("Could not open socket to $this->{ip}:$this->{port}");
        return;
    }


    my $service = $rv ? 'RenderingControl' : 'AVTransport';
    my $url = $rv ? $this->{controlURL} : $this->{transportURL};

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
	    $sock->close();
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
        display($dbg_ren+1,2,"line=$line");
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
    display($dbg_ren+1,2,"content_length=$length");

    if (!$length && $headers{transfer_encoding} eq 'chunked')
    {
        my $hex = <$sock>;
        $hex =~ s/^\s*//g;
        $hex =~ s/\s*$//g;
        $length = hex($hex);
        display($dbg_ren+1,2,"using chunked transfer_encoding($hex) length=$length");
    }

    # continuing ...

    if (!$length)
    {
        error("No content length returned by response");
	    $sock->close();
        return;
    }

    my $data;
    my $rslt = $sock->read($data,$length);
    $sock->close();

    if (!$rslt || $rslt != $length)
    {
        error("Could not read $length bytes from socket");
        return;
    }
    if (!$data)
    {
        error("No data found in action response");
        return;
    }


    display($dbg_ren+1,2,"got "._def($rslt)." bytes from socket");

    display($dbg_ren+1,2,"--------------- response --------------------");
    display($dbg_ren+1,2,"'$data'");
    display($dbg_ren+1,2,"--------------------------------------------");

    # return to caller

    return $data;

}   # private_doAction



#------------------------------------------------------------
# getDLNARenderers
#------------------------------------------------------------
# Return list of current known DLNA Renderers
# With known fields names.
# See Renderer.pm for more information.


sub fix_url
{
    my ($url) = @_;
    $url = '/'.$url if ($url && $url !~ /^\//);
    return $url;
}


sub getDLNARenderers
    # Returns a hash by id (ip:port) of available DLNA Renderers,
	# where each record has the below known fields.
{
	my ($refresh) = @_;
	display($dbg_ssdp_search,0,"getDLNARenderers()");

	if ($refresh)
	{
		# Get and loop through the XML MediaRenderer:1
		# devicesreturned by getUPNPDeviceList();

		my $ua = LWP::UserAgent->new();
		my @dev_list = getUPNPDeviceList('urn:schemas-upnp-org:device:MediaRenderer:1',$ua);
		display($dbg_ssdp_search,1,"found ".scalar(@dev_list)." devices");

		for my $xml (@dev_list)
		{
			my $device = $xml->{device};
			my $type = $device->{deviceType};
			if ($type ne 'urn:schemas-upnp-org:device:MediaRenderer:1')
			{
				error("unexpected typ $type in getDLNARenderers");
				next;
			}
			my $id = "$xml->{ip}:$xml->{port}";
			my $name = $device->{friendlyName};
			display($dbg_ssdp_search,1,"found renderer(id=$id) '$name'");

			# loop thru the services to find the
			# AVTransport and RenderingControl services
			# and save their urls into the params.

			my $service_list = $device->{serviceList};
			my $services = $service_list->{service};
			$services = [$services] if ref($services) !~ /ARRAY/;

			my $transportURL = '';
			my $controlURL = '';
			my $max_vol = 0;
			my $can_mute = 0;

			for my $service (@$services)
			{
				my $type = $service->{serviceType};
				if ($type eq 'urn:schemas-upnp-org:service:AVTransport:1')
				{
					$transportURL = fix_url($service->{controlURL});
					if (1)	# debugging
					{
						my $url = "http://$xml->{ip}:$xml->{port}";
						$url .= "/" if ($service->{SCPDURL} !~ /^\//);
						$url .= $service->{SCPDURL};
						my $response = $ua->get($url);
						if (!$response->is_success())
						{
							error("Could not get AVTransport description xml from $url");
						}
						elsif (0)	# debugging
						{
							my $content = $response->content();
							my $dbg_file = $url;
							$dbg_file =~ s/:|\//./g;
							printVarToFile(1,"/junk/$dbg_file",$content);
						}
					}
				}
				elsif ($type eq 'urn:schemas-upnp-org:service:RenderingControl:1')
				{
					$controlURL = fix_url($service->{controlURL});
					my $url = "http://$xml->{ip}:$xml->{port}";
					$url .= "/" if ($service->{SCPDURL} !~ /^\//);
					$url .= $service->{SCPDURL};
					($max_vol,$can_mute) = getSupportedControls($ua,$url);
				}
			}

			# Give error if either url is missing.
			# The controlURL for the volume control.

			if (!$transportURL)
			{
				error("Could not find AVTransport transportURL for renderer($name)");
			}
			if (!$controlURL)
			{
				error("Could not find RenderingControl controlURL for renderer($name)");
			}

			# Find the existing renderer if any
			# If we do not find an transportURL, then we will not wipe out an
			# existing renderer, but will not create a new renderer object.

			my $renderer = $g_renderers{$id};
			if ($renderer)
			{
				$renderer->{transportURL} = $transportURL if $transportURL;
				$renderer->{controlURL} = $controlURL if $controlURL;

				# update these fields from the dlna_renderer
				# just in case they have changed ...

				$renderer->{maxVol}  = $max_vol;
				$renderer->{canMute} = $can_mute;
				$renderer->{online}  = 2;
			}
			elsif ($transportURL)
			{
				$renderer = DLNARenderer->new();
				$renderer->{id} 	= $id;
				$renderer->{name} 	= $name;
				$renderer->{ip}		= $xml->{ip};
				$renderer->{port}   = $xml->{port};
				$renderer->{transportURL} = $transportURL;
				$renderer->{controlURL}   = $controlURL || '';
				$renderer->{maxVol}  = $max_vol;
				$renderer->{canMute} = $can_mute;
				$renderer->{canLoud} = 0;
				$renderer->{maxBal}  = 0;
				$renderer->{maxFade} = 0;
				$renderer->{maxBass} = 0;
				$renderer->{maxMid}  = 0;
				$renderer->{maxHigh} = 0;
				$renderer->{online}  = 2;
				$g_renderers{$id} = $renderer;
			}
			else
			{
				error("Cannot create a Renderer object without a transportURL");
			}

		}	# for each XML device


        # set the "online" status
		# and remove stale entries
		# client should check if it's disappeared!
		# never take the local renderer offline

        for my $id (keys(%g_renderers))
        {
            my $renderer = $g_renderers{$id};
			next if $local_renderer && $renderer->{id} eq $local_renderer->{id};
            $renderer->{online} ||= 0;
            $renderer->{online} = $renderer->{online}==2 ? 1 : 0;
            delete $g_renderers{$id} if $refresh == 2 && !$renderer->{online};
		}

        # write it out

        write_dlna_renderer_cache();

	}

	# finished, return the global list

    return \%g_renderers;
}



sub getSupportedControls
	# get the Max Volumne integer and
	# whether the device supports Mute
{
    my ($ua,$url) = @_;
    display($dbg_ssdp_search,1,"getSupportedControls($url)");
    my $response = $ua->get($url);
    if (!$response->is_success())
    {
        error("Could not get RendererControl description xml from $url");
        return (0,0);
    }

    my $xml;
    my $content = $response->content();

    if (0)	# debugging
	{
		my $dbg_file = $url;
		$dbg_file =~ s/:|\//./g;
		printVarToFile(1,"/junk/$dbg_file",$content);
	}

	my $xmlsimple = XML::Simple->new();
    eval { $xml = $xmlsimple->XMLin($content) };
    if ($@)
    {
        error("Unable to parse xml from $url:".$@);
        return (0,0);
    }

    # get values with sanity checks

	my $max_vol = 0;
	my $can_mute = 0;

    if ($xml->{actionList}->{action}->{GetVolume} &&
        $xml->{actionList}->{action}->{SetVolume})
    {
        my $volume = $xml->{serviceStateTable}->{stateVariable}->{Volume};
        $max_vol = $volume->{allowedValueRange}->{maximum} || 0;
        display($dbg_ssdp_search,2,"got maxVol=$max_vol");
	}

    if ($xml->{actionList}->{action}->{GetMute} &&
        $xml->{actionList}->{action}->{SetMute})
    {
        $can_mute = $xml->{serviceStateTable}->{stateVariable}->{Mute} ? 1 : 0;
        display($dbg_ssdp_search,2,"got canMute=$can_mute");
    }

    return ($max_vol,$can_mute);

}




#--------------------------------------------
# Lower Level Generalized Search for UPNP Devices
#--------------------------------------------

sub getUPNPDeviceList
    # Send out a general UPNP M-SEARCH, then get the
    # service description from each device that replies,
	# and return them as a list of xml hashes,
	# with url, ip, port, and path added.
	#
	# The contents returned are specified by UPNP
	#
	# Takes an optional $ua, but will create one if needed
{
	my ($search_device,$ua) = @_;
		# interesting values are
		# ssdp:all (find everything)
		# ssdp:discover (find root devices)
		# urn:schemas-upnp-org:device:MediaRenderer:1 (DLNA Renderers)

    display($dbg_ssdp_search,0,"getUPNPDeviceList()");
	$ua ||= LWP::UserAgent->new();

    #------------------------------------------------
    # send the broadcast message
    #------------------------------------------------

    my $mx = 3;   # number of seconds window is open for replies
    my $mcast_addr = $ssdp_group . ':' . $ssdp_port;
    my $ssdp_header = <<"SSDP_SEARCH_MSG";
M-SEARCH * HTTP/1.1
Host: $mcast_addr
Man: "ssdp:discover"
ST: $search_device
MX: $mx

SSDP_SEARCH_MSG

    $ssdp_header =~ s/\r//g;
    $ssdp_header =~ s/\n/\r\n/g;

    display($dbg_ssdp_search,1,"creating socket server_ip=$server_ip local_port=8679 ssdp_port=#ssdp_port");

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
    display($dbg_ssdp_search,1,"sending broadcast message");
    _mcast_send( $sock, $ssdp_header, $mcast_addr );

    #------------------------------------------------------
    # loop thru replies to get list of matching devices
    #------------------------------------------------------

    my @device_replies;
    my $sel = IO::Select->new($sock);
    while ( $sel->can_read( $mx ) )
    {
        my $ssdp_res_msg;
        recv ($sock, $ssdp_res_msg, 4096, 0);

        display($dbg_ssdp_search+2,2,"DEVICE RESPONSE");
        for my $line (split(/\n/,$ssdp_res_msg))
        {
            $line =~ s/\s*$//;
            next if ($line eq '');
            display($dbg_ssdp_search+2,3,$line);
        }
        if ($ssdp_res_msg !~ m/LOCATION[ :]+(.*)\r/i)
        {
            error("no LOCATION found in SSDP message");
            next;
        }
        my $dev_location = $1;
        display($dbg_ssdp_search,2,"device_reply from '$dev_location'");
        push @device_replies,$dev_location;
    }

    #----------------------------------------------------------
    # for each found device, get it's device description
    #----------------------------------------------------------

    my @dev_list;
    display($dbg_ssdp_search,1,"getting device descriptions");
    for my $url (@device_replies)
    {
        display($dbg_ssdp_search,2,"getting $url");
        my $response = $ua->get($url);
        if (!$response->is_success())
        {
            error("Could not get device xml from $url");
            next;
        }

        my $xml;
        my $content = $response->content();

        if (0)	# debugging
		{
			my $dbg_file = $url;
			$dbg_file =~ s/:|\//./g;
			printVarToFile(1,"/junk/$dbg_file",$content);
		}

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

            if (0)	# debugging
            {
                display($dbg_ssdp_search+2,1,"------------- XML ------------------");
                use Data::Dumper;
                print Dumper($xml);
                display($dbg_ssdp_search+2,0,"------------- XML ------------------");
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
                    display($dbg_ssdp_search,4,"$field=$val");
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



#----------------------------------------------------------------
# Static Testing
#----------------------------------------------------------------

if (0)
{
	# example code to get a list of active IP numbers (no other information)
	# Could perhaps be used to verify that $server_ip is available
	# local-host

	my ($name,$aliases,$addrtype,$length,@addrs) = gethostbyname('localhost');
	display(0,0,"name=$name");
	foreach my $addr (@addrs)
	{
		my $ip = join('.', unpack('C4', $addr));
		display(0,1,"ip=$ip");
	}

	# by machine name

	($name,$aliases,$addrtype,$length,@addrs) = gethostbyname($name);
	foreach my $addr (@addrs)
	{
		my $ip = join('.', unpack('C4', $addr));
		display(0,1,"ip=$ip");
	}
}




#----------------------------------------------------
# static testing
#----------------------------------------------------


if (0)	# static testing SSDP
{
	my $search_device = 'urn:schemas-upnp-org:device:MediaRenderer:1';
	# my $search_device = 'upnp:rootdevice';
	# my $search_device = 'ssdp:all';
	my @devices = getUPNPDeviceList($search_device);
}

if (0)	# static testing DLNA
{
	static_init_dlna_renderers();
	my $dlna_renderers = getDLNARenderers();
}



1;
