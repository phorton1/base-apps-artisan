#!/usr/bin/perl
#---------------------------------------
# Track.pm
#
# Can be constructed from a local database, an uri and a
# chunk of didl, or a hash from the scan.
#
# Can return a didl representation of itself
#
# "this" generallly contains the the fields as defined
# in the database, but can be extened in memory by other
# clients.
#
# They are created in shared memory as per usage by threads.
#
# Any created in memory are marked as dirty.
# Any created from a database record are marked as exists.
# Dirty is cleared on a save(), which has a force param.


package Track;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use XMLSoap;
use Database;


my $dbg_track = 0;
my $dbg_didl = 1;


# special accessors

sub getName
{
	my ($this) = @_;
	return pathName($this->{path});
}

sub getContainingPath
{
	my ($this) = @_;
	return containigPath($this->{path});
}

sub mimeType
{
	my ($this) = @_;
	return artisanMimeType($this->{type});
}


sub unused_getPublicArtUri
{
	my ($this) = @_;
	my $rslt;
	if ($this->{is_local} && $this->{has_art} & $HAS_FOLDER_ART)
	{
		$rslt = "http://$server_ip:$server_port/get_art/$this->{parent_id}/folder.jpg";
	}
	else
	{
		$rslt = $this->{art_uri};
	}
	return $rslt;
}


#------------------------------------------------------------------
# Construction
#------------------------------------------------------------------


sub new
{
	my ($class) = @_;
	my $this = db_init_rec('tracks');
	bless $this,$class;
	return $this;
}


sub newFromHash
	# error if no id provided
	# sets dity bit
{
	my ($class,$hash) = @_;
	if (!$hash->{id})
	{
		error("attempt to create track without an id!!");
		return;
	}
	my $this = $class->new();
	mergeHash($this,$hash);
	$this->{dirty} = 1;
	return $this;
}


sub newFromDb
{
	my ($class,$rec) = @_;
	my $this = $class->newFromHash($rec);
	$this->{dirty} = 0;
	$this->{exists} = 1;
	return $this;
}


sub newFromDbId
	# database tracks add in-memory exists=1 field
	# so save knows whether to do an update() or an insert
{
	my ($class,$dbh,$id) = @_;
	my $this = undef;
	my $rec = get_record_db($dbh,"SELECT * FROM tracks WHERE id='$id'");
	if ($rec)
	{
		$this = $class->newFromHash($rec);
		$this->{exists} = 1;
	}
	return $this;
}



sub newFromUriDidl
{
	my ($class,$uri,$didl) = @_;
}




sub insert
{
	my ($this,$dbh) = @_;
	if (!$this->{id})
	{
		error("attempt to insert track without an id!!");
		return;
	}

	if (insert_record_db($dbh,'tracks',$this))
	{
		$this->{dirty} = 0;
		$this->{exists} = 1;
	}
	else
	{
		error("could not insert track($this->{id}} $this->{title} into track database");
		return;
	}
	return $this;
}



sub save
	# returns 1=ok, 2=updated, 3=inserted
{
	my ($this,$dbh,$force) = @_;
	if (!$this->{id})
	{
		error("attempt to save track without an id!!");
		return;
	}

	my $ok = 1;
	if ($this->{dirty} || $force)
	{
		if ($this->{exists})
		{
			if (update_record_db($dbh,'tracks',$this))
			{
				$this->{dirty} = 0;
				$ok = 2;
			}
			else
			{
				error("could not update track($this->{id}} $this->{title} in track database");
				return;
			}
		}
		elsif ($this->insert($dbh))
		{
			$ok = 3;
		}
	}
	return $ok;
}




#----------------------------------------
# Didl
#----------------------------------------


