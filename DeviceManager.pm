#---------------------------------------
# DeviceManager.pm
#---------------------------------------

package DeviceManager;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Device;

my $dbg_mgr = 0;


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


my $device_list = shared_clone([]);


sub init_device_cache()
{
}


sub addDevice
{
	my ($device) = @_;
	display($dbg_mgr,0,"DeviceManager::addDevice($device->{local},$device->{deviceType},$device->{name}) uuid=$device->{uuid}");
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




1;
