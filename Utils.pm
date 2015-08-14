#---------------------------------------
# Utils.pm
#---------------------------------------
# Partial re-export of appUtils with
# application specific constants, vars, etc

package Utils;
use strict;
use warnings;
use threads;
use threads::shared;
use Socket;
use Sys::Hostname;
use XML::Simple;
use appUtils qw(
	$debug_level
	$warning_level
	$HOME_MACHINE
	$data_dir
	$temp_dir
	$logfile
	LOG
	error
	display
	display_bytes
	warning
	_def
	_clip
	hx
	today
	now
	pad
	pad2
	roundTwo
	CapFirst
	pretty_bytes
	getTextFile
	getTextLines
	printVarToFile
);


appUtils::set_alt_output(1);
	# prh - as of now, don't need other calls
	# on a per-thread basis.


#-------------------------
# debugging constants
#-------------------------

our $debug_level 	= 1;
our $warning_level 	= 0;

our $dbg_db 		= 2;
our $dbg_ssdp 		= 2;
our $dbg_http 		= 1;
our $dbg_stream 	= 1;
our $dbg_xml    	= 2;
our $dbg_library    = 2;
our $dbg_vlibrary   = 2;
our $dbg_webui      = 3;
our $dbg_mediafile  = 2;
our $dbg_mp3_info   = 2;
our $dbg_mp3_read   = 2;
our $dbg_mp3_write  = 2;
our $dbg_mp3_tags   = 2;
our $dbg_ren        = 2;

our $dbg_mem		= 0;



#---------------------------------------
# error severity level constants
#---------------------------------------
# 0 = grey = NONE = informational message
# 1 = green = INFO = informational message of note
# 2 = blue = LOW = lowest level issue of concern
# 3 = purple = MEDIUM = level issue of concern
# 4 = yellow = HIGH = level issue of concern
# 5 = red = EXTREME = highest level concern

our ($ERROR_NONE,
	 $ERROR_INFO,
     $ERROR_LOW,
     $ERROR_MEDIUM,
     $ERROR_HIGH,
     $ERROR_HARD ) = (0..5);


# ERROR REPORTING 2015-06-23
#
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
#
# The mapping could eventually be placed in
# the webUI to allow changing it wihtout
# restarting artisan


our %error_mappings = (

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
	'mp' => [ $ERROR_INFO,     	'APIC tag has no data in mp3 file'],
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



BEGIN
{
 	use Exporter qw( import );

	# our constants

	our @EXPORT = qw (
        $ERROR_NONE
        $ERROR_INFO
		$ERROR_LOW
        $ERROR_MEDIUM
        $ERROR_HIGH
        $ERROR_HARD
	);

	# our exports

	push @EXPORT, qw(

		$dbg_db
		$dbg_ssdp
		$dbg_http
		$dbg_stream
		$dbg_xml
		$dbg_library
		$dbg_vlibrary
		$dbg_webui
		$dbg_mediafile
		$dbg_mp3_info
		$dbg_mp3_read
		$dbg_mp3_write
		$dbg_mp3_tags
		$dbg_ren

		$ANDROID
		$HOST_ID
        $program_name
        $uuid

		$modules_as_libraries

        $script_dir
		$mp3_dir
		$mp3_dir_RE
        $cache_dir
        $log_dir

		$quitting

        $server_port
        $server_ip
        $system_update_id

		severity_to_str
		code_to_severity
		highest_severity
		error_code_str

		%stats
        bump_stat
        init_stats
        dump_stats

		dbg_hash
		clone_hash

        http_date
        add_leading_char
        secs_to_duration

        escape_tag
        unescape_tag

		mp3_relative
		mp3_absolute
		create_dirs
		split_dir

		dbg_mem

	);


	# re-exports from appUtils

	push @EXPORT, qw(
        $debug_level
        $warning_level

		$HOME_MACHINE
        $data_dir
        $temp_dir
        $logfile

        LOG
        error
        display
		display_bytes
        warning
        _clip
		_def
		hx

        today
        now
        pad
		pad2
		roundTwo
		CapFirst
		pretty_bytes
        getTextFile
		getTextLines
		printVarToFile
    );
};


our $ANDROID = !$HOME_MACHINE;
our $temp_storage = $ENV{EXTERNAL_STORAGE} || '';
our $HOST_ID = $HOME_MACHINE ? "win" :
     $temp_storage =~ /^\/mnt\/sdcard$/ ? "arm" :
    "x86";

our $program_name = 'Artisan/V1.1';
our $uuid = '56657273-696f-6e34-4d41-afacadefeed0';
our $script_dir = "/base/apps/artisan";
our $mp3_dir = "/mp3s";
our $mp3_dir_RE = '\/mp3s';
our $server_port = '8091';
our ($server_ip)=inet_ntoa((gethostbyname(hostname))[4]);

#display(0,0,"hostname=".hostname);
#display(0,0,"server_ip=$server_ip");

if ($HOST_ID eq "win")
{
	$server_ip = '192.168.100.100';
}
elsif ($HOST_ID eq "arm")
{
	$program_name = 'Artisan Android 1.1v';
	$uuid = '56657273-696f-6e34-4d41-afacadefeed3';
	$script_dir = "/external_sd2/artisan";
	$mp3_dir = "/usb_storage2/mp3s";
	$mp3_dir_RE = '\/usb_storage2\/mp3s';
	$server_ip = '192.168.100.103';
}
else	# x86
{
	$program_name = 'Artisan x86 1.1v';
	$uuid = '56657273-696f-6e34-4d41-afacadefeed4';
	$script_dir = "/media/sf_base/apps/artisan";
	$mp3_dir = "/media/sf_ccc/mp3s";
	$mp3_dir_RE = '\/media\/sf_ccc\/mp3s';
	# $server_ip = '192.168.100.103';
}


our $cache_dir = "$mp3_dir/_data";
$data_dir = "$script_dir/data";
$temp_dir = "$data_dir/temp";
our $log_dir = "$data_dir/logs";
$logfile = "$log_dir/artisan.log";
our $error_logfile = "$log_dir/error.log";

our $system_update_id = time;
share($system_update_id);

our $quitting = 0;
share($quitting);

our %stats;
#share(%stats);

# NO LOGGING ON ANDROID

$logfile = '' if ($ANDROID);


#----------------------------------
# severity constants
#----------------------------------

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
    my ($package) = @_;
    $package = package_of(1) if (!defined($package));
    LOG(0,"dump_stats($package)");
    for my $j (sort(keys(%stats)))
    {
        next if ($package && $j !~ /$package/);
        my $pstats = $stats{$j};
        LOG(1,$j);

        for my $k (sort(keys(%$pstats)))
        {
			my $val = $$pstats{$k};
			$val = pretty_bytes($val) if ($k =~ /bytes/);
            LOG(2,pad($val,8)." ".$k);
        }
    }
}


