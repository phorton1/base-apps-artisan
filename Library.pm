#---------------------------------------
# Library.pm
#---------------------------------------
# Does the library scan, building the folder and tracks database.
#
# Depends on the lower level MediaFile object, which itself maintains
# the cache of fpcalc_info text files and calling my_fpCalc as necessary
# to get the STREAM_MD5 for the track, which acts as a PERSISTENT UNIQUE
# TRACK_ID (id) in the database.  This ID will be the same even if the
# database is rebuilt.
#
#    The scan of tracks is done incrementally for speed,
#    based on certain assumptions.
#
#        If the path and timestamp have not changed
#           we assume the file has not changed
#        If the file does not exist, or the timestamp has
#           changed, we call MediaFile.  MediaFile does
#           a (quick) file_md5 checksum on the file, and uses
#           that to try to find the STREAM_MD5 (fpcalc_info)
#        If Mediafile cannot find the STREAM_MD5 it then does
#           the (slow) call to get and cache the fpCalc info
#           and return the STREAM_MD5.
#        Interestingly, the metadata itself is relatively quick.
#
# Folders get an id that is the md5 checksum of their $path
#
# By default, if there is no database found, this module will create one.
#
#---------------------------------------------------------------------
# NOTES
#---------------------------------------------------------------------
# All paths in the system are relative to the $mp3_dir defined in Utils.
# Paths in the database do not start with slashes.
#
# Here's how to copy only changed/newer files from the mp3 tree
# to the thumb drive for the car stereo
# 	xcopy  c:\mp3s d:\mp3s /d /y /s /f


package Library;
use strict;
use warnings;
use threads;
use threads::shared;
use File::Basename;
use Utils;
use Database;
use MediaFile;
use Folder;
use Track;


My::Utils::set_alt_output(1);


BEGIN
{
    use Exporter qw( import );
	our @EXPORT = qw (
		get_folder
		get_track
        get_subitems
		myMimeType
    );
};


	

my $CLEANUP_DATABASE = 1;
	# remove unused database records at end of scan	
my $CLEANUP_FPCALC_FILES = 0;
	# remove unused fpcalc_info files at end of scan


my $exclude_re = '^_';
my $rescan_time = 1800;
    # every half hour

my $dbg_count = 0;


#---------------------------------------------
# utils
#---------------------------------------------


sub mimeType
{
	my ($type) = @_;
    return 'audio/mpeg'         if ($type =~ /^mp3$/i);	   # 7231
    return 'audio/x-m4a'        if ($type =~ /^m4a$/i);    # 392
	return 'audio/x-ms-wma'     if ($type =~ /^wma$/i);    # 965
	return 'audio/x-wav'        if ($type =~ /^wav$/i);    # 0
	# mp4 files are not currently playable
	# return 'audio/mp4a-latm'    if ($filename =~ /\.m4p$/i);
	return '';
}


sub pathMimeType
{
    my ($filename) = @_;
	return mimeType($1) if ($filename =~ /.*\.(.*)$/);
    return '';
}


