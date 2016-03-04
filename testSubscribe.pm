#!/usr/bin/perl
#------------------------------------------------
# testSubscribe.pm
#
# Setup a little HTTP Server that receives openHome events
# and displays/writes them to text files, find the desired
# openHome "product" and subscribe to events from one or
# more of the openHome services

package testSubscriber;
use strict;
use warnings;
use IO::Select;
use IO::Socket::INET;
use XML::Simple;
use Utils;
use SSDPSearch;
	
$server_port = 8092;
	# use a port different than the standard Artisan server
	

my $dbg_events = 1;
	# set to 1 to see only -->EVENT
	# set to 0 to see contents of events
	# set to -1 to see details of Event HTTP flow
my $dbg_subscribe = 1;
	# set to 0 to see details of subscription reply
	
my $ONE_TIME_PER_OTHER_EVENT = 1;
	# set to 1 to only debug the first time event
	# and only those that immediately follow some other event
my $WRITE_TO_FILE = 1;
	# set to 1 to write events to files in /junk/events


my $SINGLE_THREAD = 1;
	# probably want a single thread server for this testing
my @services = qw(Product Playlist Volume Info Time);
	# all services
my $running = 1;
	# set to zero to stop the program endless loop
my $in_method : shared = 0;
	# force event processing to wait until a subscribe is finished
my $non_time_event : shared = 1;
	# reset after non-time events
my $event_num = '000000';
	# for filenames
my %last_event_text:shared;
	# keep the text for the last event per service, and
	# don't write a text file if it did not change ...
	

# set this to undef to do a device search
# or provide the ip, port, and UDN

# my $use_device = undef;
my $use_device = { ip => '192.168.0.100',port => 58645,device => {UDN =>'38875023-0ca8-f211-ffff-ffff820db37d'}};

	
mkdir "/junk/events" if $WRITE_TO_FILE && !-d "/junk/events";
	# make the event directory


#----------------------------------------------------------------------------
# HTTP Server (this)
#----------------------------------------------------------------------------



