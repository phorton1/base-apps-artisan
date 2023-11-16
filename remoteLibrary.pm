#!/usr/bin/perl
#---------------------------------------
# remoteLibrary.pm
#---------------------------------------
# API
#	getTrack
#	getFolder
#	getSubitems
#	getTrackMetadata
#	getFolderMetadata
#
# Implemented in terms of xml POST requests to a remote
# DLNA MediaServer ContentDirectory service


package remoteLibrary;
use strict;
use warnings;
use threads;
use threads::shared;
use IO::Socket::INET;
use XML::Simple;
use artisanUtils;
use Library;
use base qw(Library);


my $dbg_rlib = 0;


sub new
	# receives a $dev containing ip,port,services, etc
{
	my ($class,$params) = @_;
	display($dbg_rlib,0,"remoteLibrary::new()");
	my $this = $class->SUPER::new($params);
	bless $this,$class;
	return $this;
}



sub getTrack
{
    my ($this,$id) = @_;
	display($dbg_rlib,0,"getTrack($id)");
	my $track = '';
	error("could not getTrack($id)") if !$track;
	return $track;
}


sub getFolder
	# called once with $dbh, from HTTPServer::search_directory()
	# as part of the DLNA ContentServer:1 browse functionality
{
    my ($this,$id) = @_;
	display($dbg_rlib,0,"getFolder($id)");
	my $folder = '';


	error("could not getFolder($id)") if !$folder;
	return $folder;
}


sub getSubitems
	# Called by DLNA and webUI to return the list
	# of items in a folder given by ID.  If the
	# folder type is an 'album', $table will be
	# TRACKS, to get the tracks in an album.
	# An album may not contain subfolders.
	#
	# Otherwise, the $table will be FOLDERS and
	# we are finding the children folders of the
	# given ID (which is also a leaf "class" or "genre).
	# We sort the list so that subfolders (sub-genres)
	# show up first in the list.
{
	my ($this,$table,$id,$start,$count) = @_;
    $start ||= 0;
    $count ||= 999999;
    display($dbg_rlib+2,0,"get_subitems($table,$id,$start,$count)");
	return [];
}   # get_subitems


sub getFolderMetadata
{
	my ($this,$id) = @_;
	display($dbg_rlib,0,"getTrackMetadata($id)");

	my $folder = $this->getFolder($id);
	return [] if !$folder;

	my $use_id = 0;
	my $sections = [];

	push @$sections, meta_section(\$use_id,'Database',1,$folder);

	return $sections;
}


sub getTrackMetadata
	# Returns an object that can be turned into json,
	# that is the entire treegrid that will show in
	# the right pane of the explorer page.
	#
	# For the localLibrary this includes a tree of
	# three subtrees:
	#
	# - the Track database record
	# - the mediaFile record
	# - low level MP3/WMA/M4A tags
{
	my ($this,$id) = @_;
	display($dbg_rlib,0,"getTrackMetadata($id)");

	my $track = $this->getTrack($id);
	return [] if !$track;

	my $use_id = 0;
	my $sections = [];

	push @$sections, meta_section(\$use_id,'Database',1,$track);

	# a section that shows the resolved "mediaFile"
	# section(s) that shows the low level tags

	my $info = MediaFile->new($track->{path});
	if (!$info)
	{
		error("no mediaFile($track->{path}) in item_tags request!");
		# but don't return error (show the database anyways)
	}
	else
	{
		# the errors get their own section

		my $merrors = $info->get_errors();
		delete $info->{errors};

		push @$sections,meta_section(\$use_id,'mediaFile',0,$info,'^raw_tags$');

		# show any mediaFile warnings or errors
		# we need err_num to keep the keys separate to call json()

		if ($merrors)
		{
			my @errors;
			my @sorted = sort {$$b[0] <=> $$a[0]} @$merrors;
			for my $e (@sorted)
			{
				push @errors,[$$e[0],severity_to_str($$e[0]),$$e[1]];
			}
			push @$sections,error_section(\$use_id,'mediaFileErrors',1,\@errors);
		}

		# then based on the underlying file type, show the raw tag sections
		# re-reading a lot of stuff for m4a's

		if ($$info{type})
		{
			if ($$info{type} eq 'wma')
			{
				push @$sections,meta_section(\$use_id,'wmaTags',0,$$info{raw_tags}->{tags});
				push @$sections,meta_section(\$use_id,'wmaInfo',0,$$info{raw_tags}->{info});
			}
			elsif ($$info{type} eq 'm4a')
			{
				push @$sections,meta_section(\$use_id,'m4aTags',0,$$info{raw_tags}->{tags});
				push @$sections,meta_section(\$use_id,'m4aInfo',0,$$info{raw_tags}->{info});
			}

			else
			{
				push @$sections,meta_section(\$use_id,'mp3Tags',0,$$info{raw_tags});
			}
		}
	}

	return $sections;
}






