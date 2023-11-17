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


if (0)		# Browse ID(0) and ID(1)
{
	for my $browse_id (0..1)
	{
		print "\n";
		print "================================\n";
		print "BrowseDirectChildren($browse_id)\n";
		print "================================\n";

		my $didl = $device->didlRequest(
			'ContentDirectory',
			'Browse',[
				ObjectID => $browse_id,
				BrowseFlag => 'BrowseDirectChildren',
				Filter => '*',
				StartingIndex => 0,
				RequestedCount => 100,
				SortCriteria => '', ]);
		if ($didl)
		{
			my $containers = $didl->{container};
			for my $container (@$containers)
			{
				my $id = $container->{id};
				print "container_id($id)) $container->{'dc:title'} $container->{childCount}\n";
				my $classes = $container->{'upnp:searchClass'};
				for my $class (@$classes)
				{
					print "   content=$class->{content}:$class->{includeDerived} \n";
				}

			}	# for each child
		} 	# got $didl
	}	# for 0..1
}


if (1)		# Search for playlists
{
	print "\n";
	print "================================\n";
	print "SearchPlaylists()\n";
	print "================================\n";

	my $didl = $device->didlRequest(
		'ContentDirectory',
		'Search',[
			ContainerID => 0,
			SearchCriteria =>  'upnp:class derivedfrom "object.container.playlistContainer"',
			Filter => '*',
			StartingIndex => 0,
			RequestedCount => 100,
			SortCriteria => '',
		]);
		# Once again, WMP exhibits sensitivity to order of
		# parameters, which must be as above for Search

	if ($didl)
	{
		# With a single playlist (first playlist)
		# MS returns FIVE containers that all have the same ID,
		# and varying sets of classes !?!

		my $containers = $didl->{container};
		for my $container (@$containers)
		{
			my $id = $container->{id};
			print "container_id($id)) $container->{'dc:title'} $container->{childCount}\n";
			my $classes = $container->{'upnp:searchClass'};
			for my $class (@$classes)
			{
				print "   content=$class->{content}:$class->{includeDerived} \n";
			}

		}	# for each child
	} 	# got $didl
}




1;