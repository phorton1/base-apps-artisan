#!/usr/bin/perl
#---------------------------------------
# Library.pm
#---------------------------------------

package Library;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Device;
use base qw(Device);

my $dbg_lib = 1;


sub new
{
	my ($class,$is_local,$uuid,$friendlyName) = @_;
	display($dbg_lib,0,"Library::new($is_local,$uuid,$friendlyName");
	my $this = $class->SUPER::new(
		$is_local,
		$DEVICE_TYPE_LIBRARY,
		$uuid,
		$friendlyName);
	bless $this,$class;
	return $this;
}


1;