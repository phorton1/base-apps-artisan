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
use Utils;
use Database;


our $dbg_track = 0;

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
    );
}


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
	return Library::mimeType($this->{type});
}


sub getPublicArtUri
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
    display($dbg_xml,0,"getDidl($this->{id}) type=$this->{type}  title=$this->{title}");

	my $dlna_stuff = $this->get_dlna_stuff();
	my $pretty_duration = millis_to_duration($this->{duration},1);
	my $art_uri = $this->{has_art} & 1 ?
		"http://$server_ip:$server_port/get_art/$this->{parent_id}/folder.jpg" : "";
	my $mime_type = Library::mimeType($this->{type});
	my $url = "http://$server_ip:$server_port/media/$this->{id}.$this->{type}";
	
	
    my $didl = "";
	$didl .= "<item id=\"$this->{id}\" parentID=\"$this->{parent_id}\" restricted=\"1\">";
    $didl .= "<dc:title>".encode_xml($this->{title})."</dc:title>";
	$didl .= "<upnp:class>object.item.audioItem</upnp:class>";
	$didl .= "<upnp:genre>".encode_xml($this->{genre})."</upnp:genre>";
	$didl .= "<upnp:artist>".encode_xml($this->{artist})."</upnp:artist>";
    $didl .= "<upnp:album>".encode_xml($this->{album_title})."</upnp:album>";
    $didl .= "<upnp:originalTrackNumber>".encode_xml($this->{tracknum})."</upnp:originalTrackNumber>";
    $didl .= "<dc:date>".encode_xml($this->{year_str})."</dc:date>";
	$didl .= "<upnp:albumArtURI>".encode_xml($art_uri)."</upnp:albumArtURI>";
    $didl .= "<upnp:albumArtist>".encode_xml($this->{album_artist})."</upnp:albumArtist>";

    # had to be careful with the <res> element, as
    # WDTVLive did not work when there was whitespace (i.e. cr's)
    # in my template ... so note the >< are on the same line.
	
	my $bitrate = "";
		# don't have this, so I deliver a blank
	
    $didl .= "<res ";
    $didl .= "bitrate=\"$bitrate\" ";
    $didl .= "size=\"$this->{size}\" ";
    $didl .= "duration=\"$pretty_duration\" ";
    $didl .= "protocolInfo=\"http-get:*:$mime_type:$dlna_stuff\" ";
    $didl .= ">$url</res>";
	$didl .= "</item>";
	
	display($dbg_xml+1,0,"pre_didl=$didl");
	$didl = encode_didl($didl);
	display($dbg_xml+2,0,"didl=$didl");
	return $didl;
}


	


#------------------------------------------------
# Static Public Methods
#------------------------------------------------


sub get_dlna_stuff
	# DLNA.ORG_PN - media profile
{
	my ($this) = @_;
	my $type = $this->{type};
	my $mime_type = Library::mimeType($type);
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
	$contentfeatures .= 'DLNA.ORG_FLAGS=01500000000000000000000000000000';
    # $contentfeatures .= 'DLNA.ORG_FLAGS=00D00000000000000000000000000000';

	return $contentfeatures;
}



1;
