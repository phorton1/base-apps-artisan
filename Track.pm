#!/usr/bin/perl
#---------------------------------------
# Track.pm
#
# Can be constructed from a local database or a hash from the scan.
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
use Database;


my $dbg_track = 0;


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








1;
