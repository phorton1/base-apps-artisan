#
# Good news!
#
#	I get M-SEARCH replies for all devices & services, and I at least
#   get the ssdp:all M-SEARCH request, from Artisan Android, and
#   he gets my replies to his ssdp:all search for uuid, upnp:rootdevice,
#   MediaServer and ContentDirectory, which, for all, I return the
#   same /ServerDesc.xml!!
#
#
# MediaPlayer SSDP is maddening:
#
# - MediaPlayer does not respond to our searches
# - The MediaPlayer only seems to send out NOTIFY on
#   starting and stopping, based on it's max-age
#   - the Renderer max-age(1800) IS the MediaPlayer UI
#   - the Server max-age(900) is 'Windows Media Player Network Sharing Service' Service
#
# The only solution will be to cache the WindowsMedia player UUIDs and
# use them from the cache one we have been notified. *Maybe* I can hit
# them to see if they are alive once started.
#
# WEIRD1 - struggling to get new descriptiors (i.e. friendlyName) I learned
#     how to RUN REGEDIT AS SYSTEM: psexec -i -s c:\windows\regedit.exe
#     from a dosbox as administrtor.  The problem turned out to be that
#     I was editing the wrong fucking file (old verus current), but
#     this factoid might be useful for like when I was trying to remove
#     the teensyExpression USB devices and regedit would not let me.
#
# WEIRD2 - could not find any apps that would let me Browser my MediaServer,
#     and only one that would let me browser Windows Media Players' MediaServer.
#     It's called "DLNA Browser", but to make IT work I had to open a admin
#     dosbox and run "CheckNetIsolation.exe LoopbackExempt -a -n=55993czmade.dlnabrowser_876j7evpvqm5g"
#     to add an exception, then when I was done, with -d to delete it or
#     simply "CheckNetIsolation.exe LoopbackExempt -s" to list them, or
#     simply "CheckNetIsolation.exe LoopbackExempt" to get help on this
#     obscure exe that is not documented anywhere on the net, was recommended
#     by the program before it cached the servers, and is necessary because
#     Win10 home does not have a "Group Policy Management Editor"
#     You have to quit and restart DLNA browser for the change to take effect.
#
# WEIRD3 - "Windows Media Player" is the weirdest fucking animal.
#     "Media Player" had a folder (/albums/work) in its library, and then it
#     shows up in WMP, then sometime later they both forgot it,
#     and I re-added it to MP and it did NOT show up in WMP.
#     So I added another folder (an /albums/Favorite/Dan Hicks album)
#     and then WMP saw that, but not /work ... sigh.  And I still have
#     not been able to get it to acts as a DLNA client, need to try
#     from another machine.
#
# WEIRD4 - DLNA Browser
# 	  As it stands right now, at best DLNA Browser can only see my outer
# 	  directories, not able to traverse trees, apparently expecting
# 	  Tracks under the next level.
#
# 	  I WAS able to poke it so that the root (0) pointed to "Blues By
# 	  Nature" and it showed the tracks, but then would not stream them,
# 	  which I suspect is a format/transcoding issue.
#.
# 	  Other apps can use the http::server_ip:server_port/media/{id}.mp3
# 	  and stream the files correctly (except the one I need, the $mp
# 	  in localRenderer!) but thus far not able to get any reference
# 	  DLNA browser that works with both WMP Server and my Server.
# 	  DLNA browser works ok with WMP's Server.  I suspect the stream
# 	  problem i that DLNA Browser
#
# Some (UWP) Programs that did I installed that did
# not work, maybe same loopback issue
#     VLC - could stream my files but has no browser interface
#	  All My Media
#     Delight Media Player
#     Melosik


my $dbg_msgs = 0;
	#  0 == show intersesting new uuids, ext_devices, and state changes
	# -1 == show all uuids, ext_devices, and state changes

my @ALL_DLNA_TYPES = qw(
	schemas-upnp-org:device:MediaServer:1
	    schemas-upnp-org:service:ContentDirectory:1
	schemas-upnp-org:device:MediaRenderer:1
		schemas-upnp-org:service:RenderingControl:1
		schemas-upnp-org:service:AVTransport:1
		schemas-upnp-org:service:ConnectionManager:1
	linn-co-uk:device:Source:1
		av-openhome-org:service:Playlist:1
		av-openhome-org:service:Product:1
		av-openhome-org:service:Volume:1
		av-openhome-org:service:Time:1
		av-openhome-org:service:Info:1
);

