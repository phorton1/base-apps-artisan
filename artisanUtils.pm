#---------------------------------------
# artisanUtils.pm
#---------------------------------------
# Re-export of My::Utils @XPLAT with
# 	artisan specific constants, vars, and methods.
# In general Packages should not call display(), error(),
# warning(), or LOG() in their mainline body, or else they
# will inadvertantly call initUtils(0 == not a service) and
# set $AS_SERVICE to 0!! Use of print() is nominally allowed.


package artisanUtils;
use strict;
use warnings;
use threads;
use threads::shared;
use Socket;
use Sys::Hostname;
use Pub::Utils qw(!:win_only);
use Pub::ServerUtils;
use Encode;

my $FORKING_UNIX_SERVICE = 1;
my $USE_MINI_LIBRARY = 0;


our $system_update_id:shared = 1;
	# global system_update_id, currently used to detect
	# changes to devices and communicate them to the UI
our $DEVICE_STATE_NONE  = 0;
our $DEVICE_STATE_INIT  = 1;
our $DEVICE_STATE_READY = 2;
	# Initially for remoteLibraries.
	# localLibrary will start at DEVICE_STATE_READY as the database scan
	#	is completed before the Server even starts.
	# remoteLibraries will start at $DEVICE_STATE_OFFLINE
	#   if they are 'online' then,  if the playlists are being built
	#   (on a thread) the state will be INITIALIZING.
	# the UI will only show, and allow devices (Libraries) that
	#   are READY.



our $DEVICE_TYPE_LIBRARY  = 'library';
our $DEVICE_TYPE_RENDERER = 'renderer';

our $RENDERER_PLAY_QUEUE = 0;
our $RENDERER_PLAY_PLAYLIST = 1;

our $PLAYLIST_ABSOLUTE  = 0;
our $PLAYLIST_RELATIVE  = 1;
our $PLAYLIST_ALBUM_RELATIVE  = 2;


our $SHUFFLE_NONE = 0;
our $SHUFFLE_TRACKS = 1;
our $SHUFFLE_ALBUMS = 2;

our ($ERROR_NONE,					# 0 = grey = NONE = informational message
	 $ERROR_INFO,					# 1 = green = INFO = informational message of note
     $ERROR_LOW,					# 2 = blue = LOW = lowest level issue of concern
     $ERROR_MEDIUM,					# 3 = purple = MEDIUM = level issue of concern
     $ERROR_HIGH,					# 4 = yellow = HIGH = level issue of concern
     $ERROR_HARD ) = (0..5);		# 5 = red = EXTREME = highest level concern




BEGIN
{
 	use Exporter qw( import );

	# our exports
	# including re-rexport of Pub::ServerUtils $server_ip and $wifi_connected

	our @EXPORT = qw (

		$LINUX_PID_FILE

		$system_update_id
		$DEVICE_STATE_NONE
		$DEVICE_STATE_INIT
		$DEVICE_STATE_READY

		$DEVICE_TYPE_LIBRARY
		$DEVICE_TYPE_RENDERER

		$RENDERER_PLAY_QUEUE
		$RENDERER_PLAY_PLAYLIST

		$PLAYLIST_ABSOLUTE
		$PLAYLIST_RELATIVE
		$PLAYLIST_ALBUM_RELATIVE

		$SHUFFLE_NONE
		$SHUFFLE_TRACKS
		$SHUFFLE_ALBUMS

        $ERROR_NONE
        $ERROR_INFO
		$ERROR_LOW
        $ERROR_MEDIUM
        $ERROR_HIGH
        $ERROR_HARD

		%stats
		$quitting

		$program_name
        $this_uuid
        $artisan_perl_dir
		$mp3_dir
		$mp3_dir_RE
		$image_dir

		$wifi_connected
        $server_ip
        $server_port

		artisanMimeType

		severity_to_str
		code_to_severity
		highest_severity
		error_code_str

        bump_stat
        init_stats
        dump_stats

        escape_tag
        unescape_tag

        millis_to_duration
		duration_to_millis

		containingPath
		pathName
		mp3_relative
		mp3_absolute
		create_dirs
		split_dir
		compare_path_diff

		albumId

		compareTSLinux
		fileToDbPath
		dbToFilePath
	);


	# re-exports from My::Utils

	push @EXPORT, @Pub::Utils::EXPORT;

};