sub start_webserver_on_this_thread
	# start the server on whatever thread calls this
{
	appUtils::set_alt_output(1);
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
		display($dbg_events+2,0,"accepted ".scalar(@connections_pending)." pending connections")
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



sub handle_connection
{
	while ($in_method) { sleep(1); }
	$in_method = 1;

	my ($FH,$peer_ip_addr,$peer_src_port) = @_;
	binmode($FH);
	
	my $show_event = 1;
	$show_event = 0 if $ONE_TIME_PER_OTHER_EVENT && !$non_time_event;
	
	appUtils::set_alt_output(1) if (!$SINGLE_THREAD);
	display($dbg_events+2,0,"HTTP connect from $peer_ip_addr:$peer_src_port");

	#--------------------------------
	# show the http request header
	#--------------------------------
	# and get the content-length, if any

	my $text:shared = '';
	my $service = '';
	my $line = <$FH>;
	if ($line =~ /NOTIFY (.*) HTTP/)
	{
		$service = $1;
		$service =~ s/^\///;
		$non_time_event = $service eq "Time" ? 0 : 1;
		display(0,0,"--> EVENT($service)") if $show_event;
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
	
	my $content_length = 0;
	while (defined($line) && $line ne "\r\n")
	{
		$text .= $line;
		chomp($line);
		$line =~ s/\n |\r//g;
		display($dbg_events,2,$line) if $show_event;
		$content_length = $1 if $line =~ /Content-Length:\s*(\d+)$/;
		$line = <$FH>;
	}

	$text .= $line if defined($line);
	
	
	# if we got no request line,
	# then it is an unrecoverable error

	#--------------------------------
	# Show the content
	#--------------------------------

	if ($content_length)
	{
		my $post_data = '';
		display($dbg_events+2,1,"Getting $content_length bytes of request body") if $show_event;
		my $bytes = read($FH, $post_data, $content_length);
		warning(0,0,"Could not read $content_length bytes.  Got $bytes!!")
			if ($bytes != $content_length);
			
		my $parsed = my_parse_xml($post_data);
		$text .= $parsed;
		display($dbg_events,1,"BODY=\n$parsed") if $show_event;
	}
	
	
	my $last_text = $last_event_text{$service};
	if (!$last_text || $last_text ne $text)
	{
		display(0,0,"!last_text($service)") if (!$last_text);
		my $filename = "/junk/events/".($event_num++)."-$service.txt";
		while (-f $filename)
		{
			$filename = "/junk/events/".($event_num++)."-$service.txt";
		}
		printVarToFile($show_event && $WRITE_TO_FILE,$filename,$text);
	}
	else
	{
		display(0,1,"duplicate event!");
	}
	$last_event_text{$service} = $text;
	
	#--------------------------------
	# send the OK response
	#--------------------------------
	
	display($dbg_events+1,1,"Sending OK response") if $show_event;
	my $response = http_header({
		'statuscode' => 501,
		'content_type' => 'text/plain' });
	if (!print $FH $response)
	{
		error("Could not complete HTTP Server Response len=".length($response));
	}
	display($dbg_events+1,1,"Sent response") if $show_event;
	close($FH);
	$in_method = 0;
	
}	# handle_connection();





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



#----------------------------------------------------------------------------
# Subscribe to a single service
#----------------------------------------------------------------------------

sub subscribeService
	# subscribe to the service
{
	while ($in_method) { sleep(1); }
	$in_method = 1;
	
	my ($device_xml,$service) = @_;
	my $ip_port = "$device_xml->{ip}:$device_xml->{port}";
    display(0,0,"subscribeService($ip_port,$service)");

	# all BubbleUp OpenHome services have the same url,
	# based on the uuid ... otherwise, I'd have to get
	# the actual service descriptions ...
	
	my $uuid = $device_xml->{device}->{UDN};
	$uuid =~ s/^uuid://;
	display($dbg_subscribe,1,"uuid=$uuid");
	my $path = "/dev/$uuid/svc/av-openhome-org/$service/event";
	
	# open the socket
	
    my $sock = IO::Socket::INET->new(
        PeerAddr => $device_xml->{ip},
        PeerPort => $device_xml->{port},
        Proto => 'tcp',
        Type => SOCK_STREAM,
        Blocking => 1);
    if (!$sock)
    {
        error("Could not open socket to $device_xml->{ip}:$device_xml->{port}");
		$in_method = 0;
        return;
    }

    # build the header and request
    
    my $request = '';
    $request .= "SUBSCRIBE $path HTTP/1.1\r\n";
    $request .= "HOST: $ip_port\r\n";
	$request .= "USER-AGENT: OS/version UPnP/1.1 product/version\r\n";
	$request .= "CALLBACK: <http://$server_ip:$server_port/$service>\r\n";
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
		$in_method = 0;
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
    
    display(0,1,($ok?"SUCCESS":"FAILURE")." subscribing to $ip_port $service");
	$in_method = 0;

}   # subscribeService
	
	



#-------------------------------------------------
# main
#-------------------------------------------------

my $desired_name = 'BubbleUPnP (GA10H) (OpenHome)';
LOG(0,"Testing Subscriptions to $desired_name");

display(0,0,"Starting HTTP Server ...)");
my $thread = threads->create('start_webserver_on_this_thread');
$thread->detach();
display(0,0,"HTTP Server Started");


# Find the openHome "Product" device of the desired name

if (!$use_device)
{
	display(0,0,"Looking for OpenHome Products ....");
	my @devices = SSDPSearch::getUPNPDeviceDescriptionList('urn:av-openhome-org:service:Product:1',undef,'','');
	display(0,1,"Found ".scalar(@devices)." OpenHome Products");
	for my $check (@devices)
	{
		if ($check->{device}->{friendlyName} eq $desired_name)
		{
			LOG(1,"Found $desired_name at $check->{ip}:$check->{port}");
			$use_device = $check;
			last;
		}
	}
}


# Subscribe to the service and enter an endless loop

if (!$use_device)
{
	error("Could not find $desired_name device!!");
}
elsif (0)	# subscribe to a single service
{
	subscribeService($use_device,"Info");
	LOG(0,"waiting for events ...");
	while (1) {sleep(1)};
}
else
{
	for my $service (@services)
	{
		subscribeService($use_device,$service);
	}
	LOG(0,"waiting for events ...");
	while (1) {sleep(1)};
}

LOG(0,"Subscription test finished");


1;
