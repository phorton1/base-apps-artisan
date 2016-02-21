#!/usr/bin/perl
#------------------------------------------------
# SSDPSearch
#
# getDLNARenderers() - returns a list of DLNA Renderers known to the system
#     as a hash by ip:port of records (hashes) consisting of the following
#     fields:
#
#       id = ip:port
#   	friendlyName
#		ip
#		port
#		avControlURL
#		rendererControlURL
#		volMax
#		supportsMute    
#
# getUPNPDeviceList()
#     low level method to do a generic M_SEARCH and return
#     a list of matching devices, and the descriptive XML
#     generally considered private, as it requires a knowledgable
#     client to parse the Device XML that is returned.


package SSDPSearch;
use strict;
use warnings;
# use threads;
# use threads::shared;
use IO::Select;
use IO::Socket::INET;
use XML::Simple;
use LWP::UserAgent;
use Utils;

my $dbg_ssdp_search = -2;

my $ssdp_port = 1900;
my $ssdp_group = '239.255.255.250';


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
	my ($ua) = @_;
	display($dbg_ssdp_search,0,"getDLNARenderers()");

	my %retval;
	$ua ||= LWP::UserAgent->new();
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
		
		# create a record for the parsed object
		# this record agrees exactly with Renderer.pm
		
		my $rec = {
			id 			 => $id,
			name 		 => $name,
			ip 			 => $xml->{ip},
			port 		 => $xml->{port},
			transportURL => '',
			controlURL   => '',
			maxVol       => 0,
			canMute      => 0,
			
			# following are not set by this code
			
			canLoud      => 0,
			maxBal       => 0,
			maxFade      => 0,
			maxBass      => 0,
			maxMid       => 0,
			maxHigh      => 0,
		};

		# loop thru the services to find the
		# AVTransport and RenderingControl services
		# and save their urls into the params.
		
		my $service_list = $device->{serviceList};
		my $services = $service_list->{service};
		$services = [$services] if ref($services) !~ /ARRAY/;
		
		for my $service (@$services)
		{
			my $type = $service->{serviceType};
			if ($type eq 'urn:schemas-upnp-org:service:AVTransport:1')
			{
				$rec->{transportURL} = fix_url($service->{controlURL});
			}
			elsif ($type eq 'urn:schemas-upnp-org:service:RenderingControl:1')
			{
				$rec->{controlURL} = fix_url($service->{controlURL});
				my $url = "http://$rec->{ip}:$rec->{port}";
				$url .= "/" if ($service->{SCPDURL} !~ /^\//);
				$url .= $service->{SCPDURL};
				getSupportedControls($ua,$rec,$url);
			}
		}

		# Done with loop, give error if either url is missing.
		# But allow client to decide if they want to use it or not.
		# See Renderer::getRenderers().
		
		if (!$rec->{controlURL})
		{
			error("Could not find RenderingControl controlURL for renderer($name)");
		}
		if (!$rec->{avControlURL})
		{
			error("Could not find AVTransport transportURL for renderer($name)");
		}
		
		# We're done.
		# The client must normalize this list against the active renderer,
		# and decide if they want to use any without avControlURLs
		
		$retval{$rec->{id}} = $rec;

	}   # for every device
    
    return \%retval;
}                



sub getSupportedControls
	# get the Max Volumne integer and
	# whether the device supports Mute
{
    my ($ua,$rec,$url) = @_;
    display($dbg_ssdp_search,1,"getSupportedControls($url)");
    my $response = $ua->get($url);
    if (!$response->is_success())
    {
        error("Could not get RendererControl description xml from $url");
        return;
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
        return;
    }
 
    # sanity checks
    
    if ($xml->{actionList}->{action}->{GetMute} &&
        $xml->{actionList}->{action}->{SetMute})
    {
        $rec->{canMute} =
            $xml->{serviceStateTable}->{stateVariable}->{Mute} ? 1 : 0;
        display($dbg_ssdp_search,2,"got canMute=$rec->{canMute}");
    }
 
    if ($xml->{actionList}->{action}->{GetVolume} &&
        $xml->{actionList}->{action}->{SetVolume})
    {
        my $volume =
            $xml->{serviceStateTable}->{stateVariable}->{Volume};
        $rec->{maxVol} = $volume->{allowedValueRange}->{maximum};
        display($dbg_ssdp_search,2,"got maxVol=$rec->{maxVol}");
    }
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

    display($dbg_ssdp_search,1,"creating socket");

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



if (0)	# static testing SSDP
{
	my $search_device = 'urn:schemas-upnp-org:device:MediaRenderer:1';
	# my $search_device = 'upnp:rootdevice';
	# my $search_device = 'ssdp:all';
	my @devices = getUPNPDeviceList($search_device);
}

if (0)	# static testing DLNA
{
	my $dlna_renderers = getDLNARenderers();
}



1;
