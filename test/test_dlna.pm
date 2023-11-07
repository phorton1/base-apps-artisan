#!/usr/bin/perl
#---------------------------------------

BEGIN { push @INC,'../'; }

use strict;
use warnings;
use IO::Select;
use IO::Socket::INET;
use Net::UPnP;
use Net::UPnP::HTTP;
use Net::UPnP::Device;
use artisanUtils;

$debug_level = 0;


sub search
{
    display(0,0,"search()");
    my $mx = 3;   # number of seconds window is open for replies

    #------------------------------------------------
    # send the broadcast message
    #------------------------------------------------
    
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
    #print $ssdp_header;

    display(0,0,"--------------------------------------------------");
    display(0,1,"creating socket");

    my $sock = IO::Socket::INET->new(
        LocalAddr => $server_ip,
        LocalPort => 8679,
        PeerPort => $Net::UPnP::SSDP_PORT,
        Proto     => 'udp',
        ReuseAddr => 1,
    ) or die "Cannot create socket to send multicast $@\n";

    # add the socket to the correct IGMP multicast group
    # and actuall send the message. 
    
    _mcast_add( $sock, $mcast_addr );
    display(0,1,"sending broadcast message");
    _mcast_send( $sock, $ssdp_header, $mcast_addr );

    #------------------------------------------------------
    # loop thru replies to get device description urls
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

        display(2,2,"device_reply from ($dev_addr,$dev_port,$dev_path");
        $device_replies{"$dev_addr:$dev_port$dev_path"} = {
            msg => $ssdp_res_msg,
            ip => $dev_addr,
            port => $dev_port,
            path=>$dev_path };
    }
    
    #------------------------------------------------
    # retrieve the device descriptions
    #------------------------------------------------

    display(0,1,"resulting devices");
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
            my $server_file = "$dev_rec->{ip}.$dev_rec->{port}.$dev_rec->{path}.xml";
            $server_file =~ s/\//./g;
            printVarToFile(1,$server_file,$post_content);
        }
        
        my $dev = Net::UPnP::Device->new();
        $dev->setssdp($dev_rec->{msg});
        $dev->setdescription($post_content);

        display(0,3,$dev->getfriendlyname()."  AT $dev_rec->{ip}.$dev_rec->{port}.$dev_rec->{path}.xml");

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
            display(2,4,"$field=$val");

        }
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



#--------------------------------------------
# main
#--------------------------------------------

display(0,0,"test_dlna started");

while (1)
{
    search();
    display(0,0,"sleeping for 10 seconds ...");
    sleep(10);
}

display(0,0,"test_dlna finished");


1;
