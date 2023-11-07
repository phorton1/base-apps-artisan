#!/usr/bin/perl
#---------------------------------------
# Test a multi cast listener

use strict;
use warnings;
BEGIN { push @INC,'../'; }
use artisanUtils;

use IO::Socket;
use IO::Socket::INET;
use IO::Socket::Multicast;
display(0,0,"test_ssdp started");

my $ssdp_port = 1900;
my $local_port = 1901;
my $ssdp_group = '239.255.255.250';
my $ip_address = '192.168.100.101';
my $local_host = '127.0.0.1';

if (1)
{
    my $sock = IO::Socket::Multicast->new(
		LocalPort => $ssdp_port,
		Proto => 'udp',
        ReuseAddr => 1);

    if (!$sock)
    {
        display(0,0,"Could not create socket ".$!);
        exit 1;
    }

    display(0,0,"socket created");

    if (!$sock->mcast_add($ssdp_group))
    {
        display(0,0,"Could not subscribe to group");
        exit 1;
    }

    while (1)
    {
        my $data = '';
        display(1,0,"waiting for data...");
        my $peer_addr = $sock->recv($data,1024);
        if (!$peer_addr)
        {
            display(0,1,"received empty peer_addr");
            next;
        }
		my ($peer_src_port, $peer_addr2) = sockaddr_in($peer_addr);
		my $peer_ip_addr = inet_ntoa($peer_addr2);
        my $dlen = length($data || '');
        my $from_me = ($data =~ /MX: 237/s) ? ' FROM ME!' : '';

        display(0,1,"received $dlen bytes from $peer_ip_addr:$peer_src_port$from_me");
        display(1,0,$data);

    }
}


display(0,0,"test_ssdp finished");


1;
