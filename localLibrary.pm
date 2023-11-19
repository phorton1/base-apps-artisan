#!/usr/bin/perl
#---------------------------------------
# localLibrary.pm
#---------------------------------------
# This object defines the basic API needed to support the webUI
#
# API
#	getTrack
#	getFolder
#	getSubitems
#	getPlaylist
#	getPlaylists
#	getTrackMetadata
#	getFolderMetadata


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
use localPlaylist;
use base qw(Library);

my $dbg_llib = -2;
my $dbg_virt = 1;
my $dbg_subitems = 0;


my $ID_PLAYLISTS = 'playlists';


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
# API
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
	my $playlist = localPlaylist::getPlaylist($id);

	if ($id eq '0')
	{
		$folder = virtualRootFolder();
	}
	elsif ($id eq $ID_PLAYLISTS)
	{
		$folder = virtualPlaylistsFolder();
	}
	elsif ($playlist)
	{
		$folder = virtualPlaylistFolder($id);
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
    display($dbg_subitems,0,"get_subitems($table,$id,$start,$count)");

	my $num = 0;
	my @retval;
	my $playlist = localPlaylist::getPlaylist($id);

	# return virtual folders for playlists
	# table must be 'folders'

	if ($table eq 'folders' && $id eq $ID_PLAYLISTS)
	{
		my $names = localPlaylist->getPlaylistNames();
		display($dbg_subitems,1,"found ".scalar(@$names)." playlists");
		my $max = $start+$count-1;
		$max = @$names-1 if $max > @$names-1;
		for my $i ($start .. $max)
		{
			my $folder = virtualPlaylistFolder($names->[$i]);
			if ($folder)
			{
				push @retval,$folder;
				$num++;
			}
		}
	}

	# get tracks from playlist
	# table  must be tracks

	elsif ($table eq 'tracks' && $playlist)
	{
		my $recs = $playlist->getTracks();
		display($dbg_subitems,1,"found ".scalar(@$recs)." playlist tracks");
		my $max = $start+$count-1;
		$max = @$recs-1 if $max > @$recs-1;
		for my $i ($start .. $max)
		{
			my $rec = $recs->[$i];
			my $track = Track->newFromHash($rec);
			if ($track)
			{
				push @retval,$track;
				$num++;
			}
		}
	}

	# regular query from database

	else
	{
		my $sort_clause = ($table eq 'folders') ? 'dirtype DESC,path' : 'path';
		my $query = "SELECT * FROM $table ".
			"WHERE parent_id='$id' ".
			"ORDER BY $sort_clause";

		my $dbh = db_connect();
		my $recs = get_records_db($dbh,$query);
		db_disconnect($dbh);

		display($dbg_subitems,1,"found ".scalar(@$recs)." $table records");

		my $max = $start+$count-1;
		$max = @$recs-1 if $max > @$recs-1;

		for my $i ($start .. $max)
		{
			my $rec = $recs->[$i];

			display($dbg_subitems+1,2,pad($rec->{id},40)." ".$rec->{path});

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

			if ($item)
			{
				$num++;
				push @retval,$item;
			}

			# last if (--$count <= 0);
		}

		# add virtual playlists folder

		if ($id eq '0' && $num < $count)
		{
			$num++;
			push @retval,virtualPlaylistsFolder();
		}
	}

    display($dbg_subitems,1,"get_subitems() returning ".scalar(@retval)." items");
	return \@retval;

}   # get_subitems


sub getPlaylist
	# pass thru
{
	my ($this,$id) = @_;
	return localPlaylist::getPlaylist($id);
}

sub getPlaylists
	# pass through
{
	my ($this) = @_;
	return localPlaylist::getPlaylists();
}


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





#-----------------------------------------------
# Implementation
#-----------------------------------------------

sub virtualRootFolder
{
	display($dbg_virt,0,"virtualRootFolder()");
	return Folder->newFromHash({
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

sub virtualPlaylistsFolder
{
	display($dbg_virt,0,"virtualPlaylistsFolder()");
	return Folder->newFromHash({
		id => $ID_PLAYLISTS,
		parent_id => 0,
		title => 'playlists',
		dirtype => 'section',
		num_elements => scalar(@{localPlaylist::getPlaylists()}),
		artist => '',
		genre => '',
		path => '\playlists',
		year => substr(today(),0,4)  });
}


sub virtualPlaylistFolder
{
	my ($name) = @_;		# the id is the name of the playlist
	display($dbg_virt,0,"virtualPlaylistsFolder($name)");
	my $playlist = localPlaylist::getPlaylist($name);
	return !error("Could not find localPlalist($name)")
		if !$playlist;

	return Folder->newFromHash({
		id => $name,
		parent_id => $ID_PLAYLISTS,
		title => $name,
		dirtype => 'playlist',
		num_elements => $playlist->{num_tracks},
		artist => '',
		genre => '',
		path => "/playlists/$name",
		year => substr(today(),0,4)  });
}


#------------------------------------------------------
# Track MetaData
#------------------------------------------------------






1;