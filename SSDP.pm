#---------------------------------------
# SSDP.pm
#---------------------------------------

package SSDP;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(sleep time);
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::Multicast qw(:all);
	# Uses my own multicase implementation _mcast_send(). first
	# because I could not figure out how to do bi-directional
	# communications with the base IO::Socket::Multicast socket
	# as needed for M-SEARCH. IO::Socket::Multicase ONLY sends
	# or receives, but for M-SEARCH you need both!  Then
	# additionally because IO::SocketMulticast::mcast_send()
	# did not work on the rPi.
use Pub::Prefs;
use artisanUtils;
use DeviceManager;

our $DEBUG_SSDP_ALONE = 0;
	# If set Alive and M-SEARCH messages will NOT be sent out
	# by timer.  Artisan *may* also use this to not initialize
	# database, etc, to make it faster to boot and test SSDP.


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw ( $DEBUG_SSDP_ALONE );
}



my $dbg_ssdp = 0;
	# lifecycle of main object and threads
my $dbg_run = 0; # 0;
	#  0 == quitting notice and warnings for empty messages
	# -1 == wait loop
my $dbg_msearch = 1;  # 0;
	#  0 == M-SEARCH messages received
	# -1 == M-SEARCH messages skipped
my $dbg_responses = 1;
	#  0 == general response header
	# -1 == individual responses that are sent
my $dbg_search = 1;
	# 0 = show a header when search message sent
my $dbg_alive = 1;
	# 0 = show a header when alive messages sent
	# -1 = show individual alive messages
my $dbg_bye = 0;
my $dbg_self = 1;
	# show self skipped dmessages in SSDPListener and SSDPSearch


# Message Debugging

my $show_search_dbg = 0x100;	# 0x110;
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
my $MCAST_ADDR = "$SSDP_GROUP:$SSDP_PORT";


my $SHORT_INTERVAL = 3;
	# time between succesive 'short' alive messages

my $CACHE_MAX_AGE  = 1800;
	# How long are our SSDP advertisements valid for?
	# Spec says a minimum of 1800 seconds (30 minutes)
	# but I have seen as low as 176.
my $ALIVE_INTERVAL = 300;
	# How often, do we send out 'alive' messages?
	# Spec says we should send them out randomly
	# at a rate of not less than 1/2 cache_max_age,
my $SSDPSEARCH_INTERVAL = 60;
	# Interval between ssdp searches
my $SSDPSEARCH_TIME = 4;
	# How long to perform the search for
my $BETWEEN_MSGS = 0.10;
	# time between sending of individual packets
	# in multi-packet calls. Set to 0 for no delay.

my $running:shared = 0;
my $send_alive:shared = 0;
my $send_search:shared = 0;


sub running  	{ return $running; }
sub doAlive		{ $send_alive = 1; }
sub doSearch	{ $send_search = 1; }




#------------------------------------------
# ctor
#------------------------------------------

