#---------------------------------------
# Library.pm
#---------------------------------------

# Prh - taxonomy, esp Pop and what it means for initing new stations
# Prh - check_text_files.pm to check fpcalc_info and change_history text files

# All paths in the system are relative to the
# root $mp3_dir defined in UTIL.  Paths in the
# database do not start with slashes.

# Here's how to copy only changed/newer files from the mp3 tree
# to the thumb drive for the car stereo
#
# xcopy  c:\mp3s d:\mp3s /d /y /s /f

# PRH - need a general mechanism to rename change_history
# and other related persistent track datafiles that are based
# on stream_md5, when the stream_md5 changes in Library.pm.

# PRH - may need to remove unused _data/change_history files
# via special cleanup step.  It' obnoxious if they remain around
# after a file is delete.

# PRH - with REVERT_TIMESTAMPS it can be obnoxious to copy an
# old(est) oopy of a track into the tree ... the library scan
# does not see it as changed.  May need a touch() method, or
# to remove the fpcalc_info and change_history for the file
# to trigger a re-scan of the MediaFile metadata.

# PRH - it is obnoxious in the webUI browser when the detail
# tags include long TXXX MusicBrainz Album Artist type tags,
# etc, as the short ones at the top don't show initially.
# Splitter-pane?  maxColumnWidth?  

package Library;
use strict;
use warnings;
use threads;
use threads::shared;
use File::Basename;
use Utils;
use Database;
use MediaFile;
use History;
# use Library2;


appUtils::set_alt_output(1);

# BEGIN {$modules_as_libraries=1}
# use x_Artist;
 	

BEGIN
{
    use Exporter qw( import );
	our @EXPORT = qw (
	
		$HAS_STATION_MODULE
		
		get_folder
		get_track
        get_subitems
    );
};


	
my $REVERT_TIMESTAMPS = 1;
	# if set, artisan will maintain the earliest
	# timestamp for track files in the history.
my $CLEANUP_DATABASE = 1;
	# remove unused database records at end of each scan	
my $CLEANUP_FPCALC_FILES = 1;
my $CLEANUP_UNUSED_CHANGE_HISTORY_FILES = 1;
	# remove unused fpcalc text files at end of each scan

my $FIND_MISSING_ART = 0;
    # to look for missing folder.jpg
my $VIRTUAL_TREES = 0;
	# to build virtual trees
my $WITH_ARTISTS = 0;


our $HAS_STATION_MODULE = 0;
	# The only explicit dependency in this code
	# on Stations.pm is to build the initia default
	# station text files if we re-create the database.
	# Artisan.pm can choose to include the station file
	# or not, and this pm file can be used independent
	# of it.


my $exclude_re = '^_';
my $rescan_time = 1800;
    # every half hour
my $dbg_count = 0;


#---------------------------------------------
# utils
#---------------------------------------------

