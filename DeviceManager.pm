#---------------------------------------
# DeviceManager.pm
#---------------------------------------

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
my $dbg_desc = 0;
	#  0 = show HTTP gets
	# -1 = show descriptor details
	# -2 = show XML parsing


my $DUMP_XML_FILES = 1;
	# debugging
my $GET_SERVICE_DESCRIPTORS = 1;
	# Get Service Descriptor XML from SCPDURL
	# Currently unused but useful for understanding Devices



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
		return !error("$type($uuid) $req could not find eventSubURL")
			if !$xml_service->{eventSubURL};
		return !error("$type($uuid) $req could not find SCPDURL")
			if !$xml_service->{SCPDURL};

		$dev->{services}->{$req} = shared_clone({
			name => $req,
			controlURL => $xml_service->{controlURL},
			eventSubURL => $xml_service->{eventSubURL},
			SCPDURL => $xml_service->{SCPDURL},
		});

		# Unused, but tested code to get the Service Descriptors

		if ($GET_SERVICE_DESCRIPTORS)
		{
			my $scpdurl = "http://$ip:$port$dev->{services}->{$req}->{SCPDURL}";
			my $scpd_id = "$type.$uuid.$req.SCPDURL";
			my $scpd_xml = get_xml($ua,$scpd_id,$scpdurl);
		}
	}

	display($dbg_desc+1,0,"getDeviceXML($type) returning");
	return $dev;
}




#-----------------------------------------------------------
# updateDevice() called from SSDP
#-----------------------------------------------------------
# I want to thread these so that they are not on the SSDP thread.
# But, once again, I am afraid of re-entrancy issues, particularly
# in creating new devices.  One more stab.
#
# I spent quite a bit of time 'solving' a problem with WMP Server.
# If the " Windows Media Player Network Sharing Service" is stopped
# and restarted, then, for some effing unknown reason, simply starting
# a playlist no longer works correctly.
#
# After much messing around, I added $DEVICE_STATES and
# $WMP_PLAYLIST_KLUDGE to remoteLibrary and remotePlaylist,
# discovering that merely making a 'fake' request to the
# WMP Server (to get the playlists) 'fixes' it.
#
# That's all I ahve to say for now. A complicated scheme to
# accomodate some weird behavior from WMP's Server.


sub notifyDevice
	# notify of online change
{
	my ($device) = @_;
	$system_update_id++;
	display($dbg_devices,0,"my_update_id($system_update_id) $device->{name} ".($device->{online} ? "ONLINE" : "OFFLINE"));
}


