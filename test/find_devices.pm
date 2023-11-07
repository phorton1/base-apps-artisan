#!/usr/bin/perl
#---------------------------------------
# Test a multi cast listener

BEGIN { push @INC,'../'; }

use strict;
use warnings;
use Win32::API;
use Win32::OLE;
use Data::Dumper;
use artisanUtils;

display(0,0,"started");

my $finder = Win32::OLE->new('UPnP.UPnPDeviceFinder');
display(1,0,"finder=$finder");

my $rslt = $finder->FindByType('upnp:rootdevice', 0);
display(1,0,"back from call rslt=$rslt");

my $enum = Win32::OLE::Enum->new($rslt);
display(1,0,"enum=$enum");

my @devices = $enum->All();
display(1,0,"found ".scalar(@devices));
for my $device (@devices)
{
    display(0,1,$device->{FriendlyName});
}

display(0,0,"finished");



1;