#--------------------------------------------------------
# generic DLNA serviceRequest for remoteDevices
#--------------------------------------------------------
# Not using XML Parser
#
#	my $data = $this->private_doAction(0,'SetAVTransportURI',{
#		CurrentURI => "http://$server_ip:$server_port/media/$arg.mp3",
#	my $status = $data =~ /<CurrentTransportStatus>(.*?)<\/CurrentTransportStatus>/s ? $1 : '';
#	my $state = $data =~ /<CurrentTransportState>(.*?)<\/CurrentTransportState>/s ? $1 : '';


my $dbg_dlna = 0;


sub serviceRequest
{
    my ($this,$name,$action,$args) = @_;
	display($dbg_dlna,0,"serviceRequest($name,$action)");

	my $service = $this->{services}->{$name};
	if (!$service)
	{
		error("could not find service '$name'");
		return;
	}

	display($dbg_dlna,0,"creating socket to $this->{ip}:$this->{port}");

    my $sock = IO::Socket::INET->new(
        PeerAddr => $this->{ip},
        PeerPort => $this->{port},
        Proto => 'tcp',
        Type => SOCK_STREAM,
        Blocking => 1);
    if (!$sock)
    {
        error("Could not open socket to $this->{ip}:$this->{port}");
        return;
    }

    # build the body

	# determine which 'Browse' element was used
    # coherence seems use ns0:Browse, bubbleUp u:Browse,
    # and windows m:Browse with {content}

    my $body = '<?xml version="1.0" encoding="utf-8"?>'."\r\n";
    $body .= "<s:Envelope ";
	$body .= "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\" ";
	$body .= "xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"";
	$body .= ">";
    $body .= "<s:Body>";
    $body .= "<u:$action xmlns:u=\"urn:schemas-upnp-org:service:$name:1\">";

	# sevice specific xml elements
    # $body .= "<InstanceID>0</InstanceID>";
	# $body .= "<Channel>Master</Channel>" if ($rv);

    if ($args)
    {
        my $l = shift @$args;
		my $r = shift @$args;
		while ($l)
		{
            $body .= "<$l>$r</$l>";
			$l = shift @$args;
			$r = shift @$args;
        }
    }

    $body .= "</u:$action>";
    $body .= "</s:Body>";
    $body .= "</s:Envelope>\r\n";

    # build the header and request

    my $request = '';
    $request .= "POST $service->{controlURL} HTTP/1.1\r\n";
    $request .= "HOST: $this->{ip}:$this->{port}\r\n";
    $request .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
    $request .= "Content-Length: ".length($body)."\r\n";
    $request .= "SOAPACTION: \"urn:schemas-upnp-org:service:$name:1#$action\"\r\n";
    $request .= "\r\n";
    $request .= $body;

    # send the action

    display($dbg_dlna+2,1,"sending action($action) request");
    display($dbg_dlna+2,1,"--------------- request --------------------");
    display($dbg_dlna+2,1,$request);
    display($dbg_dlna+2,1,"--------------------------------------------");

    if (!$sock->send($request))
    {
        error("Could not send message to renderer socket");
	    $sock->close();
        return;
    }

    # get the response

    display($dbg_dlna,1,"getting action($action) response");

    my %headers;
    my $first_line = 1;
    my $line = <$sock>;
    while (defined($line) && $line ne "\r\n")
    {
        chomp($line);
        $line =~ s/\r|\n//g;
        display($dbg_dlna+1,2,"line=$line");
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
    display($dbg_dlna+1,2,"content_length=$length");

    if (!$length && $headers{transfer_encoding} eq 'chunked')
    {
        my $hex = <$sock>;
        $hex =~ s/^\s*//g;
        $hex =~ s/\s*$//g;
        $length = hex($hex);
        display($dbg_dlna+1,2,"using chunked transfer_encoding($hex) length=$length");
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


    display($dbg_dlna+1,2,"got "._def($rslt)." bytes from socket");
    display($dbg_dlna+1,2,"--------------- response --------------------");
    display($dbg_dlna+1,2,"'$data'");
    display($dbg_dlna+1,2,"--------------------------------------------");

    # return to caller

    return $data;

}   # serviceRequest()




#--------------------------------------------
# ContentDirectory1
#--------------------------------------------

sub get_metafield
    # look for &lt/&gt bracketed value of id
    # massage it as necessary
    # and set it into hash as $field
{
    my ($data,$hash,$field,$id) = @_;
    my $value = '';
    $value = $1 if ($data =~ /&lt;$id&gt;(.*?)&lt;\/$id&gt/s);
    $hash->{$field} = $value;
}



sub ContentDirectory1
{
    my ($this,$action,$args) = @_;
	display($dbg_rlib,0,"contentDirectory1($action)");
	return $this->serviceRequest(
		'ContentDirectory',
		$action,
		$args);
}



1;