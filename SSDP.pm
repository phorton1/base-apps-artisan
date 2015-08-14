#---------------------------------------
# SSDP.pm
#---------------------------------------
# Note that broadcast SSDP does not work well
# on windows. Artisan is not seen consistently,
# even though I can see M-SEARCH messages from
# the Windows SSDP "Provider", and it ends up
# hiding it from my test_dlna.pm program, and
# possibly from real clients.  It does not show
# up as a Windows Explorer - Network icons, even
# when pressing right-menu Refresh.

# The artisan version shows up if you use right-menu
# Refresh

package SSDP;
use strict;
use warnings;
use threads;
use threads::shared;
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::Multicast;
use Utils;

# port and group constants

my $ssdp_port = 1900;
my $ssdp_group = '239.255.255.250';

# How long are our SSDP advertisements valid for?
# Spec says a minimum of 1800 seconds (30 minutes)

my $cache_max_age  = 1800;    # $cache_timeout;

# How often, do we send out 'alive' messages?
# Spec says we should send them out randomly
# at a rate of not less than 1/2 cache_max_age,
#
# "In addition, the device must re-send its advertisements
# periodically prior to expiration of the duration specified
# in the CACHE-CONTROL header; it is recommended that such
# refreshing of advertisements be done at a randomly-distributed
# interval of less than one-half of the advertisement expiration time,
# so as to provide the opportunity for recovery from lost advertisements
# before the advertisement expires"

my $alive_interval = 900;	# $cache_timeout;


#-----------------------------------------------
# code
#-----------------------------------------------

sub new
{
	my ($class) = @_;

   LOG(0,"SSDP starting ...");

	my $this = ();
	$this->{NTS} = [
		"uuid:$uuid",
		'upnp:rootdevice',
		'urn:schemas-upnp-org:device:MediaServer:1',
		'urn:schemas-upnp-org:service:ContentDirectory:1',
		# Don't advertise that we're a connection manager, since we're not
		# 'urn:schemas-upnp-org:service:ConnectionManager:1',
	];
	$this->{send_socket} = IO::Socket::Multicast->new(
		LocalAddr => $server_ip,
		PeerAddr => $ssdp_group,
		PeerPort => $ssdp_port,
		Proto => 'udp',
		Blocking => 1);
    if (!$this->{send_socket})
    {
        LOG(0,'Cannot bind to SSDP sending socket($server_ip): '.$!.". Trying 127.0.0.1");
		$server_ip = '127.0.0.1';
		$this->{send_socket} = IO::Socket::Multicast->new(
			LocalAddr => $server_ip,
			PeerAddr => $ssdp_group,
			PeerPort => $ssdp_port,
			Proto => 'udp',
			Blocking => 1);
    }
	
	
    if (!$this->{send_socket})
    {
        error('Cannot bind to SSDP sending socket: '.$!);
        return;
    }
    LOG(1,"SSDP started ...");
    $this->{send_socket}->mcast_loopback(0);
	$this->{recv_socket} = undef;
	bless($this, $class);
	return $this;
}



sub start_listening_thread
{
	my ($this) = @_;
	$quitting = 0;
	LOG(0,"start_listening_thread ...");
	my $thread = threads->create(sub {
		$this->receive_messages(); 	} );
	$thread->detach();
}


sub start_alive_messages_thread
{
	my ($this) = @_;
	LOG(0,"start_alive_messages_thread ...");
	my $thread = threads->create( sub {
		$this->send_alive_messages(1); } );
	$thread->detach();
}


sub send_alive_messages
	# called with 2 the first time registering with network
	# and one (1) thereafter for normal 'keep alive' messages
{
	my ($this,$init) = @_;
	appUtils::set_alt_output(1);
	
	while(1)
	{
		$this->send_alive($init ? 2 : 1);
		display($dbg_ssdp+1,0,"sleeping $alive_interval seconds");
		sleeper('send_alive_messages',$alive_interval);
		$init = 0;
	}
}