sub albumId
	# A method to create unique ids for albums
	# album_title, if it exists, or parent_id if not
	# for sorting the Queue and Playlists by albums
{
	my ($rec) = @_;
	return $rec->{album_title} || $rec->{parent_id};
}

#--------------------------
# globals
#--------------------------
# After changing this to use $AS_SERVICE and the new
# Pub::Utils::initUtils(1) call, I typically debug by
# cd /base/apps/artisan and executing
#
# 		 perl artisan.pm NO_SERVICE
#
# in that case, $0 returns 'artian.pm', and the
# artisan_perl_directory was set to '/' causing the
# program to not work correctly.
#
# Therefore, if the artisan_perl_directory is '/',
# we change it to ./

our %stats;
our $quitting:shared = 0;


our $artisan_perl_dir = $0;
$artisan_perl_dir =~ s/^.*://;
$artisan_perl_dir =~ s/\\/\//g;
$artisan_perl_dir = pathOf($artisan_perl_dir);
$artisan_perl_dir = "./" if $artisan_perl_dir eq '/';

our $image_dir = "$artisan_perl_dir/webUI/images";

# print "0=$0\n";
# print "perl_dir=$artisan_perl_dir\n";


our $program_name = 'Artisan Perl';

# From SSDP's point of view, there are very few constraints on the
# the structure of a uuid, although almost everyone uses the standard
#
#	56657273-696f-6e34-4d41-20231112feed
#
# dash deliminted hex character format. We use our own format
# which includes human readable names.
#
# However, there is at least one constraints on how WE use the uuid.
# Because they are sent back to us via HTTP requests, we don't want
# them to include spaces, or else those will get encoded as %20 by HTTP
# making our lookups more complicated.

our $this_uuid = $program_name."-".getMachineId();
$this_uuid =~ s/\s//g;		# remove ' ' from $program name
# OLD: $this_uuid = '56657273-696f-6e34-4d41-' . $ENV{COMPUTERNAME};	# '20231112feed';

our $mp3_dir = "/mp3s";
our $mp3_dir_RE = '\/mp3s';

if (!is_win())
{
	$mp3_dir = "/media/pi/SanDisk/mp3s";
	$mp3_dir_RE = '\/media\/pi\/SanDisk\/mp3s';
}


if ($USE_MINI_LIBRARY)
{
	$mp3_dir = "/mp3s_mini";
	$mp3_dir_RE = '\/mp3s_mini';
}


$data_dir = "$mp3_dir/_data";
$temp_dir = "/base_data/temp/artisan";
$logfile = "$temp_dir/artisan.log";
my_mkdir $temp_dir if !-d $temp_dir;


our $server_port = '8091';
#	our $server_ip = '';

our $LINUX_PID_FILE = $FORKING_UNIX_SERVICE ? "$temp_dir/artisan.pid" : '';

Pub::Utils::initUtils(1);
Pub::ServerUtils::initServerUtils(1,$LINUX_PID_FILE);


# Scanning files/albums can result in numerous
# conditions that we might want to know about.
#
# The conditions are given a two letter code that
# indicates where they arised, and what they are.
# These error codes are accumulated on the parent
# album and folders recursively.
#
# The mapping of the error codes to severity levels
# can change, depending on what I happen to be looking
# for at a given time.  Changing the mapping here
# changes what displays in the webUI, and merely
# needs a restart of Artisan(), NOT a rescan.
#
# An unmapped error is given $ERROR_HARD to highlight
# that it needs to be added to this list.

