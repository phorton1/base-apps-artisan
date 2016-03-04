#!/usr/bin/perl
#------------------------------------------------
# test.pm
#
# pretty print some xml

use strict;
use warnings;
use IO::Select;
use IO::Socket::INET;
use XML::Simple;
use appUtils;



#----------------------------------------------------------------------------
# Testing an action
#----------------------------------------------------------------------------

sub encode_didl
{
	my ($s) = @_;
	$s =~ s/"/&quot;/g;
	$s =~ s/</&lt;/g;
	$s =~ s/>/&gt;/g;
	return $s;	
}



sub doOpenHomeAction
{
	my ($ip,$port,$control_url,$service,$action,$args) = @_;
    display(0,0,"doOpenHomeAction($service,$action)");

    my $sock = IO::Socket::INET->new(
        PeerAddr => $ip,
        PeerPort => $port,
        Proto => 'tcp',
        Type => SOCK_STREAM,
        Blocking => 1);
    if (!$sock)
    {
        error("Could not open socket to $ip}:$port");
        return;
    }

    # build the body    

    my $xml = '<?xml version="1.0" encoding="utf-8"?>'."\r\n";
    $xml .= "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">";
    $xml .= "<s:Body>";
    $xml .= "<u:$action xmlns:u=\"urn:av-openhome-org:service:$service:1\">";
    
    if ($args)
    {
        for my $k (keys(%$args))
        {
			display(0,1,"arg($k)=$args->{$k}");
            $xml .= "<$k>$args->{$k}</$k>";        
        }
    }
    
    $xml .= "</u:$action>";
    $xml .= "</s:Body>";
    $xml .= "</s:Envelope>\r\n";

    # build the header and request
    
    my $request = '';
    $request .= "POST $control_url/$service/action HTTP/1.1\r\n";
    $request .= "HOST: $ip:$port\r\n";
    $request .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
    $request .= "Content-Length: ".length($xml)."\r\n";
    $request .= "soapaction: \"urn:av-openhome-org:service:$service:1#$action\"\r\n";
    $request .= "\r\n";
    $request .= $xml;

    # send the action

    display(0,1,"sending action($action) request");
    display(0,1,"--------------- request --------------------");
    display(0,1,$request);
    display(0,1,"--------------------------------------------");
    
    if (!$sock->send($request))
    {
        error("Could not send message to renderer socket");
	    $sock->close();
        return;
    }

    # get the response
    
    display(0,1,"getting action($action) response");
    
    my %headers;
    my $first_line = 1;
    my $line = <$sock>;
    while (defined($line) && $line ne "\r\n")
    {
        chomp($line);
        $line =~ s/\r|\n//g;
        display(0,2,"line=$line");
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
    
    # WDTV puts out chunked which I think means that
    # the length is on a the next line, in hex
    
    my $length = $headers{content_length};
    display(0,2,"content_length=$length");

    if (!$length && $headers{transfer_encoding} eq 'chunked')
    {
        my $hex = <$sock>;
        $hex =~ s/^\s*//g;
        $hex =~ s/\s*$//g;
        $length = hex($hex);
        display(0,2,"using chunked transfer_encoding($hex) length=$length");
    }

    # continuing ...
    
    if (!$length)
    {
        error("No content length returned by response");
	    $sock->close();
        return;
    }
    
    my $data;
    my $rslt = $sock->read($data,$length);
    $sock->close();

    if (!$rslt || $rslt != $length)
    {
        error("Could not read $length bytes from socket");
        return;
    }
    if (!$data)
    {
        error("No data found in action response");
        return;
    }
    
    
    display(0,2,"got "._def($rslt)." bytes from socket");
    
    display(0,2,"--------------- response --------------------");
    display(0,2,"'$data'");
    display(0,2,"--------------------------------------------");
    
    # return to caller
    
    return $data;

}   # doOpenHomeAction
	
	
	

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




#-----------------------------------------------
# main
#-----------------------------------------------

my $ip = '192.168.0.104';
my $port = 58645;
my $urn = '38875023-0ca8-f211-ffff-fffffbda5e0c';
# car stereo? my $urn = '38875023-0ca8-f211-ffff-ffff820db37d';



my $song_args = {
		AfterId => 0,
		Uri => "http://192.168.0.103:8008/dlna_server/media/f5b84b605c5deb21c17190d67bb7acea.mp3",
		MetaData => encode_didl(
			'<DIDL-Lite>'.
			'<item id="f5b84b605c5deb21c17190d67bb7acea" parentID="5" restricted="1">'.
			'<upnp:class>object.item.audioItem.musicTrack</upnp:class>'.
			'<dc:title>Willie Boy\'s Shuffle</dc:title>'.
			'<dc:creator>Blues By Nature</dc:creator>'.
			'<upnp:artist>Blues By Nature</upnp:artist>'.
			'<upnp:artist role="AlbumArtist">Blues By Nature</upnp:artist>'.
			'<upnp:albumArtURI>http://192.168.0.103:8008/dlna_server/5/folder.jpg</upnp:albumArtURI>'.
			'<upnp:genre>Blues New</upnp:genre>'.
			'<dc:date>1995</dc:date>'.
			'<upnp:album>Blue To The Bone</upnp:album>'.
			'<upnp:originalTrackNumber>10</upnp:originalTrackNumber>'.
			'<ownerUdn>56657273-696f-6e34-4d41-aaaaaaafeed6</ownerUdn>'.
			'<res protocolInfo="http-get:*:audio/mpeg:DLNA.ORG_PN=MP3;DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01500000000000000000000000000000" size="1712120" duration="0:04:04.000">http://192.168.0.103:8008/dlna_server/media/f5b84b605c5deb21c17190d67bb7acea.mp3</res>'.
			'</item>'.
			'</DIDL-Lite>' )};
		

LOG(0,"test.pm started ...");

my $data = doOpenHomeAction(
	"192.168.0.100",
	58645,
	"/dev/$urn/svc/av-openhome-org",
	"Playlist",
	"ReadList",
	{IdList => "1 2 3 4"} );

if ($data)
{
	display(0,0,"XML=\n".my_parse_xml($data));
	printVarToFile(1,"/junk/readlist.raw.xml",$data);
	printVarToFile(1,"/junk/readlist.xml",my_parse_xml($data));
}

LOG(0,"test.pm finished");

1;