sub send_byebye
	# Send a number of byebye messages to the multicast
	# 'send' broadcast socket. Sends one message for each
	# of the NTS array: uuid, rootdevice, MediaServer:1, and
	# ContentDirectory:1
{
	my ($this,$amount) = @_;
	$amount ||= 2;
	$quitting = 1;

    display($dbg_ssdp,0,"------> send_byebye($amount)");

	for (1..$amount)
	{
		foreach my $nt (@{$this->{NTS}})
		{
			$this->{send_socket}->send(	$this->ssdp_message(1,'send_byebye',{
                nt     => $nt,
                nts    => 'byebye',
                usn    => generate_usn($nt) }));
		}
		sleeper('send_byebye',3) if ($amount > 1);
	}
}


sub send_alive
	# Send a number of alive messages to the multicast
	# 'send' broadcast socket. Sends one message for each
	# of the NTS array: uuid, rootdevice, MediaServer:1, and
	# ContentDirectory:1
{
	my ($this,$amount) = @_;
	$amount ||= 2;

	if ($quitting)
	{
		warning(0,0,"exiting send_alive() due to quitting=1");
		return;
	}
	display($dbg_ssdp,0,"--------> send_alive($amount)");

	for (1..$amount)
	{
		foreach my $nt (@{$this->{NTS}})
		{
			$this->{send_socket}->send($this->ssdp_message(1,'send_alive',{
                nt     => $nt,
                nts    => 'alive',
                usn    => generate_usn($nt)	}));
		}
		sleeper('send_alive',3) if ($amount > 1);
	}
}



#---------------------------------------------
# pieces of main message (request) handler
#---------------------------------------------

sub send_responses
	# Send a specific response to a specific client
	# over the 'recieve' multicast socket on which we
	# received an M_SEARCH request.  Sends up to
	# one message for each of the NTS array: uuid, rootdevice,
	# MediaServer:1, and ContentDirectory:1, depending on
	# what the client asked for.
{
	my ($this,
        $destination_ip,    # client ip address
        $destination_port,  # client original source port, which gets the destination port for the response of the discover
        $stparam,           # type of service client requested 
        $mx) = @_;          # sleep timer


	# make a list of our services that the client
	# asked for.  I have yet to see a request with
	# ssdp:all ...
	
	my @STS = ();
    if ($stparam eq "ssdp:all")
    {
        @STS = @{$this->{NTS}};
    }
    else
    {
        foreach my $nts (@{$this->{NTS}})
        {
            push(@STS, $stparam) if $stparam eq $nts;
        }
    }

	# Send the specific reponses (for each
	# thing we are) to the client ip:port

	if (@STS)
	{
		display($dbg_ssdp,0,"send_response($stparam MX=$mx) to $destination_ip:$destination_port");
		foreach my $st (@STS)
		{
			sleeper('send_response',$mx);
			display($dbg_ssdp+1,1,"send_response($st MX=$mx) to $destination_ip:$destination_port");
	
			my $data = $this->ssdp_message(0,'send_response',{
				nts      => 'alive',
				usn      => generate_usn($st),
				st       => $st });
			

			# send the response
			
			if ($quitting)
			{
				warning(0,0,"exiting send_responses() due to quitting=1");
				return;
			}
			
			my $bytes_queued = $this->{recv_socket}->mcast_send(
				$data,
				$destination_ip.":".$destination_port);
	
			display($dbg_ssdp+1,1,"send to $destination_ip:$destination_port rslt=$bytes_queued");
			if ($bytes_queued != length($data))
			{
				warning(0,0,"Could only mcast_send($bytes_queued/".length($data)." bytes to $destination_ip:$destination_port");
			}
		}
	}
}