#---------------------------------------------------------------------
# Utility Routines
#---------------------------------------------------------------------

sub dbg_hash
{
	my ($level,$indent,$title,$hash) = @_;
	display($level,$indent,"dbg_hash($title)",1);
	for my $k (sort(keys(%$hash)))
	{
		display($level,$indent+1,"$k = $hash->{$k}",1);
	}
}



sub clone_hash
{
    my ($hash) = @_;
    my $new = {};
    %$new = %$hash;
    return $new;
}


sub http_date
	# return the current gmt_time in the wonky unix date format
{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime();
	my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',);
	my @days = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',);

	$year += 1900;
	$hour = add_leading_char($hour, 2, '0');
	$min = add_leading_char($min, 2, '0');
	$sec = add_leading_char($sec, 2, '0');

	return "$days[$wday], $mday $months[$mon] $year $hour:$min:$sec GMT";
}




sub add_leading_char
{
	my ($string,$length,$char) = @_;
	while (length($string) < $length)
	{
		$string = $char . $string;
	}

	return $string;
}


# notes on xml and encoding.
#
# for example, the 'é' in 'Les Lables de Légende'
# came in as orig(C3 A9) from the mb_track_info file
# C:/mp3s/_data/mb_track_info/7ca4892022582c2b90c8bdca8657c888.xml
# was being written as (E9) to my my file:
# C:\mp3s\_data\unresolved_albums\albums.Blues.Old.Buddy Guy - The Treasure Untold.xml
# and then would not re-parse in xml_simple
#
# C3 A9 is the UTF-8 encoding of the latin ascii character E9
# it gets changed automatically on reading to E9 by xml_simple
# but we have to manually convert it back, here ...
#
# Note that this is different than unescape_tags(), below
#
# use Encode qw/encode decode/;
# $text = encode('UTF-8',$text);
#     # change single ascii byte E9 for é into two bytes C3 A9


sub escape_tag
    # replace characters outside of 0x20-0xff
	# with html &#NNN; tags where NNN is decimal.
	# replace \'s with \x5c
	#
	# Used in the decoding MP3 tag sub_ids, hence it's name.
	# Also called by the tag details sections of uiExplorer.pm.
	#
	# NOT CALLED by HTTPXML.pm!!
{
    my ($s) = @_;
    if ($s)
    {
        # old:
		# $s =~ s/(\\|[^\x20-\xff])/'\x'.unpack('H2',$1)/eg;

		# 2015-06-21
		# use decimal equivilants it's easier

		$s =~ s/(\\)/\\x5c/g;
		$s =~ s/([^\x20-\x7f])/"&#".ord($1).";"/eg;
    }
    return $s;
}


sub unescape_tag
	# opposite of escape_tag, it was only
	# called by encoding MP3 tags in y_MP3TagListWrite.pm
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



sub secs_to_duration
	# duplicated as prettyDuration or something like that
{
	my ($seconds) = @_;
    $seconds ||= 0;

	my $minutes = 0;
	$minutes = int($seconds / 60) if $seconds > 59;
	$seconds -= $minutes * 60 if $seconds;
	my $hours = 0;
	$hours = int($minutes / 60) if $minutes > 59;
	$minutes -= $hours * 60 if $hours;

	my $string = '';
	$string .= add_leading_char($hours,2,'0').':';
	$string .= add_leading_char($minutes,2,'0').':';
	$string .= add_leading_char($seconds,2,'0');

	return $string;
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



sub split_dir
	# Used for generating folder database records in Library.pm
	# and getting default filename information in MediaFile.pm
	# Intended to be the only code that knows my special
	# folder structure/implied artist for the Grateful Dead.
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
		track title artist ext))
	{
		$rec->{$field} = '';
	}

	# return an empty record for root
	# otherwise, it's at least a section

	$rec->{name} = 'Folders';
	$rec->{type} = 'root';
	if ($fullpath)
	{
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
		# with special handling for the dead

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





sub dbg_mem
{
    my ($indent,$msg) = @_;
    if ($dbg_mem <= $debug_level)
    {
		if ($ANDROID)
		{
			display(0,0,"Memory $msg\n\n". (`free`)."\n");
		}
		else
		{
			require Sys::MemInfo;

			my $total = Sys::MemInfo::totalmem();
			my $free = Sys::MemInfo::freemem();
			my $used = $total - $free;

			display($dbg_mem,-1,"MEMORY  ".pretty_bytes($used)." / ".pretty_bytes($total)." $msg",1);
		}
    }
}



1;
