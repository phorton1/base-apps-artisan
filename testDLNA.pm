#!/usr/bin/perl
#---------------------------------------
# testDLNA.pm
#---------------------------------------
# tests various calls to vrious DLNA devices

use strict;
use warnings;
use threads;
use threads::shared;
use Data::Dumper;
use IO::Socket::INET;
use artisanUtils;
use httpUtils;
use remoteLibrary;
use DeviceManager;

$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;


#----------------------
# test main
#----------------------

my $device = findDevice($DEVICE_TYPE_LIBRARY,
	'0d6c7f8d-71b4-43db-bfd6-2198e6114470' );
	# name=LENOVO3: WMP:

display(0,0,"found device: $device->{name}");

# WMP Media Server is fucking sensitive to the
# order of arguments!  I was struggling just to
# get it working ... and this order, from
# DLNA Browser' made it go ...


for my $browse_id (0..1)
{
	print "\n\n\n";
	print "================================\n";
	print "BrowserDirectChildren($browse_id)\n";
	print "================================\n";

	my $data = $device->ContentDirectory1('Browse',[
		ObjectID => $browse_id,
		BrowseFlag => 'BrowseDirectChildren',
		Filter => '*',
		StartingIndex => 0,
		RequestedCount => 100,
		SortCriteria => '', ]);


	if ($data)
	{
		my $xml = parseXML($data,{
			what => "BrowseWMP($browse_id).response",
			show_hdr  => 1,
			show_dump => 0,
			addl_level => 0,
			dump => 1,
			decode_didl => 0,
			raw => 1,
			pretty => 1,
			my_dump => 1,
			dumper => 1, });

		if ($xml)
		{
			my $soap_env = $xml->{'SOAP-ENV:Body'} || '';
			print "SOAP_ENV=$soap_env\n";
			my $bresponse = $soap_env ? $soap_env->{'m:BrowseResponse'} : '';
			print "bresponse=$bresponse\n";
			my $result = $bresponse ? $bresponse->{Result} : '';
			print "result=$result\n";
			my $didl_text = $result ? $result->{content} : '';

			if ($didl_text)
			{
				my $didl = parseXML($didl_text,{
					what => "BrowseWMP($browse_id).didl",
					show_hdr  => 1,
					show_dump => 0,
					addl_level => 0,
					dump => 0,
					decode_didl => 0,
					raw => 1,
					pretty => 1,
					my_dump => 1,
					dumper => 1, });

				# WMP Returns a bunch of folders we are not necessarily interested in.
				# in a hash by key
				#
				#	1 = Music
				#   2 = Pictures
				#   3 = Videos
				#  12 = Playlists
				#
				# which has a sublists of upnp:SearchClass containing the
				# container type which we *could* use to filter down to interesting values

				if ($didl)
				{
					my $containers = $didl->{container};
					$containers ||= {};

					for my $container_id (sort keys %$containers)
					{
						my $container = $containers->{$container_id};
						print "container_id($container_id)) $container->{'dc:title'} $container->{childCount}\n";
						my $classes = $container->{'upnp:searchClass'};
						for my $class (@$classes)
						{
							print "   content=$class->{content}:$class->{includeDerived} \n";
						}

					}	# for each child
				}	# parsed DIDL
			}	# got didl_text
			else
			{
				warning(0,0,"Could not get didl_text");
			}
		}	# got xml
	} 	# got data
}	# for 0..1


1;