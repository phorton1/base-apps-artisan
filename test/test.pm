#!/usr/bin/perl
#---------------------------------------

BEGIN { push @INC,'../' };

use strict;
use warnings;
use threads;
use threads::shared;
use IO::Select;
use IO::Socket::INET;
use XML::Simple;
use LWP::UserAgent;
use artisanUtils;


my $this =
{
    ip => '192.168.100.127',
    port => 10184,
    avControlURL => '/MediaRenderer_AVTransport/control',
};

    

sub doAction
{
    my ($this,$rv,$action,$args) = @_;
    display(0,0,"doAction($rv,$action)");

    my $sock = IO::Socket::INET->new(
        PeerAddr => $this->{ip},
        PeerPort => $this->{port},
        Proto => 'tcp',
        Type => SOCK_STREAM,
        Blocking => 1);
    if (!$sock)
    {
        error("Could not open socket to $this->{ip}:$this->{port}");
        $this->{state} = 'ERROR';
        return;
    }



    my $service = $rv ? 'RenderingControl' : 'AVTransport';
    my $url = $rv ? $this->{rendererControlURL} : $this->{avControlURL};

    # build the body    

    my $body = '<?xml version="1.0" encoding="utf-8"?>'."\r\n";
    $body .= "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">";
    $body .= "<s:Body>";
    $body .= "<u:$action xmlns:u=\"urn:schemas-upnp-org:service:$service:1\">";
    $body .= "<InstanceID>0</InstanceID>";
    $body .= "<Channel>Master</Channel>" if ($rv);
    
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
    $request .= "POST $url HTTP/1.1\r\n";
    $request .= "HOST: $this->{ip}:$this->{port}\r\n";
    $request .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
    $request .= "Content-Length: ".length($body)."\r\n";
    $request .= "SOAPACTION: \"urn:schemas-upnp-org:service:$service:1#$action\"\r\n";
    $request .= "\r\n";
    $request .= $body;

    # send the action

    display(0,1,"sending action($action) request");
    display(0,1,"--------------- request --------------------");
    display(0,1,$request);
    display(0,1,"--------------------------------------------");
    
    if (!$sock->send($request))
    {
        error("Could not send message to renderer socket");
        $this->{state} = 'ERROR';
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
    if (!$length && $headers{transfer_encoding} eq 'chunked')
    {
        my $hex = <$sock>;
        chomp($hex);
        $length = hex($hex);
    }
    
        
        
    
    my $data = '';
    if (!$length)
    {
        error("No content length returned by response. trying to read by eols");
        my $line = <$sock>;
        while (defined($line) && $line ne "\r\n")
        {
            display(0,4,"line=$line");
            $data .= $line;
            $line = <$sock>;
        }
    }
    else
    {
        my $rslt = $sock->read($data,$length);
        if (!$rslt || $rslt != $length)
        {
            error("Could not read $length bytes from socket. Got $rslt");
            $this->{state} = 'ERROR';
            #return;
        }
        display(0,1,"got "._def($rslt)." bytes from socket");
    }    
    if (!$data)
    {
        error("No data found in action response");
        $this->{state} = 'ERROR';
        return;
    }
    
            
    display(0,1,"--------------- response --------------------");
    display(0,1,"'$data'");
    display(0,1,"--------------------------------------------");
    
    # return to caller
    
    $sock->close();
    return $data;

}   # doAction


my $data = doAction($this,0,'GetTransportInfo');


1;
