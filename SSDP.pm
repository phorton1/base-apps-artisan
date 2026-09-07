#---------------------------------------
# SSDP.pm
#---------------------------------------
# Advertises this Artisan instance on the LAN as a generic
# UPnP Basic device so that it shows up, with its icon, IP
# address, and a link to the webUI, in things like the
# Windows Explorer Network tab.
#
# Sends NOTIFY alive messages periodically, NOTIFY byebye
# messages when quitting, and answers M-SEARCH requests for
# the things we are.  Nothing else.  We do not search for,
# or keep track of, any other devices.
#
# The device description that the LOCATION header points to
# is served by HTTPServer::ServerDesc().
#
# History: this is the advertising half of the original
# SSDP.pm, which also searched for DLNA libraries and
# renderers and fed them to DeviceManager.  That half was
# removed along with all DLNA support in September 2026.

package SSDP;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(sleep time);
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::Multicast qw(:all);
	# Uses my own _mcast_send() rather than the one in
	# IO::Socket::Multicast because that one did not work
	# on the rPi.  The Multicast socket is only used to
	# receive M-SEARCH requests.
use artisanUtils;


my $dbg_ssdp = 0;
	# lifecycle of the thread
my $dbg_run = 0;
	#  0 == quitting notice and warnings for empty messages
	# -1 == wait loop
my $dbg_msearch = 1;
	#  0 == M-SEARCH messages we respond to
	# -1 == M-SEARCH messages we skip
my $dbg_responses = 1;
	#  0 == general response header
	# -1 == individual responses that are sent
my $dbg_alive = 1;
	#  0 == show a header when alive messages sent
	# -1 == show individual alive messages
my $dbg_bye = 0;
my $dbg_parse = 1;


my $SSDP_PORT = 1900;
my $SSDP_GROUP = '239.255.255.250';
my $MCAST_ADDR = "$SSDP_GROUP:$SSDP_PORT";

my $SHORT_INTERVAL = 3;
	# time between succesive 'short' alive messages at startup
my $CACHE_MAX_AGE  = 1800;
	# How long our advertisements are valid for.
	# Spec says a minimum of 1800 seconds (30 minutes)
my $ALIVE_INTERVAL = 300;
	# How often we send out 'alive' messages.
	# Spec says randomly at not less than 1/2 cache_max_age
my $BETWEEN_MSGS = 0.10;
	# time between sending of individual packets
	# in multi-packet calls. Set to 0 for no delay.

my $running:shared = 0;

sub running  	{ return $running; }


# The things we advertise ourselves as, and respond
# to M-SEARCH requests for.

my $DEVICE_TYPE = 'urn:schemas-upnp-org:device:Basic:1';

my @NTS = (
	"uuid:$this_uuid",
	'upnp:rootdevice',
	$DEVICE_TYPE,
);


#------------------------------------------
# ctor
#------------------------------------------

sub new
{
	my ($class) = @_;
    display($dbg_ssdp,0,"SSDP starting ...");
	my $this = {};
	bless($this, $class);
	my $thread = threads->create(\&run, $this);
	$thread->detach();
	return $this;
}



#---------------------------------------------
# run()
#---------------------------------------------