my %error_mappings = (

	# note is a special code that is not stored
	# on the track, or propogated to parents

	'note' => [ $ERROR_NONE,		'no error'],

	# m = MediaFile.pm
	# starting with highest level track errors

	'mt' => [ $ERROR_LOW,  		'Illegal track name (like 01-Track 01.mp2)'],
	'mx' => [ $ERROR_HARD, 		'Has "^bob " in the album_artist'],
	'm9' => [ $ERROR_HARD,    	'Could not open file in MediaFile::fromFileType'],

	# other media file errors

	'md' => [ $ERROR_NONE,		'Missing required metadata'],
	'mf' => [ $ERROR_INFO,		'fpcalc error'],
	'mi' => [ $ERROR_INFO,     	'Ovewriting tag album (name) with non-matching folder value after removing punctuation etc'],
	'mj' => [ $ERROR_INFO,  	'Ovewriting tag besides album (name) with non-matching folder/filename value after removing punctuation etc'],
	'mm' => [ $ERROR_MEDIUM,  	'unknown picture MIME type'],
	'mp' => [ $ERROR_MEDIUM,    'No folder.jpg in track folder'],
	'mq' => [ $ERROR_INFO,     	'APIC tag has no data in mp3 file'],
    'mr' => [ $ERROR_MEDIUM,  	'fpcalc cant parse line'],
	'mu' => [ $ERROR_HARD,    	'Unknown stream (DRM)'],
	'my' => [ $ERROR_MEDIUM,	'Track does not have a Year'],
	'mz' => [ $ERROR_MEDIUM,  	'more than five fpcalc errors'],

	# i = MP4Info.pm

	'ia' => [ $ERROR_NONE,		'MP3Info::close(abort_changes & DIRTY)'],

	# t = MP3TagList.pm

	'ta' => [ $ERROR_HIGH,		'undefined value passed to _add_tag()'],
	'tb' => [ $ERROR_INFO,		'add_tag() dropping item'],
	'tc' => [ $ERROR_HIGH,		'Unknown tag'],
	'td' => [ $ERROR_HIGH,		'v3+ tag found in v2 file'],
	'te' => [ $ERROR_HIGH,		'Version specific frame(found in different version file'],
	'tf' => [ $ERROR_HIGH,		'Dropping V4 tag while writing V3 file'],
	'tg' => [ $ERROR_HIGH,		'unknown tag in v2_to_v3_tag()'],
	'th' => [ $ERROR_HIGH,		'no mapping in v2_to_v3_tag()'],
	'ti' => [ $ERROR_NONE,		'dropping v2 tag'],
	'tj' => [ $ERROR_HIGH,		'unknown tag in v3_to_v4_tag()'],
	'tk' => [ $ERROR_HIGH,		'v3_to_v4_tag() called on incorrect version tag!'],
	'tl' => [ $ERROR_INFO,		'dropping v3->v4(TRDC) mapping'],
	'tm' => [ $ERROR_INFO,		'v3_to_v4_tag() cant map tag'],
	'tn' => [ $ERROR_HIGH,		'Unknown tag for version'],
	'to' => [ $ERROR_HIGH,		'Bad version for tag'],
	'tp' => [ $ERROR_NONE,  	'overwriting version tag with diffent value (v1 tag is not a substr of v2 tag)'],
	'tq' => [ $ERROR_INFO,		'attempt to set same tag to more than one value.'],
	'tr' => [ $ERROR_NONE,		'setting dirty due to decode'],
	'ts' => [ $ERROR_INFO,		'theres still a number in genre'],

	# r = MP3InfoRead.pm

	'ra' => [ $ERROR_HIGH,		'_get_v1_tags() could not read 128bytes'],
	'rb' => [ $ERROR_HIGH,		'ID3v2 versions older than ID3v2.2.0 not supported'],
	'rc' => [ $ERROR_HIGH,		'Version 2 compression was never supportable'],
	'rd' => [ $ERROR_MEDIUM,	'get_v2_data() read failure'],
	're' => [ $ERROR_HARD,		'Could not read end tag bytes'],
	'rf' => [ $ERROR_MEDIUM,	'loop thru frames got id=undef'],
	'rg' => [ $ERROR_INFO,		'attempt to read bytes past end'],
	'rh' => [ $ERROR_MEDIUM,	'Encrypted'],
	'ri' => [ $ERROR_MEDIUM,	'Zlib compressed frame'],
	'rj' => [ $ERROR_HIGH,		'size mismatch on frame'],
	'rk' => [ $ERROR_INFO,		'Malformed ISO-8859-1/UTF-8 text'],
	'rl' => [ $ERROR_INFO,		'Malformed UTF-16/UTF-16BE text'],
	'rm' => [ $ERROR_MEDIUM,	'invalid frame'],
	'rn' => [ $ERROR_MEDIUM,	'Bad frame size(1)'],
	'ro' => [ $ERROR_HIGH,		'Bad frame size(2)'],
	'rp' => [ $ERROR_HARD,		'Could not read 10 bytes at v2h->{offset}'],
	'rq' => [ $ERROR_MEDIUM,	'Could not read RIFFOR 10 bytes at v2h->{offset}'],
	'rr' => [ $ERROR_NONE,    	'no ID3v2 tag found'],
	'rs' => [ $ERROR_HIGH,		'unsupported major version number'],
	'rt' => [ $ERROR_HIGH,		'unsupported minor version number'],
	'ru' => [ $ERROR_HIGH,		'Bogus extended header size'],
	'rv' => [ $ERROR_HARD,		'Could not read ver3 extended header'],
	'rw' => [ $ERROR_HARD,		'Could not read ver4 extended header'],
	'rx' => [ $ERROR_LOW,		'update bit found in ... it may not be handled correctly'],
	'ry' => [ $ERROR_HARD,		'Could not read 10 bytes of footer'],
	'rz' => [ $ERROR_HIGH,		'Footer found in non v4 ID3 section'],
	'r1' => [ $ERROR_HIGH,		'invalid footer marker in ID3 section'],
	'r2' => [ $ERROR_HARD,		'Could not read three byte id3 footer recheck'],
	'r3' => [ $ERROR_HIGH,		'invalid id3 footer'],

	# p = MP3Encoding.pm

	'pa' => [ $ERROR_MEDIUM,	'decoded result still has non printable characters'],
	'pb' => [ $ERROR_INFO,		'replacing non-printable chars in with . dots'],

	# v = y_MP3TagListWrite.pm

	'va' => [ $ERROR_HIGH,		'no subid'],
	'vb' => [ $ERROR_HIGH,		'encoding error'],
	'vc' => [ $ERROR_HIGH,		'unexpected id length after decoding'],

);



