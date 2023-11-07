#!/usr/bin/perl
#------------------------------------------------
# testSubscribe.pm
#
# Setup a little HTTP Server that receives UPnP events
# and displays/writes them to text files, and subscribe
# to one or more Devices/Services

package testSubscriber;
use strict;
use warnings;
use IO::Select;
use IO::Socket::INET;
use XML::Simple;
use artisanUtils;
use SSDPSearch;

my $dbg_http = -1;
my $dbg_subscribe = 0;


my $WRITE_TO_FILE = 1;
	# to write to /junk/events
my $SINGLE_THREAD = 1;
	# probably want a single thread server for this testing
my $server_port = 8092;
	# use a port different than the standard Artisan server
	
my $LOOPING_EVENT_RE = 'Time|RenderingControl';
	# will not be shown
	
my $in_connection = 0;


mkdir "/junk/events" if ($WRITE_TO_FILE);

$debug_level = 0;
	# SET THE GLOBAL DEBUG LEVEL
	
#----------------------------------------------------------------------------
# HTTP Server (this)
#----------------------------------------------------------------------------



sub start_webserver_on_this_thread
	# start the server on whatever thread calls this
{
	My::Utils::set_alt_output(1);
	display(0,0,"HTTPServer starting ...");

	local *S;
	socket(S, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die "Can't open HTTPServer socket: $!\n";
	setsockopt(S, SOL_SOCKET, SO_REUSEADDR, 1);
	my $ip = inet_aton($server_ip);
	bind(S, sockaddr_in($server_port, $ip));
	if (!listen(S, 5))
    {
        error("Can't listen to HTTPServer socket: $!\n");
        return;
    }

	my $ss = IO::Select->new();
	$ss->add(*S);

    LOG(0,"HTTPServer started on $server_ip:$server_port");
	while(1)
	{
		my @connections_pending = $ss->can_read($SINGLE_THREAD?1:60);
		display($dbg_http+2,0,"accepted ".scalar(@connections_pending)." pending connections")
			if (@connections_pending);
		for my $connection (@connections_pending)
		{
			my $FH;
			my $remote = accept($FH, $connection);
			my ($peer_src_port, $peer_addr) = sockaddr_in($remote);
			my $peer_ip_addr = inet_ntoa($peer_addr);
			
			if ($SINGLE_THREAD)
			{
				handle_connection( $FH, $peer_ip_addr, $peer_src_port );
			}
			else
			{
				my $thread = threads->create(\&handle_connection, $FH, $peer_ip_addr, $peer_src_port);
				$thread->detach();
			}
		}
	}
}	# start_webserver_on_this_thread()



#-----------------------
# Connection
#-----------------------


my %last_event_text;

sub handle_connection
{
	while ($in_connection) { sleep(1); }
	$in_connection = 1;

	my ($FH,$peer_ip_addr,$peer_src_port) = @_;
	binmode($FH);
	
	My::Utils::set_alt_output(1) if (!$SINGLE_THREAD);
	display($dbg_http+4,0,"HTTP connect from $peer_ip_addr:$peer_src_port");

	#--------------------------------
	# get the http request header
	#--------------------------------
	# and get the content-length, if any

	
	my $service = '';
	my $line = <$FH>;
	if ($line =~ /NOTIFY (.*) HTTP/)
	{
		$service = $1;
		$service =~ s/^\///;
	}
	else
	{
		error("Unexpected request: "._def($line));
		my $response = http_header({
			statuscode   => 501,
			content_type => 'text/plain' });
		print $FH $response;
		close($FH);
		return 0;
	}

	my $is_loop_event = $service =~ /$LOOPING_EVENT_RE/ ? 1 : 0;
	my $use_dbg = $is_loop_event ? $dbg_http + 2 : 0;
	$use_dbg = 0;
	
	display($use_dbg,0,"Event($service) from $peer_ip_addr:$peer_src_port");
	
	my $text = "";
	my $result = {};
	$result->{ip} = $peer_ip_addr;
	$result->{port} = $peer_src_port;
	$result->{service} = $service;
	$result->{headers} = {};

	my $content_length = 0;
	while (defined($line=<$FH>) && $line ne "\r\n")
	{
		$text .= $line;
		chomp($line);
		$line =~ s/\n|\r//g;
		display($use_dbg+2,2,$line);
		my $pos = index($line,":");
		if ($pos>=0)
		{
			my $lval = substr($line,0,$pos);
			my $rval = substr($line,$pos+1);
			$rval =~ s/^\s|\\s$//g;
			$result->{headers}->{lc($lval)} = $rval;
			$content_length = $1
				if lc($line) =~	/content-length:\s*(\d+)$/;

			display($use_dbg+1,1,"header($lval)=$rval");
		}
	}

	$text .= $line if defined($line);
	# if we got no request line,
	# then it is an unrecoverable error

	#--------------------------------
	# Get the content
	#--------------------------------

	if ($content_length)
	{
		my $post_data = '';
		display($use_dbg+1,1,"Getting $content_length bytes of request body");
		my $bytes = read($FH, $post_data, $content_length);
		warning(0,0,"Could not read $content_length bytes.  Got $bytes!!")
			if ($bytes != $content_length);
			
		my $parsed = my_parse_xml($post_data);
		$text .= $post_data;
		display($use_dbg+2,1,"BODY=\n$parsed");
		$result->{parsed} = $parsed;
		$result->{post_data} = $post_data;
	}
	
	$result->{text} = $text;
	my $last_text = $last_event_text{$service};
	if (!$last_text || $last_text ne $text)
	{
		$last_event_text{$service} = $text;
		processEvent($result,$is_loop_event)
	}

	#--------------------------------
	# send the OK response
	#--------------------------------
	
	display($use_dbg+1,1,"Sending OK response");
	my $response = http_header({
		'statuscode' => 501,
		'content_type' => 'text/plain' });
	if (!print $FH $response)
	{
		error("Could not complete HTTP Server Response len=".length($response));
	}
	display($use_dbg+1,1,"Sent response");
	close($FH);
	$in_connection = 0;
	
}	# handle_connection();



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


#---------------------------------------------------------------
# Subscribe
#---------------------------------------------------------------


sub http_header
{
	my ($params) = @_;

	my %HTTP_CODES = (
		200 => 'OK',
		206 => 'Partial Content',
		400 => 'Bad request',
		403 => 'Forbidden',
		404 => 'Not found',
		406 => 'Not acceptable',
		501 => 'Not implemented' );

	my @response = ();
	push(@response, "HTTP/1.1 ".$$params{'statuscode'}." ".$HTTP_CODES{$$params{'statuscode'}}); # TODO (maybe) differ between http protocol versions
	push(@response, "Server: $program_name");
	push(@response, "Content-Type: ".$params->{'content_type'}) if $params->{'content_type'};
	push(@response, "Content-Length: ".$params->{'content_length'}) if $params->{'content_length'};
	push(@response, "Date: ".http_date());
	if (defined($$params{'additional_header'}))
	{
		for my $header (@{$$params{'additional_header'}})
		{
			push(@response, $header);
		}
	}
	
	push(@response, 'Cache-Control: no-cache');
	push(@response, 'Connection: close');
	return join("\r\n", @response)."\r\n\r\n";
}


sub subscribeService
	# subscribe to the service
{
	while ($in_connection) { sleep(1); }
	$in_connection = 1;

	my ($service) = @_;
	my $ip = $service->{ip};
	my $port = $service->{port};
	my $urn = $service->{urn};
	my $service_name = $service->{service_name};
	my $event_path = $service->{event_path};
	
    LOG(0,"subscribeService($service_name) at $ip:$port");
	
	# open the socket
	
    my $sock = IO::Socket::INET->new(
        PeerAddr => $ip,
        PeerPort => $port,
        Proto => 'tcp',
        Type => SOCK_STREAM,
        Blocking => 1);
    if (!$sock)
    {
        error("Could not open socket to $ip:$port");
		$in_connection = 0;
        return;
    }

    # build the header and request
    
    my $request = '';
    $request .= "SUBSCRIBE $event_path HTTP/1.1\r\n";
    $request .= "HOST: $ip:$port\r\n";
	$request .= "USER-AGENT: OS/version UPnP/1.1 product/version\r\n";
	$request .= "CALLBACK: <http://$server_ip:$server_port/$service_name>\r\n";
	$request .= "NT: upnp:event\r\n";;
	$request .= "TIMEOUT: Second-1800\r\n";
    $request .= "\r\n";
	
    # send the request

    display($dbg_subscribe,1,"sending SUBSCRIBE request");
    display($dbg_subscribe+1,1,"--------------- request --------------------");
    display($dbg_subscribe+1,1,$request);
    display($dbg_subscribe+1,1,"--------------------------------------------");
    
    if (!$sock->send($request))
    {
        error("Could not send message to renderer socket");
	    $sock->close();
		$in_connection = 0;
        return;
    }

    # get the response
    
    display($dbg_subscribe,1,"getting SUBSCRIBE response");
    
	my %headers;
    my $first_line = 1;
    my $line = <$sock>;
    my $ok = $line =~ /OK/ ? 1 : 0;
	
    while (defined($line) && $line ne "\r\n")
    {
        chomp($line);
        $line =~ s/\r|\n//g;
        display($dbg_subscribe,2,"response=$line");
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
    
    display(0,1,($ok?"SUCCESS":"FAILURE")." subscribing to $service_name at $ip:$port");
	$in_connection = 0;

}   # subscribeService
	
	



#----------------------------------------------------------------------------
# Process a single event (write it to a file)
#----------------------------------------------------------------------------

my $NUM_LOOPING_EVENTS = 5;
	# only print/show the first five looping events
	
my %num_loopers;
my $event_num = "00000";

sub processEvent
{
	my ($event,$is_loop) = @_;
	my $ip = $event->{ip};
	my $port = $event->{port};
	my $service = $event->{service};
	my $key = "$ip:$port:$service";
	
	if ($is_loop)
	{
		$num_loopers{$key} ||= 0;
		return if ($num_loopers{$key}++ >= $NUM_LOOPING_EVENTS);
	}
	
	$event_num++;
	my $filename = "/junk/events/$event_num.$ip.$port.$service.txt";
	display(0,0,"filename=$filename");
	printVarToFile($WRITE_TO_FILE,$filename,$event->{text},1);
}



#-------------------------------------------------
# params
#-------------------------------------------------

my $location_exclude_re = '';

# my $service_re = 'RenderingControl';
my $service_re = 'AVTransport';
my $device_re = 'BubbleUPnP \(GA10H\)';
my $location_include_re = '192.168.0.100';



# my $service_re = 'Playlist';
# my $device_re = 'BubbleUPnP \(GA10H\) \(OpenHome\)';
# my $location_include_re = '192.168.0.100';


#-------------------------------------------------
# main
#-------------------------------------------------

LOG(0,"Testing Subscriptions");
my %found_services;

# start the http server

display(0,0,"Starting HTTP Server ...)");
my $thread = threads->create('start_webserver_on_this_thread');
$thread->detach();
display(0,0,"HTTP Server Started");

# get the devices

my @devices = SSDPSearch::getUPNPDeviceDescriptionList(
	'ssdp:all',
	undef,
	$location_include_re,
	$location_exclude_re);

# subscribe to them


for my $device_xml (@devices)
{
	my $ip = $device_xml->{ip};
	my $port = $device_xml->{port};
	my $device = $device_xml->{device};
	my $name = $device->{friendlyName};
	display(2,0,"device: $name at $ip:$port");
	if ($name =~ /$device_re/)
	{
		my $service_list = $device->{serviceList};
		my $services = $service_list->{service};
		$services = [$services] if ref($services) !~ /ARRAY/;

		display(0,0,"Device: $name at $ip:$port");
		
		for my $service (@$services)
		{
			my $usn = $service->{serviceType};
			my $event_path = $service->{eventSubURL};

			display(3,1,"usn = $usn");
			$usn =~ /urn:(.*):service:(.*):/;
			my ($urn,$service_name) = ($1,$2);
			my $key = "$ip:$port:$service_name";

			if ($urn &&
				$service_name &&
				$service_name =~ /$service_re/ &&
				$event_path &&
				!$found_services{$key})
			{
				display(3,1,"service: $service_name  urn=$urn");
					$found_services{$key} = {
						ip => $ip,
						port => $port,
						urn => $urn,
						service_name => $service_name,
						event_path => $event_path } ;
			}
		}
	}
}


# SUBSCRIBE TO THE SERVICES

LOG(0,"Subscribing to Services");
for my $service (values(%found_services))
{
	subscribeService($service);
}


# ENDLESS LOOP

LOG(0,"waiting for events ...");
while (1) {sleep(1)};


1;
