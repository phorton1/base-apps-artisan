#!/usr/bin/perl
#---------------------------------------
# remoteRenderer.pm
#---------------------------------------

package remoteRenderer;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Renderer;
use base qw(Renderer);

my $dbg_rlib = 0;


sub new
{
	my ($class,$uuid,$friendlyName,$params) = @_;
	display($dbg_rlib,0,"remoteRenderer::new($uuid,$friendlyName)");
	my $this = $class->SUPER::new(
		0,
		$uuid,
		$friendlyName);

	mergeHash($this,shared_clone($params));

	bless $this,$class;
	return $this;
}



1;