sub new
{
	my ($class,$params) = @_;

	$params ||= {};
	getObjectPref($params,'SSDP_FIND_ARTISAN_LIBRARIES',1);
	getObjectPref($params,'SSDP_FIND_OTHER_LIBRARIES',0);
	getObjectPref($params,'SSDP_FIND_RENDERERS',0);

    display_hash($dbg_ssdp,0,"SSDP starting ...",$params);

	my $this = $params;
	$this->{NTS} = [
		"uuid:$this_uuid",
		'upnp:rootdevice',
		'urn:schemas-upnp-org:device:MediaServer:1',
		'urn:schemas-upnp-org:service:ContentDirectory:1',
		# Don't advertise that we're a connection manager, since we're not
		# 'urn:schemas-upnp-org:service:ConnectionManager:1',
	];

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

	#-----------------------------------
	# Sending socket
	#-----------------------------------
	# Really struggled with this.
	#
	# (a) I need to use my own _multicast messages to get bi-directional socket
	#     as needed for M-SEARCH, which is not supported in IO::Socket:::Multicast
	#     as far as I could determine.
	# (b) to get response from both local and remote WMP I need to specify no
	#     LocalAddr (or 0.0.0.0) and send out TWO M-SEARCH messages as below.
	#
	# Note that $send_port is undef if 0.0.0.0 or no LocalAddr is specified
	# in $USE_MY_MULTICAST ctor
	#
	#	my $send_port = $send_sock->sockport() || 0;
	#
	# returns 'undef'

	my $send_sock = IO::Socket::INET->new(
			# LocalAddr => $server_ip,
			# LocalAddr => '127.0.0.1',
			# LocalAddr => '0.0.0.0',
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


	#-----------------------------------
	# Recieving Socket
	#-----------------------------------

    my $recv_sock = IO::Socket::Multicast->new(
        Proto => 'udp',
        # Blocking => 1,
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

	my $next_search = 0;
	my $alive_long = 0;
	my $next_alive = time() + rand($SHORT_INTERVAL);
	$this->send_alive($send_sock);

    #---------------------------------------
    # wait for and process messages
    #---------------------------------------
	# get NOTIFY or M_SEARCH requests or
	# HTTP search REPLY messaeges while
	# occasionally sending alive/search

	$running = 1;
    while (1)
    {
		if (!$quitting)
		{
			# receive next packet

			my $any_read = 0;
			my $sel = IO::Select->new( $recv_sock, $send_sock );
			my @can_read = $sel->can_read(0.05);
			for my $sock (@can_read)	# if ($sel->can_read(0.05))
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
					warning($dbg_run,0,"exiting SSDPListener() due to quitting==1");
					return;
				}

				# read packet data

				my ($peer_port, $peer_addr2) = sockaddr_in($peer_addr);
				my $peer_ip = inet_ntoa($peer_addr2);
				my $dlen = length($data || '');
				if (!$dlen)
				{
					warning($dbg_run,0,"empty SSDP message from  from $peer_ip$peer_port");
					next;
				}
				if ($data =~ /$this_uuid/s)
				{
					display($dbg_self,0,"Skipping message from self based on uuid");
					next;
				}

				#------------------------------------------------
				# Proccess receieved data
				#------------------------------------------------

				my $message = parse_ssdp_message($data,$peer_ip,$peer_port);
				if ($message->{TYPE} eq 'REPLY' || $message->{TYPE} eq 'NOTIFY')
				{
					$this->processExternalMessage($message->{TYPE},$message,$peer_ip,$peer_port);
				}
				elsif ($message->{TYPE} eq 'M-SEARCH')
				{
					if ($message->{MAN} eq '"ssdp:discover"')
					{
						if (($peer_ip eq $server_ip ||
							 $peer_ip eq '127.0.0,1') &&
							$message->{USER_AGENT} &&
							$message->{USER_AGENT} =~ /Artisan/)
						{
							display($dbg_self,0,"Skipping M-SEARCH message from self based on peer_ip($peer_ip)==$server_ip and user_agent($message->{USER_AGENT})");
							next;
						}

						# We only respond to certain ST's (our NTS)

						my $send_reply = $message->{ST} eq 'ssdp:all' ? 1 : 0;
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
							display($dbg_msearch,0,"M-SEARCH($message->{ST}) MX($message->{MX}) from $peer_ip:$peer_port",0,$UTILS_COLOR_LIGHT_GREEN);

							# regarding rPi returning undef $bytes from $recv_sock->mcast_send
							# 	in send_responses()
							# this is the only call to send_responses.
							# Note that we have an actual $sock that we just read from.
							# Maybe if we just call send on that instead of trying to use
							# mcast_send?

							send_responses($this,
								$sock,	# testing
								# $recv_sock,	# working
								$peer_ip,
								$peer_port,
								$message->{ST},
								$message->{MX});
						}
						else
						{
							display($dbg_msearch+1,0,"skipping M-SEARCH($message->{ST}) from $peer_ip:$peer_port");
						}
					}
					else
					{
						display_hash(0,0,"skipping non 'ssdp:discover' M-SEARCH message",$message);
						error("non ssdp:discover message");
					}
				}
				else
				{
					warning(0,0,"Unexpected Message TYPE: $data");
				}

			}	# can_read()

			if (!$any_read)
			{
				if ($send_alive || (!$DEBUG_SSDP_ALONE && (time() > $next_alive)))
				{
					$send_alive = 0;
					$this->send_alive($send_sock);
					$alive_long = !$alive_long;
					$next_alive = $alive_long ?
						time() + ($ALIVE_INTERVAL/2) + rand($ALIVE_INTERVAL/2) :
						time() + ($SHORT_INTERVAL/2) + rand($SHORT_INTERVAL/2);
				}

				elsif ($send_search || (!$DEBUG_SSDP_ALONE &&  (time() > $next_search)))
				{
					DeviceManager::invalidateOldDevices();
						# check for invalid (timed out) devices on every search

					$send_search = 0;
					display($dbg_search,0,"sendSearch()",0,$UTILS_COLOR_LIGHT_CYAN);
					my $msg = search_msg();

					# OK, weirdness, to get WMP on THIS machine to respond, I
					# have to use 0.0.0.0 or no LocalAddr and send out a 2nd
					# message specifically to 127.0.0.1  !?!?!
					#
					# There's some kind of a loopback option I'm probably missing.

					_mcast_send( $send_sock, $msg, $MCAST_ADDR );
					_mcast_send( $send_sock, $msg, "127.0.0.1:$SSDP_PORT" ) if is_win();
					 $next_search = time() + $SSDPSEARCH_INTERVAL;
				}
			}

			sleep(0.10);

		}	# if !$quitting

		elsif ($running)
		{
			display($dbg_ssdp,0,"suspending SSDPListener thread");
			$this->send_byebye($send_sock);
			$running = 0;
			display($dbg_ssdp,0,"SSDPListener thread suspended");
		}
		else	# suspended
		{
			sleep(1);
		}

	}	# while 1

	# never gets here
	display($dbg_ssdp,0,"SSDPListener() ended");

}	# SSDPListener()



#-------------------------------------------------
# Sending Things
#-------------------------------------------------