#---------------------------------
# Mime utilities
#---------------------------------

sub artisanMimeType
{
	my ($filename_or_ext) = @_;
	my $ext = lc($filename_or_ext);
	$ext =~ s/^.*\.//;
	my $mime_type =
		$ext eq 'mp3' ? 'audio/mpeg' :
		$ext eq 'm4a' ? 'audio/x-m4a' :
		$ext eq 'wma' ? 'audio/x-ms-wma' :
		$ext eq 'wav' ? 'audio/x-wav' : '';
	# display(0,0,"artisanMimeType($filename_or_ext  ext($ext) = $mime_type");
	return $mime_type;
}


#----------------------------------
# severity constants
#----------------------------------


sub code_to_severity
{
	my ($code) = @_;
	my $exists = $error_mappings{$code};
	return defined($exists) ? $exists->[0] : $ERROR_HARD;
}


sub highest_severity
{
	my ($s) = @_;
	my @parts = split(/,/,$s);
	my $highest = 0;
	for my $part (@parts)
	{
		my $got = code_to_severity($part);
		$highest = $got if $got > $highest;
	}
	return $highest;
}


sub error_code_str
{
	my ($code) = @_;
	my $exists = $error_mappings{$code};
	return defined($exists) ? $exists->[1] : '';
}


