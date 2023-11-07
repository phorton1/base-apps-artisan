#!/usr/bin/perl
#---------------------------------------
# A one sided control point that works within artisan.
#
# This is planned to provide Artisan with the ability to "play" it's
# own songlists via DLNA, to act as a kind of "radio station" with a
# web (or android) UI to control what songs get played.  The playlists
# are called "rotations".
#
# The idea is that by sending one song at a time to a given DLNA renderer,
# we get the user experience we want, that the renderer shows the current
# song being played.  It would then be nice to have more control within
# the renderer's UI, at a minimum, the ability to skip a song in the rotation.
#
# Another alternative is perhaps to provide one big contiquous stream to
# the renderer, with embedded IDV3.2 tags that will cause it to show the
# current song being played.  However, I understand the technology for
# DLNA control points a bit already, and it seems doable.
#
# So the first experiment is to merely locate renderers, take control
# of one, and make it request a song from artisan.
#
# I'm not sure of support for Net::UPnP on the android, but I'll start on windows.

package Renderer;
use strict;
use warnings;
use threads;
use threads::shared;
use IO::Select;
use IO::Socket::INET;


use Net::UPnP;
use Net::UPnP::HTTP;
use Net::UPnP::Device;
use Net::UPnP::AV::MediaRenderer;
use Net::UPnP::ControlPoint;

use artisanUtils;

$debug_level = 0;

# following to be gotten from SSDP discovery

my $bubbleUp_port = 58645;
my $bubbleUp_ip = '192.168.100.103';
my $subscribe_path = '/dev/3ec2d6d3-cbbe-c85e-ffff-ffff95eb140a/svc/upnp-org/AVTransport/event';
my $action_path = '/dev/3ec2d6d3-cbbe-c85e-ffff-ffff95eb140a/svc/upnp-org/AVTransport/action';




#------------------------------------------------------------
# getTargetRenderer
#------------------------------------------------------------

my $target_renderer = 'bubbleUp g2110';

sub getTargetRenderer
    # implemented two different ways
{
    my @dev_list;
    if (0)  # get dev_list using Net::UPnP::ControlPoint()
    {
        display(0,0,"getTargetRenderer(Net::UPnP)");    
        my $control_point = Net::UPnP::ControlPoint->new();
        @dev_list = $control_point->search(st =>'upnp:rootdevice', mx => 3);
    }
    else    # get dev_list using using broadcast html
    {
        display(0,0,"getTargetRenderer(Broadcast HTML");    
        @dev_list = getUPNPDeviceList();
    }

    # look thru the devices for a MediaRenderer of the given name
    
    display(0,1,"found ".scalar(@dev_list)." devices");
    for my $dev (@dev_list)
    {
        my $type = $dev->getdevicetype();
        my $name = $dev->getfriendlyname();
        display(0,2,"checking '$name' = $type");
                
        if ($type eq 'urn:schemas-upnp-org:device:MediaRenderer:1' &&
            $name eq $target_renderer)
        {
            my $renderer = Net::UPnP::AV::MediaRenderer->new();
            $renderer->setdevice($dev);
            display(0,1,"getTargtRenderer() returning $dev==$renderer");
            return $renderer;
        }
    }
    display(0,3,"getTargtRenderer() returning undef");
}
    

# hard coded getUPNPDeviceList



