#---------------------------------------
# SSDP.pm
#---------------------------------------
# Note that being an SSDP device does not work well on Windows.
# Artisan is consistently seen in Windows Explorer, as it gets
# searhed for by the Windows SSDP "Provider", but is not generally
# visible (i.e. to Artisan Android) on the network.
#
# This is irregardless of whether we send out Alive messages or not

package SSDP;
use strict;
use warnings;
use threads;
use threads::shared;
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::Multicast;
use LWP::UserAgent;
use artisanUtils;
use Device;
use DeviceManager;


my $dbg_ssdp = 0;
	# lifecycle of main object and threads
my $dbg_self = 1;
	# show self skippe dmessages in SSDPListener and SSDPSearch

# SSDPAlive

my $dbg_alive = 1;
	# -1 == wait loop
my $dbg_bye = 1;


# SSDPListener

my $dbg_listener = 0;
	#  0 == quitting notice and warnings for empty messages
	# -1 == wait loop
my $dbg_msearch = 0;
	#  0 == M-SEARCH messages received
	# -1 == M-SEARCH messages skipped
my $dbg_responses = 1;
	#  0 == general response header
	# -1 == individual responses that are sent

# SSDPSearch

my $dbg_search = 0;
	#  0 == (cyan) header when starting search
	# -1 == creating socket and sending message notifications
my $show_search_dbg = 0x110;
	# bitwise, high order nibble is New Devices,
	# middle is Known Devices, and last is all msgs.
	# 0=off, 1=line, 2=hash


#==================================================================================
# Main SSDP Server
#==================================================================================
# Is both thread listening for external M_SEARCH and M_NOTIFY messages,
# and sends out KEEP_ALIVE messages.

my $SSDP_PORT = 1900;
my $SSDP_GROUP = '239.255.255.250';


my $CACHE_MAX_AGE  = 1800;
	# How long are our SSDP advertisements valid for?
	# Spec says a minimum of 1800 seconds (30 minutes)
	# but I have seen as low as 176.
my $ALIVE_INTERVAL = 900;	# $cache_timeout;
	# How often, do we send out 'alive' messages?
	# Spec says we should send them out randomly
	# at a rate of not less than 1/2 cache_max_age,
my $SSDPSEARCH_INTERVAL = 20;
	# Interval between ssdp searches
my $SSDPSEARCH_TIME = 4;
	# How long to perform the search for


sub new
{
	my ($class) = @_;

    display($dbg_ssdp,0,"SSDP starting ...");

	my $this = ();
	$this->{NTS} = [
		"uuid:$this_uuid",
		'upnp:rootdevice',
		'urn:schemas-upnp-org:device:MediaServer:1',
		'urn:schemas-upnp-org:service:ContentDirectory:1',
		# Don't advertise that we're a connection manager, since we're not
		# 'urn:schemas-upnp-org:service:ConnectionManager:1',
	];
	my $sock = IO::Socket::Multicast->new(
		LocalAddr => $server_ip,
		PeerAddr => $SSDP_GROUP,
		PeerPort => $SSDP_PORT,
		Proto => 'udp',
		Blocking => 1);
    if (!$sock)
    {
        LOG(0,'Cannot bind to SSDP sending socket($server_ip): '.$!.". Trying 127.0.0.1");
		$sock = IO::Socket::Multicast->new(
			LocalAddr => '127.0.0.1',
			PeerAddr => $SSDP_GROUP,
			PeerPort => $SSDP_PORT,
			Proto => 'udp',
			Blocking => 1);
    }
    if (!$sock)
    {
        error('Cannot bind to SSDP sending socket: '.$!);
        return;
    }
    $sock->mcast_loopback(0);
	my $got_port = $sock->sockport();

    display($dbg_ssdp,0,"SSDP started on $server_ip:$got_port");
	$this->{send_socket} = $sock;
	$this->{send_port} = $got_port;
	$this->{recv_socket} = undef;
	bless($this, $class);

	my $thread = threads->create(\&SSDPListener, $this);
	$thread->detach();

	$thread = threads->create(\&SSDPAlive, $this);
	$thread->detach();

	$thread = threads->create(\&SSDPSearch, $this);
	$thread->detach();

	return $this;
}