sub myMimeType
{
    my ($filename) = @_;
    return 'audio/mpeg'         if ($filename =~ /\.mp3$/i);	# 7231
    return 'audio/x-m4a'        if ($filename =~ /\.m4a$/i);    # 392
	return 'audio/x-ms-wma'     if ($filename =~ /\.wma$/i);    # 965
	return 'audio/x-wav'        if ($filename =~ /\.wav$/i);    # 0
	# mp4 files are not currently playable
	# return 'audio/mp4a-latm'    if ($filename =~ /\.m4p$/i);
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


sub propogate_highest_error
	# given a MediaFile error level on a track,
	# bubble it up through the track's album,
	# and the albums parents.
{
	my ($params,$track) = @_;
	my $level = $track->{HIGHEST_ERROR};
	my $folders_by_id = $params->{folders_by_id};
	my $folder = $folders_by_id->{$track->{PARENT_ID}};
	while ($folder)
	{
		if ($level > $folder->{new_high})
		{
			$folder->{new_high} = $level;
		}
		$folder = $folders_by_id->{$folder->{PARENT_ID}};
	}
	
	# stats (can be commented out for performance)
	
	for my $code (split(/,/,$track->{ERROR_CODES}))
	{
		my $severity_str = severity_to_str(code_to_severity($code));
		bump_stat("TRACK_ERROR($severity_str,$code)=".error_code_str($code));
	}
		
}


sub propogate_highest_folder_error
	# given a folder new_high error level
	# bubble it up through the parent folders
{
	my ($params,$in_folder) = @_;
	my $level = $in_folder->{new_folder_high};
	my $folders_by_id = $params->{folders_by_id};
	my $folder = $folders_by_id->{$in_folder->{PARENT_ID}};
	while ($folder)
	{
		if ($level > $folder->{new_folder_high})
		{
			$folder->{new_folder_high} = $level;
		}
		$folder = $folders_by_id->{$folder->{PARENT_ID}};
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
        folders => {},
		folders_by_id => {},
        tracks => {},
		artists => {},
		
		file_md5_tracks => {},
		stream_md5_tracks => {},

		# change detection to rebuild virtual treees
		# only keeps track of changes that might matter
		# and that amounts to a track or folder being
		# deleted. Virtual folders don't really care
		# if the attributes of a track or folder change.
		# unless a folder becomes an album or vice versa
		
		num_tracks_deleted => 0,
		num_folders_deleted => 0,
		num_folders_changed => 0,
		
	};
}



sub scanner_thread
{
    my ($one_time) = @_;

	my $first_time = 1;
	appUtils::set_alt_output(1);

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

		if ($WITH_ARTISTS)
		{
			artist::init_artists($params,1);
				push @marks, [ time(), 'init_artists' ];
		}
        get_db_recs($params);
			push @marks, [ time(), 'get_db_recs' ];
        scan_directory($params,0,$mp3_dir);
			push @marks, [ time(), 'scan_directories' ];
		do_cleanup($params);
			push @marks, [ time(), 'do_cleanup' ];
	    
		if ($WITH_ARTISTS)
		{
			artist::finalize_artists($params);
				push @marks, [ time(), 'finalize_artists' ];
		}
		
		if ($VIRTUAL_TREES)
		{
			my $rebuild =
				$params->{num_tracks_deleted} ||
				$params->{num_folders_deleted} ||
				$params->{num_folders_changed} ? 1 : 0;
				
			create_virtual_trees($params,$rebuild);		
			push @marks, [ time(), 'create_virtual_trees' ];
		}
		
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
		
		if ($is_new_database && $first_time && $HAS_STATION_MODULE)
		{
			Station::setDefaultStations();
		}
		
		$first_time = 0;
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
	
    my $folders = get_records_db($dbh,"SELECT * FROM FOLDERS");
    LOG(1,"found ".scalar(@$folders)." folders");
	bump_stat('init_db_folders',scalar(@$folders));
    for my $folder (@$folders)
    {
        $params->{folders}->{$folder->{FULLPATH}} = $folder;
        $params->{folders_by_id}->{$folder->{ID}} = $folder;
    }
	
    my $tracks = get_records_db($dbh,"SELECT * FROM TRACKS");
    LOG(1,"found ".scalar(@$tracks)." tracks");
	bump_stat('init_db_tracks',scalar(@$folders));
    for my $track (@$tracks)
    {
        $params->{tracks}->{$track->{FULLNAME}} = $track;
		$params->{file_md5_tracks}->{$track->{FILE_MD5}} = $track;
		$params->{stream_md5_tracks}->{$track->{STREAM_MD5}} = $track;
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
		'TRACKS',
		'FULLNAME',
		'num_tracks_deleted',
		'file_deleted');
	return if !del_unused_items(
		$params,
		$folders,
		'FOLDERS',
		'FULLPATH',
		'num_folders_deleted',
		'folder_deleted',
		$folders_by_id);
	return if !del_unused_text_files(
		$params,
		$CLEANUP_FPCALC_FILES,
		'FILE_MD5',
		'fpcalc_info');
	return if !del_unused_text_files(
		$params,
		$CLEANUP_UNUSED_CHANGE_HISTORY_FILES,
		'STREAM_MD5',
		'change_history');
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

	# commite before, and after, for safety
	
	$params->{dbh}->commit();
	display($dbg_library-1,0,($CLEANUP_DATABASE?"DELETE":"SHOW")." UNUSED $table");
	
	for my $path (sort(keys(%$hash)))
	{
		my $item = $hash->{$path};
		if (!$item->{exists})
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
				delete $other_hash->{$item->{ID}} if ($other_hash);
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
    my $recs =   get_records_db($params->{dbh},"select $field_id from TRACKS");
    display($dbg_library-1,1,"mark ".scalar(@$recs)." of ".scalar(keys(%id_used)." $subdir filenames as used"));
    for my $rec (@$recs)
    {
        my $id = $rec->{$field_id};
        if (!$id_used{$id})
        {
            warning(0,0,"NO $subdir file for $field_id=$id  path=$rec->{FULLNAME}");
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
		if ($deleting && $field_id eq 'STREAM_MD5')
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
            my $mime_type = myMimeType($entry);
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
	
	$folder->{new_high} = 0;
	$folder->{new_folder_high} = 0;
	
    for my $file (@files)
    {
        my $file = add_track($params,$folder,$dir,$file);
		return if !$file;
    }

	# do the subfolders
	
    for my $subdir (@subdirs)
    {
        return if !scan_directory($params,$folder->{ID},"$dir/$subdir");
    }

	# validate this folder
	
	validate_folder($params,$folder);

	# if the folder was changed after we got it's ID,
	# we need to rewrite it.  This will always happen
	# with new folders that have album art, since we
	# set the ART_URI right after we created the record.
	# We also check if the highest level for the folder
	# has changed as result of the scan
	
	my $dbh = $params->{dbh};
	if ($folder->{changed} ||
		$folder->{new_high} != $folder->{HIGHEST_ERROR} ||
		$folder->{new_folder_high} != $folder->{HIGHEST_FOLDER_ERROR})
	{
		display(9,0,"folder_update_changed $folder->{FULLPATH}") if $folder->{changed};
		display(9,0,"folder_update_new_high old=$folder->{HIGHEST_ERROR} new=$folder->{new_high}") if $folder->{new_high} != $folder->{HIGHEST_ERROR};
		display(9,0,"folder_update_new_folder_high old=$folder->{HIGHEST_FOLDER_ERROR} new=$folder->{new_folder_high}") if $folder->{new_folder_high} != $folder->{HIGHEST_FOLDER_ERROR};

		bump_stat("folder_update_changed") if $folder->{changed};
		bump_stat("folder_update_new_high") if $folder->{new_high} != $folder->{HIGHEST_ERROR};
		bump_stat("folder_update_new_folder_high") if $folder->{new_folder_high} != $folder->{HIGHEST_FOLDER_ERROR};
		
		$folder->{HIGHEST_ERROR} = $folder->{new_high};
		$folder->{HIGHEST_FOLDER_ERROR} = $folder->{new_folder_high};
		if (!update_record_db($dbh,'FOLDERS',$folder))
		{
			error("Could not update final FOLDER record for $dir");
			return;
		}
	}
	
	# commit changes on each completed directory
	
	$dbh->commit();
	return 1;
}



sub set_folder_error
{
	my ($params,$folder,$error_level,$message) = @_;
	display($dbg_library+2,0,"set_folder_error($error_level,$message) on $folder->{FULLPATH}");

	$folder->{errors} ||= [];
	push @{$folder->{errors}},{level=>$error_level,msg=>$message};

	$folder->{FOLDER_ERROR} ||= 0;
	$folder->{FOLDER_ERROR} = $error_level if ($error_level>$folder->{FOLDER_ERROR});
	# finished - handle the results
	
	if ($params && $error_level  > $folder->{new_folder_high})
	{
		$folder->{new_folder_high} = $error_level;
		propogate_highest_folder_error($params,$folder);
	}
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
	
	if ($folder->{DIRTYPE} eq 'album')
	{
		# check that the folder name equals the artist - title
		# make sure it has exactly two parts
		
		my $check_artist = $folder->{ARTIST};
		$check_artist =~ s/&/and/g;
		
		my @parts = split(/ - /,$folder->{NAME});
		if ($folder->{CLASS} =~ /^Dead/)
		{
			#if ($folder->{NAME} ne $folder->{TITLE})
			#{
			#	set_folder_error($params,$folder,$ERROR_MEDIUM,"Misnamed dead folder");
			#}
			
			if (@parts != 1)
			{
				set_folder_error($params,$folder,$ERROR_MEDIUM,"Dash in dead folder name");
			}				
		}			
		elsif ($folder->{CLASS} ne "")
		{
			# 2015-06-20 as of today the folder TITLE comes back with ' _ ' converted to ' - '
			# and since the folder artist/title ALWAYS comes from the name, this check is not
			# particularly useful
			#
			#if ($folder->{NAME} ne "$folder->{ARTIST} - $folder->{TITLE}")
			#{
			#	set_folder_error($params,$folder,$ERROR_MEDIUM,"Misnamed folder");
			#}
			
			if (@parts != 2)
			{
				set_folder_error($params,$folder,$ERROR_HIGH,"Expected 'artist - title' folder name");
			}
			elsif ($check_artist !~ /^various$/i &&
				   $check_artist !~ /^original soundtrack$/i &&
				   !(-f "$cache_dir/artists/$check_artist.txt"))
			{
				set_folder_error($params,$folder,$ERROR_HIGH,"Unknown artist '$folder->{ARTIST}'");
			}
		}			
			
		
		# check for HAS_ART on all albums/singles (class ne '')
		
		if (!$folder->{HAS_ART})
		{
			set_folder_error($params,$folder,$ERROR_LOW,"No folder art");
		}
		
	}
}


#-------------------------------------------------
# add folder
#-------------------------------------------------

sub add_folder
	# add the folder to the tree
{
	my ($params,$parent_id,$in_dir,$subdirs,$files) = @_;
	my $dbh = $params->{dbh};
		
	# parse the mp3_relative relative folder name
	
	my $use_path = mp3_relative($in_dir);
	my $split = split_dir(0,$use_path,$files);
	my $is_album = $split->{type} eq 'album';
	my $num_elements = $is_album ? @$files : @$subdirs;

	bump_stat("type_folder_$split->{type}");
	
	# see if the folder already exists in
	# the database, and add it if it doesn't.
	# setting the 'new' bit.
	
	my $folder = $params->{folders}->{$use_path};
	if (!$folder)
	{
		display($dbg_library,0,"add_folder($use_path)");
		bump_stat('folder_added');

		$folder = db_init_folder();
		$folder->{PARENT_ID} = $parent_id;
		$folder->{DIRTYPE}   = $split->{type};
		$folder->{FULLPATH}  = $use_path;
		$folder->{PATH}      = $split->{path};
		$folder->{NAME}      = $split->{name};
		$folder->{CLASS}     = $split->{class};
		$folder->{HAS_ART}   = (-f "$in_dir/folder.jpg") ? 1 : 0;
		bump_stat("has_".($folder->{HAS_ART}?'':'no_')."art");
		
		# set album metadata fields
		
        $folder->{GENRE}     = $is_album ? $split->{class} : '';
		$folder->{TITLE}     = $is_album ? clean_str($split->{album_title}) : $folder->{NAME};
		$folder->{ARTIST}    = $is_album ? clean_str($split->{album_artist}) : '';		
		$folder->{NUM_ELEMENTS} = $num_elements;
		$folder->{ROTATION} = 0;
		
		# insert record into database
		# and re-get it so that we have the folder id,
		# which we need for ART_URI 
		# which means we set exists AFTER the insert

		if (!insert_record_db($dbh,'FOLDERS',$folder))
		{
			error("Could not insert FOLDER record for $use_path");
			return;
		}
		$folder = get_record_db($dbh,"SELECT * FROM FOLDERS WHERE FULLPATH=?",[$use_path]);

		if (!$folder)
		{
			error("Could not re-get FOLDER record for $use_path");
			return;
		}
		if (!$folder->{ID})
		{
			error("no folder ID returned by insert_record");
			return;
		}
		
		# the folder id is now valid
		
		$folder->{exists} = 1;
        $params->{folders}->{$folder->{FULLPATH}} = $folder;
        $params->{folders_by_id}->{$folder->{ID}} = $folder;
	}

	# Here we notice if the number of elements changed,
	# the presence of folder.jpg changed, or the folder type
	# changed.
	#
	# Note that folder type change implies class type change,
	# which in-turn, implies a genre change
	#
	# We don't mark the folder as changed 'yet'.
	#
	# $num_elements will be incorrect for rare cases where
	# a track does not get added correctly due to an error.
	
	else
	{
		$folder->{exists} = 1;
		my $has_art = (-f "$in_dir/folder.jpg") ? 1 : 0;
		bump_stat("has_".($has_art?'':'no_')."art");
		
		if ($folder->{NUM_ELEMENTS} != $num_elements ||
			$folder->{DIRTYPE} ne $split->{type} ||
			$folder->{HAS_ART} ne $has_art)
		{
			display($dbg_library,0,"folder_change($in_dir)");
			$params->{num_folders_changed} ++;
				# special meaning - it has changed types and
				# virtual trees need to be rebuilt
				
			bump_stat('folder_changed');
			$folder->{DIRTYPE} = $split->{type};
			$folder->{HAS_ART} = $has_art;
			
			my $rslt = db_do($dbh,"UPDATE FOLDERS SET ".
					"DIRTYPE=?,".
					"HAS_ART=?,".
					"CLASS=?,".
					# "ART_URI=?,".
					"GENRE=?,".
					"NUM_ELEMENTS=? ".
					"WHERE ID='$folder->{ID}'",
				[ $split->{type},
				  $has_art,
				  $split->{class},
				  # $folder->{ART_URI},
				  $is_album ? $split->{class} : '',
				  $num_elements 
				]);
			
			if (!$rslt)
			{
				error("Could not update2 FOLDERS for $use_path");
				return;
			}
			
			$folder->{changed} = 0;
		}
		else
		{
			bump_stat("folder_unchanged");
		}
	}
	
	# add any new artist found to the in memory data
	# structure, making no assumptions about their type

	if ($WITH_ARTISTS &&
		$folder->{ARTIST} &&
		!artist::get_artist($params,$folder->{ARTIST}))
	{
		artist::new_artist(
			"dir:$use_path",
			$params,
			$folder->{ARTIST},
			'', # $folder->{CLASS},
			'');
	}
	
	return $folder;
}



#-------------------------------------------------
# add_track
#-------------------------------------------------


sub	add_track
	# add or update a track in the database
	# We get or initialize a new record, then get
	# metadata as needed, and then, at the end of
	# the routine, insert or update the record as needed.
	# NOTE that new in-memory records don thave their ID set!
	# PRH - NOT SURE THIS IS WORTH THE 10 ms ..
{
	my ($params,$folder,$in_dir,$file) = @_;
	display(0,-1,"Scanning $dbg_count") if ($dbg_count % 100) == 0;
	$dbg_count++;

	my $path = mp3_relative($in_dir);
    my $fullname = "$path/$file";
	
    if (0)
    {
        use Encode;
        use utf8;
        # display_bytes(0,0,(utf8::is_utf8($path)?"UTF8":"PERL")." path0=$path",$path);
        $path = Encode::decode("utf-8",$fullname);
        # display_bytes(0,0,(utf8::is_utf8($path)?"UTF8":"PERL")." path1=$path",$path);
        utf8::downgrade($fullname);
        # display_bytes(0,0,(utf8::is_utf8($path)?"UTF8":"PERL")." path2=$path",$path);
    }
	
	
	my $mime_type = myMimeType($file);
	my $ext = $file =~ /.*\.(.*?)$/ ? $1 : error("no file extension!");
   	my @fileinfo = stat("$in_dir/$file");
	my $size = $fileinfo[7];
	my $timestamp = $fileinfo[9];
    my $track = $params->{tracks}->{$fullname};
	if (00 && $track && $fullname =~ /Marc Broussard - Momentary Setback\/04/)
	{
		unlink "$cache_dir/fpcalc_info/$track->{FILE_MD5}.txt";
		$track->{TIMESTAMP} = 0
	}

    bump_stat('tot_bytes',$fileinfo[7]);
	bump_stat($mime_type);

	# set bit to get metadata if the file changed
	# or we need to look for album art

	my $info;
	my $get_meta_data = 0;
	$get_meta_data = 1 if
		!$track ||
		$track->{TIMESTAMP} != $timestamp ||
		($track->{HAS_ART} && !$folder->{HAS_ART} && $FIND_MISSING_ART);
		
	if ($get_meta_data)
	{
		$info = MediaFile->new($fullname);
		bump_stat('meta_data_get');
		if (!$info)
		{
			error("Could not get MediaFile($fullname)");
			exit 1;
		}
	}
		
	# change detection

	my $history_rec;
	my $write_history = 0;
	my $delete_stream_md5 = '';

	# if the track does not exist, it is an error
	# to create a new track with an STREAM_MD5 or
	# FILE_MD5 that points to an existing file.
	
	if (!$track)
	{
		bump_stat("file_added");
		display($dbg_library,0,"add_track($file)");
		my $old_file_md5 = $info->{file_md5};
		my $old_stream_md5 = $info->{stream_md5};
		my $old_file_track = $params->{file_md5_tracks}->{$old_file_md5};
		my $old_stream_track = $params->{stream_md5_tracks}->{$old_stream_md5};
		
		display($dbg_library+1,1,"old_file_md5=$old_file_md5   track="._def($old_file_track));
		display($dbg_library+1,1,"old_stream_md5=$old_stream_md5   track="._def($old_stream_track));
			
		if ($old_file_track && -f "$mp3_dir/$old_file_track->{FULLNAME}")
		{
			error("DUPLICATE file_md5($old_file_md5) AT $fullname\nOTHER=$old_file_track->{FULLNAME}");
			exit 1;
		}
		if ($old_stream_track && -f "$mp3_dir/$old_stream_track->{FULLNAME}")
		{
			error("DUPLICATE stream_md5($old_stream_md5) AT $fullname\nOTHER=$old_stream_track->{FULLNAME}");
			exit 1;
		}

		# get the history in both cases
		
		$history_rec = get_track_change_history($old_stream_md5);

		# if there is an $old_stream_track, then the file has
		# been renamed or moved. Get the history for the $old_stream_track,
		# and mark a file change event.
	
		if ($old_stream_track)
		{
			bump_stat("file moved/renamed");
			my ($diff1,$diff2) = compare_path_diff($old_stream_track->{FULLNAME},$fullname);
			warning(0,1,"File($old_stream_md5) moved/renamed from \"$diff1\" to \"$diff2\"");

			if (!$history_rec)
			{
				error("Could not find existing history for old_stream_md5=$old_stream_md5");
				exit 1;
			}
			add_track_change_history_event($history_rec,$timestamp,"moved/renamed from \"$diff1\" to \"$diff2\"");
			$write_history = 1;
			
			# delete the old_file_tracks
			# and old_stream_id tracks
			# with an assertion that they are
			# the same if both exist
			
			if ($old_file_track)
			{
				display($dbg_library,1,"removing old file_md5($old_file_md5) from hash");
				if ($old_file_track->{ID} ne $old_stream_track->{ID})
				{
					error("HUH?  old_file_track_id($old_file_track->{ID}) ne old_stream_track($old_stream_track->{ID}) in $fullname");
					exit 1;
				}
				delete $params->{file_md5_tracks}->{$old_file_md5};
			}

			display($dbg_library,1,"Remove old track($old_stream_md5)=$old_stream_track->{ID}=$old_stream_track->{FULLNAME}");
			if (!db_do($params->{dbh},"delete from TRACKS where ID='$old_stream_track->{ID}'"))
			{
				error("Could not remove old track($old_stream_md5)=$old_stream_track->{ID}");
				exit 1;
			}
		
			delete $params->{stream_md5_tracks}->{$old_stream_md5};
			delete $params->{tracks}->{$old_stream_track->{FULLNAME}};
		}
		else
		{
			if (!$history_rec)
			{
				display($dbg_library,1,"creating new history file for $old_stream_md5");
				$history_rec = new_track_change_history($old_stream_md5,$timestamp,"initial setting");
				$write_history = 1;
			}
			else
			{
				display($dbg_library,1,"got existing history for $old_stream_md5");
			}
		}
		
		# CONTINUING TO CREATE A NEW RECORD

		$track = db_init_track();
		$track->{new}       = 1;
		$track->{exists}    = 1;
		$track->{PARENT_ID} = $folder->{ID};
		$track->{FULLNAME}  = $fullname;
		$track->{PATH}      = $path;
		$track->{NAME}      = $file;
		$track->{FILEEXT}   = $ext;
        $track->{TIMESTAMP} = $timestamp;
        $track->{SIZE}      = $size;
        $track->{MIME_TYPE} = $mime_type;
		$track->{FILE_MD5}  = $info->{file_md5};
		$track->{STREAM_MD5}= $info->{stream_md5};
		$track->{ROTATION}  = 0;
		$track->{ERROR_CODES} = $info->{error_codes};
		$track->{HIGHEST_ERROR} = 0;
	}
	else
	{
		$track->{exists} = 1;
		
		if ($track->{TIMESTAMP} != $timestamp)
		{
			bump_stat("file_changed");
			display($dbg_library,1,"timestamp changed from ".
				History::dateToLocalText($track->{TIMESTAMP}).
				"  to ".History::dateToLocalText($timestamp).
				" in file($fullname)");
			
			display($dbg_library,1,"track file_md5=$track->{FILE_MD5}  stream_md5=$track->{STREAM_MD5}");
			display($dbg_library,1,"info file_md5=$info->{file_md5}  stream_md5=$info->{stream_md5}");
			
      		$track->{SIZE} = $size;
			$track->{FILE_MD5} = $info->{file_md5};
			
			$track->{TIMESTAMP} = $timestamp;
			$track->{ERROR_CODES} = $info->{error_codes};
			$track->{HIGHEST_ERROR} = 0;
			
			$track->{changed} = 1;
			
			# get the history record for the old_id and if the 
			# stream_md5 changed, mark the old history for deletion,
			# and remove the stream_md5 from the hash
			# remove the file_md5 from the hash if it changed.
			# Add a history event for the timestamp change.
			
			my $old_stream_md5 = $track->{STREAM_MD5};
			$history_rec = get_track_change_history($old_stream_md5);
			if (!$history_rec)
			{
				error("Could not find existing history for existing track $old_stream_md5");
				exit 1;
			}
			
			if ($old_stream_md5 ne $info->{stream_md5})
			{
				$track->{STREAM_MD5} = $info->{stream_md5};
				bump_stat("timestamp history marked for deletion");
				display($dbg_library,1,"stream_md5($old_stream_md5) changed to $info->{stream_md5} in $fullname .. deleting old one");

				add_track_change_history_event($history_rec,$timestamp,"stream_md($old_stream_md5) changed to $info->{stream_md5}");
				delete $params->{stream_md5_tracks}->{$old_stream_md5};
				$delete_stream_md5 = $old_stream_md5;
			}

			if ($track->{FILE_MD5} ne $info->{file_md5})
			{
				display($dbg_library,1,"removing unused file_md5($$track->{FILE_MD5}) from hash");
				delete $params->{file_md5_tracks}->{$track->{FILE_MD5}};
			}
				
			add_track_change_history_event($history_rec,$timestamp,"timestamp_changed");
			$write_history = 1;
		}
		else
		{
			bump_stat("file_unchanged");
		}
	}

	# Revert file timestamp if needed
	
	if (!$track || $track->{changed})
	{
		my $first_history_timestamp = get_oldest_history_timestamp($history_rec);
		if ($REVERT_TIMESTAMPS && $timestamp != $first_history_timestamp)
		{
			bump_stat("timestamp_reverted");
			bump_stat("timestamp_reverted in existing track");
			warning(0,1,"Reverting timestamp on existing track($info->{stream_md5})=$fullname");
			display($dbg_library,2,"new=".History::dateToLocalText($timestamp)."   old=".History::dateToLocalText($first_history_timestamp));
			exit 1 if !setTimestampGMTInt("$mp3_dir/$fullname",$first_history_timestamp);
			$track->{TIMESTAMP} = $first_history_timestamp;
			add_track_change_history_event($history_rec,$first_history_timestamp,"reverting");
			$write_history = 1;
		}
	}

	# process the metadata as needed
	# may set track->{changed}
	# We also re-initialize the error level for the track
	
	if ($get_meta_data)
	{
		if (!get_meta_data($params,$track,$folder,$info))
		{
			error("Could not get meta_data for track ($file)");
			exit 1;
		}
	}
	
	# check for a change to highest error
	
	my $highest = highest_severity($track->{ERROR_CODES});
	if ($highest != $track->{HIGHEST_ERROR})
	{
		$track->{HIGHEST_ERROR} = $highest;
		$track->{changed} = 1;
	}
	
	# write the record if it's new or needs to be updated
	
	my $dbh = $params->{dbh};
	if ($track->{new})
	{
		if (!insert_record_db($dbh,'TRACKS',$track))
		{
			error("Could not insert TRACK record for $fullname");
			exit 1;
		}
        $params->{tracks}->{$track->{FULLNAME}} = $track;
		$track->{changed} = 0;
	}
	elsif ($track->{changed})
	{
		if (!update_record_db($dbh,'TRACKS',$track))
		{
			error("Could not update TRACK record for $fullname");
			exit 1;
		}
		$track->{changed} = 0;
	}

	# add it to in-memory hashes in every case

	$params->{tracks}->{$fullname} = $track;
	$params->{file_md5_tracks}->{$track->{FILE_MD5}} = $track;
	$params->{stream_md5_tracks}->{$track->{STREAM_MD5}} = $track;
	
	# propogate the highest error level upwards
	
	propogate_highest_error($params,$track);
	
	# write the new history, and delete
	# the old one if need be
	
	if ($write_history && !write_track_change_history($track->{STREAM_MD5},$history_rec))
	{
		error("Could not write history($track->{STREAM_MD5}) for $fullname");
		exit 1;
	}
	if ($delete_stream_md5 && !delete_track_change_history($delete_stream_md5))
	{
		error("Could not delete old history($delete_stream_md5) for $fullname");
		exit 1;
	}
	
	# add any new artist found to the in memory data
	# structure, making no assumptions about their type
	
	if ($WITH_ARTISTS &&
		$track->{ARTIST} &&
		!artist::get_artist($params,$track->{ARTIST}))
	{
		artist::new_artist(
			"file:$fullname",
			$params,
			$track->{ARTIST},
			'', # $folder->{CLASS},
			'');
	}
	if ($WITH_ARTISTS &&
		$track->{ALBUM_ARTIST} &&
		!artist::get_artist($params,$track->{ALBUM_ARTIST}))
	{
		artist::new_artist(
			"file:$fullname",
			$params,
			$track->{ALBUM_ARTIST},
			'', # $folder->{CLASS},
			'');
	}
		
	
	return 1;
}
	
	
#-------------------------------------------------
# add_track subfunctions
#-------------------------------------------------

my $test_pic_num = '000000';

sub get_meta_data
{
	my ($params,$track,$folder,$info) = @_;
	
	# set and note any changes in the meta_data
	# and set the 'changed' bit so it gets written

	my $meta_changed = '';
	my @meta_fields = qw(artist album title genre year tracknum duration album_artist has_art);
	for my $field (@meta_fields)
	{
		my $new = $info->{$field} || '';
		my $old = $track->{uc($field)} || '';
		if ($new ne $old)
		{
			$meta_changed .= $field."='$new' (old='$old'),";
			$track->{uc($field)} = $new;
		}
	}

	# update the database if anything changed

	if ($meta_changed)
	{
		$track->{changed} = 1;
		if (!$track->{new})
		{
			display($dbg_library+1,1,"metadata($meta_changed) changed for $track->{NAME}");
			bump_stat("meta_data_changed");
		}
	}
	else
	{
		display($dbg_library+1,1,"metadata unchanged for $track->{NAME}");
		bump_stat("meta_data_unchanged");
	}

	# fix the folders missing art problem if possible
	
	if ($track->{HAS_ART} &&
		!$folder->{HAS_ART} &&
		$FIND_MISSING_ART )
	{
		bump_stat("missing_art_checked");
		display($dbg_library+1,0,"checking missing art from $track->{FULLNAME}");
		my @pics = $info->get_pictures();
		if (!@pics)
		{
			error("huh - track HASART but no pics returned from MediaFile!");
		}
		else
		{
			if (0)	# debugging
			{
				for (my $i=0; $i<@pics; $i++)
				{
					my $jpeg = $pics[$i];
					dump_jpg("/junk/test_pics/test_pic.".($test_pic_num++).".jpg",$jpeg);
				}
			}
			
			my $selected = pop(@pics);
			if ($selected)
			{
				bump_stat("missing_art_found");
				$folder->{changed} = 1;
				$folder->{HAS_ART} = dump_jpg(
					"$mp3_dir/$folder->{FULLPATH}/folder.jpg",
					$selected);
			}
		}
	}	# look for missing art
	
	return 1;
}



sub	dump_jpg
{
	my ($ofile,$jpeg) = @_;
	LOG(0,"WRITING JPEG  to $ofile");
	if (!open(OFILE,">$ofile"))
	{
		error("Could not open $ofile for writing");
		return 0;
	}
	binmode OFILE;
	print OFILE $jpeg;
	close OFILE;
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
	
	if ($id eq '0')
	{
		return {
			ID => 0,
			PARENT_ID => -1,
			TITLE => 'All Artisan Folders',
			DIRTYPE => 'root',
			NUM_ELEMENTS => 1,
			ARTIST => '',
			GENRE => '',
			YEAR => substr(today(),0,4),
		};
	}
	
	return get_virtual_item($dbh,'FOLDERS',$1)
		if ($id && $VIRTUAL_TREES && $id =~ /^([a-z]\d+)$/);

    my $rec = get_record_db($dbh,"SELECT * FROM FOLDERS WHERE ID='$id'");
    return $rec;
}


sub get_track
{
    my ($dbh,$id) = @_;
	return get_virtual_item($dbh,'TRACKS',$1)
		if ($id && $VIRTUAL_TREES && $id =~ /^([a-z]\d+)$/);
    my $rec = get_record_db($dbh,"SELECT * FROM TRACKS WHERE ID='$id'");
    return $rec;
}


sub get_folder_parent_id
{
	my ($dbh,$id) = @_;
    display($dbg_library+1,0,"get_folder_parent($id)");
	my $folder = get_folder($dbh,$id);
	return $folder ? $folder->{PARENT_ID} : - 1;
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

	# check for virtual item request
	
	return get_virtual_subitems($dbh,$table,$1,$start,$count)
		if ($id && $VIRTUAL_TREES && $id =~ /^([a-z]\d+)$/);

    if ($id !~ /^\d+$/)
	{
		error("Unknown id in get_subitems: $id");
		return [];
	}
	
	my $sort_clause = ($table eq 'FOLDERS') ? 'DIRTYPE DESC,' : '';

	my $query = "SELECT * FROM $table ".
		"WHERE PARENT_ID='$id' ".
		"ORDER BY $sort_clause NAME";
	my $recs = get_records_db($dbh,$query);

	# add the virtual roots

	add_virtual_roots($dbh,$recs) if ($VIRTUAL_TREES && $id == 0);
	
	my $dbg_num = $recs ? scalar(@$recs) : 0;
	display($dbg_library,1,"get_subitems($table,$id,$start,$count) found $dbg_num items");
	
	my @recs;
	for my $rec (@$recs)
	{
		next if ($start-- > 0);
		display($dbg_library,2,pad($rec->{ID},5)." ".pad($rec->{NAME},30)." ".$rec->{PATH});
		push @recs,$rec;
		last if (--$count <= 0);
	}

	return \@recs;

}   # get_subitems




1;