sub getUPNPDeviceList
    # Send out a general UPNP root device request, then get the
    # service description from each device, and find the
    # urn:schemas-upnp-org:device:MediaRenderer:1  that corresponds
    # to the $target_renderer friendly name ...
{
    display(0,0,"getUPNPDeviceList()");
    
    #------------------------------------------------
    # send the broadcast message
    #------------------------------------------------
    
    my $mx = 3;   # number of seconds window is open for replies
    my $mcast_addr = $Net::UPnP::SSDP_ADDR . ':' . $Net::UPnP::SSDP_PORT;
    my $ssdp_header = <<"SSDP_SEARCH_MSG";
M-SEARCH * HTTP/1.1
Host: $mcast_addr
Man: "ssdp:discover"
ST: upnp:rootdevice
MX: $mx

SSDP_SEARCH_MSG

    $ssdp_header =~ s/\r//g;
    $ssdp_header =~ s/\n/\r\n/g;

    display(0,1,"creating socket");

    my $sock = IO::Socket::INET->new(
        LocalAddr => $server_ip,
        LocalPort => 8679,
        PeerPort => $Net::UPnP::SSDP_PORT, # $ssdp_port
        Proto     => 'udp',
        ReuseAddr => 1,
    ) or die "Cannot create socket to send multicast $@\n";

    # add the socket to the correct IGMP multicast group
    # and actually send the message. 
    
    _mcast_add( $sock, $mcast_addr );
    display(0,1,"sending broadcast message");
    _mcast_send( $sock, $ssdp_header, $mcast_addr );

    #------------------------------------------------------
    # loop thru replies to get list of root devices
    #------------------------------------------------------
    
    my %device_replies;
    my $sel = IO::Select->new($sock);
    while ( $sel->can_read( $mx ) )
    {
        my $ssdp_res_msg;
        recv ($sock, $ssdp_res_msg, 4096, 0);

        display(2,2,"DEVICE RESPONSE");
        for my $line (split(/\n/,$ssdp_res_msg))
        {
            $line =~ s/\s*$//;
            next if ($line eq '');
            display(2,3,$line);
        }
        if ($ssdp_res_msg !~ m/LOCATION[ :]+(.*)\r/i)
        {
            error("no LOCATION found in SSDP message");
            next;
        }
        my $dev_location = $1;
        if ($dev_location !~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i)
        {
            error("no IP:PORT found in LOCATION");
            next;
        }
        my $dev_addr = $1;
        my $dev_port = $2;
        my $dev_path = '/' . $3;

        display(0,2,"device_reply from ($dev_addr,$dev_port,$dev_path");
        $device_replies{"$dev_addr:$dev_port$dev_path"} = {
            msg => $ssdp_res_msg,
            ip => $dev_addr,
            port => $dev_port,
            path=>$dev_path };
    }
    
    #----------------------------------------------------------
    # for each found device, get it's device description
    #----------------------------------------------------------
    # and return if and when the target renderer is found.

    my @dev_list;
    display(0,1,"creating devices");
    for my $dev_path (sort(keys(%device_replies)))
    {
        my $dev_rec = $device_replies{$dev_path};
        my $http_req = Net::UPnP::HTTP->new();
        
        display(2,2,"GET device xml $dev_path");
        my $post_res = $http_req->post($dev_rec->{ip},$dev_rec->{port},"GET", $dev_rec->{path}, "", "");
        display(2,3,"GET status=$post_res->getstatus()");
        my $post_content = $post_res->getcontent();
        display(2,3,"GET received ".length($post_content)." bytes");
        
        if (0)
        {
            my $server_file = "$temp_dir/$dev_rec->{ip}.$dev_rec->{port}.$dev_rec->{path}.xml";
            $server_file =~ s/\//./g;
            printVarToFile(1,$server_file,$post_content);
        }
        
        my $dev = Net::UPnP::Device->new();
        $dev->setssdp($dev_rec->{msg});
        $dev->setdescription($post_content);
        push @dev_list,$dev;
        
        display(0,3,$dev->getfriendlyname()."  AT $dev_rec->{ip}:$dev_rec->{port}$dev_rec->{path}.xml");
    
        if (0)
        {
            for my $field (qw(
                devicetype
                friendlyname
                manufacturer
                manufacturerurl
                modeldescription
                modelname
                modelnumber
                serialnumber
                udn
                upc))
            {
                my $fxn = "get$field";
                my $val = $dev->$fxn($dev);
                display(0,4,"$field=$val");
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


#----------------------------------------------------
# Fake little library for meta data xml
#----------------------------------------------------
use Library;
use Database;

my $dbh = db_connect();


sub didl_header
{
    my $xml = filter_lines(1,undef,<<EOXML);
<DIDL-Lite
    xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
    xmlns:sec="http://www.sec.co.kr/dlna"
    xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" >
EOXML
	return $xml;
}


sub didl_footer
{
    my $xml = filter_lines(1,undef,<<EOXML);
</DIDL-Lite>
EOXML
    return $xml;
}


sub get_item_meta_didl
{
    my ($item_num) = @_;
    display(1,0,"get_item_meta_didl($item_num)");
    my $item = get_track($dbh,$item_num);
    display(1,1,"item="._def($item)." parent_id=".($item?$item->{PARENT_ID}:'undef'));
    my $parent = get_folder($dbh,$item->{PARENT_ID});
    display(1,1,"parent="._def($parent)." parent_id=".($item?$item->{PARENT_ID}:'undef'));
    display(0,1,"($item_num) == $item->{FULLNAME}");
    
    my $meta_didl =
        didl_header() .
        xml_item($item,$parent) .
        didl_footer();
        
    return $meta_didl;
}



#---------------------------------------------------
# An event listener threaded server
#---------------------------------------------------
# Don't know if I want to do this. It's fast enough to parse, and the
# events only occur on track changes (with full metadata).
# In artisan this *may* be better handled thru the main HTTP client

use Socket;
use XML::Simple;

my $listener_port = 8070;

my $SINGLE_THREAD = 1;
    # This server (listener) always runs in it's own thread.
    # This variable, if 0, spawns a new thread for each connection
    
    
sub start_event_listener
{
	display(0,0,"event listener starting ...");

	local *S;
	if (!socket(S, PF_INET, SOCK_STREAM, getprotobyname('tcp')))
    {
        error("Can't open event_listener socket: $!\n");
        exit 1;
    }
    
	setsockopt(S, SOL_SOCKET, SO_REUSEADDR, 1);
	my $ip = inet_aton($server_ip);
	bind(S, sockaddr_in($listener_port, $ip));
	if (!listen(S, 5))
    {
        error("Can't listen to event_listener socket: $!\n");
        exit 1;
    }

	my $ss = IO::Select->new();
	$ss->add(*S);

    LOG(0,"event_listener started on $server_ip:$listener_port");
	
    while(1)
	{
		my @connections_pending = $ss->can_read($SINGLE_THREAD?1:10);
    	next if !@connections_pending;
        
		display(0,0,"event_listener accepted ".scalar(@connections_pending)." connections");
	        
		for my $connection (@connections_pending)
		{
			my $FH;
			my $remote = accept($FH, $connection);
			my ($peer_src_port, $peer_addr) = sockaddr_in($remote);
			my $peer_ip_addr = inet_ntoa($peer_addr);
			
			if ($SINGLE_THREAD)
			{
				handle_event( $FH, $peer_ip_addr, $peer_src_port );
			}
			else
			{
				my $thread = threads->create(\&handle_event, $FH, $peer_ip_addr, $peer_src_port);
				$thread->detach();
			}
		}
	}
}



sub handle_event
{
	my ($FH,$peer_ip_addr,$peer_src_port) = @_;
	display(0,0,"event from $peer_ip_addr:$peer_src_port");
    
    my $response = http_header({
        statuscode   => 200,
    	content_type => 'text/plain' });

	#--------------------------------
	# parse http request header
	#--------------------------------

	binmode($FH);

	my %CGI = ();
	my %ENV = ();
    my $request = '';
	my $first_line = '';
	my $request_line = <$FH>;
    $request .= ($request_line || '');

	while (defined($request_line) && $request_line ne "\r\n")
	{
		next if !$request_line;
		$request_line =~ s/\r\n//g;
		chomp($request_line);

        display(0,1,"request_line=$request_line");
        
		if (!$first_line)
		{
			$first_line = $request_line;
			my @parts = split(' ', $first_line);
			close $FH if @parts != 3;
			$ENV{METHOD} = $parts[0];
			$ENV{OBJECT} = $parts[1];
			$ENV{HTTP_VERSION} = $parts[2];
		}
		else
		{
			my ($name, $value) = split(':', $request_line, 2);
			$name = uc($name);
			$value =~ s/^\s//g;
			$CGI{$name} = $value;
		}
		$request_line = <$FH>;
        $request .= $request_line;
	}

	if (!defined($ENV{METHOD}) || !defined($ENV{OBJECT}))
	{
		error("Unable to parse event HTTP from $peer_ip_addr:$peer_src_port first_line=$first_line");
		$response = http_header({
			statuscode   => 501,
			content_type => 'text/plain' });
	}
    else 
    {
        display(0,1,"$ENV{METHOD} $ENV{OBJECT} from $peer_ip_addr:$peer_src_port");
        
        #--------------------------------
        # Parse POST request XML
        #--------------------------------
    
        my $post_xml = undef;
        if ($CGI{'CONTENT-LENGTH'})
        {
            display(0,1,"Getting POST data");
            if (defined($CGI{'CONTENT-LENGTH'}) && length($CGI{'CONTENT-LENGTH'}) > 0)
            {
                display(0,2,"Reading $CGI{'CONTENT-LENGTH'} bytes from POSTDATA");
                read($FH, $CGI{POSTDATA}, $CGI{'CONTENT-LENGTH'});
            }
            else
            {
                display(0,2,"Looking for cr-lf in POSTDATA");
                $CGI{'POSTDATA'} = <$FH>;
            }
            display(1,1,"POSTDATA: $CGI{POSTDATA}");
            display(0,1,"parsing POST XML");
    
            my $xmlsimple = XML::Simple->new();
            eval { $post_xml = $xmlsimple->XMLin($CGI{POSTDATA}) };
            if ($@)
            {
                error("Unable to parse xml from $peer_ip_addr:$peer_src_port:".$@);
                my $response = http_header({
                    statuscode   => 501,
                    content_type => 'text/plain' });
            }
            else
            {
                display(0,1,"------------- XML ------------------");
                use Data::Dumper;
                print Dumper($post_xml);
                display(0,0,"------------- XML ------------------");
            }
        }
    }
    
	print $FH $response;
	close($FH);
	return 0;    
}


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
    # push(@response, "Last-Modified: ".PDLNA::Utils::http_date());

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




sub subscribe_events
    # Subscribe to the av transport service events
{
    my $request = '';
    $request .= "SUBSCRIBE $subscribe_path HTTP/1.1\r\n";
    $request .= "HOST: $bubbleUp_ip:$bubbleUp_port\n";
    $request .= "CALLBACK: <http://$server_ip:$listener_port>\r\n";
    $request .= "NT: upnp:event\r\n";
    $request .= "TIMEOUT: 60\r\n";
    $request .= "\r\n";

    display(0,0,"subscribing to transport events");

	my $sock = IO::Socket::INET->new(
        # LocalAddr => $server_ip,
        # LocalPort => 8078,
		PeerAddr => $bubbleUp_ip,
		PeerPort => $bubbleUp_port,
		Proto => 'tcp',
        Type => SOCK_STREAM,
		Blocking => 1);

    display(0,1,"sending subscribe request");
    
    $sock->send($request);

    display(0,1,"getting subscribe response");

    my $data = '';
    my $remote = $sock->recv($data,1024);
    my ($peer_port, $peer_addr) = sockaddr_in($remote);
	my $peer_ip = inet_ntoa($peer_addr);

    display(0,1,"peer_addr=$peer_ip:$peer_port");
    display(2,1,"data=$data");
    display(0,1,"done with subscription");
}
    

#---------------------------------------------
# getPosition
#--------------------------------------------

my $action_sock = undef;
    # a socket that will be re-used to talk to the renderer

sub doAction
{
    my ($action,$args) = @_;
    
    display(0,0,"doAction($action)");

    if (!$action_sock)
    {
        display(0,1,"creating action_sock");
        $action_sock = IO::Socket::INET->new(
            # LocalAddr => $server_ip,
            # LocalPort => 8078,
            PeerAddr => $bubbleUp_ip,
            PeerPort => $bubbleUp_port,
            Proto => 'tcp',
            Type => SOCK_STREAM,
            Blocking => 1);
        if (!$action_sock)
        {
            error("Could not create action_sock");
            exit 1;
        }
    }

    # build the body    

    my $body = '';
    $body .= "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">";
    $body .= "<s:Body>";
    $body .= "<u:$action xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">";
    $body .= "<InstanceID>0</InstanceID>";
    
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
    $request .= "POST $action_path HTTP/1.1\r\n";
    $request .= "HOST: $bubbleUp_ip:$bubbleUp_port\r\n";
    $request .= "Content-Type: text/xml\r\n";
    $request .= "Content-Length: ".length($body)."\r\n";
    $request .= "SOAPACTION: \"urn:schemas-upnp-org:service:AVTransport:1#$action\"\r\n";
    $request .= "\r\n";
    $request .= $body;

    # send the action

    display(2,1,"sending action($action) request");
    display(2,1,"--------------- request --------------------");
    display(2,1,$request);
    display(2,1,"--------------------------------------------");
    
    $action_sock->send($request);

    # get the response
    
    display(1,1,"getting action($action) response");

    my $data = '';
    my $response = $action_sock->recv($data,1024 * 128);
    my ($peer_port, $peer_addr) = sockaddr_in($response);
	my $peer_ip = inet_ntoa($peer_addr);

    display(1,1,"peer_addr=$peer_ip:$peer_port");
    display(1,1,"returning ".length($data)." bytes of data");

    display(2,1,"--------------- response --------------------");
    display(2,1,$data);
    display(2,1,"--------------------------------------------");
    
    # return to caller
    
    return $data;

}   # doAction






my $last_track = '';
my $last_duration  = '';
my $last_reltime = '';
    
sub getPositionInfo
{
    my $data = doAction('GetPositionInfo');
    my $track = $data =~ /<Track>(.*?)<\/Track>/s ? $1 : '';
    my $duration = $data =~ /<TrackDuration>(.*?)<\/TrackDuration>/s ? $1 : '';
    my $reltime = $data =~ /<RelTime>(.*?)<\/RelTime>/s ? $1 : '';
    
    if (($track && $track ne $last_track) ||
        ($duration && $duration ne $last_duration) ||
        ($reltime && $reltime ne $last_reltime))
    {
        $last_track = $track if ($track);
        $last_duration = $duration if ($duration);
        $last_reltime = $reltime if ($reltime);

        display(0,1,"$last_track($last_duration) $last_reltime");
    }
}
    

#--------------------------------------------
# main
#--------------------------------------------
use Time::HiRes;

display(0,0,"test_dlna started");

my $thread;
my $renderer;

if (0)
{
    # get the renderer
    
    $renderer = getTargetRenderer();
    if (!$renderer)
    {
        error("Could not get target_renderer($target_renderer)");
        exit 1;
    }
    my $dev = $renderer->getdevice();
    my $avtrans_service = $dev->getservicebyname($Net::UPnP::AV::MediaRenderer::AVTRNSPORT_SERVICE_TYPE);
}


# start the event listener
# and subscribe to events


if (0)
{
    $thread = threads->create('start_event_listener');
    $thread->detach();
    subscribe_events();
}


#-----------------
# The loop
#-----------------

display(0,0,"stopping renderer ..");
#$renderer->stop();
doAction('Stop');

my $count = 10;
my $first_time = 1;
while ($count--)
{
    # set the song
    
    my $song_number = int(rand(1000));
    display(0,0,"set_transport($song_number.mp3) ..");
    
    #$renderer->setAVTransportURI(
    doAction('SetAVTransportURI',{
        CurrentURI => "http://$server_ip:$server_port/media/$song_number.mp3",
        CurrentURIMetaData => get_item_meta_didl($song_number) });

    # play the song
    
    display(0,0,"play song ..");
    #$renderer->play();
    doAction('Play',{ Speed => 1});
    my $time = time();
    
    # monitor the renderer
    
    display(0,0,"sleeping");
    while (time() < $time + 30)
    {
        getPositionInfo();
        sleep(1);
    }
}


db_disconnect($dbh);
display(0,0,"test_dlna finished");


1;