sub severity_to_str
{
	my ($i) = @_;
	return 'NONE' if ($i == 0);
	return 'INFO' if ($i == 1);
	return 'LOW' if ($i == 2);
	return 'MEDIUM' if ($i == 3);
	return 'HIGH' if ($i == 4);
	return 'HARD_ERROR' if ($i == 5);
	return '';
}



#-----------------------------------------------------------
# statistics
#-----------------------------------------------------------
# stats don't work in threads

sub bump_stat
{
    my ($stat,$amt) = @_;
	$stat ||= '';
	$amt ||= 1;

    my ($package) = caller(1);
	if (!$stats{$package})
	{
		my $aref = {};
		#share($aref);
	    $stats{$package} = $aref;
	}
    $stats{$package}->{$stat} ||= 0;
    $stats{$package}->{$stat} += $amt;
}



sub init_stats
{
    my ($package) = @_;
    if (!$package)
    {
        %stats = ();
    }
    else
    {
        for my $k (keys(%stats))
        {
            next if (!$k =~ /$package/);
            delete $stats{$k};
        }
    }
}


sub dump_stats
{
    # my ($package) = @_;
    # $package = package_of(1) if (!defined($package));
    LOG(0,"dump_stats()");	# $package)");
    for my $j (sort(keys(%stats)))
    {
        # next if ($package && $j !~ /$package/);
        my $pstats = $stats{$j};
        LOG(1,$j);
        for my $k (sort(keys(%$pstats)))
        {
			my $val = $$pstats{$k};
			$val = prettyBytes($val) if ($k =~ /bytes/);
            LOG(2,pad($val,8)." ".$k);
        }
    }
}


#---------------------------------------------------------------------
# String Utility Routines (and encoding/decoding)
#---------------------------------------------------------------------


sub escape_tag
    # slighly different than XMLSoap::encode_xml()
	# does same DECIMAL encoding of non-printable characters
	# but has special case to replace \'s with \x5c
	#
	# Used in the decoding of MP3 tag sub_ids
{
    my ($s) = @_;
    if ($s)
    {
		$s =~ s/(\\)/\\x5c/g;
		$s =~ s/([^\x20-\x7f])/"&#".ord($1).";"/eg;
    }
    return $s;
}



sub unescape_tag
	# opposite of escape_tag, it was only
	# called by encoding MP3 tags in my MP3TagListWrite.pm
	# which is no longer used.
{
    my ($s) = @_;
    if ($s)
    {
		$s =~ s/\\x19/'/g;		# added special case
        $s =~ s/\\x(..)/pack('H2',$1)/eg;
        $s =~ s/\\#(\d+);/chr($1)/eg;
    }
    return $s;
}



#---------------------------------------------
# Time / Date Routines
#---------------------------------------------

sub millis_to_duration
	# there are actually three possibilities (see java)
{
	my ($millis,$precise) = @_;
	$millis ||= 0;

	my $hours = 0;
	my $minutes = 0;
	my $seconds = int($millis/1000);
	$millis = $millis % 1000;

	$minutes = int($seconds / 60) if $seconds > 59;
	$seconds -= $minutes * 60 if $seconds;
	$hours = int($minutes / 60) if $minutes > 59;
	$minutes -= $hours * 60 if $hours;

	my $string = '';
	if ($precise)	# Bub doesn't like decimals
	{
		$string .= pad2($hours).':'; 	# if $hours;
		$string .= pad2($minutes).':';
		$string .= pad2($seconds); # .'.';
	}
	else
	{
		if ($hours)
		{
			$string .= "$hours:";
			$string .= pad2($minutes).':';
		}
		else
		{
			$string .= "$minutes:";
		}
		$string .= pad2($seconds);
	}
	return $string;
}



sub duration_to_millis
{
	my ($duration) = @_;
	my $secs = 0;
	my $millis = 0;

	my @parts = split(/:/,$duration);
	my $num_parts = @parts;
	if ($num_parts && $parts[$num_parts-1] =~ /\./)
	{
		my @parts2 = split(/\./,$parts[$num_parts-1]);
		$parts[$num_parts-1] = $parts2[0];
		$millis = int($parts2[1]);
	}

	for my $part (@parts)
	{
		$secs *= 60;
		$secs += int($part);
	}

	$millis += $secs * 1000;
	return $millis;
}




