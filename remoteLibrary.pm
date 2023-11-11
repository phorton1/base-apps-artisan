#!/usr/bin/perl
#---------------------------------------
# remoteLibrary.pm
#---------------------------------------

package remoteLibrary;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Library;
use base qw(Library);

my $dbg_rlib = 0;


sub new
{
	my ($class,$uuid,$friendlyName) = @_;
	display($dbg_rlib,0,"remoteLibrary::new($uuid,$friendlyName)");
	my $this = $class->SUPER::new(
		0,
		$uuid,
		$friendlyName);
	bless $this,$class;
	return $this;
}



1;