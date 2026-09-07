#---------------------------------------
# DeviceManager.pm
#---------------------------------------

# The registry of the Devices (Library and Renderer) known to
# this instance of Artisan, looked up by type and uuid.

package DeviceManager;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;


my $dbg_devices = -1;
	#  0 = show new and additions
	# -1 = show status changes



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

my $device_list = shared_clone([]);


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




1;