sub getDidl
{
	my ($this) = @_;
    display($dbg_didl,0,"getDidl($this->{id}) type=$this->{type}  title=$this->{title}");

	my $dlna_stuff = $this->dlna_content_features();
	my $pretty_duration = millis_to_duration($this->{duration},1);
	my $mime_type = artisanMimeType($this->{type});
	my $url = "http://$server_ip:$server_port/media/$this->{id}.$this->{type}";

	my $art_uri = $this->{art_uri};
	$art_uri =  "http://$server_ip:$server_port/get_art/$this->{parent_id}/folder.jpg"
		if !$art_uri && ($this->{has_art} & $HAS_FOLDER_ART);

	# WMP returns top three lines, then RES, then everything else

    my $didl = "";
	$didl .= "<item id=\"$this->{id}\" parentID=\"$this->{parent_id}\" restricted=\"0\">";
    $didl .= "<dc:title>".encode_content($this->{title})."</dc:title>";
    $didl .= "<dc:creator>".encode_content($this->{album_artist})."</dc:creator>" if $this->{album_artist};

	# WMP <res> includes sampleFrequency, bitsPerSample, and nrAudioChannels,
	# that I don't have, and microsoft:codec which only it can use

	my $bitrate = "88200";
		# don't have this, so I fake it to CD quality
    $didl .= "<res ";
    $didl .= "size=\"$this->{size}\" ";
    $didl .= "duration=\"$pretty_duration\" ";
    $didl .= "bitrate=\"$bitrate\" ";
    $didl .= "protocolInfo=\"http-get:*:$mime_type:$dlna_stuff\" ";
    $didl .= ">$url</res>";

	# Everything else
    # class was object.item.audioItem
	# seems like all dc's should come before all upnp's
	# i don't include any dc:description

	# this seems to be breaking on "Jimmy Thackery & the Drivers"
	# which brings up the whole question of encoding


	$didl .= "<upnp:class>object.item.audioItem.musicTrack</upnp:class>";
	$didl .= "<upnp:genre>".encode_content($this->{genre})."</upnp:genre>" if $this->{genre};
	$didl .= "<upnp:artist>".encode_content($this->{artist})."</upnp:artist>" if $this->{artist};
    $didl .= "<upnp:album>".encode_content($this->{album_title})."</upnp:album>" if $this->{album_title};
    $didl .= "<upnp:originalTrackNumber>".encode_xml($this->{tracknum})."</upnp:originalTrackNumber>" if $this->{tracknum};

	$didl .= "<dc:date>".encode_xml($this->{year_str})."</dc:date>" if $this->{year_str};
	$didl .= "<upnp:albumArtURI>".encode_xml($art_uri)."</upnp:albumArtURI>";
    $didl .= "<upnp:albumArtist>".encode_content($this->{album_artist})."</upnp:albumArtist>" if $this->{album_artist};

	# Try including the miscrosoft specific path

	my $folder_path = pathOf($this->{path});
	$folder_path =~ s/\//\\/g;
	$didl .= "<desc id=\"folderPath\" ";
	$didl .= "nameSpace=\"urn:schemas-microsoft-com:WMPNSS-1-0/\" ";
	$didl .= "xmlns:microsoft=\"urn:schemas-microsoft-com:WMPNSS-1-0/\">";
	$didl .= "&lt;microsoft:folderPath&gt;".encode_content($folder_path)."&lt;/microsoft:folderPath&gt;";
	$didl .= "</desc>";

	# END OF DIDL

	$didl .= "</item>";
	display($dbg_didl+1,0,"pre_didl=$didl");
	$didl = encode_didl($didl);
	display($dbg_didl+2,0,"didl=$didl");
	return $didl;
}