sub run
{
	my ($this) = @_;

	display($dbg_ssdp,0,"SSDP::run() starting");

	# Sending socket.  Note that no LocalAddr is specified.

	my $send_sock = IO::Socket::INET->new(
			PeerPort  => $SSDP_PORT,
			Proto     => 'udp',
			ReuseAddr => 1);
	if (!$send_sock)
	{
		error("Cannot create send_socket: $@");
		return;
	}
	if (!_mcast_add( $send_sock, $MCAST_ADDR ))
	{
		$send_sock->close();
		return;
	}

    display($dbg_run+1,1,"SSDP::run() opened send socket ");

	# Recieving socket

    my $recv_sock = IO::Socket::Multicast->new(
        Proto => 'udp',
        ReuseAddr => 1,
        LocalPort => $SSDP_PORT,
	);
    if (!$recv_sock)
    {
		$send_sock->close();
        error("Could not create recv_socket ".$!);
        return;
    }
    if (!$recv_sock->mcast_add($SSDP_GROUP))
    {
        $recv_sock->close();
		$send_sock->close();
        error("Could not subscribe to group: $!");
        return;
    }

    display($dbg_run+1,1,"SSDP::run() opened recv socket ");

	my $alive_long = 0;
	my $next_alive = time() + rand($SHORT_INTERVAL);
	$this->send_alive($send_sock);

    #---------------------------------------
    # wait for and process messages
    #---------------------------------------
	# answer M-SEARCH requests while
	# occasionally sending alive messages

	$running = 1;
    while (1)
    {
		if (!$quitting)
		{
			my $any_read = 0;
			my $sel = IO::Select->new( $recv_sock, $send_sock );
			my @can_read = $sel->can_read(0.05);
			for my $sock (@can_read)
			{
				display($dbg_run+1,0,"reading data from $sock...");
				$any_read = 1;

				my $data = '';
				my $peer_addr = $sock->recv($data,1024);
				if (!$peer_addr)
				{
					error("received empty peer_addr".$!);
					next;
				}
				if ($quitting)
				{
					warning($dbg_run,0,"exiting SSDP::run() due to quitting==1");
					return;
				}

				my ($peer_port, $peer_addr2) = sockaddr_in($peer_addr);
				my $peer_ip = inet_ntoa($peer_addr2);
				my $dlen = length($data || '');
				if (!$dlen)
				{
					warning($dbg_run,0,"empty SSDP message from $peer_ip:$peer_port");
					next;
				}
				next if $data =~ /$this_uuid/s;
					# skip our own messages

				# The only messages we care about are M-SEARCH
				# requests for the things we are.  NOTIFY and
				# REPLY messages from other devices are ignored.

				my $message = parse_ssdp_message($data);
				next if $message->{TYPE} ne 'M-SEARCH';
				next if ($message->{MAN} || '') ne '"ssdp:discover"';

				my $st = $message->{ST} || '';
				my $send_reply = $st eq 'ssdp:all' ? 1 : 0;
				for my $type (@NTS)
				{
					if ($type eq $st)
					{
						$send_reply = 1;
						last;
					}
				}

				if ($send_reply)
				{
					display($dbg_msearch,0,"M-SEARCH($st) MX($message->{MX}) from $peer_ip:$peer_port",0,$UTILS_COLOR_LIGHT_GREEN);
					send_responses($this,$sock,$peer_ip,$peer_port,$st);
				}
				else
				{
					display($dbg_msearch+1,0,"skipping M-SEARCH($st) from $peer_ip:$peer_port");
				}

			}	# can_read()

			if (!$any_read && time() > $next_alive)
			{
				$this->send_alive($send_sock);
				$alive_long = !$alive_long;
				$next_alive = $alive_long ?
					time() + ($ALIVE_INTERVAL/2) + rand($ALIVE_INTERVAL/2) :
					time() + ($SHORT_INTERVAL/2) + rand($SHORT_INTERVAL/2);
			}

			sleep(0.10);

		}	# if !$quitting

		elsif ($running)
		{
			display($dbg_ssdp,0,"suspending SSDP thread");
			$this->send_byebye($send_sock);
			$running = 0;
			display($dbg_ssdp,0,"SSDP thread suspended");
		}
		else	# suspended
		{
			sleep(1);
		}

	}	# while 1

	# never gets here
	display($dbg_ssdp,0,"SSDP::run() ended");

}	# run()



#-------------------------------------------------
# Sending Things
#-------------------------------------------------

sub send_alive
{
	my ($this,$sock) = @_;
	display($dbg_alive,0,"send_alive()");
	foreach my $nt (@NTS)
	{
		last if $quitting;
		display($dbg_alive+1,1,"send_alive($nt)");
		my $msg = $this->ssdp_message(1,'send_alive',{
			nt     => $nt,
			nts    => 'alive',
			usn    => generate_usn($nt)	});
		_mcast_send( $sock, $msg, $MCAST_ADDR );
		last if $quitting;
		sleep($BETWEEN_MSGS) if $BETWEEN_MSGS;
	}
}