sub search_msg
{
	# my ($port) = @_;
	my $search_device = 'ssdp:all';
		# interesting values are
		# ssdp:all (find everything)
		# upnp:rootdevice (find root devices)
		# urn:schemas-upnp-org:device:MediaServer:1 (DLNA Renderers)
		# urn:schemas-upnp-org:device:MediaRenderer:1 (DLNA Renderers)
    my $msg = <<"SSDP_SEARCH_MSG";
M-SEARCH * HTTP/1.1
HOST: $MCAST_ADDR
ST: $search_device
MAN: "ssdp:discover"
MX: $SSDPSEARCH_TIME
USER-AGENT: Artisan

SSDP_SEARCH_MSG

    $msg =~ s/\n/\r\n/g;
	return $msg;
}


sub send_alive
{
	my ($this,$sock) = @_;
	display($dbg_alive,0,"send_alive()");
	foreach my $nt (@{$this->{NTS}})
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
	# sends out 2 byebyes
{
	my ($this,$sock) = @_;
    display($dbg_bye,0,"send_byebye()");
	foreach my $nt (@{$this->{NTS}})
	{
		last if $quitting;
		my $msg = $this->ssdp_message(1,'send_byebye',{
			nt     => $nt,
			nts    => 'byebye',
			usn    => generate_usn($nt) });
		_mcast_send( $sock, $msg, $MCAST_ADDR );
		last if $quitting;
		sleep($BETWEEN_MSGS) if $BETWEEN_MSGS;
	}
}


sub send_responses
	# Send responses to a specific client over the 'recieve'
	# multicast socket on which we received an M_SEARCH request.
	# Since the socket here

{
	my ($this,
		$sock,
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
		display($dbg_responses,0,"send_responses for($stparam,MX=$mx) to $destination_ip:$destination_port");
		foreach my $st (@sts)
		{
			# sleeper('send_response',$mx);
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

			# OLD code with $recv_sock in call
			#
			#	my $bytes = $sock->mcast_send(
			#		$data,
			#		$destination_ip.":".$destination_port);

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
		$msg .= "USN: $usn\r\n";	# $$params{usn}\r\n";

		# IF the date is required, gmtime() may work,
		# and may not require 'GMT'
		# $msg .= "DATE: ".gmtime()." GMT\r\n";

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


sub unused_mcast_drop
{
    my ( $sock, $host ) = @_;
    my ( $addr, $port ) = split /:/, $host;
    my $ip_mreq = inet_aton( $addr ) . INADDR_ANY;

    if (!setsockopt(
        $sock,
        getprotobyname('ip') || 0,
        _constant('IP_DROP_MEMBERSHIP'),
        $ip_mreq  ))
    {
        error("Unable to drop IGMP membership: $!");
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
    # print "Sent $bytes bytes\n";
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
	my ($this,$caller,$message,$ip,$port) = @_;
	$ip ||= '';
	$port ||= '';
	my $from_addr = $ip ? "$ip:$port" : '';

	my $usn = $message->{USN} || '';
	my $nts = $message->{NTS} || '';

	# all messages will contain a uuid: in the USN
	# we are only interested in certain upnp device types
	# and mildly interested in the alive state (alive | byebye)

	my $uuid  = $usn =~ /uuid:(.*?)(:|$)/ ? $1 : '';
	my $utype = $usn =~ /:device:(.*)$/   ? $1 : '';
	my $state = $nts =~ /^ssdp:(.*)$/     ? $1 : '';

	# prettify for debugging

	$usn =~ s/^.*?(::|$)//;
	$usn =~ s/^urn://;
	$usn =~ s/^schemas-upnp-org://;

	# Find devices based on params

    my $type =	$utype eq 'MediaServer:1' ?
		$this->{SSDP_FIND_ARTISAN_LIBRARIES} &&  $uuid =~ /Artisan/ ?
			$DEVICE_TYPE_LIBRARY :
		$this->{SSDP_FIND_LIBRARIES}  ?
			$DEVICE_TYPE_LIBRARY :
		$this->{SSDP_FIND_RENDERERS} && $utype eq 'MediaRenderer:1' ?
			$DEVICE_TYPE_RENDERER : '' : '';

	my $mask = 1;
	$mask |= $type ? 0x10 : 0;
	$mask |= $type && !findDevice($type,$uuid) ? 0x100 : 0;

	my $show_hash = ($mask << 1) & $show_search_dbg;
	my $show_line = $show_hash || ($mask & $show_search_dbg);

	# printf "show_dbg(%03X) mask(%03X) show_hash(%03X) show_line(%03X)\n",$show_dbg,$mask,$show_hash,$show_line;

	my $PAD_USN = 0;	# 50
	my $PAD_ALIVE = 0;	# 14

	my $dbg_msg = sprintf "SSDP(%03X) ".pad($uuid,35)." ".pad($state,$PAD_USN)." ".pad($usn,$PAD_USN)." from $caller $from_addr",$mask;
	display(0,-1,$dbg_msg) if $show_line;
	display_hash(0,-1,$dbg_msg,$message) if $show_hash;

	DeviceManager::updateDevice($type,$uuid,$state,$message)
	 	if ($type)
}



1;	# end of SSDP.pm