# From WMP
#
#  <item id="4-11154" restricted="0" parentID="4">
#    <dc:title>¿Y Como Es El?</dc:title>
#    <dc:creator>José Luis Perales</dc:creator>
#    <res size="4009469"
#	 	duration="0:04:08.777"
#		bitrate="16002"
#		protocolInfo="http-get:*:audio/x-ms-wma:DLNA.ORG_PN=WMABASE;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000"
#		sampleFrequency="44100"
#		bitsPerSample="16"
#		nrAudioChannels="2"
#		microsoft:codec="{00000161-0000-0010-8000-00AA00389B71}">http://10.237.50.101:10243/WMPNSSv4/1140102379/1_NC0xMTE1NA.wma
#	</res>
#    <res duration="0:04:08.777" bitrate="176400" protocolInfo="http-get:*:audio/L16;rate=44100;channels=2:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=10;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000" sampleFrequency="44100" bitsPerSample="16" nrAudioChannels="2" microsoft:codec="{00000001-0000-0010-8000-00AA00389B71}">http://10.237.50.101:10243/WMPNSSv4/1140102379/NC0xMTE1NA.wma?formatID=50</res>
#    <res duration="0:04:08.777" bitrate="88200" protocolInfo="http-get:*:audio/L16;rate=44100;channels=1:DLNA.ORG_PN=LPCM;DLNA.ORG_OP=10;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000" sampleFrequency="44100" bitsPerSample="16" nrAudioChannels="1" microsoft:codec="{00000001-0000-0010-8000-00AA00389B71}">http://10.237.50.101:10243/WMPNSSv4/1140102379/NC0xMTE1NA.wma?formatID=47</res>
#    <res duration="0:04:08.777" bitrate="24000" protocolInfo="http-get:*:audio/mp4:DLNA.ORG_PN=AAC_ISO_320;DLNA.ORG_OP=10;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000" sampleFrequency="48000" nrAudioChannels="2" microsoft:codec="{00001610-0000-0010-8000-00AA00389B71}">http://10.237.50.101:10243/WMPNSSv4/1140102379/NC0xMTE1NA.m4a?formatID=19</res>
#    <res duration="0:04:08.777" bitrate="32000" protocolInfo="http-get:*:audio/vnd.dolby.dd-raw:DLNA.ORG_PN=AC3;DLNA.ORG_OP=10;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000" sampleFrequency="48000" nrAudioChannels="2" microsoft:codec="{E06D802C-DB46-11CF-B4D1-00805F6CBBEA}">http://10.237.50.101:10243/WMPNSSv4/1140102379/NC0xMTE1NA.wma?formatID=27</res>
#    <res duration="0:04:08.777" bitrate="24000" protocolInfo="http-get:*:audio/vnd.dlna.adts:DLNA.ORG_PN=AAC_ADTS_320;DLNA.ORG_OP=10;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000" sampleFrequency="48000" nrAudioChannels="2" microsoft:codec="{00001610-0000-0010-8000-00AA00389B71}">http://10.237.50.101:10243/WMPNSSv4/1140102379/NC0xMTE1NA.adts?formatID=31</res>
#    <res duration="0:04:08.777" bitrate="24000" protocolInfo="http-get:*:audio/mpeg:DLNA.ORG_PN=MP3;DLNA.ORG_OP=10;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=01700000000000000000000000000000" sampleFrequency="44100" nrAudioChannels="2" microsoft:codec="{00000055-0000-0010-8000-00AA00389B71}">http://10.237.50.101:10243/WMPNSSv4/1140102379/NC0xMTE1NA.mp3?formatID=59</res>
#    <upnp:class>object.item.audioItem.musicTrack</upnp:class>
#    <upnp:genre>Latin</upnp:genre>
#    <dc:publisher>EMI International</dc:publisher>
#    <upnp:artist role="AlbumArtist">Various Artists</upnp:artist>
#    <upnp:artist role="Performer">José Luis Perales</upnp:artist>
#    <upnp:author role="Composer">José Luis Perales</upnp:author>
#    <upnp:album>20 Baladas Insuperables</upnp:album>
#    <upnp:originalTrackNumber>1</upnp:originalTrackNumber>
#    <dc:date>2003-01-01</dc:date>
#    <upnp:actor role="José Luis Perales">José Luis Perales</upnp:actor>
#    <upnp:toc>14+96+4977+92F1+D21B+12167+160B4+1A961+1EFCF+237DA+278F0+2BBBF+31A3D+35791+39FD7+3E44F+42C25+474A7+4C4C0+505AC+5444D+57D4D</upnp:toc>
#    <upnp:albumArtURI dlna:profileID="JPEG_SM">http://10.237.50.101:10243/WMPNSSv4/1140102379/0_NC0xMTE1NA.jpg?albumArt=true</upnp:albumArtURI>
#    <upnp:albumArtURI dlna:profileID="JPEG_TN">http://10.237.50.101:10243/WMPNSSv4/1140102379/NC0xMTE1NA.jpg?albumArt=true,formatID=37,width=160,height=160</upnp:albumArtURI>
#    <desc id="artist" nameSpace="urn:schemas-microsoft-com:WMPNSS-1-0/" xmlns:microsoft="urn:schemas-microsoft-com:WMPNSS-1-0/">&lt;microsoft:artistAlbumArtist&gt;Various Artists&lt;/microsoft:artistAlbumArtist&gt;&lt;microsoft:artistPerformer&gt;José Luis Perales&lt;/microsoft:artistPerformer&gt;</desc>
#    <desc id="author" nameSpace="urn:schemas-microsoft-com:WMPNSS-1-0/" xmlns:microsoft="urn:schemas-microsoft-com:WMPNSS-1-0/">&lt;microsoft:authorComposer&gt;José Luis Perales&lt;/microsoft:authorComposer&gt;</desc>
#    <desc id="Year" nameSpace="urn:schemas-microsoft-com:WMPNSS-1-0/" xmlns:microsoft="urn:schemas-microsoft-com:WMPNSS-1-0/">&lt;microsoft:year&gt;2003&lt;/microsoft:year&gt;</desc>
#    <desc id="folderPath" nameSpace="urn:schemas-microsoft-com:WMPNSS-1-0/" xmlns:microsoft="urn:schemas-microsoft-com:WMPNSS-1-0/">&lt;microsoft:folderPath&gt;Shared Music\World\Tipico\Various - 20 Baladas Insuperables&lt;/microsoft:folderPath&gt;</desc>
#    <desc id="fileInfo" nameSpace="urn:schemas-microsoft-com:WMPNSS-1-0/" xmlns:microsoft="urn:schemas-microsoft-com:WMPNSS-1-0/">&lt;microsoft:fileIdentifier&gt;AMGa_id=R   662145;AMGp_id=VA;AMGt_id=T  6608953&lt;/microsoft:fileIdentifier&gt;</desc>
#  </item>