#-------------------------------------------------
# SSDPAlive
#-------------------------------------------------

sub SSDPAlive
	# calls twice the first time registering with network
	# and once thereafter for normal 'keep alive' messages
{
	my ($this) = @_;
	my $inited = 0;
	display($dbg_ssdp,0,"SSDPAlive() thread running");
	while(1)
	{
		if ($quitting)
		{
			warning(0,0,"exiting SSDPAlive() due to quitting==1");
			last;
		}
		$this->send_alive($inited ? 1 : 2);
		display($dbg_alive+1,0,"sleeping $ALIVE_INTERVAL seconds");
		sleeper('send_alive_messages',$ALIVE_INTERVAL);
		$inited = 1;
	}
	display($dbg_ssdp,0,"SSDPAlive() thread ended");
	$this->send_byebye();
}



sub send_byebye
	# sends out 2 byebyes
{
	my ($this) = @_;
    display($dbg_bye,0,"send_byebye()");
	for (1..2)
	{
		foreach my $nt (@{$this->{NTS}})
		{
			$this->{send_socket}->send(	$this->ssdp_message(1,'send_byebye',{
				nt     => $nt,
				nts    => 'byebye',
				usn    => generate_usn($nt) }));
		}
		sleeper('send_byebye',3);
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
		warning(0,0,"exiting send_alive() due to quitting==1");
		return;
	}
	display($dbg_alive,0,"send_alive($amount)");

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
# SSDPListener
#---------------------------------------------

sub SSDPListener
{
	my ($this) = @_;

	display($dbg_ssdp,0,"SSDPListener() starting");

    my $sock = IO::Socket::Multicast->new(
        Proto => 'udp',
        Blocking => 1,
        ReuseAddr => 1,
        LocalPort => $SSDP_PORT,
	);

    if (!$sock)
    {
        error("Could not create socket ".$!);
        return;
    }
    if (!$sock->mcast_add($SSDP_GROUP))
    {
        $sock->close();
        error("Could not subscribe to group: $!");
        return;
    }

    $this->{recv_socket} = $sock;
    display($dbg_ssdp,0,"SSDPListener() running");

    #---------------------------------------
    # wait for and process messages
    #---------------------------------------
	# get a NOTIFY or M_SEARCH request

    while (1)
    {
		# receive next packet

        my $data = '';
        display($dbg_listener+1,0,"waiting for data...");
        my $peer_addr = $sock->recv($data,1024);
        if (!$peer_addr)
        {
            error("received empty peer_addr".$!);
            next;
        }
		if ($quitting)
		{
			warning($dbg_listener,0,"exiting SSDPListener() due to quitting==1");
			return;
		}

		# read packet data

		my ($peer_port, $peer_addr2) = sockaddr_in($peer_addr);
		my $peer_ip = inet_ntoa($peer_addr2);
        my $dlen = length($data || '');
		if (!$dlen)
		{
			warning($dbg_listener,0,"empty SSDP message from  from $peer_ip$peer_port");
			next;
		}
		if ($data =~ /$this_uuid/s)
		{
			display($dbg_self,0,"Skipping message from self\n".$data);
			next;
		}

        #------------------------------------------------
		# Proccess requests
        #------------------------------------------------
		# We are currently only responding to ssdp:discover upnp:rootdevice M-SEARCH requests

		my $message = parse_ssdp_message($data,$peer_ip,$peer_port);
		if ($message->{TYPE} eq 'NO_TYPE' || $message->{TYPE} eq 'NOTIFY')
        {
			processExternalMessage("LISTEN",$message,$peer_ip,$peer_port);
        }
	    elsif ($message->{TYPE} eq 'M-SEARCH')
		{
			if ($message->{MAN} eq '"ssdp:discover"')
			{
				if (!$message->{USER_AGENT} || $message->{USER_AGENT} ne 'Artisan')
				{
					# We only respond to certain ST's (our NTS)

					my $send_reply = 0;
					for my $type (@{$this->{NTS}})
					{
						if ($type eq $message->{ST})
						{
							$send_reply = 1;
							last;
						}
					}

					if ($send_reply)
					{
						display($dbg_msearch,0,"M-SEARCH($message->{ST}) from $peer_ip:$peer_port",0,$Pub::Utils::win_color_light_green);
						$this->send_responses(
							$peer_ip,
							$peer_port,
							$message->{ST},
							$message->{MX});
					}
					else
					{
						display($dbg_msearch+1,0,"skipping M-SEARCH($message->{ST}) from $peer_ip:$peer_port");
					}

				}	# M-SEARCH from myself
			}
			else
			{
				display_hash(0,0,"skipping non 'ssdp:discover' M-SEARCH message",$message);
				error("non ssdp:discover message");
			}
        }
		$this->{debug_this} = 0;

    }	# for each message (request)
}	# SSDPListener()



sub send_responses
	# Send responses to a specific client over the 'recieve'
	# multicast socket on which we received an M_SEARCH request.
{
	my ($this,
        $destination_ip,    # client ip address
        $destination_port,  # client original source port, which gets the destination port for the response of the discover
        $stparam,           # type of service client requested
        $mx) = @_;          # sleep timer

	# make a list of our services that the client asked for

	my @sts = ();
    if ($stparam eq "ssdp:all")
    {
        @sts = @{$this->{NTS}};
    }
    else
    {
        foreach my $nts (@{$this->{NTS}})
        {
            push(@sts, $stparam) if $stparam eq $nts;
        }
    }

	# Send the specific reponses (for each
	# thing we are) to the client ip:port

	if (@sts)
	{
		display($dbg_responses,0,"send_response($stparam,MX=$mx) to $destination_ip:$destination_port");
		foreach my $st (@sts)
		{
			sleeper('send_response',$mx);
			display($dbg_responses+1,1,"send_response($st MX=$mx) to $destination_ip:$destination_port");

			my $data = $this->ssdp_message(0,'send_response',{
				nts      => 'alive',
				usn      => generate_usn($st),
				st       => $st });

			if ($quitting)
			{
				warning(0,0,"exiting send_responses() due to quitting=1");
				return;
			}

			my $bytes = $this->{recv_socket}->mcast_send(
				$data,
				$destination_ip.":".$destination_port);

			display($dbg_responses+1,1,"send to $destination_ip:$destination_port rslt=$bytes");
			if ($bytes != length($data))
			{
				warning(0,0,"Could only mcast_send($bytes/".length($data)." bytes to $destination_ip:$destination_port");
			}
		}
	}
}



#--------------------------------------------------
# Utilities common to SSDPAlive and SSDPListener
#--------------------------------------------------

my $USE_OLD_PDLNA_USN = 1;


sub ssdp_message
{
	my ($this,$notify,$from,$params) = @_;
	my $alive = $$params{'nts'} eq 'alive';

	my $msg = '';
	my $usn = $USE_OLD_PDLNA_USN ?
		$$params{usn} :
		"uuid:$this_uuid\r\n";

	if ($notify)
	{
		$msg = "NOTIFY * HTTP/1.1\r\n";
		$msg .= "HOST: $SSDP_GROUP:$SSDP_PORT\r\n";
		if ($alive)
		{
			$msg .= "CACHE-CONTROL: max-age=$CACHE_MAX_AGE\r\n";
			$msg .= "LOCATION: http://$server_ip:$server_port/ServerDesc.xml\r\n";
		}
		$msg .= "NT: $$params{nt}\r\n";
		$msg .= "NTS: ssdp:$$params{nts}\r\n";
		$msg .= "SERVER: UPnP/1.0 $program_name\r\n"
			if $alive;
		$msg .= "USN: $usn\r\n";
		$msg .= "\r\n";
	}
	else
	{
		$msg = "HTTP/1.1 200 OK\r\n";
		$msg .= "CACHE-CONTROL: max-age=$CACHE_MAX_AGE\r\n";
		$msg .= "LOCATION: http://$server_ip:$server_port/ServerDesc.xml\r\n";
		$msg .= "SERVER: UPnP/1.0 $program_name\r\n";

		$msg .= "EXT:\r\n";
		$msg .= "ST: $$params{st}\r\n";
		$msg .= "USN: $usn\r\n";	# $$params{usn}\r\n";

		# IF the date is required, gmtime() may work,
		# and all http_date() did was add " GMT" to that.
		# $msg .= "DATE: ".gmtime()."\r\n";
		# $msg .= "DATE: ".http_date()."\r\n";

		# $msg .= "CONTENT-LENGTH: 0\r\n"; # if 0;

		$msg .= "\r\n";
	}

	# debugging ... break the response into lines and display it
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
	if ($nt eq $this_uuid)
	{
		$usn = "uuid:".$this_uuid;
	}
	else
	{
		$usn .= "uuid:".$this_uuid."::".$nt;
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



#==================================================================================
# SSDPSearch
#==================================================================================
# Is a thread that does an SSDP Search every so often.

sub SSDPSearch
{
	sleep(2);
	display($dbg_ssdp,0,"SSDPSearch thread started");
	while (1)
	{
		ssdp_search();
		sleep($SSDPSEARCH_INTERVAL);
	}
}


sub ssdp_search
{
	my $search_device = 'ssdp:all';
		# interesting values are
		# ssdp:all (find everything)
		# upnp:rootdevice (find root devices)
		# urn:schemas-upnp-org:device:MediaServer:1 (DLNA Renderers)
		# urn:schemas-upnp-org:device:MediaRenderer:1 (DLNA Renderers)

	my $ua = LWP::UserAgent->new();

    #------------------------------------------------
    # send the broadcast message
    #------------------------------------------------

    my $mcast_addr = $SSDP_GROUP . ':' . $SSDP_PORT;
    my $ssdp_header = <<"SSDP_SEARCH_MSG";
M-SEARCH * HTTP/1.1
HOST: $mcast_addr
MAN: "ssdp:discover"
ST: $search_device
MX: $SSDPSEARCH_TIME
USER-AGENT: Artisan

SSDP_SEARCH_MSG

    $ssdp_header =~ s/\r//g;
    $ssdp_header =~ s/\n/\r\n/g;

    display($dbg_search+1,0,"ssdp_search() creating socket");

    my $sock = IO::Socket::INET->new(
        LocalAddr => $server_ip,
        # LocalPort => 8679,
        PeerPort  => $SSDP_PORT,
        Proto     => 'udp',
        ReuseAddr => 1);
    if (!$sock)
    {
        error("Cannot create socket to send multicast $@");
        return;
    }

	my $dbg_port = $sock->sockport();
    display($dbg_search,0,"ssdp_search() port=$dbg_port",0,$Pub::Utils::win_color_cyan);

    # add the socket to the correct IGMP multicast group
    # and actually send the message.

    _mcast_add( $sock, $mcast_addr );
    display($dbg_search+1,1,"sending broadcast message");
    _mcast_send( $sock, $ssdp_header, $mcast_addr );

    # loop getting replies and passing them to
	# processExternalMessage();

    my $sel = IO::Select->new($sock);
    while ( $sel->can_read( $SSDPSEARCH_TIME + 1) )
    {
        my $data;
        recv ($sock, $data, 4096, 0);
		if ($data =~ /$this_uuid/s)
		{
			display($dbg_self,0,"Skipping message from self\n".$data);
			next;
		}
		my $message = parse_ssdp_message($data);
		processExternalMessage("SEARCH",$message);
    }
    close $sock;
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
# Parse is common to both SSDPListener and SSDPSearch
#----------------------------------------------------------------

my $dbg_parse = 1;

sub parse_ssdp_message
{
	my ($data) = @_;
	my $message = {};
	my @lines = split(/\n/, $data);
	for (my $i = 0; $i < @lines; $i++)
	{
		chomp($lines[$i]);
		$lines[$i] =~ s/\r//g;
	}

	# line0 will be
	#	M-SEARCH * HTTP/1.1 - from LISTEN
	#	NOTIFY * HTTP/1.1   - from LISTEN
	#	HTTP/1.1 200 OK     - from SEARCH
	# and we map the last to "REPLY"

	my $line0 = shift(@lines);

	if ($line0 =~ /(NOTIFY|M-SEARCH)/i)
	{
		$message->{TYPE}	=  uc($1);
	}
	else
	{
    	$message->{TYPE} = 'REPLY';
	}

	display($dbg_parse,0,"ssdp_message($message->{TYPE})");

	# the rest of the message *should* be colon delimited values

	foreach my $line (@lines)
	{
		last if length($line) == 0;
		my $pos = index($line,":");
		if ($pos >= 0)
		{
			my $lval = uc(substr($line,0,$pos));
			my $rval = substr($line,$pos+1);
			$lval =~ s/^\s+|\s+$//g;
			$lval =~ s/-/_/g;
			$rval = "" if !defined($rval);
			$rval =~ s/^\s+|\s+$//g;
			$rval =~ s/\s+$//;

			display($dbg_parse+1,1,"$lval = '$rval'");
			$message->{$lval} = $rval;
		}
		else
		{
        	error("parse_ssdp_msg() - Unknown line: $line");
		}
	}

	return $message;

}   # parse_ssdp_message()



#=============================================================
# Process external SSDP message
#=============================================================
# This is essentially a filtration step for all incoming external
# SSDP devices before we create our Artican Devices from the messages,
# at which point we will use the LOCATION member to get more info.

sub processExternalMessage
	# $caller will either be NOTIFY if from SSDPListener
	# or SEARCH if from SSDPSearch. $message is a parsed
	# ssdp_message
{
	my ($caller,$message,$ip,$port) = @_;
	$ip ||= '';
	$port ||= '';
	my $from_addr = $ip ? "$ip:$port" : '';

	my $usn = $message->{USN} || '';
	my $nts = $message->{NTS} || '';

	# all messages will contain a uuid: in the USN
	# we are only interested in certain upnp device types
	# and mildly interested in the alive state (alive | byebye)

	my $uuid  = $usn =~ /uuid:(.*?)(:|$)/ ? $1 : '';
	my $type  = $usn =~ /:device:(.*)$/   ? $1 : '';
	my $state = $nts =~ /^ssdp:(.*)$/     ? $1 : '';

	# prettify for debugging

	$usn =~ s/^.*?(::|$)//;
	$usn =~ s/^urn://;
	$usn =~ s/^schemas-upnp-org://;

    my $deviceType =
		$type eq 'MediaServer:1' ? $DEVICE_TYPE_LIBRARY :
		$type eq 'MediaRenderer:1' ? $DEVICE_TYPE_RENDERER : '';

	my $mask = 1;
	$mask |= $deviceType ? 0x10 : 0;
	$mask |= $deviceType && !findDevice($deviceType,$uuid) ? 0x100 : 0;

	my $show_hash = ($mask << 1) & $show_search_dbg;
	my $show_line = $show_hash || ($mask & $show_search_dbg);

	# printf "show_dbg(%03X) mask(%03X) show_hash(%03X) show_line(%03X)\n",$show_dbg,$mask,$show_hash,$show_line;
	my $dbg_msg = sprintf "SSDP(%03X) ".pad($uuid,35)." ".pad($state,14)." ".pad($usn,50)." from $caller $from_addr",$mask;
	display(0,-1,$dbg_msg) if $show_line;
	display_hash(0,-1,$dbg_msg,$message) if $show_hash;

	DeviceManager::updateDevice($deviceType,$uuid,$state,$message)
		if ($deviceType)
}



1;