# The ConnectionManager is a apparently a service of both the
# MediaPlayer MediaServer AND the MediaPlayer MediaRenderer


my $external_devices:shared = shared_clone{};
	# hash of NOTIFY devices by uuid, with sub hash of 'services'
	# each time we encounter a USN with uuid: we *may* add a new entry to this
	# with anything following ::


sub processExternalMessage
	# $caller will either be NOTIFY if from SSDPListener
	# or SEARCH if from SSDPSearch. $message is a parsed
	# ssdp_message
{
	my ($caller,$message,$ip,$port) = @_;
	$ip ||= '';
	$port ||= '';
	my $from_addr = $ip ? "$ip:$port" : '';

	my $usn = $message->{USN} || '';
	my $nts = $message->{NTS} || '';

	# the main thing we look at first is the USN
	# all messages will contain a uuid: in the USN

	my $uuid   = $usn =~ /uuid:(.*?)(:|$)/ 			? $1 : '';
	my $class;

	# show the whole urn if $dbg_msgs < 0

	if ($dbg_msgs < 0)
	{
		$class = $usn;
	}
	else	# otherwise, show abbreviated device:, service:, or what follows ::
	{
		$class = $usn =~ /:(device|service):(.*)$/ ? "$1:$2" : '';
		$class = $1 if !$class && $usn =~ /::(.*)$/;
	}

	my $state  = $nts =~ /^ssdp:(.*)$/     			? $1 : '';
	my $age    = '';

	if ($state eq 'alive' &&
		$message->{CACHE_CONTROL} &&
		$message->{CACHE_CONTROL} =~ /max-age=(.*)$/i )
	{
		$state = "alive($1)";
	}

	my $key = $uuid . ($class ? "-$class" : '');

	my $interesting = 0;
	for my $type (@ALL_DLNA_TYPES)
	{
		if ($usn =~ /$type/)
		{
			$interesting = 1;
			last;
		}
	}

	# should probably show ALL alive messages for sanity
	# or invalidate them ourselves to cause them to redisplay
	# if they truly timeout

	my $ext_device = $external_devices->{$key};
	if (!$ext_device)
	{
		display($dbg_msgs,-1,"EXT_DEVICE ".pad($uuid,35)." ".pad($state,14)." ".pad($class,40)." from $caller $from_addr")
			if $interesting || $dbg_msgs < 0;
		$ext_device = $external_devices->{$key} = shared_clone{ state => $state };
	}
	if ($state && $ext_device->{state} ne $state)
	{
		display($dbg_msgs,-1,"STATE_CHG  ".pad($uuid,35)." ".pad($state,14)." ".pad($class,40)." from $caller $from_addr")
			if $interesting || $dbg_msgs < 0;
		$ext_device->{state} = $state;
	}

}




