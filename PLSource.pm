#!/usr/bin/perl
#---------------------------------------
# PLSource.pm - Playlist Source
#---------------------------------------

package PLSource;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Device;
use base qw(Device);

my $dbg_pls = 1;


sub new
{
	my ($class,$params) = @_;	# $is_local,$uuid,$friendlyName) = @_;
	$params->{deviceType} ||= $DEVICE_TYPE_PLSOURCE;
	my $this = $class->SUPER::new($params);
		# $is_local,
		# $DEVICE_TYPE_PLSOURCE,
		# $uuid,
		# $friendlyName);
	bless $this,$class;
	return $this;
}


1;
