#!/usr/bin/perl
#---------------------------------------
# Device.pm
#---------------------------------------
# UPNP devices are complicated.
# 	They generally present themselves as outer level upnp::rootdevvices
# 	and can contain multiple inner upnp device types. We are only care
# 	about devices that present certain device types,
#
# 		upnp-org:device:MediaServer (DLNA MediaServer device)
#		upnp-org:device:MediaRenderer (DLNA MediaRenderer device)
#		linn-co-uk:device:Source (OpenHome Source device
#
# Each upnp device type presents a list of service that we understand
#	and know how to use:
#
#		DLNA MediaServer - provides a ContentDirectory service
#		DLNA MediaRenderer - provides AVTransport and RenderingControl services
#       OpenHome Source - provides an OpenPlaylist service
#
# In Artisan, we abstract those three upnp types into our own deviceTypes
#
#	   	Library - a DLNA MediaServer
# 		Renderer - a DLNA MediaRenderer
# 		PLSource - An Open Home (Playlist) Source
#
# The object created by this package is ONE of those deviceTypes, and
# the same physical device can have more than one of theee deviceTypes
# in the global list of Devices.  In fact both Artisan Perl and Artisan
# Android ARE (or can be) all three kinds of deviceTypes, but, of course,
# the system works with any devices that present compliant UPNP devices
# of the types we know.
#
# For each of the devicesTypes there is a generic base class that
# presents an orthogonal API to the device's service, and from
# which are derived local and remote classes.
#
#	Device
#		Library
#			localLibarary
#			remoteLibrary (DLNA MediaServer)
#		Renderer
#			localRenderer
#			remoteRenderer (DLNA Renderer)
#		PLSource
#			localPLSource
#			remotePLSource (Open Home Source)
#
# Local Devices implement the orthogonal API into direct method calls,
# wheras Remote Devices turn those API calls into HTTP requests and replies


package Device;
use strict;
use warnings;
use threads;
use threads::shared;
use IO::Socket::INET;
use artisanUtils;
use httpUtils;


my $dbg_device = 0;

my $dbg_dlna = 0;

my $dbg_response = 0;


sub new
{
	my ($class, $params) = @_;
	if ($dbg_device < 0)
	{
		display_hash($dbg_device,0,"Device::new",$params);
	}
	else
	{
		display($dbg_device,0,"Device::new($params->{deviceType} $params->{name}=$params->{uuid}"),
	}
	my $this = shared_clone($params);
		# local 		=> $is_local,
		# deviceType 	=> $deviceType,
		# uuid 			=> $uuid,
		# name 			=> $friendlyName,
		# ip			=> '',
		# port			=> '',
		# services 		=> '',
		# online 		=> time(),
		# max_age 		=> $DEFAULT_MAX_AGE,
	bless $this,$class;
	return $this;
}




sub deviceDir
{
	my ($this) = @_;
	my $dir = "$temp_dir/$this->{deviceType}/$this->{uuid}";
	my_mkdir($dir) if !(-d $dir);
	return $dir;
}


# Encoding Weirdness
#
# Even though didl $content parsed correctly from request,
# and I wrote it out to the cache using binmode, when
# I delete the database and rebuild it from the cache files,
# xml parsing was failing at char(87466) in Browse(107).didl.txt
# using the didl $content read from the cachefile..
#
# It was apparently a spanish 'e' chr(233), even though
# there are dozens of them before that point.  Even using
# display_bytes, the re-read content was exactly the same
# as the original content ?!?!
#
# The 'solution' was to 'ascii-encode' the stuff I write
# to the cache, and then ascii-decode it when I get it
# from the cache.  This made it work, but I still don't
# like it or understsand why I needed to do this.


sub encode_ascii
	# change any high chars into their ampersand equivilants
{
	my $string = shift;
    $string =~ s/([^\x00-\x7f])/"&#".ord($1).";"/eg;
	return $string;
}
sub decode_ascii
	# change any ampersand equivilants to their high characters
{
	my $string = shift;
    $string =~ s/\\#(\d+);/chr($1)/eg;
	return $string;
}



sub didlRequest
	# method expects a <Result> containing DIDL text
	# and is used for content requests.
{
    my ($this,$params) = @_;
	my $dbg = $params->{dbg};
	my $dbg_name = $params->{dbg_name};
	display($dbg,0,"didlRequest($dbg_name)");

	my $content;
	my $cache_file = $params->{cache_file};
	if (-f $cache_file)
	{
		$content = getTextFile($cache_file,1);
		$content = decode_ascii($content);
		display($dbg,1,"got ".length($content)." bytes from $cache_file");
		$params->{dump_dir} = '';
			# don't re-dump results from cache
	}
	else
	{
		my $aresponse = $this->serviceRequest($params);
		return if !$aresponse;

		my $result = $aresponse->{Result};
		if (!$result)
		{
			$params->{error} = error("Could not get <Result> from $dbg_name");
			return;
		}

		$content = $result ? $result->{content} : '';
		if (!$content)
		{
			$params->{error} = error("Could not get content from $dbg_name");
			return;
		}

		display($dbg,1,"writing ".length($content)." bytes to $cache_file");
		printVarToFile(1,$cache_file,encode_ascii($content),1);
	}

	# if ($dbg_name eq 'Browse(107)')
	# {
	# 	# char 87466
	# 	my $funny = substr($content,87460,12);
	# 	display_bytes(0,0,"funny",$funny);
	# }

	$params->{decode_didl} = 1;
	my $didl = parseXML($content,$params);
	display($dbg,0,"didlRequest($dbg_name) returning "._def($didl));
	return $didl;
}