sub parse_ssdp_message
	# only called by 
{
	my ($input_data,$output_data) = @_;
	my @lines = split('\n', $input_data);
	for (my $i = 0; $i < @lines; $i++)
	{
		chomp($lines[$i]);
		$lines[$i] =~ s/\r//g;
		# splice(@lines, $i, 1) if length($lines[$i]) == 0;
	}

	my $line0 = shift(@lines);
	if ($line0 =~ /(NOTIFY|M-SEARCH)/i)
	{
		$$output_data{TYPE}	=  uc($1);
	}
	else
	{
    	error("parse_ssdp_msg() - Not NOTIFY or M-SEARCH");
		return 0;
	}

	foreach my $line (@lines)
	{
		last if length($line) == 0;
		
		if ($line =~ /^([\w\-]+):\s*(.*)$/i)
		{
			$$output_data{uc($1)} = $2;
		}
		else
		{
        	error("parse_ssdp_msg() - Unknown line: $line");
			return 0;
		}
	}

	# some final sanitations

	if (1)
	{
		if (defined($$output_data{USN}))
		{
			my ($a, undef) = split('::', $$output_data{USN});
			$$output_data{USN} = $a;
		}
	
		if (defined($$output_data{'CACHE-CONTROL'}))
		{
			my $time = time();
			$$output_data{'CACHE-CONTROL'} = $1
				if $$output_data{'CACHE-CONTROL'} =~ /^max-age\s*=\s*(\d+)/i;
			$$output_data{'CACHE-CONTROL'} += $time;
		}

	}
	
	# Note that the spec says that a message received without
	# an MX field should be ignored.  
	#
	# "If the search request does not contain an MX header,
	# the device must silently discard and ignore the search request."
	
	if (0 && !defined($$output_data{MX}))
	{
		warning(0,0,"parse_ssdp_msg() - Skipping SSDP message without MX value");
		$$output_data{MX} = 3
		# return;
	}	

	return 1;

}   # parse_ssdp_message()




#---------------------------------------------
# main SSDP message handler
#---------------------------------------------

sub receive_messages
    #---------------------------------------
	# create the listener socket IN THIS THREAD
    #---------------------------------------
	# So, the server is basically working, but one thing bothers me.
	# It currently requires that the android is connected to the router.
	#
	# 1. Artisan/BubbleUp works if the android is connected to the
	#    router, and has a valid ip address, i.e. 192.168.100.103,
	#    and we use that ip for the http/ssdp servers, and artisan
	#    can be "seen" by windows.
	#
	# 2. Artisan/BubbleUp also works if the android is connected
	#    to the router (it has a valid ip address), but we use localhost
	#    127.0.0.1, as the ip for the http/ssdp servers. Of course,
	#    in this case, it cannot be seen in Windows.
	#
	# 3. But if we turn off wifi, or are not connected to the router,
	#    which are two different cases, even if we use 127.0.0.1,
	#    things go awry. BTW, artisan works ok on Windows.
	#
	# 4. First, we get an error trying to subscribe the listener socket,
	#    below, with $! telling us that there is "no such device".
	#    I found something on the net that suggests that I need to
	#    manually enable multicast on the 'lo' device.
	#
	#    From: http://ubuntuforums.org/showthread.php?t=2178191
	#
	#    So, I booted ubuntu, and typed the following:
	#
	#       > ifconfig lo multicast
	#       > route add -net 239.255.255.250 netmask 255.255.255.255 dev lo
	#
	#    which took me a few tries (not sure the netmask is correct), and
	#    not connected, or with Wifi turned off, artisan no longer gets the error,
	#    although bubbleUp still cannot see it.
	#
	# 5. You can see the ifconfig by typing "ifconfig -a", and can see the
	#    routing table by just typing "route".
	#
	#    After the above commands, ifconfig -a shows the 'lo' device with MULTICAST
	#    and a mask of 255.0.0.0.  Note that this change lasts while the machine is running,
	#    and appears to be made to linux/ubuntu regardless of which shell you make the change in.
	#    In ubuntu, the following reverts the system to its previous state:
	#
	#    route del 239.255.255.250
	#    ifconfig lo -multicast
	#
	# 6. Wonder if I need to do this with busybox (no) to the android linux, as well.
	#    ifconfig is different between ubuntu and linux. The same commands in linux
	#
	#       > ip link set lo multicast on"
	#       > ip route add 239.255.255.250/32 dev lo
	#
	#    and to reset
	#
	#       > ip route del 239.255.255.250
	#		> ip link set lo multicast off
	#
	#    FWIW it looks like ubunto and linux are sharing the routing table.
	#    It is one operating system from that perspective ...
	#
	# Funny that the local bubbleup dlna server works ...
	