#------------------------------------------------
# Static Public Methods
#------------------------------------------------


sub dlna_content_features
	# DLNA.ORG_PN - media profile
{
	my ($this) = @_;
	my $type = $this->{type};
	my $mime_type = artisanMimeType($type);
		# we get audio/x-wma,
		# WMP returns audio/x-ms-wma
	my $contentfeatures = '';

    # $contentfeatures .= 'DLNA.ORG_PN=LPCM;' if $mime_type eq 'audio/L16';
    $contentfeatures .= 'DLNA.ORG_PN=LPCM;' if $mime_type eq 'audio/x-aiff';
    $contentfeatures .= 'DLNA.ORG_PN=LPCM;' if $mime_type eq 'audio/x-wav';
    $contentfeatures .= 'DLNA.ORG_PN=WMABASE;' if $mime_type eq 'audio/x-ms-wma';
    $contentfeatures .= 'DLNA.ORG_PN=MP3;' if $mime_type eq 'audio/mpeg';
    # $contentfeatures .= 'DLNA.ORG_PN=JPEG_LRG;' if $mime_type eq 'image/jpeg';
    # $contentfeatures .= 'DLNA.ORG_PN=JPEG_TN;' if $mime_type eq 'JPEG_TN';
    # $contentfeatures .= 'DLNA.ORG_PN=JPEG_SM;' if $mime_type eq 'JPEG_SM';

	# DLNA.ORG_OP=ab
	#   a - server supports TimeSeekRange
	#   b - server supports RANGE
    # $contentfeatures .= 'DLNA.ORG_OP=00;' if ($item->{TYPE} eq 'image');
	$contentfeatures .= 'DLNA.ORG_OP=01;';
    # $contentfeatures .= 'DLNA.ORG_OP=00;';

	# todo: DLNA.ORG_PS - supported play speeds
	# DLNA.ORG_CI - for transcoded media items it is set to 1
	$contentfeatures .= 'DLNA.ORG_CI=0;';

	# DLNA.ORG_FLAGS - binary flags with device parameters
	# WMP returns 0170000....
	$contentfeatures .= 'DLNA.ORG_FLAGS=01500000000000000000000000000000';
    # $contentfeatures .= 'DLNA.ORG_FLAGS=00D00000000000000000000000000000';

	return $contentfeatures;
}



1;
