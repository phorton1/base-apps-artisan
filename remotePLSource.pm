#!/usr/bin/perl
#-------------------------------------------------
# remotePLSource.pm - Remote Playlist Source
#-------------------------------------------------

package remotePLSource;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use PLSource;
use base qw(PLSource);

my $dbg_rpls = 0;


sub new
{
	my ($class,$uuid,$friendlyName) = @_;
	display($dbg_rpls,0,"remotePLSource::new($uuid,$friendlyName)");
	my $this = $class->SUPER::new(
		0,
		$uuid,
		$friendlyName);
	bless $this,$class;
	return $this;
}


1;