{
	my ($this) = @_;
	appUtils::set_alt_output(1);

	# Note on parameters for Multicast->new()
	# Here are the original working parameters.
	#
	#    Proto => 'udp',
	#    Blocking => 1,
	#    ReuseAddr => 1,
	#    LocalPort => $ssdp_port,

    my $sock = IO::Socket::Multicast->new(
        Proto => 'udp',
        Blocking => 1,
        ReuseAddr => 1,
        LocalPort => $ssdp_port,

		# Below are some parameters I tried thinking that
		# the localaddr and port must be explicitly specified,
		# and that PeerPort, instead of LocalPort should be set
		# to the SSDP port:
		#		
		#    LocalAddr => $server_ip,
		#    LocalPort => 8092,
		#    PeerPort => $ssdp_port,
		#
		# This did not seem to help, and in fact, just adding
		# the "LocalAddr" line made artisan stop working on andriod,
		# i think, so I am very hestitant to change these params.
	);
	

    if (!$sock)
    {
        error("Could not create socket ".$!);
        return;
    }
    if (!$sock->mcast_add($ssdp_group))
    {
        $sock->close();
        error("Could not subscribe to group: $!");
        return;
    }
    $this->{recv_socket} = $sock;
    display($dbg_ssdp,0,"SSDP receive started ...");

    #---------------------------------------
    # wait for and process messages
    #---------------------------------------
	# get a NOTIFY or M_SEARCH request
	# note use of dbg_disp for debug override
	
    while (1)
    {
        my $data = '';
		my %message = ();

        display($dbg_ssdp+2,0,"waiting for data...");
        my $peer_addr = $sock->recv($data,1024);
        if (!$peer_addr)
        {
            error("received empty peer_addr".$!);
            next;
        }
		if ($quitting)
		{
			warning(0,0,"exiting receive_messages() due to quitting=1");
			return;
		}

		my ($peer_src_port, $peer_addr2) = sockaddr_in($peer_addr);
		my $peer_ip_addr = inet_ntoa($peer_addr2);
        my $dlen = length($data || '');

        # log_request('SSDP',$peer_ip_addr,$peer_src_port,$data);

		if (!parse_ssdp_message($data, \%message))
		{
			# errors already reported in parse_ssdp_message()
			# error("Unable to parse SSDP message from client($peer_ip_addr)");
			next;
		}
		if ($message{TYPE} eq 'NOTIFY' &&
			$message{USN} &&
			$message{USN} =~ $uuid)
		{
			display($dbg_ssdp+2,0,"Skipping SSDP NOTIFY message from self");
			next;
		}
		
		# a little personal debugging
		
        display($dbg_ssdp+1,0,"received $dlen bytes from $peer_ip_addr:$peer_src_port");
		
        #------------------------------------------------
		# Proccess requests
        #------------------------------------------------
		# Note that we do nothing with NOTIFY messages
		# at the current timeas WE NEVER GET ANY (except our own)
		
		if ($message{TYPE} eq 'NOTIFY')
        {
            display($dbg_ssdp,0,"NOTIFY  message from $peer_ip_addr:$peer_src_port");
			for my $k (sort(keys(%message)))
			{
				display($dbg_ssdp+1,1,"$k=$message{$k}");
			}

            # NTS == ssdp:byebye ||
			# update the device database
			# update_device($peer_ip_addr,$peer_src_port,\%message);
        }
	    elsif ($message{TYPE} eq 'M-SEARCH')
		{
            display($dbg_ssdp,0,"M-SEARCH message from $peer_ip_addr:$peer_src_port");
			for my $k (sort(keys(%message)))
			{
				display($dbg_ssdp+1,1,"$k=$message{$k}");
			}
			if (defined($message{MAN}) &&
                $message{MAN} eq '"ssdp:discover"')
			{
				display($dbg_ssdp+1,1,"processing M-SEARCH message $message{MAN}");
				$this->send_responses(
                    $peer_ip_addr,
                    $peer_src_port,
                    $message{ST},
                    $message{MX});
			}
			else
			{
				warning(0,0,"skipping non 'ssdp:discover' M-SEARCH message");
			}
        }
		$this->{debug_this} = 0;

    }	# for each message (request)
}	# receive messages



