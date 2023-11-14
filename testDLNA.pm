#!/usr/bin/perl
#---------------------------------------
# testDLNA.pm
#---------------------------------------
# tests various calls to vrious DLNA devices

use strict;
use warnings;
use threads;
use threads::shared;
use IO::Socket::INET;
use artisanUtils;
use remoteLibrary;
use DeviceManager;



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

$device->ContentDirectory1('Browse',[
	ObjectID => 0,
	BrowseFlag => 'BrowseDirectChildren',
	Filter => '*',
	StartingIndex => 0,
	RequestedCount => 100,
	SortCriteria => '', ]);


# finally got!
#
# '<?xml version="1.0"?>
# <SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><SOAP-ENV:Body><m:BrowseResponse xmlns:m="urn:schemas-upnp-org:service:ContentDirectory:1"><Result xmlns:dt="urn:schemas-microsoft-com:datatypes" dt:dt="string">&lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/"
# xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"
# xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
# xmlns:microsoft="urn:schemas-microsoft-com:WMPNSS-1-0/"
# xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/"
# &gt;&lt;container id="1" restricted="1" parentID="0" childCount="10" searchable="1"&gt;&lt;dc:title&gt;Music&lt;/dc:title&gt;&lt;upnp:class name="object.container"&gt;object.container&lt;/upnp:class&gt;&lt;upnp:writeStatus&gt;NOT_WRITABLE&lt;/upnp:writeStatus&gt;&lt;upnp:searchClass includeDerived="1"&gt;object.item.audioItem&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.playlistContainer&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="1"&gt;object.container.genre&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.storageFolder&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.genre.musicGenre&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.audioItem.musicTrack&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.album.musicAlbum&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.audioItem.audioBook&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="1"&gt;object.container.album&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.person.musicArtist&lt;/upnp:searchClass&gt;&lt;/container&gt;
# &lt;container id="3" restricted="1" parentID="0" childCount="7" searchable="1"&gt;&lt;dc:title&gt;Pictures&lt;/dc:title&gt;&lt;upnp:class name="object.container"&gt;object.container&lt;/upnp:class&gt;&lt;upnp:writeStatus&gt;NOT_WRITABLE&lt;/upnp:writeStatus&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.playlistContainer&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.imageItem.photo&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.album.photoAlbum&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.storageFolder&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.album.photoAlbum.dateTaken&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="1"&gt;object.container.album&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="1"&gt;object.item.imageItem&lt;/upnp:searchClass&gt;&lt;/container&gt;
# &lt;container id="12" restricted="1" parentID="0" childCount="2" searchable="1"&gt;&lt;dc:title&gt;Playlists&lt;/dc:title&gt;&lt;upnp:class name="object.container"&gt;object.container&lt;/upnp:class&gt;&lt;upnp:writeStatus&gt;NOT_WRITABLE&lt;/upnp:writeStatus&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.videoItem.musicVideoClip&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.audioItem.musicTrack&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.imageItem.photo&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.videoItem.videoBroadcast&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.audioItem.audioBook&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.videoItem.movie&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.videoItem&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.playlistContainer&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.storageFolder&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.imageItem&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.audioItem&lt;/upnp:searchClass&gt;&lt;/container&gt;
# &lt;container id="2" restricted="1" parentID="0" childCount="8" searchable="1"&gt;&lt;dc:title&gt;Videos&lt;/dc:title&gt;&lt;upnp:class name="object.container"&gt;object.container&lt;/upnp:class&gt;&lt;upnp:writeStatus&gt;NOT_WRITABLE&lt;/upnp:writeStatus&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.album.videoAlbum&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.videoItem.musicVideoClip&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.videoItem.videoBroadcast&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.person.movieActor&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="1"&gt;object.container.album&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.item.videoItem.movie&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="1"&gt;object.container.genre&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="1"&gt;object.item.videoItem&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.playlistContainer&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.genre.movieGenre&lt;/upnp:searchClass&gt;&lt;upnp:searchClass includeDerived="0"&gt;object.container.storageFolder&lt;/upnp:searchClass&gt;&lt;/container&gt;
# &lt;/DIDL-Lite&gt;</Result><NumberReturned xmlns:dt="urn:schemas-microsoft-com:datatypes" dt:dt="ui4">4</NumberReturned><TotalMatches xmlns:dt="urn:schemas-microsoft-com:datatypes" dt:dt="ui4">4</TotalMatches><UpdateID xmlns:dt="urn:schemas-microsoft-com:datatypes" dt:dt="ui4">0</UpdateID></m:BrowseResponse></SOAP-ENV:Body></SOAP-ENV:Envelope>



# SUBSCRIBE request from WMP
#
#	SUBSCRIBE /upnp/event/ContentDirectory1 HTTP/1.1
#	Cache-Control: no-cache
#	Connection: Close
#	Pragma: no-cache
#	User-Agent: Microsoft-Windows/10.0 UPnP/1.0
#	NT: upnp:event
#	Callback: <http://10.237.50.101:2869/upnp/eventing/esingnommv>
#	Timeout: Second-1800
#	Host: 10.237.50.101:8091


1;