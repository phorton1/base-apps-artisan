#---------------------------------------
# DeviceManager.pm
#---------------------------------------
# We will need a monitoring thread to support max-age


package DeviceManager;
use strict;
use warnings;
use threads;
use threads::shared;
use LWP::UserAgent;
use httpUtils;
use artisanUtils;
use Device;



my $dbg_devices = -1;
	#  0 = show new and additions
	# -1 = show status changes
my $dbg_desc = -1;
	#  0 = show HTTP gets
	# -1 = show descriptor details
	# -2 = show XML parsing
my $dbg_cache = 0;
	# 0 = headers
	# -1 = read details

my $DUMP_XML_FILES = 1;
	# debugging


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (

		addDevice
		findDevice
		getDevicesByType

		$local_library
		$local_renderer
		$local_plsource

	);
};


our $local_library;
our $local_renderer;
our $local_plsource;

my $DEFAULT_MAX_AGE = 1800;

my $device_list = shared_clone([]);
my $device_cache_file = "$data_dir/device_cache.txt";
	# unlink $device_cache_file;
read_device_cache();
	# static initialization !!


sub addDevice
{
	my ($device) = @_;
	display($dbg_devices,0,"DeviceManager::addDevice($device->{local},$device->{deviceType},$device->{name}) uuid=$device->{uuid}");
	push @$device_list,$device;

	$local_library = $device if $device->{local} && $device->{deviceType} eq $DEVICE_TYPE_LIBRARY;
	$local_renderer = $device if $device->{local} && $device->{deviceType} eq $DEVICE_TYPE_RENDERER;
	$local_plsource = $device if $device->{local} && $device->{deviceType} eq $DEVICE_TYPE_PLSOURCE;

	return $device;
}


sub findDevice
{
	my ($deviceType, $uuid) = @_;
	my $found = '';
	for my $device (@$device_list)
	{
		return $device if
			$device->{deviceType} eq $deviceType &&
			$device->{uuid} eq $uuid;
	}
	return '';
}

sub getDevicesByType
{
	my ($type) = @_;
	my $devices = [];
	for my $device (@$device_list)
	{
		push @$devices,$device
			if $device->{deviceType} eq $type;
	}
	return $devices;
}



#-------------------------------------
# cache file
#-------------------------------------

sub read_device_cache
{
	display($dbg_cache,0,"read_device_cache()");

	my $device;
	my $service;
	my @lines = getTextLines($device_cache_file);
	for my $line (@lines)
	{
		my $pos = index($line,"=");
		my $lval = substr($line,0,$pos);
		my $rval = substr($line,$pos+1);
		if ($lval eq 'device')
		{
			display($dbg_cache+1,1,"cache_device($rval)");
			$device = shared_clone({ services => shared_clone({})});
			bless $device,"remote$rval";
			push @$device_list,$device;
			$device->{metadata} = shared_clone({})
				if $rval eq $DEVICE_TYPE_RENDERER;
			$service = '';
		}
		elsif ($lval eq 'service')
		{
			display($dbg_cache+1,2,"service($rval)");
			$service= shared_clone({});
			$device->{services}->{$rval} = $service;
		}
		else
		{
			display($dbg_cache+1,2+($service?1:0),"$lval='$rval'");
			$service ?
				$service->{$lval} = $rval :
				$device->{$lval} = $rval;
		}
	}
}


sub write_device_cache
{
	display($dbg_cache,0,"write_device_cache()");

	my $text = '';
	for my $device (@$device_list)
	{
		next if $device->{local};
		$text .= "device=$device->{deviceType}\n";
		for my $field (sort keys %$device)
		{
			next if $field =~ /metadata|playlist|services/;
			$text .= "$field=$device->{$field}\n";
		}
		for my $name (sort keys %{$device->{services}})
		{
			$text .= "service=$name\n";

			my $service = $device->{services}->{$name};
			for my $field (sort keys %$service)
			{
				$text .= "$field=$service->{$field}\n";
			}
		}
	}
	printVarToFile(1,$device_cache_file,$text);
}




#-------------------------------
# process device XML
#-------------------------------

sub getXML
{
	my ($ua,$dbg_id,$location) = @_;
	display($dbg_desc,0,"getXML() from $location");

    my $response = $ua->get($location);
    if (!$response->is_success())
    {
        error("Could not get xml content from $location");
        return;
    }

    my $data = $response->content();
	my $xml = parseXML($data, {
		what => $dbg_id,
		addl_level => 0,
		show_hdr => $dbg_desc,
		show_dump => $dbg_desc < -1,
		dump => $DUMP_XML_FILES,
		decode_didl => 0,
		raw => 0,
		pretty => 1,
		my_dump => 0,
		dumper => 1 });

	return $xml;
}



