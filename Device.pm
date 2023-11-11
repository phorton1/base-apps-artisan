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
# wheras Remote Devices turn those API calls into HTTP (XML and JSON)
# requests and replies.

package Device;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;


my $dbg_device = 1;


our $DEVICE_TYPE_LIBRARY  = 'Library';
our $DEVICE_TYPE_RENDERER = 'Renderer';
our $DEVICE_TYPE_PLSOURCE = 'PLSource';


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		$DEVICE_TYPE_LIBRARY
		$DEVICE_TYPE_RENDERER
		$DEVICE_TYPE_PLSOURCE
	);
};




sub new
{
	my ($class, $is_local, $deviceType, $uuid, $friendlyName) = @_;
	display($dbg_device,0,"Device::new($is_local,$deviceType,$uuid,$friendlyName");
	my $this = shared_clone({
		local => $is_local,
		deviceType => $deviceType,
		uuid => $uuid,
		name => $friendlyName,
		services => shared_clone({}) });
	bless $this,$class;
	return $this;
}


sub addService
{
	my ($this, $id, $service) = @_;
	$this->{services}->{$id} = $service;
}


1;
