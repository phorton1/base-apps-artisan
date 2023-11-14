#!/usr/bin/perl
#---------------------------------------
# localLibrary.pm
#---------------------------------------
# This object defines the basic API needed by
# a remoteLibrary to support the webUI


package localLibrary;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Database;
use Folder;
use Track;
use Library;
use base qw(Library);

my $dbg_llib = 0;


sub new
{
	my ($class) = @_;
	display($dbg_llib,0,"localLibrary::new()");
	my $this = $class->SUPER::new({
		local => 1,
		uuid  => $this_uuid,
		name  => $program_name });
	bless $this,$class;
	return $this;
}


#----------------------------------------------------------
# library accessors
#----------------------------------------------------------


sub getTrack
	# never called with $dbh, but API implemented for consistency
{
    my ($this,$id,$dbh) = @_;
	display($dbg_llib,0,"getTrack($id)");
	my $connected = 0;
	if (!$dbh)
	{
		$connected = 1;
		$dbh = db_connect();
	}
	my $track = Track->newFromDbId($dbh,$id);
	db_disconnect($dbh) if ($connected);
	error("could not getTrack($id)") if !$track;
	return $track;
}


sub getFolder
	# called once with $dbh, from HTTPServer::search_directory()
	# as part of the DLNA ContentServer:1 browse functionality
{
    my ($this,$id,$dbh) = @_;
	display($dbg_llib,0,"getFolder($id) dbh="._def($dbh));

	# if 0, return a fake record

	my $folder;
	if ($id eq '0')
	{
		$folder = Folder->newFromHash({
			id => 0,
			parent_id => -1,
			title => 'All Artisan Folders',
			dirtype => 'root',
			num_elements => 1,
			artist => '',
			genre => '',
			path => '',
			year => substr(today(),0,4)  });
	}
	else
	{
		my $connected = 0;
		if (!$dbh)
		{
			$connected = 1;
			$dbh = db_connect();
		}
		$folder = Folder->newFromDbId($dbh,$id);
		db_disconnect($dbh) if ($connected);
	}
	error("could not getFolder($id)") if !$folder;
	return $folder;
}


sub getSubitems
	# Called by DLNA and webUI to return the list
	# of items in a folder given by ID.  If the
	# folder type is an 'album', $table will be
	# TRACKS, to get the tracks in an album.
	# An album may not contain subfolders.
	#
	# Otherwise, the $table will be FOLDERS and
	# we are finding the children folders of the
	# given ID (which is also a leaf "class" or "genre).
	# We sort the list so that subfolders (sub-genres)
	# show up first in the list.
{
	my ($this,$table,$id,$start,$count) = @_;
    $start ||= 0;
    $count ||= 999999;
    display($dbg_llib+2,0,"get_subitems($table,$id,$start,$count)");

	my $sort_clause = ($table eq 'folders') ? 'dirtype DESC,path' : 'path';
	my $query = "SELECT * FROM $table ".
		"WHERE parent_id='$id' ".
		"ORDER BY $sort_clause";

	my $dbh = db_connect();
	my $recs = get_records_db($dbh,$query);
	db_disconnect($dbh);

	my $dbg_num = $recs ? scalar(@$recs) : 0;
	display($dbg_llib+1,1,"get_subitems($table,$id,$start,$count) found $dbg_num items");

	my @retval;
	for my $rec (@$recs)
	{
		next if ($start-- > 0);
		display($dbg_llib+2,2,pad($rec->{id},40)." ".$rec->{path});

		my $item;
		if ($table eq 'tracks')
		{
			$item = Track->newFromDb($rec);
		}
		else
		{
			$item = Folder->newFromDb($rec);
			DatabaseMain::validate_folder(undef,$rec);
		}


		push @retval,$item;
		last if (--$count <= 0);
	}

	return \@retval;

}   # get_subitems





#------------------------------------------------------
# Track MetaData
#------------------------------------------------------

sub getTrackMetadata
	# Returns an object that can be turned into json,
	# that is the entire treegrid that will show in
	# the right pane of the explorer page.
	#
	# For the localLibrary this includes a tree of
	# three subtrees:
	#
	# - the Track database record
	# - the mediaFile record
	# - low level MP3/WMA/M4A tags
{
	my ($this,$id) = @_;
	display($dbg_llib,0,"getTrackMetadata($id)");

	my $track = $this->getTrack($id);
	return [] if !$track;

	my $use_id = 0;
	my $sections = [];

	push @$sections, meta_section(\$use_id,'Database',1,$track);

	# a section that shows the resolved "mediaFile"
	# section(s) that shows the low level tags

	my $info = MediaFile->new($track->{path});
	if (!$info)
	{
		error("no mediaFile($track->{path}) in item_tags request!");
		# but don't return error (show the database anyways)
	}
	else
	{
		# the errors get their own section

		my $merrors = $info->get_errors();
		delete $info->{errors};

		push @$sections,meta_section(\$use_id,'mediaFile',0,$info,'^raw_tags$');

		# show any mediaFile warnings or errors
		# we need err_num to keep the keys separate to call json()

		if ($merrors)
		{
			my @errors;
			my @sorted = sort {$$b[0] <=> $$a[0]} @$merrors;
			for my $e (@sorted)
			{
				push @errors,[$$e[0],severity_to_str($$e[0]),$$e[1]];
			}
			push @$sections,error_section(\$use_id,'mediaFileErrors',1,\@errors);
		}

		# then based on the underlying file type, show the raw tag sections
		# re-reading a lot of stuff for m4a's

		if ($$info{type})
		{
			if ($$info{type} eq 'wma')
			{
				push @$sections,meta_section(\$use_id,'wmaTags',0,$$info{raw_tags}->{tags});
				push @$sections,meta_section(\$use_id,'wmaInfo',0,$$info{raw_tags}->{info});
			}
			elsif ($$info{type} eq 'm4a')
			{
				push @$sections,meta_section(\$use_id,'m4aTags',0,$$info{raw_tags}->{tags});
				push @$sections,meta_section(\$use_id,'m4aInfo',0,$$info{raw_tags}->{info});
			}

			else
			{
				push @$sections,meta_section(\$use_id,'mp3Tags',0,$$info{raw_tags});
			}
		}
	}

	return $sections;
}




#---------------------------------
# folder meta data
#---------------------------------


sub getFolderMetadata
{
	my ($this,$id) = @_;
	display($dbg_llib,0,"getTrackMetadata($id)");

	my $folder = $this->getFolder($id);
	return [] if !$folder;

	my $use_id = 0;
	my $sections = [];

	push @$sections, meta_section(\$use_id,'Database',1,$folder);

	return $sections;
}






1;