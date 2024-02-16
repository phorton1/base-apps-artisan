#!/usr/bin/perl
#---------------------------------------
# Folder.pm
#
# Can be constructed from a local database
# or a hash hash from the scan.
#
# The ID is generated from a md5 checksum of the path.
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


package Folder;
use strict;
use warnings;
use threads;
use threads::shared;
use Digest::MD5 'md5_hex';
use Database;
use artisanUtils;
use XMLSoap;


my $dbg_folder = 0;
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
	return containingPath($this->{path});
}



#------------------------------------------------------------------
# Construction
#------------------------------------------------------------------

sub new
	# create without a path
{
	my ($class) = @_;
	my $this = db_init_rec('folders');
	bless $this,$class;
	return $this;
}



my $next_folder_id:shared = 0;

sub newFromHash
	# sets the id to the md5 hash of the path
	# sets dirty bit
{
	my ($class,$hash) = @_;
	if (!$hash->{path})
	{
		if ($hash->{dirtype} && $hash->{dirtype} eq "root")
		{
			# it is ok to create an empty root record in memory
		}
		else
		{
			error("Attempt to create folder without path. dirtype=$hash->{dirtype}");
			return;
		}
	}

	my $this = $class->new();
	mergeHash($this,$hash);

	# create id if it does not already exist

	if (!defined($this->{id}) || $this->{id} eq "")
	{
		if (1)
		{
			if ($this->{path})
			{
				$this->{id} = md5_hex($this->{path});
			}
			else	# special case of the root node /mp3s
			{
				$this->{id} = "0";
			}
		}
		else
		{
			$this->{id} = $next_folder_id++;
		}
	}

	$this->{dirty} = 1;
	return $this;
}


sub newFromDb
{
	my ($class,$rec) = @_;
	my $this = $class->newFromHash($rec);
	if ($this)
	{
		$this->{dirty} = 0;
		$this->{exists} = 1;
	}
	return $this;
}



sub newFromDbId
	# database folders add in-memory exists=1 field
	# so save knows whether to do an update() or an insert
{
	my ($class,$dbh,$id) = @_;
	my $this = undef;
	my $rec = get_record_db($dbh,"SELECT * FROM folders WHERE id='$id'");
	if ($rec)
	{
		$this = $class->newFromHash($rec);
		if ($this)
		{
			$this->{exists} = 1;
		}
	}
	return $this;
}



sub insert
{
	my ($this,$dbh) = @_;
	if (!defined($this->{id}))
	{
		error("attempt to insert folder without an id!!",0,1);
		# My::Utils::display_hash(0,0,"this",$this);
		return;
	}
	if (insert_record_db($dbh,'folders',$this))
	{
		$this->{dirty} = 0;
		$this->{exists} = 1;
	}
	else
	{
		error("could not insert folder($this->{id}} $this->{title} into folder database");
		return;
	}
	return $this;
}



sub save
	# returns 1=ok, 2=updated, 3=inserted
{
	my ($this,$dbh,$force) = @_;
	if (!defined($this->{id}) || $this->{id} eq "")
	{
		error("attempt to save folder without an id!!");
		return;
	}

	my $ok = 1;
	if ($this->{dirty} || $force)
	{
		display($dbg_folder+1,1,"saving dirty="._def($this->{dirty})." exists="._def($this->{exists})." Folder(" . pathName($this->{path}).")");
		if ($this->{exists})
		{
			if (update_record_db($dbh,'folders',$this))
			{
				$this->{dirty} = 0;
				$ok = 2;
			}
			else
			{
				error("could not update folder($this->{id}} $this->{title} in folder database");
				return;
			}
		}
		elsif ($this->insert($dbh))
		{
			$ok = 3;
		}
	}
	else
	{
		display(0,1,"not saving clean Folder(" . pathName($this->{path}).")");

	}
	return $ok;
}




#----------------------------------------
# Didl
#----------------------------------------


