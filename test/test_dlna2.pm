#!/usr/bin/perl
#---------------------------------------
use strict;
use warnings;
use Socket;
use Net::UPnP::HTTP;
BEGIN { push @INC,'../'; }
use artisanUtils;



sub search
{
    my $max = 15;
    my $port = 1900;
    my $ip_addr = '239.255.255.250';
    my $eol = "\n";  # "\015\012";

	# "SSDP_SEARCH_MSG",
        
    my @ssdp_header_fields = (
        "M-SEARCH * HTTP/1.1",
        "Host: $ip_addr:$port",
        "Man: \"ssdp:discover\"",
        "ST: upnp:rootdevice",
        "MX: $max");

    my $ssdp_header = ''.join($eol,@ssdp_header_fields).$eol.$eol;
	$ssdp_header =~ s/\r//g;
	$ssdp_header =~ s/\n/\r\n/g;
    display(0,0,"search() called");
    display(0,0,$ssdp_header);

	if (!socket(SSDP_SOCK, AF_INET, SOCK_DGRAM, getprotobyname('udp')))
    {
        display(0,1,"socket failed");
    }

	my $ssdp_mcast = sockaddr_in($port, inet_aton($ip_addr));
	if (!send(SSDP_SOCK, $ssdp_header, 0, $ssdp_mcast))
    {
        display(0,1,"Could not send broadcast message");
    }
    else
    {
        display(0,1,"broadcast message sent");
    }

    my $rout;
	my $rin = '';
    my @devlist;
	vec ($rin, fileno(SSDP_SOCK), 1) = 1;
	while (select($rout = $rin, undef, undef, ($max * 2)))
    {
        display(0,1,"response received");

		my $ssdp_res_msg;
        recv(SSDP_SOCK, $ssdp_res_msg, 4096, 0);
        display(0,2,"recieved ".length($ssdp_res_msg)." bytes");
    	display(1,2,$ssdp_res_msg);

		if ($ssdp_res_msg !~ m/LOCATION[ :]+(.*)\r/i)
        {
            display(0,2,"skipping no LOCATION in response");
			next;
		}
		my $dev_location = $1;
		if ($dev_location !~ m/http:\/\/([0-9a-z.]+)[:]*([0-9]*)\/(.*)/i)
        {
            display(0,2,"skipping no http: found in response");
			next;
		}
		my $dev_addr = $1;
		my $dev_port = $2;
		my $dev_path = '/' . $3;
        display(0,1,"sending GET to $dev_addr:$dev_port$dev_path");

		my $http_req = Net::UPnP::HTTP->new();
		#my $http_req = Net::HTTP->new();
		my $post_res = $http_req->post($dev_addr, $dev_port, "GET", $dev_path, "", "");
        if (!$post_res)
        {
            display(0,2,"ERROR: not result from get");
        }
        else
        {
            my $post_content = $post_res->getcontent();
    		display(0,2,"received GET response ".length($post_content)." bytes");
    		display(2,2,"received ".$post_res->getstatus());
    		display(1,2,$post_res->getheader());
    		display(2,2,$post_res->getcontent());

            #my $dev = Net::UPnP::Device->new();
            #$dev->setssdp($ssdp_res_msg);
            #$dev->setdescription($post_content);
            #display(0,2,"name=".$dev->getfriendlyname());

     		display(1,2,"ssdp = $ssdp_res_msg");
    	 	display(2,2,"description = $post_content");
    		# push(@devlist, $dev);
        }
	}

	close(SSDP_SOCK);
	return @devlist;
}


#--------------------------------------------
# main
#--------------------------------------------

display(0,0,"test_dlna started");

while (1)
{
    search();
}

display(0,0,"test_dlna finished");


1;
