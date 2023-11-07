#!/usr/bin/perl
#---------------------------------------
use strict;
use warnings;
BEGIN { push @INC,'../'; }
use artisanUtils;

# $Net::UPnP::DEBUG = 1;


my $server;
my $renderer;
my $re_server   = "Plex";       # re for input DLNA server
my $re_renderer = 'WDTVLive';   # re for output DLNA renderer

my @search_path = (
    'Music',
    'Music',
    'By Folder' );


#--------------------------------------------
# search copied from ControlPoint.pm
#--------------------------------------------

use Socket;
use Net::UPnP::Device;


sub search
{
    my $max = 15;
    my $port = 1900;
    my $ip_addr = '239.255.255.250';
    my $eol = "\015\012";

    my @ssdp_header_fields = (
        "SSDP_SEARCH_MSG",
        "M-SEARCH * HTTP/1.1",
        "Host: $ip_addr:$port",
        "Man: \"ssdp:discover\"",
        "ST: upnp:rootdevice",
        "MX: $max");

    my $ssdp_header = join($eol,@ssdp_header_fields).$eol.$eol;
	#$ssdp_header =~ s/\r//g;
	#$ssdp_header =~ s/\n/\r\n/g;
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
		my $post_res = $http_req->post($dev_addr, $dev_port, "GET", $dev_path, "", "");

		display(0,2,"received GET response ".($post_res?length($post_res->getcontent()):'undef'));
		display(2,2,"received ".$post_res->getstatus());
		display(1,2,$post_res->getheader());
		display(2,2,$post_res->getcontent());

        my $post_content = $post_res->getcontent();
		my $dev = Net::UPnP::Device->new();
 		$dev->setssdp($ssdp_res_msg);
		$dev->setdescription($post_content);

        display(0,2,"name=".$dev->getfriendlyname());
 		display(1,2,"ssdp = $ssdp_res_msg");
	 	display(2,2,"description = $post_content");
		push(@devlist, $dev);
	}

	close(SSDP_SOCK);
	return @devlist;
}


#------------------------------------------------------------
# init
#------------------------------------------------------------

sub init
{
    my @dev_list;

    if (1)
    {
        use Net::UPnP::ControlPoint;
        my $obj = Net::UPnP::ControlPoint->new();
        @dev_list = $obj->search(mx => 15);
    }
    else
    {
        @dev_list = search();
    }

    display(0,1,"Found ".scalar(@dev_list)." devices");

    foreach my $dev (@dev_list)
    {
        my $device_type = $dev->getdevicetype();
        my $device_name = $dev->getfriendlyname();

        display(0,1,"device($device_name) $device_type");

        if ($device_type eq 'urn:schemas-upnp-org:device:MediaServer:1' &&
            $device_name =~ /$re_server/)
        {
            display(0,2,"SERVER");
            if (!$dev->getservicebyname('urn:schemas-upnp-org:service:ContentDirectory:1'))
            {
                error("NO CONTENT DIRECTORY on server!");
                exit 1;
            }
            $server = Net::UPnP::AV::MediaServer->new();
            $server->setdevice($dev);
        }
        if ($device_type eq 'urn:schemas-upnp-org:device:MediaRenderer:1' &&
            $device_name =~ /$re_renderer/)
        {
            display(0,2,"RENDERER");
            $renderer = Net::UPnP::AV::MediaRenderer->new();
            $renderer->setdevice($dev);
        }
    }

    if (!$server)
    {
        error("Could not find dlna server");
    }
    if (!$renderer)
    {
        error("Could not find dlna renderer");
    }
}   # init


#------------------------------------------------------------
# routines
#------------------------------------------------------------

use Net::UPnP::AV::MediaRenderer;
use Net::UPnP::ActionResponse;
use Net::UPnP::AV::MediaServer;
use Net::UPnP;
use Net::UPnP::HTTP;

sub get_renderer_state
{
    my ($renderer) = @_;
    my $dev = $renderer->getdevice();
    my $condir_service = $dev->getservicebyname('urn:schemas-upnp-org:service:AVTransport:1');
    my %action_in_arg = (
        'ObjectID' => 0,
        'InstanceID' => '0' );
    my $action_res = $condir_service->postcontrol('GetTransportInfo', \%action_in_arg);
    my $actrion_out_arg = $action_res->getargumentlist();
    my $state = $actrion_out_arg->{'CurrentTransportState'};
    display(0,3,"current state is <<$state>>");
    return $state;
}


sub find_content
{
    my ($server, $content, $level) = @_;
    my $id = $content ? $content->getid() : 0;
    my $title = $content ? $content->gettitle() : 'root';

    if ($content && $content->isitem())
    {
        # if (length($content->getdate()))
        # return $content if ($title =~ /$filename/)

        display(0,$level,"item(".$content->gettitle().") ");
            #"id='".$content->getid()."' ".
            #"type='".$content->getcontenttype()."' ".
            #"url='".$content->geturl()."' ");
    }

    return if ($content && !$content->iscontainer());

    display(0,$level,"$title");

    if ($level && $level <= @search_path)
    {
        my $part = $search_path[$level-1];
        return if ($title !~ /^($part)$/);
    }

    my @children = $server->getcontentlist(ObjectID => $id );
    return if (!@children);

    for my $child (@children)
    {
        find_content($server, $child, $level+1);
    }
}


#--------------------------------------------
# main
#--------------------------------------------

display(0,0,"test_dlna started");

while (1)
{
    display(0,0,"searching");
    init();
}

if ($renderer && $server)
{
    my $state = get_renderer_state($renderer);
    my $content; #  = find_content($server, undef, 0);

    if ($content)
    {
        my $meta = '&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; '.
            'xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; '.
            'xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot;&gt;&lt;'.
            'item id=&quot;2\$8\$1B&quot; parentID=&quot;2\$15&quot; '.
            'restricted=&quot;true&quot;&gt; &lt;dc:title&gt;final_movie&lt;/dc:title&gt; '.
            '&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt; '.
            '&lt;res protocolInfo=&quot;http-get:*:video/x-msvideo:*&quot; '.
            'size=&quot;138332664&quot; duration=&quot;2:35:27.079&quot; '.
            'resolution=&quot;1366x768&quot; bitrate=&quot;6002933&quot; '.
            'sampleFrequency=&quot;44100&quot; nrAudioChannels=&quot;1&quot;&gt;$file&lt;'.
            '/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;';

        $renderer->setAVTransportURI(
            InstanceID => 0,
            CurrentURI => $content->geturl(),
            CurrentURIMetaData => $meta);

        $renderer->stop() if ($state =~ /PLAY/);
        $renderer->play();
    }
}


display(0,0,"test_dlna finished");


1;