sub getDidl
{
	my ($this) = @_;
    display($dbg_didl,0,"getDidl($this->{id})");

    my $container = $this->{dirtype} eq 'album' ?
        'object.container.album.musicAlbum' :
		'object.container';

	my $art_uri = $this->{art_uri};
	$art_uri = "http://$server_ip:$server_port/get_art/$this->{id}/folder.jpg"
		if !$art_uri && $this->{has_art};

	my $didl = "<container ";
    $didl .= "id=\"$this->{id}\" ";
    $didl .= "restricted=\"1\" ";
    $didl .= "parentID=\"$this->{parent_id}\" ";
    $didl .= "childCount=\"$this->{num_elements}\" ";
    $didl .= "searchable=\"1\" ";
	$didl .= ">";


	# The class is either the root 'container' type, or the
	# final 'album.musicAlbum' type.

    $didl .= "<dc:title>". encode_content($this->{title}) ."</dc:title>";
    $didl .= "<upnp:class name=\"$container\">$container</upnp:class>";
	$didl .= "<upnp:writeStatus>NOT_WRITABLE</upnp:writeStatus>";

	# WMP returns a list of all the possible container types a folder can
	# be in a sublist of upnp:SearchClass containing the
	# container type which we can used by the client filter our results
	# down to folders they are interested in.

	if (1)
	{
		my @album_types = qw(
			item.audioItem:0
			container:0
			container.storageFolder:0
			item.audioItem.musicTrack:0
			container.album.musicAlbum:0
			item.audioItem.audioBook:0
		);

		my @playlist_types = qw(
			item.audioItem:0
			container:0
			container.storageFolder:0
			item.audioItem.musicTrack:0
			container.album.musicAlbum:0
			item.audioItem.audioBook:0
		);

		my @section_types = qw(
			container:0
			container.storageFolder:0
			container.album.musicAlbum:1
			item.audioItem:1
			item.audioItem.audioBook:1
			item.audioItem.musicTrack:1
		);

		my @root_types = qw(
			item.audioItem:1
			container.playlistContainer:0
			container:0
			container:1
			container.storageFolder:0
			container.genre.musicGenre:0
			item.audioItem.musicTrack:0
			container.album.musicAlbum:0
			item.audioItem.audioBook:0
			container.album:1
			container.person.musicArtist:0 );

		my $use_types =
			($this->{dirtype} eq 'root')  ? \@root_types :
			($this->{dirtype} eq 'section') ? \@section_types :
			($this->{dirtype} eq 'playlist') ? \@playlist_types :
			\@album_types;


		for my $combined_type (@$use_types)
		{
			my ($type,$derived) = split(/:/,$combined_type);
			$didl .= "<upnp:searchClass includeDerived=\"$derived\">";
			$didl.= "object.$type";
			$didl .= "</upnp:searchClass>";
		}
	}

	# these fields only included for music albums

	if ($this->{dirtype} eq 'album')
	{
		$didl .= "<upnp:genre>". encode_content($this->{genre}) ."</upnp:genre> ";
		$didl .= "<upnp:artist>". encode_content($this->{artist}) ."</upnp:artist> ";
		$didl .= "<upnp:albumArtist>". encode_content($this->{artist}) ."</upnp:albumArtist> ";
		$didl .= "<dc:date>$this->{year_str}</dc:date> ";
		$didl .= "<upnp:albumArtURI>". encode_xml($art_uri) ."</upnp:albumArtURI> ";
	}

	$didl .= "</container>";
	display($dbg_didl+1,0,"pre_didl=$didl");
	$didl = encode_didl($didl);
	display($dbg_didl+2,0,"didl=$didl");
	return $didl;
}





#------------------------------------------------
# Static Public Methods
#------------------------------------------------


sub dlna_content_features
	# DLNA.ORG_PN - media profile
{
	my ($this) = @_;
	my $type = $this->{type};
	my $mime_type = artisanMimeType($type);
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
