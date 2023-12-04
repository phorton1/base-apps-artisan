#---------------------------------------
# DeviceManager.pm
#---------------------------------------
# TODO: support for 'online' versus 'offline' remoteDevices
#     starting here with a monitoring thread to that works
#     across invocations, going all the way up to the UI
#     which should not use, or connect to, a device that
#     is not online.
# TODO: ContentDirectory1 SUBSCRIPTION caching/timeout


package DeviceManager;
use strict;
use warnings;
use threads;
use threads::shared;
use LWP::UserAgent;
use httpUtils;
use artisanUtils;
use Device;



my $dbg_devices = 0;
	#  0 = show new and additions
	# -1 = show status changes
my $dbg_desc = -1;
	#  0 = show HTTP gets
	# -1 = show descriptor details
	# -2 = show XML parsing
my $dbg_cache = 0;
	# 0 = read_headers
	# -1 = write_header && read details

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

	);
};


our $local_library;
our $local_renderer;

my $DEFAULT_MAX_AGE = 1800;

my $device_list = shared_clone([]);
my $device_cache_file = "$temp_dir/device_cache.txt";
	# unlink $device_cache_file;


sub addDevice
{
	my ($device) = @_;
	display($dbg_devices,0,"DeviceManager::addDevice($device->{local},$device->{type},$device->{name}) uuid=$device->{uuid}");
	push @$device_list,$device;

	$local_library = $device if $device->{local} && $device->{type} eq $DEVICE_TYPE_LIBRARY;
	$local_renderer = $device if $device->{local} && $device->{type} eq $DEVICE_TYPE_RENDERER;

	return $device;
}


sub findDevice
{
	my ($type, $uuid) = @_;
	my $found = '';
	for my $device (@$device_list)
	{
		return $device if
			$device->{type} eq $type &&
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
			if $device->{type} eq $type;
	}
	return $devices;
}



#-------------------------------------
# cache file
#-------------------------------------

sub read_device_cache
{
	display($dbg_cache,0,"read_device_cache()");

	my $devs = [];
	my $dev;
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
			$dev = shared_clone({
				type => $rval,
				services => shared_clone({}) });
			$dev->{metadata} = shared_clone({})
				if $rval eq $DEVICE_TYPE_RENDERER;
			push @$devs,$dev;
			$service = '';
		}
		elsif ($lval eq 'service')
		{
			display($dbg_cache+1,2,"service($rval)");
			$service= shared_clone({});
			$dev->{services}->{$rval} = $service;
		}
		else
		{
			display($dbg_cache+1,2+($service?1:0),"$lval='$rval'");
			$service ?
				$service->{$lval} = $rval :
				$dev->{$lval} = $rval;
		}
	}

	# call proper ctors

	for $dev (@$devs)
	{
		my $device = $dev->{type} eq $DEVICE_TYPE_LIBRARY ?
			 $dev->{remote_artisan} ?
				remoteArtisan->new($dev) :
				remoteLibrary->new($dev) :
			remoteRenderer->new($dev);
			push @$device_list,$device;
	}
}



