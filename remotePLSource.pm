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
	my ($class,$params) = @_;
	display($dbg_rpls,0,"remotePLSource::new()");
	my $this = $class->SUPER::new($params);
	bless $this,$class;
	return $this;
}


1;