sub getDeviceXML
{
 	my ($deviceType,$uuid,$location) = @_;
	display($dbg_desc,0,"getDeviceXML($deviceType) from $location");

	return !error("$deviceType($uuid) could not get ip:port from '$location'")
		if $location !~ /^http:\/\/(\d+\.\d+\.\d+\.\d+):(\d+)\//;
	my ($ip,$port) = ($1,$2);
	display($dbg_desc,1,"ip:port = $ip:$port");

	my $dev = shared_clone({
		uuid => $uuid,
		deviceType => $deviceType,
		ip => $ip,
		port => $port,
		services => shared_clone({}), });

	my $ua = LWP::UserAgent->new();
	my $dbg_id = "$deviceType.$uuid";
	my $device_xml = getXML($ua,$dbg_id,$location);
	return if !$device_xml;

	my $xml_dev = $device_xml->{device};
	return !error("$deviceType($uuid) No 'device' in device_xml")
		if !$xml_dev;

	my $fname = $xml_dev->{friendlyName};
	return !error("$deviceType($uuid) No 'friendlyName' in device_xml")
		if !$fname;
	display($dbg_desc,1,"friendlyName=$fname");

	if ($fname =~ /(.*): WMP/ ||
		$fname =~ /\((.*) : Windows Media Player\)/)
	{
		$fname = "WMP.$1";
		display($dbg_desc,1,"modified friendlyName=$fname");
	}
	$dev->{name} = $fname;


	my $service_list = $xml_dev->{serviceList};
	return !error("$deviceType($uuid) No 'serviceList' in device_xml")
		if !$service_list;
	my $xml_services = $service_list->{service};
	return !error("$deviceType($uuid) No 'serviceList->{service}' in device_xml")
		if !$xml_services;

	display($dbg_desc,1,"services=$xml_services ref=".ref($xml_services));
	$xml_services = [$xml_services] if ref($xml_services) !~ /ARRAY/;

	for my $req ($deviceType eq $DEVICE_TYPE_LIBRARY ?
		qw(ContentDirectory) :
		qw(RenderingControl AVTransport))
	{
		display($dbg_desc+1,1,"getDeviceService($req)");
		my $xml_service;
		for my $serv (@$xml_services)
		{
			my $service_type = $serv->{serviceType} || '';
			next if $service_type !~ /$req:1/;
			$xml_service = $serv;
			last;
		}

		return !error("$deviceType($uuid) couldn not find service($req)")
			if !$xml_service;
		display($dbg_desc+1,2,"found service $xml_service->{serviceType}");

		return !error("$deviceType($uuid) $req could not find controlURL")
			if !$xml_service->{controlURL};
		# return !error("$deviceType($uuid) $req could not find eventSubURL")
		# 	if !$xml_service->{eventSubURL};
		# return !error("$deviceType($uuid) $req could not find SCPDURL")
		# 	if !$xml_service->{SCPDURL};

		$dev->{services}->{$req} = shared_clone({
			name => $req,
			controlURL => $xml_service->{controlURL},
			#eventSubURL => $xml_service->{eventURL},
			#SCPDURL => $xml_service->{SCPDURL},
		});
	}

	display($dbg_desc+1,0,"getDeviceXML($deviceType) returning");
	return $dev;
}




#-----------------------------------------------------------
# called from SSDP
#-----------------------------------------------------------

sub notifyDevice
	# notify of new or online change
{
	my ($device,$is_new) = @_;
}

sub updateDevice
{
	my ($deviceType,$uuid,$state,$message) = @_;
	my $device = findDevice($deviceType,$uuid);

	if (!$device)
	{
		display($dbg_devices,-1,"updateDevice(NEW) $deviceType $uuid $state");
		my $location = $message->{LOCATION} || '';
		return error("No location for $deviceType($uuid) state($state)")
			if !$location;
		display($dbg_devices+1,-2,"location=$location");

		my $dev = getDeviceXML($deviceType,$uuid,$location);
		return if !$dev;

		$dev->{max_age} = $DEFAULT_MAX_AGE;

		$device = $deviceType eq $DEVICE_TYPE_LIBRARY ?
			remoteLibrary->new($dev) :
			remoteRenderer->new($dev);

		if ($state eq 'byebye')
		{
			$device->{online} = '';
			$device->{max_age} = 0;
		}

		push @$device_list,$device;
		write_device_cache();
		notifyDevice($device,1);
	}
	else
	{
		if ($state eq 'byebye')
		{
			$device->{online} = '';
			$device->{max_age} = 0;
			display($dbg_devices+1,-1,"updateDevice STATE_CHG(byebye) $deviceType $device->{name}")
		}
		else
		{
			my $cache_ctrl = $message->{CACHE_CONTROL} || '';
			my $max_age = $cache_ctrl =~ /max-age=(\d+)$/ ? $1 : $DEFAULT_MAX_AGE;
			display($dbg_devices+1,-1,"updateDevice STATE_CHG(alive,$max_age) $deviceType $device->{name}")
				if !$device->{online};
			$device->{online} = time();
			$device->{max_age} = $max_age;
			write_device_cache();
		}
	}
}




1;