#
# Examples from old DLNA_Renderer
#
#	return $this->private_doAction(0,'Stop') ? 1 : 0;
#	return $this->private_doAction(0,'SetAVTransportURI',{
#		CurrentURI => "http://$server_ip:$server_port/media/$arg.mp3",
#	       CurrentURIMetaData => $track->getDidl() });
#	return $this->private_doAction(0,'Play',{ Speed => 1}) ? 1 : 0;
#	return $this->private_doAction(0,'Seek',{
#		Unit => 'REL_TIME',
#		Target => $time_str})  ? 1 : 0;
#	return $this->private_doAction(0,'Pause') ? 1 : 0;
#
#	my $data = $this->private_doAction(0,'GetTransportInfo');
#		my $status = $data =~ /<CurrentTransportStatus>(.*?)<\/CurrentTransportStatus>/s ? $1 : '';
#		my $state = $data =~ /<CurrentTransportState>(.*?)<\/CurrentTransportState>/s ? $1 : '';
#		$state = 'ERROR' if ($status ne 'OK');
#
#	my $data = $this->private_doAction(0,'GetPositionInfo');
#		my $dur_str = $data =~ /<TrackDuration>(.*?)<\/TrackDuration>/s ? $1 : '';
#		my $pos_str = $data =~ /<RelTime>(.*?)<\/RelTime>/s ? $1 : '';
#		$retval{duration} = duration_to_millis($dur_str);
#		$retval{position} = duration_to_millis($pos_str);
#		$retval{uri} = $data =~ /<TrackURI>(.*?)<\/TrackURI>/s ? $1 : '';
#		$retval{type} = $retval{uri} =~ /.*\.(.*?)$/ ? uc($1) : '';
#
#		$retval{song_id} = "";
#		if ($retval{uri} =~ /http:\/\/$server_ip:$server_port\/media\/(.*?)\.mp3/)
#		    $retval{song_id} = $1;
#		    display($dbg_dlna_ren+2,0,"getSongNum() found song_id=$retval{song_id}");
#
#		$retval{metadata} = shared_clone({});
#		get_metafield($data,$retval{metadata},'title','dc:title');
#		get_metafield($data,$retval{metadata},'artist','upnp:artist');
#		get_metafield($data,$retval{metadata},'artist','dc:creator') if !$retval{metadata}->{artist};
#		get_metafield($data,$retval{metadata},'art_uri','upnp:albumArtURI');
#		get_metafield($data,$retval{metadata},'genre','upnp:genre');
#		get_metafield($data,$retval{metadata},'year_str','dc:date');
#		get_metafield($data,$retval{metadata},'album_title','upnp:album');
#		get_metafield($data,$retval{metadata},'album_artist','upnp:albumArtist');
#		get_metafield($data,$retval{metadata},'track_num','upnp:originalTrackNumber');
#		$retval{metadata}->{size} = ($data =~ /size="(\d+)"/) ? $1 : 0;
#		$retval{metadata}->{pretty_size} = bytesAsKMGT($retval{metadata}->{size});
#
#		# Get a better version of the 'type' from the DLNA info
#		# esp. since we ourselves sent the wrong file extension
#		# in the kludge in get_item_meta_didl()
#
#		$retval{type} = 'WMA' if ($data =~ /audio\/x-ms-wma/);
#		$retval{type} = 'WAV' if ($data =~ /audio\/x-wav/);
#		$retval{type} = 'M4A' if ($data =~ /audio\/x-m4a/);
#
#	$data = $this->private_doAction(1,'GetVolume');
#	$data = $this->private_doAction(1,'GetMute');




request
  POST /upnp/control/ContentDirectory1 HTTP/1.1
  SOAPACTION: "urn:schemas-upnp-org:service:ContentDirectory:1#Browse"
  User-Agent: DLNA Browser W10
  Content-Length: 453
  Content-Type: text/xml; charset="utf-8"
  Host: 10.237.50.101:8091
  Connection: Keep-Alive
POST /upnp/control/ContentDirectory1 from 10.237.50.101:61228


POSTDATA:
	<?xml version="1.0" encoding="utf-8"?>
	<s:Envelope
		s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"
		xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
		<s:Body>
			<u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
				<ObjectID>0</ObjectID>
				<BrowseFlag>BrowseDirectChildren</BrowseFlag>
				<Filter>*</Filter>
				<StartingIndex>0</StartingIndex>
				<RequestedCount>100</RequestedCount>
				<SortCriteria></SortCriteria>
			</u:Browse>
		</s:Body>
	</s:Envelope>

XML RECEIVED
    's:encodingStyle' => 'http://schemas.xmlsoap.org/soap/encoding/',
    'xmlns:s' => 'http://schemas.xmlsoap.org/soap/envelope/',
    's:Body' => {
      'u:Browse' => {
        'Filter' => '*',
        'RequestedCount' => '100',
        'ObjectID' => '0',
        'SortCriteria' => {},
        'xmlns:u' => 'urn:schemas-upnp-org:service:ContentDirectory:1',
        'BrowseFlag' => 'BrowseDirectChildren',
        'StartingIndex' => '0'
      }
    }



<?xml version="1.0" encoding="utf-8"?><s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Browse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><ObjectID>0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>100</RequestedCount><SortCriteria></SortCriteria></u:Browse></s:Body></s:Envelope>





