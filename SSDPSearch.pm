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

my $dbg_ssdp_search = 0;

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
	my @dev_list = getUPNPDeviceDescriptionList('urn:schemas-upnp-org:device:MediaRenderer:1',$ua);
	display($dbg_ssdp_search,1,"found ".scalar(@dev_list)." devices");
	
	for my $device_xml (@dev_list)
	{
		my $device = $device_xml->{device};
		my $type = $device->{deviceType};
		if ($type ne 'urn:schemas-upnp-org:device:MediaRenderer:1')
		{
			error("unexpected typ $type in getDLNARenderers");
			next;
		}
		my $id = "$device_xml->{ip}:$device_xml->{port}";
		my $name = $device->{friendlyName};
		display($dbg_ssdp_search,1,"found renderer(id=$id) '$name'");
		
		# create a record for the parsed object
		# this record agrees exactly with Renderer.pm
		
		my $rec = {
			id 			 => $id,
			name 		 => $name,
			ip 			 => $device_xml->{ip},
			port 		 => $device_xml->{port},
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
				getSupportedControls($ua,$device_xml,$service,$rec);
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
    my ($ua,$device_xml,$service,$rec) = @_;
	
	my $type = $service->{serviceType};
	$type =~ s/^urn://;		# make it more readable
	my $display_name = "service.$device_xml->{ip}:$device_xml->{port}-$type";
    display($dbg_ssdp_search,1,"getSupportedControls($display_name)");
	
	my $xml = getDeviceDescriptionFile($ua,$device_xml,$service);
	return if !$xml;
 
    # sanity checks
    
    if ($xml->{actionList}->{action}->{GetMute} &&
        $xml->{actionList}->{action}->{SetMute})
    {
        $rec->{canMute} =
            $xml->{serviceStateTable}->{stateVariable}->{Mute} ? 1 : 0;
        display($dbg_ssdp_search,2,"got canMute=$rec->{canMute}");
    }
	else
	{
        display($dbg_ssdp_search,2,"cannot control Mute");
	}
 
    if ($xml->{actionList}->{action}->{GetVolume} &&
        $xml->{actionList}->{action}->{SetVolume})
    {
        my $volume =
            $xml->{serviceStateTable}->{stateVariable}->{Volume};
        $rec->{maxVol} = $volume->{allowedValueRange}->{maximum};
        display($dbg_ssdp_search,2,"got maxVol=$rec->{maxVol}");
    }
	else
	{
        display($dbg_ssdp_search,2,"cannot control Volume");
	}
}



sub getServiceDescriptionFile
	# given a service xml record from a UPNP Device Description,
	# get the Service Description, and return it as parse xml
{
    my ($ua,$device_xml,$service) = @_;
	
	my $type = $service->{serviceType};
	$type =~ s/^urn://;		# make it more readable
	my $display_name = "service.$device_xml->{ip}:$device_xml->{port}-$type";
    display($dbg_ssdp_search,1,"getServiceDescriptionFile($display_name)");

	# get the url, and get the content
	
	my $url = fix_url($service->{SCPDURL});
	if (!$url)
	{
		error("Could not find SCPDURL for $display_name");
		return;
	}
	
	return getDescriptionFile($ua,"http://$device_xml->{ip}:$device_xml->{port}".$url,$display_name)
}
	
	
sub getDescriptionFile
	# given an url to an xml file, get it, and parse
{
	my ($ua,$url,$display_name) = @_;
    display($dbg_ssdp_search,1,"getDescriptionFile($display_name)");
    display($dbg_ssdp_search,2,"url=$url");
	
    my $response = $ua->get($url);
    if (!$response->is_success())
    {
        error("Could not get xml content from $url");
        return;
    }

    my $content = $response->content();
	dbg_dump($content,$display_name.".txt.xml");
	dbg_dump_xml($content,$display_name.".xml");
	
	# parse it into xml    
	
    my $xml;
	my $xmlsimple = XML::Simple->new();
    eval { $xml = $xmlsimple->XMLin($content) };
    if ($@)
    {
        error("Unable to parse xml from $url:".$@);
        return;
    }
	if (!$xml)
	{
		error("No parsed xml return for $url!!");
		return;
	}
	return $xml;
}
	
 


#--------------------------------------------
# Lower Level Generalized Search for UPNP Devices
#--------------------------------------------

sub getUPNPDeviceDescriptionList
    # Send out a general UPNP M-SEARCH, then get the
    # service description from each device that replies,
	# and return the device descriptions in a list of
	# xml hashes, with url, ip, port, and path added.
	# The contents returned are specified by UPNP
	# Takes an optional $ua, but will create one if needed
{
	my ($search_device,$ua,$include_re,$exclude_re) = @_;
		# interesting values are
		# ssdp:all (find everything)
		# ssdp:discover (find root devices)
		# urn:schemas-upnp-org:device:MediaRenderer:1 (DLNA Renderers)
		
    display($dbg_ssdp_search,0,"getUPNPDeviceList()");
	$ua ||= LWP::UserAgent->new();
	my $device_replies = getUPNPDeviceList($search_device,$ua,$include_re,$exclude_re);
    #----------------------------------------------------------
    # for each found device, get it's device description
    #----------------------------------------------------------

    my @dev_list;
    display($dbg_ssdp_search,1,"getting device descriptions");
    for my $rec (@$device_replies)
    {
		my $url = $rec->{url};
		my $device_name = $rec->{st};
	    display($dbg_ssdp_search,1,"getting services($device_name)");
		display($dbg_ssdp_search,2,"url=$url");
		
		if ($url !~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i)
		{
			error("ill formed device url: $url");
			next;
		}
		my $ip = $1;
		my $port = $2;
		my $path = $3;
		my $display_name = "device.$ip.$port-$device_name";

		# get the xml
		
		my $xml = getDescriptionFile($ua,$url,$display_name);
		next if !$xml;

		$xml->{ip} = $ip;
		$xml->{port} = $port;
		$xml->{path} = $path;
		$xml->{url} = $url;
		push @dev_list,$xml;
            
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

    return @dev_list;
}
	
	
	
sub getUPNPDeviceList
    # Send out a general UPNP M-SEARCH, then get the
    # service description from each device that replies,
	# and return a list of records containing fields:
	#
	#    url = the url for the device description file
	#    st = uuid:blah, urn: upnp:rootdevice, etc)
{
	my ($search_device,$ua,$include_re,$exclude_re) = @_;
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

        if ($ssdp_res_msg !~ m/LOCATION[ :]+(.*)\r/i)
        {
            error("no LOCATION found in SSDP message");
            next;
        }
		
		my $rec = { url => $1 };

		if ((!$include_re || $rec->{url} =~ /$include_re/) &&
		    (!$exclude_re || $rec->{url} !~ /$exclude_re/))
		{
	        display($dbg_ssdp_search+2,2,"DEVICE RESPONSE");
			for my $line (split(/\n/,$ssdp_res_msg))
			{
				$line =~ s/\s*$//g;
				next if ($line eq '');
				display($dbg_ssdp_search+2,3,$line);
				
				# only uuid records have usn: fields!!
				
				if ($line =~ /^st:(.*)$/i)
				{
					my $st = $1;
					$st =~ s/\s//g;
					$rec->{st} = $st;
				}
			}
			display($dbg_ssdp_search,2,"device_reply from '$rec->{url}'");
			display($dbg_ssdp_search,3,"device=$rec->{st}");
	        push @device_replies,$rec;
		}
    }
    close $sock;
	return  \@device_replies;
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
# Debugging
#----------------------------------------------------------------


sub dbg_dump
	# TURN IT ALL ON OR OFF HERE
{
	my ($text,$filename) = @_;
	if (1)
	{
		mkdir "/junk/ssdp_search" if !-d "/junk/ssdp_search";
		$filename =~ s/:|\//./g;
		printVarToFile(1,"/junk/ssdp_search/$filename",$text);
	}
}


sub dbg_dump_xml
{
	my ($xml,$filename) = @_;
	my $text = my_parse_xml($xml);
	dbg_dump($text,$filename);
}



#----------------------------------------------------------------------------
# XML Pretty Printer
#----------------------------------------------------------------------------

sub my_parse_xml
	# pretty print xml that comes in a blahb
{
	my ($data) = @_;
	$data =~ s/\n/ /sg;
	$data =~ s/^\s*//;
	
	my $level = 0;
	my $retval = '';

	while ($data =~ s/^(.*?)<(.*?)>//)
	{
		my $text = $1;
		my $token = $2;
		$retval .= $text if length($text);
		$data =~ s/^\s*//;
		
		my $closure = $token =~ /^\// ? 1 : 0;
		my $self_contained = $token =~ /\/$/ ? 1 : 0;
		my $text_follows = $data =~ /^</ ? 0 : 1;
		$level-- if !$self_contained && $closure;

		$retval .= indent($level) if !length($text);  # if !$closure;
		$retval .= "<".$token.">";
		$retval .= "\n" if !$text_follows || $closure;
		
		$level++ if !$self_contained && !$closure && $token !~ /^.xml/;
	}
	return $retval;
}


sub indent
{
	my ($level) = @_;
	my $txt = '';
	while ($level--) {$txt .= "  ";}
	return $txt;
}




sub dbg_devices
	# using the ssdp_search value
	# for device that match include_re and dont match exclude_re,
	# get the device, and all service descriptions.
{
	my ($ssdp_search,$include_re,$exclude_re) = @_;
	$include_re ||= '';
	$exclude_re ||= '';
	display(0,0,"dbg_devices($ssdp_search,$include_re,$exclude_re)");
	
	my $ua = LWP::UserAgent->new();
	my @dev_list = getUPNPDeviceDescriptionList($ssdp_search,$ua,$include_re,$exclude_re);
	display($dbg_ssdp_search,1,"found ".scalar(@dev_list)." devices");
	
	for my $device_xml (@dev_list)
	{
		my $device = $device_xml->{device};
		my $name = $device->{friendlyName};
		my $device_type = $device->{deviceType};
		$device_type =~ s/^urn://;
		my $display_name = "$device_xml->{ip}:$device_xml->{port}-$device_type";
		display($dbg_ssdp_search,1,"checking device $display_name=$name");
		
		my $service_list = $device->{serviceList};
		my $services = $service_list->{service};
		$services = [$services] if ref($services) !~ /ARRAY/;
		
		for my $service (@$services)
		{
			my $service_type = $service->{serviceType};
			$service_type =~ s/^urn://;
			display($dbg_ssdp_search,1,"found service $service_type");
			getServiceDescriptionFile($ua,$device_xml,$service);
		}
	}
	display(0,0,"dbg_devices() finished");
}
			
			
			
sub dbg_get_and_group_devices
	# group services that share a common description file
	# returns a hash that contains records ...
	#       url
	#       sts (array)
{
	my ($name,$dev_list) = @_;
	display(0,0,"found ".scalar(@$dev_list)." $name devices");

	my %hash;
	for my $device_rec (@$dev_list)
	{
		my $url = $device_rec->{url};
		my $rec = $hash{$url};
		if (!$rec)
		{
			display(0,1,"$name");
			$rec = {url=>$url, sts=>[]};
			$hash{$url} = $rec;
		}
		push @{$rec->{sts}},$device_rec->{st};
		display(0,2,"$device_rec->{st}");
	}
	return \%hash;
}
			
			
sub dbg_compare_devices
{
	my ($name1,$include_re1,$name2,$include_re2) = @_;
	my $ua = LWP::UserAgent->new();
	my $dev_list1 = getUPNPDeviceList('ssdp:all',undef,$include_re1,'');
	my $dev_list2 = getUPNPDeviceList('ssdp:all',undef,$include_re2,'');
	my $dev_hash1 = dbg_get_and_group_devices($name1,$dev_list1);
	my $dev_hash2 = dbg_get_and_group_devices($name2,$dev_list2);
}


#----------------------------------------------------------------
# Static Testing
#----------------------------------------------------------------


if (0)	# obsolete
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



if (1)	# static testing SSDP
{
	my $search_device = 'ssdp:all';
	# my $search_device = 'upnp:rootdevice';
	# my $search_device = 'urn:schemas-upnp-org:device:MediaRenderer:1';
	dbg_devices($search_device,'','');	# 192.168.0.103:8008');
}


if (0)
{
	# compare what I return to what Bubble Returns
	dbg_compare_devices(
		'BubbleUp', '192.168.0.100',
		'Artisan',  '192.168.0.190:8008');
}


if (0)	# static testing DLNA
{
	my $dlna_renderers = getDLNARenderers();
}



1;
