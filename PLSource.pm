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
	my ($class,$is_local,$uuid,$friendlyName) = @_;
	my $this = $class->SUPER::new(
		$is_local,
		$DEVICE_TYPE_PLSOURCE,
		$uuid,
		$friendlyName);
	bless $this,$class;
	return $this;
}


1;
