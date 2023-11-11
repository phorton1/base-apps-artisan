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
use artisanUtils;

my $dbg_ssdp = 0;
my $dbg_alive = 0;
	# -1 == wait loop
my $dbg_bye = 1;

my $dbg_listener = 0;
	# -1 includes skipped non-self messages
	# -2 includes wait loop
my $dbg_listener_data = 1;
	# shows bytes read from socket
my $dbg_self = 1;
	# shows self skipped messags
my $dbg_responses = 0;
	# -1 == individual responses

# port and group constants

our $SSDP_PORT = 1900;
our $SSDP_GROUP = '239.255.255.250';

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		$SSDP_PORT
		$DEVICE_TYPE_RENDERER
		$SSDP_GROUP
	);
};





# How long are our SSDP advertisements valid for?
# Spec says a minimum of 1800 seconds (30 minutes)

my $CACHE_MAX_AGE  = 1800;    # $cache_timeout;

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

my $ALIVE_INTERVAL = 900;	# $cache_timeout;


#-----------------------------------------------
# code
#-----------------------------------------------

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

	$this->send_byebye(1);

	my $thread = threads->create(\&SSDPListener, $this);
	$thread->detach();

	$thread = threads->create(\&SSDPAlive, $this);
	$thread->detach();

	return $this;
}




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
}


sub send_byebye
	# Send a number of byebye messages to the multicast
	# 'send' broadcast socket. Sends one message for each
	# of the NTS array: uuid, rootdevice, MediaServer:1, and
	# ContentDirectory:1
{
	my ($this,$amount) = @_;
	$amount ||= 2;

    display($dbg_bye,0,"send_byebye($amount)");

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
		display($dbg_responses,0,"send_response($stparam,MX=$mx) to $destination_ip:$destination_port");
		foreach my $st (@STS)
		{
			sleeper('send_response',$mx);
			display($dbg_responses+1,1,"send_response($st MX=$mx) to $destination_ip:$destination_port");

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

			display($dbg_responses+1,1,"send to $destination_ip:$destination_port rslt=$bytes_queued");
			if ($bytes_queued != length($data))
			{
				warning(0,0,"Could only mcast_send($bytes_queued/".length($data)." bytes to $destination_ip:$destination_port");
			}
		}
	}
}




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

	my $line0 = shift(@lines);
	if ($line0 =~ /(NOTIFY|M-SEARCH)/i)
	{
		$message->{TYPE} =  uc($1);
	}
	else
	{
    	error("parse_ssdp_msg() - Not NOTIFY or M-SEARCH");
		return;
	}

	foreach my $line (@lines)
	{
		last if length($line) == 0;
		my $pos = index($line,":");
		if ($pos >= 0)
		{
			my $lval = substr($line,0,$pos);
			my $rval = substr($line,$pos+1);
			$lval =~ s/-/_/g;
			$rval = "" if !defined($rval);
			$rval =~ s/^\s+//;
			$rval =~ s/\s+$//;

			$message->{uc($lval)} = $rval;
		}
		else
		{
        	error("parse_ssdp_msg() - Unknown line: $line");
			return;
		}
	}

	# some final sanitations

	$message->{ST} ||= '';
	$message->{NTS} ||= '';
	$message->{URN} ||= '';
	$message->{MAN} ||= '';
	$message->{USER_AGENT} ||= '';


	return $message;

}   # parse_ssdp_message()




#---------------------------------------------
# main SSDP message handler
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
        display($dbg_listener+2,0,"waiting for data...");
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
        display($dbg_listener_data,0,"received $dlen bytes from $peer_ip:$peer_port");

		# parse the packet and skip self messges
		# errors already reported in parse_ssdp_message()

		my $message = parse_ssdp_message($data);
		next if !$message;


        #------------------------------------------------
		# Proccess requests
        #------------------------------------------------
		# At the current time WE NEVER GET ANY NOTIFIES from anyone else

		if ($message->{TYPE} eq 'NOTIFY')
        {
			my $nts = $message->{NTS} || '';
			my $usn = $message->{USN} || '';
			my $location = $message->{LOCATION} || '';
			my $action = $nts =~ /ssdp:(.*)/ ? $1 : "";

			display_hash($dbg_listener,0,"NOTIFY($action) from $peer_ip$peer_port",$message);
			error("notify message to $server_ip:$this->{send_port}!!!");

            # If we did receive one we should add the device if not known,
			# or set it to state==NONE if action == bye_bye
        }
	    elsif ($message->{TYPE} eq 'M-SEARCH')
		{
			if ($message->{MAN} eq '"ssdp:discover"')
			{
				if ($message->{ST} eq 'upnp:rootdevice')
				{
					display($dbg_ssdp,0,"M-SEARCH($message->{ST}) from $peer_ip:$peer_port");
					$this->send_responses(
						$peer_ip,
						$peer_port,
						$message->{ST},
						$message->{MX});
				}
				else
				{
				    display($dbg_listener+1,0,"skipping M-SEARCH($message->{ST}) from $peer_ip:$peer_port");
				}
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
		$msg .= "DATE: ".http_date()."\r\n";
		#$msg .= "CONTENT-LENGTH: 0\r\n"; # if 0;
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


1;