#----------------------------------------------------------
# directories
#----------------------------------------------------------



sub mp3_relative
{
	my ($path) = @_;
	my $new_path = $path;
	$new_path =~ s/^$mp3_dir_RE//;
	$new_path =~ s/^\///;
	$new_path ||= "";
	# display(0,0,"mp3_relative($path)=$new_path");
	return $new_path;
}

sub mp3_absolute
{
	my ($path) = @_;
	$path = $path ? "$mp3_dir/$path" : $mp3_dir;
	return $path;
}



sub create_dirs
	# Given an ABSOLUTE FILENAME
	# Create the directories to hold it
	# Use a dummy leaf to create a dir
{
    my ($file_path) = @_;
    my @parts = split(/\//,$file_path);
    pop @parts;
    my $root = '';
    for my $subdir (@parts)
    {
        next if (!$subdir);
        $root .= "/$subdir";
        if (!(-d $root))
        {
            display(0,1,"mkdir($root)");
            bump_stat('dirs created');
            mkdir $root;
        }
    }
}



sub containingPath
	# return the path portion of a filename, if any
{
	my ($fullpath) = @_;
	$fullpath ||= '';
	my $path = "";
	$path = $1 if ($fullpath =~ /^(.*)\/.*?$/);
	return $path;
}


sub pathName
	# return the last portion of a path
	# i.e. the leaf folder/filename
{
	my ($path) = @_;
	$path ||= '';
	my $name = $path;
	$name = $1 if ($path =~ /^.*\/(.*?)$/);
	return $name;
}



sub split_dir
	# Used for generating folder database records in Library.pm
	# and getting default filename information in MediaFile.pm
	# Intended to be the only code that knows my special
	# folder structure/implied artist for the Grateful Dead
	# and Beatles.
	#
	# Takes an $mp3_dir relative path to a folder or (media) file.
	# Returns members
	#
	#      path = the parent path that holds this file or folder
	#      name = leaf filename or foldername
	#
	# Breaks the following fields out of the "full" path
	#
	#      type = root, section, class, album, track
	#      section = albums, singles, unresolved
	#      class = Blue, Blues New, etc
	#      album_name = full folder name
	#      album_artist = the artist portion of the album_name
	#      album_title = the title portion of the album_name
	#	   year_str
	#
	# for tracks the following are added
	#
	#      track - title - artist . ext
	#
	# Note the difference between track artist and the album_artist.
	# artist will be set to album_artist if not otherwise defined
{
	my ($is_track,$fullpath,$files) = @_;

	my $rec = {};
	for my $field (qw(
		path name
		type section class album_name album_artist album_title name
		track title artist ext year_str))
	{
		$rec->{$field} = '';
	}

	# return an empty record for root
	# otherwise, it's at least a section

	$rec->{name} = 'folders';
	$rec->{type} = 'root';
	if ($fullpath)
	{
		$rec->{year_str} = $1
			if $fullpath =~ / (\d\d\d\d)($|\/|\.mp3)/ ||
			   $fullpath =~ /(\d\d\d\d)-\d\d-\d\d/ ||
			   $fullpath =~ /(\d\d\d\d) (Concert|Season)/;

		# the first path element is the section (albums, singles, unresolved)
		# set the usable parent path and node (track or folder) name

		my @parts = split(/\//,$fullpath);
		$rec->{name} = pop @parts;
		$rec->{path} = join('/',@parts);
		$rec->{section} = shift @parts;
		$rec->{type} = @parts ? 'class' : 'section';

		# if there are files, it's an album
		# or it may be a track. otherwise,
		# what remains is the class

		if ($files && @$files)
		{
			$rec->{type} = 'album';
			$rec->{album_name} = $rec->{name};
		}
		elsif ($is_track)
		{
			$rec->{type} = 'track';
			$rec->{album_name} = pop @parts;

			my $fn = $rec->{name};
			$rec->{ext} = $1 if ($fn =~ s/\.(...)$//);
			my @tparts = split(' - ',$fn);
			my $p1 = shift @tparts;
			if (@tparts && $p1 =~ /^\d+$/)
			{
				$rec->{track} = $p1;
				$p1 = shift @tparts;
			}
			$rec->{title} = $p1;
			$rec->{artist} = pop @tparts if (@parts);
		}

		# the parts that remain are the class

		$rec->{class} = join(' ',@parts);

		# split the album_name into it's parts
		# with special handling for the dead and beatles

		if ($rec->{album_name})
		{
			($rec->{album_artist},
			 $rec->{album_title}) = split(' - ',$rec->{album_name});

			if ($rec->{class} =~ /Dead/)
			{
				$rec->{album_title} = $rec->{album_name};
				$rec->{album_artist} = 'Grateful Dead';
				$rec->{album_artist} = 'Jerry Garcia'
					if ($rec->{class} =~ /Jerry/);
			}
			elsif ($rec->{class} =~ /Beatles/)
			{
				# The year is part of the path but not the title for my beatles albums
				# so they are sorted by year, but the year doesn't show up in the title

				$rec->{album_title} = $rec->{album_name};
				if ($rec->{album_title} =~ s/^(\d\d\d\d) -//)
				{
					$rec->{year_str} = $1;
					# print "$rec->{album_title} year_str=$rec->{year_str}\n";

				}

				$rec->{album_artist} = 'The Beatles';
			}

			elsif (!$rec->{album_title})
			{
				warning(0,0,"No title for album at $fullpath");
				$rec->{album_title} = '';
			}
		}
	}

	# overrides

	$rec->{artist} = $rec->{album_artist} if (!$rec->{artist});
	if (0) #$fullpath =~ /T.B. Is Killing Me/)
	{
		display(0,0,"split_dir($fullpath)");
		for my $k (sort(keys(%$rec)))
		{
			display(0,1,"$k=$rec->{$k}");
		}
	}

	# within album_title, etc, change escaped underscores
	# into dashes for display

	$rec->{album_title} =~ s/ _ / - /g;
	$rec->{album_artist} =~ s/ _ / - /g;
	$rec->{title} =~ s/ _ / - /g;
	$rec->{artist} =~ s/ _ / - /g;

	return $rec;
}



sub compare_path_diff
    # compare two paths and show the shortest
	# string that shows the difference.
{
    my ($s1,$s2) = @_;

	my @parts1 = split(/\//,$s1);
	my @parts2 = split(/\//,$s2);

	while (@parts1 && @parts2)
	{
		last if ($parts1[0] ne $parts2[0]);
		shift @parts1;
		shift @parts2;
	}

	return (join('/',@parts1),join('/',@parts2));
}



#----------------------------------------------------
# unused debugging
#----------------------------------------------------

my $dbg_mem = 0;

sub unused_dbg_mem
	# platform specific
{
    my ($indent,$msg) = @_;
    if ($dbg_mem <= $debug_level)
    {
		require Sys::MemInfo;

		my $total = Sys::MemInfo::totalmem();
		my $free = Sys::MemInfo::freemem();
		my $used = $total - $free;

		display($dbg_mem,-1,"MEMORY  ".prettyBytes($used)." / ".prettyBytes($total)." $msg",1);
    }
}


#--------------------------------------
# Cross Platform Database Fixes
#--------------------------------------

sub compareTSLinux
	# compare two linux integer timestamps and return
	# true if they are more than two seconds apart
{
	my ($ts1,$ts2) = @_;
	my $dif = $ts1 - $ts2;
	return 1 if $dif > 2 || $dif < -2;
	return 0;
}


sub fileToDbPath
{
	my ($path) = @_;
	$path = Encode::decode("utf-8",$path) if !is_win();
	return $path;
}


sub dbToFilePath
{
	my ($path) = @_;
	$path = Encode::encode("utf-8",$path) if !is_win();
	return $path;
}




1;
