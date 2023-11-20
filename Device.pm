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
	display_hash($dbg_device,0,"Device::new",$params);
	my $this = shared_clone($params);
		# local 		=> $is_local,
		# deviceType 	=> $deviceType,
		# uuid 		=> $uuid,
		# name 		=> $friendlyName,
		# ip			=> '',
		# port		=> '',
		# services 	=> '',
		# online 		=> time(),
		# max_age 	=> $DEFAULT_MAX_AGE,
	bless $this,$class;
	return $this;
}




sub cacheDir
{
	my ($this) = @_;
	my $cache_dir = "$temp_dir/$this->{uuid}";
	mkdir $cache_dir if !(-d $cache_dir);
	return $cache_dir;
}


sub cacheName
{
	my ($this,$service_name,$action,$args) = @_;
	my $cache_name = "$service_name.$action";
	if ($args)
	{
		my $num = @$args / 2;
		for (my $i=0; $i<$num; $i++)
		{
			my $l = $args->[$i*2];
			my $r = $args->[$i*2 + 1];
			$r =~ s/:|"|\*/~/g;
			$cache_name .= ".$l=$r";
		}
	}

	my $cache_dir = $this->cacheDir();
	return "$cache_dir/$cache_name.txt";
}



sub dumpDir
{
	my ($this) = @_;
	return $this->cacheDir()."/dumps";
}

sub dbgName
{
	my ($this,$action,$args) = @_;
	my $dbg_main_arg = $args->[1];
	$dbg_main_arg = '' if !defined($dbg_main_arg);
	my $dbg_name = "$this->{name}.$action($dbg_main_arg)";
	$dbg_name =~ s/:|"//g;
	return $dbg_name;
}




sub didlRequest
	# method expects a <Result> containing DIDL text
	# and is used for content requests.
{
    my ($this,$service_name,$action,$args) = @_;

	my $dbg_name = $this->dbgName($action,$args);
	display($dbg_dlna,0,"DIDL($service_name) Request($dbg_name)");

	my $aresponse = $this->serviceRequest($service_name,$action,$args);
	return if !$aresponse;

	my $result = $aresponse->{Result};
	if (!$result)
	{
		error("Could not get <Result> from $dbg_name");
		return;
	}
	my $from_cache = $aresponse->{from_cache};
	display($dbg_dlna,1,"DIDL($service_name) from_cache") if $from_cache;
	my $content = $result ? $result->{content} : '';
	if (!$content)
	{
		error("Could not get content from $dbg_name");
		return;
	}

	my $didl = parseXML($content,{
		what => "$dbg_name.didl",
		show_hdr  => 1,
		show_dump => 0,
		addl_level => 0,
		dump => !$from_cache,
		dump_dir => $this->dumpDir(),
		decode_didl => 0,
		raw => 0,
		pretty => 1,
		my_dump => 0,
		dumper => 1, });

	return if !$didl;
	$didl->{from_cache} = $from_cache;
	return $didl;
}



sub serviceRequest
	# this method works with all kinds of actions
	# and returns aresponses that *may* contain
	# everything that is needed with no further
	# parsing. see 'didlRequest' for the method
	# that expects a <Result> containing DIDL in it.
{
    my ($this,$service_name,$action,$args) = @_;
	my $dbg_name = $this->dbgName($action,$args);
	display($dbg_dlna,0,"service($service_name) Request($dbg_name)");

    my $data;
	my $from_cache = 0;
	my $cache_name = $this->cacheName($service_name,$action,$args);
	if (-f $cache_name)
	{
		display($dbg_dlna,1,"serviceRequest() found cachefile");
		$data = getTextFile($cache_name,1);
		$from_cache = 1;
	}
	else
	{
		my $service = $this->{services}->{$service_name};
		if (!$service)
		{
			error("could not find service '$service_name'");
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
			error("Could not open socket to $this->{ip}:$this->{port}");
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
			error("No content length returned by response");
			$sock->close();
			return;
		}


		my $rslt = $sock->read($data,$length);
		$sock->close();

		if (!$rslt || $rslt != $length)
		{
			error("Could not read $length bytes from socket");
			return;
		}
		if (!$data)
		{
			error("No data found in $dbg_name response");
			return;
		}

		display($dbg_dlna+1,2,"got "._def($rslt)." bytes from socket");
		display($dbg_dlna+1,2,"--------------- response --------------------");
		display($dbg_dlna+1,2,"'$data'");
		display($dbg_dlna+1,2,"--------------------------------------------");
	}

	printVarToFile(!$from_cache,$cache_name,$data,1);

	my $xml = parseXML($data,{
		what => $dbg_name,
		show_hdr  => $dbg_response <= 0,
		show_dump => $dbg_response < 0,
		addl_level => 0,
		dump => !$from_cache,
		dump_dir => $this->dumpDir(),
		decode_didl => 0,
		raw => 0,
		pretty => 1,
		my_dump => 0,
		dumper => 1, });
	return if !$xml;

	my $soap_env = $xml->{'SOAP-ENV:Body'};
	if (!$soap_env)
	{
		error("Could not find SOAP_ENV:Body in $dbg_name response");
		return;
	}

	my $fault = $soap_env->{'SOAP-ENV:Fault'};
	if ($fault)
	{
		my $detail = $fault->{detail} || '';
		my $upnp_error = $detail ? $detail->{'u:UPnPError'} : '';
		my $code = $upnp_error ? $upnp_error->{'u:errorCode'} : '';
		my $descrip = $upnp_error ? $upnp_error->{'u:errorDescription'} : '';
		error("SOAP-ENV:Fault code($code) descrip($descrip) in $dbg_name response");
		return;
	}

	my $action_response = $soap_env->{'m:'.$action.'Response'};
	if (!$soap_env)
	{
		error("Could not find m:$action Response in $dbg_name response");
		return;
	}

	display($dbg_dlna,0,"$dbg_name returning $action_response");
	$action_response->{from_cache} = $from_cache;
	return $action_response;

}   # serviceRequest()







1;