sub serviceRequest
	# this method works with all kinds of actions
	# and returns aresponses that *may* contain
	# everything that is needed with no further
	# parsing. see 'didlRequest' for the method
	# that expects a <Result> containing DIDL in it.
{
    my ($this,$params) = @_;
	my $dbg = $params->{dbg};
	my $dbg_name = $params->{dbg_name};
	my $service_name = $params->{service};
	my $action = $params->{action};
	my $args = $params->{args};

	display($dbg_dlna,0,"serviceRequest($dbg_name) service($service_name) action($action)");

	my $service = $this->{services}->{$service_name};
	if (!$service)
	{
		$params->{error} = error("$dbg_name could not find service '$service_name'");
		return;
	}

	display($dbg_dlna+1,0,"creating socket to $this->{ip}:$this->{port}");

	my $sock = IO::Socket::INET->new(
		PeerAddr => $this->{ip},
		PeerPort => $this->{port},
		Proto => 'tcp',
		Type => SOCK_STREAM,
		Blocking => 1);
	if (!$sock)
	{
		$params->{error} = error("$dbg_name could not open socket to $this->{ip}:$this->{port}");
		return;
	}

	# build the body

	my $content = soap_header();
	$content .= "<u:$action xmlns:u=\"urn:schemas-upnp-org:service:$service_name:1\">";

	# add sevice specific xml request elements

	if ($args)
	{
		my $num = @$args / 2;
		for (my $i=0; $i<$num; $i++)
		{
			my $l = $args->[$i*2];
			my $r = $args->[$i*2 + 1];
			$content .= "<$l>$r</$l>";
		}
	}

	$content .= "</u:$action>";
	$content .= soap_footer();

	# build the header and request

	my $request = '';
	$request .= "POST $service->{controlURL} HTTP/1.1\r\n";
	$request .= "HOST: $this->{ip}:$this->{port}\r\n";
	$request .= "Content-Type: text/xml; charset=\"utf-8\"\r\n";
	$request .= "Content-Length: ".length($content)."\r\n";
	$request .= "SOAPACTION: \"urn:schemas-upnp-org:service:$service_name:1#$action\"\r\n";
	$request .= "\r\n";
	$request .= $content;

	# send the action

	display($dbg_dlna+2,1,"sending $dbg_name request");
	display($dbg_dlna+2,1,"--------------- request --------------------");
	display($dbg_dlna+2,1,$request);
	display($dbg_dlna+2,1,"--------------------------------------------");

	if (!$sock->send($request))
	{
		$params->{error} = error("$dbg_name could not send message to renderer socket");
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

	if (!$length &&
		 $headers{transfer_encoding} &&
		 $headers{transfer_encoding} eq 'chunked')
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
		$params->{error} = error("No content length returned by $dbg_name response");
		$sock->close();
		return;
	}


	my $data;
	my $bytes = $sock->read($data,$length);
	$sock->close();

	if (!$bytes || $bytes != $length)
	{
		$params->{error} = error("$dbg_name could not read $length bytes from socket");
		return;
	}
	if (!$data)
	{
		$params->{error} = error("No data found in $dbg_name response");
		return;
	}

	display($dbg_dlna+1,2,"got "._def($bytes)." bytes from socket");
	display($dbg_dlna+1,2,"--------------- response --------------------");
	display($dbg_dlna+1,2,"'$data'");
	display($dbg_dlna+1,2,"--------------------------------------------");

	my $xml = parseXML($data,$params);
	return if !$xml;

	my $soap_env = $xml->{'SOAP-ENV:Body'};
	if (!$soap_env)
	{
		$params->{error} = error("Could not find SOAP_ENV:Body in $dbg_name response");
		return;
	}

	my $fault = $soap_env->{'SOAP-ENV:Fault'};
	if ($fault)
	{
		my $detail = $fault->{detail} || '';
		my $upnp_error = $detail ? $detail->{'u:UPnPError'} : '';
		my $code = $upnp_error ? $upnp_error->{'u:errorCode'} : '';
		my $descrip = $upnp_error ? $upnp_error->{'u:errorDescription'} : '';
		$params->{error} = error("SOAP-ENV:Fault code($code) descrip($descrip) in $dbg_name response");
		return;
	}

	my $rslt = $soap_env->{'m:'.$action.'Response'};
	if (!$soap_env)
	{
		$params->{error} = error("Could not find m:$action Response in $dbg_name response");
		return;
	}

	display($dbg_dlna,0,"serviceRequest($dbg_name) returning $rslt");
	return $rslt;

}   # serviceRequest()







1;
