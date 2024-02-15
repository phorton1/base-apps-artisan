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
#	find

package localLibrary;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Track;
use Folder;
use Library;
use Database;
use base qw(Library);


my $dbg_llib = 0;
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
		name  => "Artisan(".getMachineId().")",
		ip    => $server_ip,
		port  => $server_port,
		online => time(),
		state  => $DEVICE_STATE_READY });
	bless $this,$class;
	return $this;
}


sub dataDir
{
	return $data_dir;
}


#----------------------------------------------------------
# API
#----------------------------------------------------------

sub getTrack
	# never called with $dbh, but API implemented for consistency
{
    my ($this,$id,$dbh,$dbg) = @_;
	$dbg = $dbg_llib if !defined($dbg);
	display($dbg,0,"getTrack($id)");
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
    my ($this,$id,$dbh,$dbg) = @_;
	$dbg = $dbg_llib if !defined($dbg);
	display($dbg,0,"getFolder($id) dbh="._def($dbh));

	# if 0, return a fake record

	my $folder;
	my $def = localPlaylist::getPlaylistDefById($id);

	if ($id eq '0')
	{
		$folder = $this->virtualRootFolder();
	}
	elsif ($id eq $ID_PLAYLISTS)
	{
		$folder = $this->virtualPlaylistsFolder();
	}
	elsif ($def)
	{
		$folder = $this->virtualPlaylistFolder($def);
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
		db_disconnect($dbh) if $connected;
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


	my $def = localPlaylist::getPlaylistDefById($id);

	# return virtual folders for playlists
	# table must be 'folders'

	if ($table eq 'folders' && $id eq $ID_PLAYLISTS)
	{
		my $defs = localPlaylist::getPlaylistDefs();
		if ($defs && @$defs)
		{
			my $num_defs = @$defs;
			display($dbg_subitems,1,"found $num_defs defaultPlaylists");
			my $max = $start+$count-1;
			$max = $num_defs-1 if $max > $num_defs-1;
			for my $i ($start .. $max)
			{
				my $def = $defs->[$i];
				my $folder = $this->virtualPlaylistFolder($def);
				if ($folder)
				{
					push @retval,$folder;
					$num++;
				}
			}
		}
	}

	# get tracks from playlist
	# table  must be tracks

	elsif ($table eq 'tracks' && $def)
	{
		my $recs = localPlaylist::getTracks($def,$start,$count);
		if ($recs)
		{
			display($dbg_subitems,1,"found ".scalar(@$recs)." playlist tracks");
			for my $rec (@$recs)
			{
				my $track = Track->newFromHash($rec);
				if ($track)
				{
					push @retval,$track;
					$num++;
				}
			}
		}
	}

	# regular query from database

	# else
	# {
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
			my $folder = $this->virtualPlaylistsFolder();
			push @retval,$folder if $folder;
		}

	# }

    display($dbg_subitems,1,"get_subitems() returning ".scalar(@retval)." items");
	return \@retval;

}   # get_subitems





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

	my $file_path = dbToFilePath($track->{path});
	my $info = MediaFile->new($file_path);
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
	my ($this) = @_;
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
	my ($this) = @_;
	display($dbg_virt,0,"virtualPlaylistsFolder()");
	my $defs = localPlaylist::getPlaylistDefs();
	return if !$defs;
	my $num_defs = @$defs;
	return if !$num_defs;

	return Folder->newFromHash({
		id => $ID_PLAYLISTS,
		parent_id => 0,
		title => 'playlists',
		dirtype => 'section',
		num_elements => $num_defs,
		artist => '',
		genre => '',
		path => '\playlists',
		year => substr(today(),0,4)  });
}


sub virtualPlaylistFolder
{
	my ($this,$def) = @_;
	my $name = $def->{name};
	display($dbg_virt,0,"virtualPlaylistFolder($name)");

	return Folder->newFromHash({
		id => $def->{id},
		parent_id => $ID_PLAYLISTS,
		title => $name,
		dirtype => 'playlist',
		num_elements => $def->{count},
		artist => '',
		genre => '',
		path => "/playlists/$name",
		year => substr(today(),0,4)  });
}



#-------------------------------------------
# Playlist API
#-------------------------------------------

sub getPlaylists
	# pass through
{
	my ($this) = @_;
	display($dbg_llib,0,"getPlaylists()");
	return Playlist::getPlaylists($this);
}



sub getPlaylist
	# pass thru
{
	my ($this,$id) = @_;
	display($dbg_llib,0,"getPlaylist($id)");
	return Playlist::getPlaylist($this,$id);
}


sub getPlaylistTrack
{
    my ($this,$id,$version,$mode,$index) = @_;
	display($dbg_llib,0,"getPlaylist($id,$version,$mode,$index)");
	my $playlist = Playlist::getPlaylist($this,$id);
	return if !$playlist;
	return $playlist->getPlaylistTrack($version,$mode,$index);
}


sub sortPlaylist
{
    my ($this,$id,$shuffle) = @_;
	display($dbg_llib,0,"sortPlaylist($id,$shuffle)");
	my $playlist = Playlist::getPlaylist($this,$id);
	return if !$playlist;
	return $playlist->sortPlaylist($shuffle);
}





#------------------------------------
# find
#------------------------------------

my $dbg_find = 0;


sub clause
{
	my ($field,$value) = @_;
	return "$field LIKE \"%$value%\"";
}


sub find
{
	my ($this,$params) = @_;

	my $where_clause = '';
	my $any = url_decode($params->{any} || '');
	my $album = url_decode($params->{album} || '');
	my $title = url_decode($params->{title} || '');
	my $artist = url_decode($params->{artist} || '');

	display($dbg_find,0,"find($any,$album,$title,$artist)");

	if ($any)
	{
		$where_clause = "(" .
			clause('title',$any) . " OR ".
			clause('artist',$any) . " OR ".
			clause('album_title',$any) . " OR ".
			clause('album_artist',$any) . ")";
	}
	if ($album)
	{
		$where_clause .= " AND " if $where_clause;
		$where_clause .= "(" . clause('album_title',$album) . ")";
	}
	if ($title)
	{
		$where_clause .= " AND " if $where_clause;
		$where_clause .= "(" . clause('title',$title) . ")";
	}
	if ($artist)
	{
		$where_clause .= " AND " if $where_clause;
		$where_clause .= "(" .
			clause('artist',$artist) . " OR ".
			clause('album_artist',$artist) . ")";
	}

	if (!$where_clause)
	{
		return error("NO fields specified for find");
	}

	my $query = "SELECT * FROM tracks WHERE $where_clause ORDER BY path";

	display($dbg_find,1,"query = $query");

	my $dbh = db_connect();
	my $recs = get_records_db($dbh,$query);
	db_disconnect($dbh);

	display($dbg_find,1,"found ".scalar(@$recs)." recs");
	return error("NO records found") if !@$recs;

	my $tracks = [];
	for my $rec (@$recs)
	{
		display($dbg_find,2,"track($rec->{path}");
		push @$tracks,Track->newFromDb($rec);
	}

	return $tracks;

}




1;