sub updateDevice
{
	my ($type,					# Currently only called with $DEVICE_TYPE_LIBRARY
		$uuid,					# the UUID of the library
		$state,					# can be blank, 'alive', 'byebye'
		$message) = @_;			# the entire message received by SSDP

	display_hash($dbg_devices+2,0,"MESSAGE",$message);

	# Every message has a LOCATION
	# We check for IP changes and notify UI if it changes
	# Maps 127.0.0.1 to $server_ip to handle the fact
	# that we have to M-SEARCH for local WMP on 127.0.0.1, but
	# it NOTIFIES alive on 10.237.50.101

	my $location = $message->{LOCATION} || '';
	return error("No location for $type($uuid) state($state)")
		if !$location;

	return !error("$type($uuid) could not get ip:port from '$location'")
		if $location !~ /^http:\/\/(\d+\.\d+\.\d+\.\d+):(\d+)\//;
	my ($ip,$port) = ($1,$2);
	display($dbg_desc+2,1,"ip:port = $ip:$port");

	if ($ip eq '127.0.0.1')
	{
		display($dbg_devices+2,1,"mapping 127.0.0.1 to $server_ip");
		$ip = $server_ip;
	}

	my $device = findDevice($type,$uuid);

	my $notify = 0;
		# -1 = offline,
		#  1 = online
	my $ip_change = 0;
		# did the ip address change?

	if (!$device)
	{
		display($dbg_devices,1,"updateDevice(NEW) $type $uuid $state");

		display($dbg_devices+1,2,"location=$location");

		my $dev = getDeviceXML($type,$uuid,$location);
		return if !$dev;

		$dev->{ip} = $ip;
		$dev->{port} = $port;
		$dev->{online} = time();
		$dev->{max_age} = $DEFAULT_MAX_AGE;

		$device = $type eq $DEVICE_TYPE_LIBRARY ?
			$dev->{name} =~ /Artisan/ ?
				remoteArtisan->new($dev) :
				remoteLibrary->new($dev) :
			remoteRenderer->new($dev);

		# JIC we happen to start with a bye-bye message

		if ($state eq 'byebye')
		{
			$notify = -1;
			$device->{online} = '';
			$device->{max_age} = 0;
		}
		else
		{
			$notify = 1;
		}

		# Unused code to subscribe to remoteLibrary's eventSubURL
		#
		# else
		# {
		# 	$device->subscribe()
		# 		if $device->can('subscribe');
		# }

		push @$device_list,$device;
	}
	elsif ($state eq 'byebye')
	{
		$notify = -1 if $device->{online};
		$device->{online} = '';
		$device->{max_age} = 0;
		display($dbg_devices+1,1,"updateDevice STATE_CHG(byebye) $type $device->{name} notify=$notify");
	}
	else
	{
		$notify = 1 if !$device->{online};
		my $cache_ctrl = $message->{CACHE_CONTROL} || '';
		my $max_age = $cache_ctrl =~ /max-age=(\d+)$/ ? $1 : $DEFAULT_MAX_AGE;
		display($dbg_devices+1,-1,"updateDevice STATE_CHG(alive,$max_age) $type $device->{name}")
			if !$device->{online};
		$device->{online} = time();
		$device->{max_age} = $max_age;
	}


	# detect IP or PORT changes

	if ($device->{ip} ne $ip ||
		$device->{port} ne $port)
	{
		display($dbg_devices+1,-1,"updateDevice IP_PORT_CHG from($device->{ip}:$device->{port}) to ($ip:$port)");
		$device->{ip} = $ip;
		$device->{port} = $port;
		$ip_change = 1;
	}

	# Unused code to asynchronously get the remoteLibrary's systemUpdateId
	#
	# $device->getSystemUpdateId()
	# 	if $device->can('getSystemUpdateId');

	#----------------------------------------------
	# notification
	#----------------------------------------------
	# There are only two kinds of devices here:
	# remoteLibraries and remoteArtisans.
	#
	# We simply notify remoteArtisan on any changes and it just works.
	# But for WMP we can only notify immediately if going offline.
	# Otherwise we have to do the $WMP_PLAYLIST_KLUDGE

	if ($device->{type} eq $DEVICE_TYPE_LIBRARY)
	{
		if ($device->{remote_artisan})
		{
			notifyDevice($device) if $notify || $ip_change;
		}
		elsif ($notify == -1)		# offline
		{
			$device->{state} = $DEVICE_STATE_NONE;
			notifyDevice($device);
		}
		elsif ($notify || $ip_change)
		{
			$device->{state} = $DEVICE_STATE_NONE;
			$device->startThread();
		}
	}
}



sub invalidateOldDevices
	# This *should* work. Never seen it happen
{
	display($dbg_devices+2,0,"Invalidate Devices");

	for my $device (@$device_list)
	{
		# we WILL keep track of remote artisan's states
		# all external devices are currently libraries

		next if $device->{local};
		next if $device->{type} ne $DEVICE_TYPE_LIBRARY;
		next if !$device->{online};

		my $now = time();
		my $timeout = $device->{online} + $device->{max_age};
		display($dbg_devices+2,1,"checking($device->{name} now=$now timeout=$timeout");

		if ($now > $timeout)
		{
			$device->{online} = '';
			$device->{max_age} = 0;
			warning($dbg_devices+1,0,"invalidating($device->{name})");
			notifyDevice($device);
		}
	}

}



1;
