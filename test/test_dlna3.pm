#!/usr/bin/perl
#---------------------------------------
use strict;
use warnings;
use IO::Select;
use IO::Socket;
use IO::Socket::INET;
use IO::Socket::Multicast;
use Net::UPnP::HTTP;
use Net::UPnP::Device;
BEGIN { push @INC,'../'; }
use Utils;

$logfile = 'test_dlna3.log';
$error_logfile = 'test_dlna3.error.log';

sub search
{
    display(0,0,"search()");

    my $max = 15;
    my $ssdp_port = 1900;
    my $ssdp_group = '239.255.255.250';
    my $ip_address = '192.168.100.101';
    my $dev = 'upnp:rootdevice';

    my $ssdp_header = <<SSDP_SEARCH_MSG;
M-SEARCH * HTTP/1.1
Host: $ssdp_group:$ssdp_port
Man: "ssdp:discover"
ST: $dev
MX: $max

SSDP_SEARCH_MSG

    $ssdp_header =~ s/\r//g;
    $ssdp_header =~ s/\n/\r\n/g;

    display(0,1,"creating socket");
    my $sock = IO::Socket::Multicast->new(
		LocalAddr => $ip_address,
		PeerAddr => $ssdp_group,
		PeerPort => $ssdp_port,
		Proto => 'udp',
        ReuseAddr => 1,
    );

    if (!$sock)
    {
        error("Could not create socket: $@");
        exit 1;
    }
    $sock->mcast_add($ssdp_group);
    $sock->mcast_loopback(0);

    display(0,1,"sending broadcast message");
    $sock->mcast_send($ssdp_header,"$ssdp_group:$ssdp_port");
    display(0,1,"broadcast message sent");

    my @dev_list = ();
    my $ssdp_message = '';
    while ( my $peer_addr = $sock->recv($ssdp_message,4096) )
    {
        display(0,1,"received response");
        if (!defined($peer_addr))
        {
            error("NO RESULT from recv!");
            next;
        }
        my ($peer_port,$peer_ip) = sockaddr_in($peer_addr);
        display(0,1,"received ".length($ssdp_message)." from $peer_ip:$peer_port");

        if ($ssdp_message !~ m/LOCATION[ :]+(.*)\r/i)
        {
            display(0,2,"no LOCATION");
            next;
        }
        my $dev_location = $1;
        if ($dev_location !~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i)
        {
            display(0,2,"no HTTP");
            next;
        }
        my $dev_addr = $1;
        my $dev_port = $2;
        my $dev_path = '/' . $3;

        display(0,2,"GET($dev_addr,$dev_port,$dev_path");
        my $http_req = Net::UPnP::HTTP->new();
        my $post_res = $http_req->post($dev_addr, $dev_port, "GET", $dev_path, "", "");
        if (!$post_res)
        {
            display(0,2,"no result!");
        }
        else
        {
            my $post_content = $post_res->getcontent();
            display(0,2,"received ".length($post_content)." bytes");

            my $dev = Net::UPnP::Device->new();
            $dev->setssdp($ssdp_message);
            $dev->setdescription($post_content);
            display(0,2,"friendlyName = ".$dev->getfriendlyname());
            push(@dev_list, $dev);
        }
    }

    close $sock;
    return @dev_list;
}


#--------------------------------------------
# main
#--------------------------------------------

display(0,0,"test_dlna started");

while (1)
{
    search();
    display(0,0,"sleeping ...");
    sleep(10);
}

display(0,0,"test_dlna finished");


1;