sub funny
	# for tf 'filename has funny characters in it'
{
    my ($s) = @_;
    return ($s =~ /([^ ().,!&'_\-A-Za-z0-9])/) ? 1 : 0;
}


sub clean_str
	# remove trailing and leading whitespace
	# and always return at least ''
{
    my ($s) = @_;
    $s ||= '';
    $s =~ s/^\s*//;
    $s =~ s/\s*$//;
	return $s;
}


sub propogate_highest_track_error
	# given a MediaFile error level on a track,
	# bubble it up through the track's album,
	# and the albums parents.
{
	my ($params,$track) = @_;
	my $level = $track->{highest_error};
	my $folders_by_id = $params->{folders_by_id};
	my $folder = $folders_by_id->{$track->{parent_id}};

	# display(0,0,"propogate_highest_error($track->{id}) parent=$track->{parent_id}");
	
	while ($folder)
	{
		if ($level > $folder->{new_highest_track_error})
		{
			$folder->{new_highest_track_error} = $level;
		}
		# display(0,1,"propogate($folder->{id}) parent_id=$folder->{parent_id} getting "._def($folders_by_id->{$folder->{parent_id}}));
		$folder = $folders_by_id->{$folder->{parent_id}};
	}
	
	# stats (can be commented out for performance)
	
	for my $code (split(/,/,$track->{error_codes}))
	{
		my $severity_str = severity_to_str(code_to_severity($code));
		bump_stat("TRACK_ERROR($severity_str,$code)=".error_code_str($code));
	}
		
}


sub propogate_highest_folder_error
	# given a folder new_highest_track_error error level
	# bubble it up through the parent folders
{
	my ($params,$in_folder) = @_;
	my $level = $in_folder->{new_highest_folder_error};
	my $folders_by_id = $params->{folders_by_id};
	my $folder = $folders_by_id->{$in_folder->{parent_id}};

	# display(0,0,"propogate_highest_folder_error($in_folder->{id}) parent_id=$folder->{parent_id}");
	
	while ($folder)
	{
		if ($level > $folder->{new_highest_folder_error})
		{
			$folder->{new_highest_folder_error} = $level;
		}
		# display(0,1,"propogate($folder->{id}) parent_id=$folder->{parent_id} getting "._def($folders_by_id->{$folder->{parent_id}}));
		$folder = $folders_by_id->{$folder->{parent_id}};
	}
}



sub setTimestampGMTInt
{
	my ($filename,$int) = @_;
	display($dbg_library,0,"setTimestsampGMTInt($int,$filename)");
	my $rslt = utime $int,$int,$filename;
	if (!$rslt)
	{
		error("Could not set timestamp($int) on $filename");
	}
	return $rslt;
}



#----------------------------------------------------------
# library scanner
#----------------------------------------------------------

sub init_params
{
    my ($dbh) = @_;
    return {
        dbh => $dbh,
		
		# We start by getting the existing folders and tracks
		# into hashes, for speed.
		
        folders => {},			# folders by path
		folders_by_id => {},	# folders by (integer) FOLDER_ID
        tracks => {},			# tracks by path
		tracks_by_id => {},		# tracks by (stream_md5) TRACK_ID
		file_md5_tracks => {},	# tracks by file_md5 (detect unused fpCalc files)

		# Statistic gathered during the scan

		num_tracks_deleted => 0,
		num_folders_deleted => 0,
		num_folders_changed => 0,
		
	};
}



sub scanner_thread
{
    my ($one_time) = @_;

	My::Utils::set_alt_output(1);

	LOG(0,"Starting scanner_thread()");
	while(1)
	{
    	LOG(0,"scanning directories ...");
		init_stats();

		$dbg_count = 0;

		my $dbh = db_connect();
		$dbh->{AutoCommit} = 0;
        my $params = init_params($dbh);
		
		my @marks;
		push @marks, [ time(), 'started' ];

        get_db_recs($params);
			push @marks, [ time(), 'get_db_recs' ];
        scan_directory($params,"",$mp3_dir);
			push @marks, [ time(), 'scan_directories' ];
		do_cleanup($params);
			push @marks, [ time(), 'do_cleanup' ];
	    
		my $total_time = $marks[ @marks-1 ]->[0] - $marks[0]->[0];
		LOG(0,"directory scan took $total_time seconds");

		for (my $i=1; $i<@marks; $i++)
		{
			my $desc = $marks[$i]->[1];
			my $dur = $marks[$i]->[0] - $marks[$i-1]->[0];
			LOG(0,"    ".pad($dur." secs",10)." $desc");
		}
		dump_stats('');  # undef is just this module!
		
		db_disconnect($dbh);
		undef $params;
		
        return if ($one_time);
		sleep($rescan_time);
	}
}


	

#------------------------------------------------
# initial and final passes
#------------------------------------------------

sub get_db_recs
	# get folders and tracks from the database
	# set needs_scan == 2 for cleanup
	# wonder if these should be hashed by ID?
{
    my ($params) = @_;
    LOG(0,"get_db_recs()");
	my $dbh = $params->{dbh};
	
    my $folders = get_records_db($dbh,"SELECT * FROM folders");
    LOG(1,"found ".scalar(@$folders)." folders");
	bump_stat('init_db_folders',scalar(@$folders));
    for my $rec (@$folders)
    {
		my $folder = Folder->newFromDb($rec);
        $params->{folders}->{$folder->{path}} = $folder;
        $params->{folders_by_id}->{$folder->{id}} = $folder;
    }
	
    my $tracks = get_records_db($dbh,"SELECT * FROM tracks");
    LOG(1,"found ".scalar(@$tracks)." tracks");
	bump_stat('init_db_tracks',scalar(@$folders));
    for my $rec (@$tracks)
    {
		my $track = Track->newFromDb($rec);
        $params->{tracks}->{$track->{path}} = $track;
		$params->{tracks_by_id}->{$track->{id}} = $track;
		$params->{file_md5_tracks}->{$track->{file_md5}} = $track;
    }
}




sub do_cleanup
	# remove any files or tracks which no longer exist
{
	my ($params) = @_;
	my $folders = $params->{folders};
	my $folders_by_id = $params->{folders_by_id};
	my $tracks = $params->{tracks};

	LOG(0,"do_cleanup()");
	
	return if !del_unused_items(
		$params,
		$tracks,
		'tracks',
		'path',
		'num_tracks_deleted',
		'file_deleted');
	return if !del_unused_items(
		$params,
		$folders,
		'folders',
		'path',
		'num_folders_deleted',
		'folder_deleted',
		$folders_by_id);
	return if !del_unused_text_files(
		$params,
		$CLEANUP_FPCALC_FILES,
		'file_md5',
		'fpcalc_info');
	return 1;
}
	
	


sub del_unused_items
	# if !$CLEANUP_DATABASE just displays what
	# records *would* be deleted.
{	
	my ($params,
		$hash,
		$table,
		$field_name,
		$param_inc_field,
		$bump_stat_field,
		$other_hash) = @_;

	# commit before, and after, for safety
	
	$params->{dbh}->commit();
	display($dbg_library-1,0,($CLEANUP_DATABASE?"DELETE":"SHOW")." UNUSED $table");
	
	for my $path (sort(keys(%$hash)))
	{
		my $item = $hash->{$path};
		if (!$item->{file_exists})
		{
			display($dbg_library-1,0,($CLEANUP_DATABASE?"delete":"extra")." unused $table($path)");
			# sanity check
			if (-e $path)
			{
				error("attempt to delete existing $table($path)");
				return;
			}
			
			if ($CLEANUP_DATABASE)	# do_it
			{
				if (!db_do($params->{dbh},"DELETE FROM $table WHERE $field_name=?",[$path]))
				{
					error("Could not delete $table($path)");
					return;
				}
				delete $hash->{$path};
				delete $other_hash->{$item->{id}} if ($other_hash);
			}
			$params->{$param_inc_field}++;
			bump_stat($bump_stat_field);
		}
	}
	
	$params->{dbh}->commit();
	
	return 1;
}




sub del_unused_text_files
	# Remove unused fpcalc fingerprint file that no
	# longer have tracks in the database.  Note that
	# in normal usage, this means that the database
	# has already been cleaned up to remove unused
	# track records.  If that has not been done, this
	# method is not a conclusive list of the extra
	# fpcalc files in the system.
{
	my ($params,$deleting,$field_id,$subdir) = @_;
    my %id_used;

    display($dbg_library-1,0,($deleting?"DELETE":"SHOW")." UNUSED $subdir FILES");
    if (!opendir(DIR,"$cache_dir/$subdir"))
    {
        error("Could not open $subdir dir");
        exit 1;
    }
    while (my $entry = readdir(DIR))
    {
        next if ($entry !~ s/\.txt$//);
        $id_used{$entry} = 1;
    }
    closedir(DIR);


    my $num_missing = 0;
    my $recs =   get_records_db($params->{dbh},"SELECT $field_id FROM tracks");
    display($dbg_library-1,1,"mark ".scalar(@$recs)." of ".scalar(keys(%id_used)." $subdir filenames as used"));
    for my $rec (@$recs)
    {
        my $id = $rec->{$field_id};
        if (!$id_used{$id})
        {
            warning(0,0,"NO $subdir file for $field_id=$id  path=$rec->{path}");
            $num_missing++;
        }
        else
        {
            $id_used{$id} = 2;
        }
    }
    error("MISSING $num_missing $subdir FILES") if $num_missing;


    display($dbg_library-1,1,($deleting?"delete":"show")." unused $subdir files...");
    my $num_extra = 0;
    for my $id (sort(keys(%id_used)))
    {
        next if $id_used{$id} == 2;
		if ($deleting && $field_id eq 'stream_md5')
		{
			warning(0,0,($deleting?"delete ":"")."unused $subdir file($id.txt)");
		}
		else
		{
			display($dbg_library-1,1,($deleting?"delete ":"")."unused $subdir file($id.txt)");
		}
        unlink "$cache_dir/$subdir/$id.txt" if $deleting;
        $num_extra++;
    }
    display($dbg_library,0,"FOUND $num_extra EXTRA $subdir FILES") if $num_extra;
	return 1;

}



#---------------------------------------------------------
# The main directory scanner
#---------------------------------------------------------

sub scan_directory
	# recurse through the directory tree and
	# add or update folders and tracks
{
	my ($params,$parent_id,$dir) = @_;
	bump_stat('scan_directory');

    # get @files and @subdirs

    my @files;
    my @subdirs;
    if (!opendir(DIR,$dir))
    {
        error("Could not opendir $dir");
        return;
    }
    while (my $entry=readdir(DIR))
    {
        next if ($entry =~ /^\./);
        my $filename = "$dir/$entry";
        if (-d $filename)
        {
		    next if $entry =~ /$exclude_re/;
            push @subdirs,$entry;
        }
        else
        {
            my $mime_type = pathMimeType($entry);
            if (!$mime_type)
			{
				if ($entry !~ /^(folder\.jpg)$/)
				{
					display(0,0,"unknown file: $dir/$entry");
				}
			}
			else
			{
				push @files,$entry;
				bump_stat('scan_dir_files');
	        }
		}
    }
    closedir DIR;

	# get or add the folder to the tree ...
	
	my $folder = add_folder($params,$parent_id,$dir,\@subdirs,\@files);
	return if !$folder;
	
	# get or add the tracks to the tree
	# clear the highest error found in this scan
	
	$folder->{new_highest_track_error} = 0;
	$folder->{new_highest_folder_error} = 0;
	
    for my $file (@files)
    {
        my $file = add_track($params,$folder,$dir,$file);
		return if !$file;
    }

	# do the subfolders
	
    for my $subdir (@subdirs)
    {
        return if !scan_directory($params,$folder->{id},"$dir/$subdir");
    }

	# validate this folder
	
	validate_folder($params,$folder);

	# if the folder was changed after we got it's ID,
	# we need to rewrite it.  This will always happen
	# with new folders that have album art, since we
	# set the ART_URI right after we created the record.
	# We also check if the highest level for the folder
	# has changed as result of the scan
	
	if ($folder->{dirty} ||
		$folder->{new_highest_track_error} != $folder->{highest_track_error} ||
		$folder->{new_highest_folder_error} != $folder->{highest_folder_error})
	{
		if (!$folder->{existrs})
		{
			display(9,0,"folder_update_changed $folder->{path}");
			display(9,0,"folder_update_new_highest_track_error old=$folder->{highest_track_error} new=$folder->{new_highest_track_error}") if $folder->{new_highest_track_error} != $folder->{highest_track_error};
			display(9,0,"folder_update_new_highest_folder_error old=$folder->{highest_folder_error} new=$folder->{new_highest_folder_error}") if $folder->{new_highest_folder_error} != $folder->{highest_folder_error};
	
			bump_stat("folder_update_changed");
			bump_stat("folder_update_new_highest_track_error") if $folder->{new_highest_track_error} != $folder->{highest_track_error};
			bump_stat("folder_update_new_highest_folder_error") if $folder->{new_highest_folder_error} != $folder->{highest_folder_error};
		}
		
		$folder->{highest_track_error} = $folder->{new_highest_track_error};
		$folder->{highest_folder_error} = $folder->{new_highest_folder_error};
		$folder->{dirty} = 1;
		
		if (!$folder->save($params->{dbh}))
		{
			error("Could not Save() FOLDER record for $dir");
			return;
		}
	}
	
	# commit changes on each completed directory
	
	$params->{dbh}->commit();
	return 1;
}



sub set_folder_error
{
	my ($params,$folder,$error_level,$message) = @_;
	display($dbg_library+2,0,"set_folder_error($error_level,$message) on $folder->{path}");

	$folder->{errors} ||= shared_clone([]);
	push @{$folder->{errors}},shared_clone({level=>$error_level,msg=>$message});

	$folder->{folder_error} ||= 0;
	$folder->{folder_error} = $error_level if ($error_level>$folder->{folder_error});
	# finished - handle the results
	
	if ($params && $error_level  > $folder->{new_highest_folder_error})
	{
		$folder->{new_highest_folder_error} = $error_level;
		propogate_highest_folder_error($params,$folder);
	}
}




sub nameFromPath
{
	my ($path) = @_;
	my $name = $path;
	$name = $1 if ($path =~ /^.*\/(.*?)$/);
	return $name;
}

	
sub validate_folder
	# creates an array on the object containing
	# error strings if any errors found
	# for use in webUI for folder.
	#
	# Call with params=undef for webUI.
	#
	# if params is !undef, and there are errors
	# FOLDER_ERROR will be set, and propogated
	# thru HIGHSET_ERROR to parent(s)
{
	my ($params,$folder) = @_;
	my $folder_error = 0;

	# only check 'albums' with tracks
	# no folder validity check on 'unresolved'
	# checks in incerasing order of importance
	
	if ($folder->{dirtype} eq 'album')
	{
		# check that the folder name equals the artist - title
		# make sure it has exactly two parts
		
		my $check_artist = $folder->{artist};
		$check_artist =~ s/&/and/g;
		
		my $folder_name = nameFromPath($folder->{path});
		
		my @parts = split(/ - /,$folder_name);
		if ($folder->{path} =~ /^\/Dead/)
		{
			if (@parts != 1)
			{
				set_folder_error($params,$folder,$ERROR_MEDIUM,"Dash in dead folder name");
			}				
		}			
		else
		{
		
			if (@parts != 2)
			{
				set_folder_error($params,$folder,$ERROR_HIGH,"Expected 'artist - title' folder name");
			}
			elsif ($check_artist !~ /^various$/i &&
				   $check_artist !~ /^original soundtrack$/i &&
				   !(-f "$cache_dir/artists/$check_artist.txt"))
			{
				set_folder_error($params,$folder,$ERROR_HIGH,"Unknown artist '$folder->{artist}'");
			}
		}			
			
		
		# check for has_art on all albums/singles (class ne '')
		
		if (!$folder->{has_art})
		{
			set_folder_error($params,$folder,$ERROR_LOW,"No folder art");
		}
		
	}
}


#-------------------------------------------------
# add folder
#-------------------------------------------------

sub add_folder
	# return the folder, which may only exist in
	# memory as dirty, or which may already be in
	# the database as exists and dirty, and in
	# all cases in-memory variable file_exists
	# is set, since we found it in a scan
{
	my ($params,$parent_id,$in_dir,$subdirs,$files) = @_;
		
	# parse the mp3_relative relative folder name
	
	my $path = mp3_relative($in_dir);
	my $split = split_dir(0,$path,$files);
	my $is_album = $split->{type} eq 'album';
	my $num_elements = $is_album ? @$files : @$subdirs;
	my $has_art = (-f "$in_dir/folder.jpg") ? $HAS_FOLDER_ART : 0;
	
	bump_stat("type_folder_$split->{type}");
	
	# see if the folder already exists in
	# the database, and add it if it doesn't.
	# setting the 'new' bit.
	
	my $folder = $params->{folders}->{$path};
	if (!$folder)
	{
		display($dbg_library,0,"add_folder($path) parent_id=$parent_id");

		$folder = Folder->newFromHash({
			is_local      => 1,
			parent_id 	  => $parent_id,
			dirtype   	  => $split->{type},
			path  	      => $path,
			has_art   	  => $has_art,
			genre         => $is_album ? $split->{class} : '',
			title   	  => $is_album ? clean_str($split->{album_title}) : pathName($path),
			artist        => $is_album ? clean_str($split->{album_artist}) : '',
			num_elements  => $num_elements });

		# the folder id is now valid
		
		$folder->{file_exists} = 1;
        $params->{folders}->{$folder->{path}} = $folder;
        $params->{folders_by_id}->{$folder->{id}} = $folder;
		
		bump_stat('folder_added');
		bump_stat("has_".($folder->{has_art}?'':'no_')."art");
	}

	# Here we notice if the number of elements changed,
	# the presence of folder.jpg changed, or the folder type
	# changed, if so, we update the files and set it dirty
	
	else
	{
		$folder->{file_exists} = 1;
		bump_stat("has_".($has_art?'':'no_')."art");
		
		if ($folder->{num_elements} != $num_elements ||
			$folder->{dirtype} ne $split->{type} ||
			$folder->{has_art} ne $has_art)
		{
			display($dbg_library,0,"folder_change($in_dir)");
			$params->{num_folders_changed} ++;
				# special meaning - it has changed types
				
			bump_stat('folder_changed');
			$folder->{dirtype} = $split->{type};
			$folder->{has_art} = $has_art;
			$folder->{dirty} = 1;
		}
		else
		{
			bump_stat("folder_unchanged");
		}
	}
	
	return $folder;
}



#-------------------------------------------------
# add_track
#-------------------------------------------------


sub	add_track
	# create or re-use the existin track
	# unlike folders, tracks are saved() immediately
	# We get or initialize a new record, then get
	# metadata as needed, and then, at the end of
	# the routine, save() teh track
{
	my ($params,$folder,$in_dir,$file) = @_;
	display(0,-1,"Scanning $dbg_count") if ($dbg_count % 100) == 0;
	$dbg_count++;

	#-----------------------------------
	# get the file information
	#-----------------------------------
	# and try to find the track by name
	# in the existing database ..
	
	my $dir = mp3_relative($in_dir);
    my $path = "$dir/$file";
	my $type = $file =~ /.*\.(.*?)$/ ? $1 : error("no file extension!");
   	my @fileinfo = stat("$in_dir/$file");
	my $size = $fileinfo[7];
	my $timestamp = $fileinfo[9];
    my $track = $params->{tracks}->{$path};

    bump_stat('tot_bytes',$fileinfo[7]);
	bump_stat("type_".$type);

	# set bit to get metadata if there is no database
	# record, if the timestamp changed, or if the folder
	# does not have art, and we are looking for art.

	my $info;
	my $get_meta_data = !$track || $track->{timestamp} != $timestamp  ? 1 : 0;
		
	if ($get_meta_data)
	{
		$info = MediaFile->new($path);
		bump_stat('meta_data_get');
		if (!$info)
		{
			error("Could not get MediaFile($path)");
			exit 1;
		}
		if (!$info->{id})
		{
			error("Could not get id (STREAM_MD5) from MediaFile($path)");
			exit 1;
		}
	}

	#------------------------------------------
	# change detection
	#------------------------------------------
	# Now that we have the meta_data we have the id and the FILE_MD5
	# and can use ithem to detect changes, enforce uniqueness, etc.
	#	
	# Give an error in the unlikely case that a file with same path
	# now has a different id (stream_md5)
	#
	# Note that otherwise, we assume the same filename, with the
	# same timestamp, is the same damned file!
	
	if ($track && $info && $track->{id} ne $info->{id})
	{
		error("Yikes: File '$path' has different stream_md5 in database, than that returned by MediaFile!!");
		exit 1;
	}
	
	# If there was there was no track in the database at this path
	# but there is another existing track (file) with the same id
	# it is a fatal error ...
	
	if (!$track)
	{
		my $old_track = $params->{tracks_by_id}->{$info->{id}};

		display($dbg_library,0,"add_track($path) old_track="._def($old_track));

		if ($old_track && -f "$mp3_dir/$old_track->{path}")
		{
			error("DUPLICATE STREAM_MD5 (ID) for $path\nFOUND AT OTHER=$old_track->{path}");
			exit 1;
		}
		
		# Otherwise, the old database record has a bad path  
		# (the file has moved or been renamed) and, since
		# so we are going to create a new database record,
		# we delete the old one from the database
		
		elsif ($old_track)
		{
			warning(0,0,"Track($old_track->{id}) moved from '$old_track->{path}' to '$path'");
			if (!db_do($params->{dbh},"DELETE FROM tracks WHERE id='$old_track->{id}'"))
			{
				error("Could not remove old track $old_track->{id}=$old_track->{path}");
				exit 1;
			}
			delete $params->{tracks_by_id}->{$old_track->{id}};
			delete $params->{tracks}->{$old_track->{path}};
		}
		
		# CONTINUING TO CREATE A NEW RECORD
		
		$track = Track->newFromHash({
			is_local   => 1,
			id         => $info->{id},
			parent_id  => $folder->{id},
			path  	   => $path,
			type       => $type,
			timestamp  => $timestamp,
			size       => $size,
			has_art    => $info->{has_art} | $folder->{has_art},
			file_md5   => $info->{file_md5},
			error_codes => $info->{error_codes} });

		$track->{file_exists}   = 1;
		bump_stat("file_new");

	}
	else
	{
		$track->{file_exists} = 1;
		
		if ($track->{timestamp} != $timestamp)
		{
			bump_stat("file timestamp changed");
			
			display($dbg_library,1,"timestamp changed from ".
				dateToLocalText($track->{timestamp}).
				"  to ".dateToLocalText($timestamp).
				" in file($path)");
			
      		$track->{size} = $size;
			$track->{timestamp} = $timestamp;
			$track->{error_codes} = $info->{error_codes};
			$track->{highest_error} = 0;
			$track->{dirty} = 1;
		}
		else
		{
			bump_stat("file_unchanged");
		}
		
		if (($track->{has_art} & $HAS_FOLDER_ART) != $folder->{has_art})
		{
			my $msg = $folder->{has_art} ? "added" : "removed";
			bump_stat("folder_art_$msg");
			bump_stat("folder_art_changed");
			display($dbg_library,1,"folder art $msg in $track->{title}");
			$track->{dirty} = 1;
		}
		
	}

	# process the metadata as needed
	# may set track->{dirty}
	
	if ($get_meta_data)
	{
		if (!get_meta_data($params,$track,$folder,$info))
		{
			error("Could not get meta_data for track ($file)");
			exit 1;
		}
	}
	
	# check for a change to highest error
	
	my $highest = highest_severity($track->{error_codes});
	if ($highest != $track->{highest_error})
	{
		$track->{highest_error} = $highest;
		$track->{dirty} = 1;
	}
	
	# write the record if it's new or needs to be updated
	
	if (!$track->save($params->{dbh}))
	{
		error("Could not save TRACK record for $path");
		exit 1;
	}
    
	# add it to in-memory hashes in every case

	$params->{tracks}->{$path} = $track;
	$params->{tracks_by_id}->{$track->{id}} = $track;
	
	# propogate the highest error level upwards
	# and return
	
	propogate_highest_track_error($params,$track);
	return 1;
	
}	# addTrack
	

	
#-------------------------------------------------
# add_track subfunctions
#-------------------------------------------------


sub get_meta_data
{
	my ($params,$track,$folder,$info) = @_;

	# set and note any changes in the meta_data
	# and set the 'changed' bit so it gets written

	my $meta_changed = '';
	my @meta_fields = qw(artist album_title title genre year_str tracknum duration album_artist);
	for my $field (@meta_fields)
	{
		my $new = $info->{$field} || '';
		my $old = $track->{$field} || '';
		
		if ($new ne $old)
		{
			$meta_changed .= $field."='$new' (old='$old'),";
			$track->{$field} = $new;
		}
	}

	# update the database if anything changed

	if ($meta_changed)
	{
		$track->{dirty} = 1;
		if ($track->{exists})
		{
			display($dbg_library+1,1,"metadata($meta_changed) changed for $track->{name}");
			bump_stat("meta_data_changed");
		}
	}
	else
	{
		display($dbg_library+1,1,"metadata unchanged for $track->{name}");
		bump_stat("meta_data_unchanged");
	}

	return 1;
}




#----------------------------------------------------------
# library accessors
#----------------------------------------------------------


sub get_folder
{
    my ($dbh,$id) = @_;
	display($dbg_library,0,"get_folder($id)");
		
		
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
	
	return $folder;
		
}



sub get_track
{
    my ($dbh,$id) = @_;
	my $connected = 0;
	if (!$dbh)
	{
		$connected = 1;
		$dbh = db_connect();
	}
		
	my $track = Track->newFromDbId($dbh,$id);
	
	db_disconnect($dbh) if ($connected);
	return $track;
}


sub get_folder_parent_id
{
	my ($dbh,$id) = @_;
    display($dbg_library+1,0,"get_folder_parent($id)");
	my $folder = Folder->newFromDbId($dbh,$id);
	return $folder ? $folder->{parent_id} : - 1;
}


sub get_subitems
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
	my ($dbh,$table,$id,$start,$count) = @_;
    $start ||= 0;
    $count ||= 999999;
    display($dbg_library,0,"get_subitems($table,$id,$start,$count)");

	my $sort_clause = ($table eq 'folders') ? 'dirtype DESC,path' : 'path';

	my $query = "SELECT * FROM $table ".
		"WHERE parent_id='$id' ".
		"ORDER BY $sort_clause";

	my $recs = get_records_db($dbh,$query);
	my $dbg_num = $recs ? scalar(@$recs) : 0;
	display($dbg_library,1,"get_subitems($table,$id,$start,$count) found $dbg_num items");
	
	my @retval;
	for my $rec (@$recs)
	{
		next if ($start-- > 0);
		display($dbg_library,2,pad($rec->{id},40)." ".$rec->{path});
		
		my $item;
		if ($table eq 'tracks')
		{
			$item = Track->newFromDb($rec);
		}
		else
		{
			$item = Folder->newFromDb($rec);
		}
		
		push @retval,$item;
		last if (--$count <= 0);
	}

	return \@retval;

	
}   # get_subitems




1;