sub send_byebye
{
	my ($this,$sock) = @_;
    display($dbg_bye,0,"send_byebye()");
	foreach my $nt (@NTS)
	{
		my $msg = $this->ssdp_message(1,'send_byebye',{
			nt     => $nt,
			nts    => 'byebye',
			usn    => generate_usn($nt) });
		_mcast_send( $sock, $msg, $MCAST_ADDR );
		sleep($BETWEEN_MSGS) if $BETWEEN_MSGS;
	}
}


sub send_responses
	# Send responses to a specific client over the socket
	# on which we received the M-SEARCH request.
{
	my ($this,
		$sock,
        $destination_ip,    # client ip address
        $destination_port,  # client original source port
        $stparam) = @_;     # type of thing the client asked for

	# make a list of the things we are that the client asked for

	my @sts = ();
    if ($stparam eq "ssdp:all")
    {
        @sts = @NTS;
    }
    else
    {
        foreach my $nts (@NTS)
        {
            push(@sts, $stparam) if $stparam eq $nts;
        }
    }

	if (@sts)
	{
		display($dbg_responses,0,"send_responses for($stparam) to $destination_ip:$destination_port");
		foreach my $st (@sts)
		{
			display($dbg_responses+1,1,"send_response($st) to $destination_ip:$destination_port");

			my $data = $this->ssdp_message(0,'send_response',{
				nts      => 'alive',
				usn      => generate_usn($st),
				st       => $st });

			if ($quitting)
			{
				warning(0,0,"exiting send_responses() due to quitting=1");
				return;
			}

			my	$bytes = _mcast_send( $sock, $data, "$destination_ip:$destination_port" );
			display($dbg_responses+2,2,"send to $destination_ip:$destination_port rslt=$bytes");
			if ($bytes != length($data))
			{
				warning(0,0,"Could only mcast_send($bytes/".length($data)." bytes to $destination_ip:$destination_port");
			}
			sleep($BETWEEN_MSGS) if $BETWEEN_MSGS;
		}
	}
}



sub ssdp_message
{
	my ($this,$notify,$from,$params) = @_;
	my $alive = $$params{'nts'} eq 'alive';

	my $msg = '';
	my $usn = $params->{usn};

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
		$msg .= "USN: $usn\r\n";
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
	return $nt eq "uuid:$this_uuid" ?
		$nt :
		"uuid:$this_uuid"."::".$nt;
}



#-------------------------------------------------
# my version of IO::Socket::MutiCast
#-------------------------------------------------

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
		return 0;
    }
	return 1;
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
	return $bytes;
}


sub _constant
	# win32 from https://github.com/MicrosoftDocs/SupportArticles-docs/blob/main/support/windows/win32/header-library-requirement-socket-ipproto-ip.md
{
    my ($name) = @_;
    my %names = (
        IP_MULTICAST_TTL  => 0,
        IP_ADD_MEMBERSHIP => 1,
		IP_DROP_MEMBERSHIP => 2,
    );
    my %constants = (
        MSWin32 => [10,12,13],

        cygwin  => [3,5],
        darwin  => [10,12],
        default => [33,35],
    );

    my $index = $names{$name};
    my $ref = $constants{ $^O } || $constants{default};
    return $ref->[ $index ];
}



#----------------------------------------------------------------
# Parse Messages
#----------------------------------------------------------------

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
	#	M-SEARCH * HTTP/1.1
	#	NOTIFY * HTTP/1.1
	#	HTTP/1.1 200 OK
	# and we map the last to "REPLY"

	my $line0 = shift(@lines);

	if ($line0 =~ /(NOTIFY|M-SEARCH)/i)
	{
		$message->{TYPE} =  uc($1);
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



1;	# end of SSDP.pm