sub write_device_cache
{
	display($dbg_cache+1,0,"write_device_cache()");

	my $text = '';
	for my $device (@$device_list)
	{
		next if $device->{local};
		$text .= "device=$device->{type}\n";
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

sub get_xml
{
	my ($ua,$dbg_id,$location) = @_;
	display($dbg_desc,0,"get_xml() from $location");

    my $response = $ua->get($location);
    if (!$response->is_success())
    {
        error("Could not get xml content from $location");
        return;
    }

	my $devices_dir = "$temp_dir/_devices";
	mkdir $devices_dir if !-d $devices_dir;

    my $data = $response->content();
	my $xml = parseXML($data, {
		dbg => $dbg_desc,
		dbg_name => $dbg_id,
		dump_dir => $DUMP_XML_FILES ? $devices_dir : '',
		decode_didl => 0,
		raw => 0,
		pretty => 1,
		my_dump => 0,
		dumper => 1 });

	return $xml;
}



sub getDeviceXML
{
 	my ($type,$uuid,$location) = @_;
	display($dbg_desc,0,"getDeviceXML($type) from $location");

	return !error("$type($uuid) could not get ip:port from '$location'")
		if $location !~ /^http:\/\/(\d+\.\d+\.\d+\.\d+):(\d+)\//;
	my ($ip,$port) = ($1,$2);
	display($dbg_desc,1,"ip:port = $ip:$port");

	my $dev = shared_clone({
		uuid => $uuid,
		type => $type,
		ip => $ip,
		port => $port,
		services => shared_clone({}), });

	my $ua = LWP::UserAgent->new();
	my $dbg_id = "$type.$uuid";
	my $device_xml = get_xml($ua,$dbg_id,$location);
	return if !$device_xml;

	my $xml_dev = $device_xml->{device};
	return !error("$type($uuid) No 'device' in device_xml")
		if !$xml_dev;

	my $fname = $xml_dev->{friendlyName};
	return !error("$type($uuid) No 'friendlyName' in device_xml")
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
	return !error("$type($uuid) No 'serviceList' in device_xml")
		if !$service_list;
	my $xml_services = $service_list->{service};
	return !error("$type($uuid) No 'serviceList->{service}' in device_xml")
		if !$xml_services;

	display($dbg_desc,1,"services=$xml_services ref=".ref($xml_services));
	$xml_services = [$xml_services] if ref($xml_services) !~ /ARRAY/;

	for my $req ($type eq $DEVICE_TYPE_LIBRARY ?
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

		return !error("$type($uuid) couldn not find service($req)")
			if !$xml_service;
		display($dbg_desc+1,2,"found service $xml_service->{serviceType}");

		return !error("$type($uuid) $req could not find controlURL")
			if !$xml_service->{controlURL};
		# return !error("$type($uuid) $req could not find eventSubURL")
		# 	if !$xml_service->{eventSubURL};
		# return !error("$type($uuid) $req could not find SCPDURL")
		# 	if !$xml_service->{SCPDURL};

		$dev->{services}->{$req} = shared_clone({
			name => $req,
			controlURL => $xml_service->{controlURL},
			#eventSubURL => $xml_service->{eventURL},
			#SCPDURL => $xml_service->{SCPDURL},
		});
	}

	display($dbg_desc+1,0,"getDeviceXML($type) returning");
	return $dev;
}




#-----------------------------------------------------------
# called from SSDP
#-----------------------------------------------------------

sub notifyDevice
	# notify of online change
{
	my ($device) = @_;
	display($dbg_devices,0,"$device->{name} ".($device->{online} ? "ONLINE" : "OFFLINE"));
}


sub updateDevice
{
	my ($type,$uuid,$state,$message) = @_;
	my $device = findDevice($type,$uuid);

	my $notify = 0;
	if (!$device)
	{
		display($dbg_devices,-1,"updateDevice(NEW) $type $uuid $state");
		my $location = $message->{LOCATION} || '';
		return error("No location for $type($uuid) state($state)")
			if !$location;
		display($dbg_devices+1,-2,"location=$location");

		my $dev = getDeviceXML($type,$uuid,$location);
		return if !$dev;

		$dev->{online} = time();
		$dev->{max_age} = $DEFAULT_MAX_AGE;

		$device = $type eq $DEVICE_TYPE_LIBRARY ?
			$dev->{name} =~ /Artisan/ ?
				remoteArtisan->new($dev) :
				remoteLibrary->new($dev) :
			remoteRenderer->new($dev);

		if ($state eq 'byebye')
		{
			$device->{online} = '';
			$device->{max_age} = 0;
		}

		push @$device_list,$device;
		$notify = 1;
	}
	else
	{
		if ($state eq 'byebye')
		{
			$notify = $device->{online} ? 1 : 0;
			$device->{online} = '';
			$device->{max_age} = 0;
			display($dbg_devices+1,-1,"updateDevice STATE_CHG(byebye) $type $device->{name}")
		}
		else
		{
			$notify = $device->{online} ? 0 : 1;
			my $cache_ctrl = $message->{CACHE_CONTROL} || '';
			my $max_age = $cache_ctrl =~ /max-age=(\d+)$/ ? $1 : $DEFAULT_MAX_AGE;
			display($dbg_devices+1,-1,"updateDevice STATE_CHG(alive,$max_age) $type $device->{name}")
				if !$device->{online};
			$device->{online} = time();
			$device->{max_age} = $max_age;
		}
	}
	write_device_cache();
	notifyDevice($device) if $notify;
}




1;