#-----------------------------------
# utilities
#-----------------------------------
# note that in the original pdlna source, the
# usn was $uuid:$NTS for everything except the
# uuid itself (which was uuid:$uuid). but that
# didn't work, particularly with the WDTV live.
# I disoverered that always using uuid:$uuid
# (empirically from other servers) made it go

my $USE_OLD_PDLNA_USN = 1;


sub ssdp_message
{
	my ($this,$notify,$from,$params) = @_;
	my $alive = $$params{'nts'} eq 'alive';

	my $msg = '';
	my $usn = $USE_OLD_PDLNA_USN ?
		$$params{usn} :
		"uuid:$uuid\r\n";
	
	if ($notify)
	{
		$msg = "NOTIFY * HTTP/1.1\r\n";
		$msg .= "HOST: $ssdp_group:$ssdp_port\r\n";
		if ($alive)
		{
			$msg .= "CACHE-CONTROL: max-age=$cache_max_age\r\n";
			$msg .= "LOCATION: http://$server_ip:$server_port/ServerDesc.xml\r\n";
		}
		$msg .= "NT: $$params{nt}\r\n";
		$msg .= "NTS: ssdp:$$params{nts}\r\n";
		$msg .= "SERVER: Windows 8.1 UPnP/1.0 $program_name\r\n"
			if $alive;
		$msg .= "USN: $usn\r\n";
		$msg .= "\r\n";
	}
	else
	{
		$msg = "HTTP/1.1 200 OK\r\n";
		$msg .= "CACHE-CONTROL: max-age=$cache_max_age\r\n";
		$msg .= "LOCATION: http://$server_ip:$server_port/ServerDesc.xml\r\n";
		$msg .= "SERVER: prhOS UPnP/1.0 $program_name\r\n";

		$msg .= "EXT:\r\n";
		$msg .= "ST: $$params{st}\r\n";
		$msg .= "USN: $usn\r\n";	# $$params{usn}\r\n";
		$msg .= "DATE: ".http_date()."\r\n";
		#$msg .= "CONTENT-LENGTH: 0\r\n"; # if 0;
		$msg .= "\r\n";
		
		# debugging ... break the response into lines and display it
	
	}	
		display($dbg_ssdp+1,0,"ssdp_message($from)");	
		for my $line (split(/\r\n/,$msg))
		{
			display($dbg_ssdp+2,1,"$line");
		}
		
	return $msg;
}


sub generate_usn
{
	my ($nt) = @_;
	my $usn = '';
	if ($nt eq $uuid)
	{
		$usn = "uuid:".$uuid;
	}
	else
	{
		$usn .= $uuid."::".$nt;
	}
	return $usn;
}


sub sleeper
{
	my ($what,$interval) = @_;
	if (!defined($interval))
	{
		error("sleeper interval not defined!");
		$interval = 3 ;
		return;
	}

	$interval -= 1;
	$interval = 0 if ($interval<0);
	
	if (1)
	{
		my $int = int(rand($interval));
		display($dbg_ssdp+1,0,"$what sleeping $int seconds");
		sleep($int);
	}
	else	# non random for debugging
	{
		display($dbg_ssdp+1,0,"$what sleeping $interval seconds");
		sleep($interval);
	}
}


1;
