#!/usr/bin/perl
#--------------------------------------------------------
# appUtils.pm
#--------------------------------------------------------
# Contains common routines and variables used by my code
# systemToNormalDate is windows specific.
#
# Note on Indentation
#
# The first parameter to LOG, and the second parameter to display()
# and warning() is the 'indent level' for the call.  As of this re-write
# display(), warning() and LOG() call are automatically nested on the
# screen by call levels, so the indent passed is just local to the
# caller.  
#
# Error() is always outdented, and display(), warning() and LOG() can
# forced to be outdented by passing -1 as their indent level.
#
# The auto-indenting is not used in the logfile. LOG() and warning()
# calls that show up in the LOGFILE *just* use the bare indent level
# you pass in.
	

package appUtils;
use strict;
use warnings;
use threads;
use threads::shared;
use Time::Local;
use Date::Calc;
use MIME::Base64;
use Crypt::RC4;

our $debug_level = 0;
our $warning_level = 2;

# color constants known by appFrame::write_monitor

our $DISPLAY_COLOR_NONE 	= 0;
our $DISPLAY_COLOR_LOG  	= 1;
our $DISPLAY_COLOR_WARNING 	= 2;
our $DISPLAY_COLOR_ERROR 	= 3;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (

		$debug_level
		$warning_level
		
		$DISPLAY_COLOR_NONE 			
		$DISPLAY_COLOR_LOG  			
		$DISPLAY_COLOR_WARNING 			
		$DISPLAY_COLOR_ERROR 			

		$FROM_SERVER
        $HOME_MACHINE
        $http_host

        $temp_dir
        $data_dir
        $image_dir
        $template_dir
        $logfile
		
  		$login_name
		
        @monthName
        %monthnum
        %params
        %cookies
		
		LOG
		myDie
		_def
		_clip
		error
		warning
		display
		error_tree
    	display_bytes

		allTrim
        hx
		pad
		pad2
		roundTwo
        round
		mergeHash
        mergeThruHash
        CapFirst
		pretty_bytes
        filterAscii

		today
        gmt_today
		year_today
        day_of_week_today

        now
		monthDays
        shortMonthName
        getTimestamp
		setTimestamp
        timeToGMTDateTime
		unixToTimestamp
		unixToDateTime
        isoToGMTTime
        isoToLocalTime
        gmtToLocalTime
        localToGMTTime
        isoTimeToPrettyTime

		normalDate
		numericToNormalDate
		usToNormalDate
		euroToNormalDate
        systemToNormalDate
		normalDateToInt
		normalDateToEuro
		normalDateToDayMonth
        charDateToNormalDate
        emTimeToNormalDate
        prettyDate
        prettyShortDate

        datePlusDays
        dateDiffDays

        getTextFile
	    getTextLines
		printVarToFile
		writeFileIfChanged
        copyTextAndUnlink

        parseParams
        parsePostParams
        parseCookies

        setCookie
        encode64
        decode64
        crypt_rc4
        fileExistsRE

    );
}


#------------------------------------------------
# configuration vars
#------------------------------------------------

our $FROM_SERVER = $ENV{'REQUEST_URI'} ? ($ENV{'REQUEST_URI'} ne ""?1:0) : 0;
our $HOME_MACHINE = $ENV{COMPUTERNAME} ? ($ENV{COMPUTERNAME} eq "LENOVO-PC") ? 1 : 0 : 0;
our $WINDOWS_OS = $ENV{OS} && $ENV{OS} =~ /windows/i ? 1 : 0;
our $http_host = $ENV{HTTP_HOST};

my $base_dir   = "/base";
our $data_dir  = "$base_dir/data";          # does not exist
our $temp_dir  = "$base_dir/temp";
our $image_dir = "$data_dir/data/images";   # does not exist
our $logfile   = "$temp_dir/app.log";
our $template_dir = "$data_dir/templates";  # does not exist

# mkdir $temp_dir if (!(-d $temp_dir));

#------------------------------------------------
# output configuration
#------------------------------------------------
# The main output routines are display(), warning(),
# error() and LOG(), and are configurable for a variety of
# conditions. In general, error() and warning() also calls
# LOG() and display().

my $display_off = 0;
    # This variable is checked first during display(), and causes all
	# display() output to be redirected to the LOG file.  It is used
	# by server processes that are not allowed to have screen output,
	# and webpages in certain configurations.
	
our $g_alt_output = 0;
	# This variable is checked second during displsa(), and causes
	# output to go to STDERR instead of STDOUT.  It is used by
	# child processes to output to the same console window as the
	# main parent process.  It is also expected to be a shared memory
	# OBJECT with {errors} and {warnings} string members to which
	# will be appeneded carriage return delmited error and warning
	# messages for use by the main process UI.
	
# The next variable that is checked in display() is FROM_SERVER,
# and if it is set, then the output will be printed in html to
# STDOUT, errors will show in red, warnings in orange, display()
# in white, and LOG messages in blue.

my $app_frame;
	# If this is set, it is expected to be an object that has
    # methods writeMonitor(self,msg,color), which writes the text,
	# and showError($msg), which brings up an alert window. 
	# This variable is also used by clients to indicate the
	# presence of an appFrame for other purposes.  Output
	# will be sent to the appFrame, if set, regardless of the
	# state of the other above variables.
	
my $SAVE_DISPLAY = 0;
	# This variable is also independent of the other variables,
	# and if set, will cause the output to also be appended to
	# a text file called 'save_display.txt' in the current working
	# directory.  It is expected to be used for specific debugging
	# situations to capture the display() output when it exceeds
	# the memory of the console window.
	
# output appearance

my $USE_COLORS = $FROM_SERVER ? 0 : 1;
	# This variable is set system wide and there is currently
	# no way to change it for individual apps. If otherwise
	# outputting to the system console, this variable will
	# cause errors to be shown in red, warnings in orange,
	# and LOG messages in white.

my $INDENT_BIAS = 20;
	# Messages that are indented more than this are biased
	# back to the outdent position.  This variable can easily
	# be made "our" and application specific.
my $CHILD_PROCESS_INDENT  = 10;
	# Messages from child processes, as indicated by their pid ($$)
	# are moved over this far to the right on the console.
	

# output configurators
	
sub setDisplayOff
{
    $display_off = shift;
}


sub set_alt_output
{
    $g_alt_output = shift;
}

sub setAppFrame
{
	$app_frame = shift;
}

sub getAppFrame
{
    return $app_frame;
}


	
#------------------------------------------------
# working vars
#------------------------------------------------
# display working variables

our $login_name     = '';
    # Unused, per-se, by this layer, except that it's
	# displayed in log messages. Used by MBE as needed.

my $_clipping = 0;
    # state variable
my $clip_width = 160;
    # the default clipping width


my $CONSOLE = undef;
my $fg_lightgray = 7;
my $fg_lightred = 12;
my $fg_yellow = 14;
my $fg_white = 15;
my $STD_OUTPUT_HANDLE = -11;

if ($WINDOWS_OS && $USE_COLORS)
{
	require Win32::Console;
	$CONSOLE = Win32::Console->new($STD_OUTPUT_HANDLE);
}

# other working vars
	
our %params;
    # from parseParams and parsePostParams
our %cookies;
    # from parseCookies

our @monthName = (
    "January",
    "Februrary",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December" );

our %monthnum;
$monthnum{"Jan"} = 1;
$monthnum{"Feb"} = 2;
$monthnum{"Mar"} = 3;
$monthnum{"Apr"} = 4;
$monthnum{"May"} = 5;
$monthnum{"Jun"} = 6;
$monthnum{"Jul"} = 7;
$monthnum{"Aug"} = 8;
$monthnum{"Sep"} = 9;
$monthnum{"Oct"} = 10;
$monthnum{"Nov"} = 11;
$monthnum{"Dec"} = 12;


my $system_date_format = "";
    # for use by systemToNormalDate



#----------------------------------
# Display Utilities
#----------------------------------

sub write_save_display
    # quick and dirty method to capture the display calls
    # to a text file for special case debugging
{
    my ($msg) = @_;
    if (!open(TEMP,">>save_display.txt"))
    {
        print "!!! Could not open save_display.txt for writing !!!\n";
        return;
    }
    print TEMP $msg."\n";
    close TEMP;
}


sub _def
    # oft used debugging utility
{
    my ($var) = @_;
    return defined($var) ? $var : 'undef';
}


sub _clip
    # callable inline in display, etc
{
    my (@params) = @_;
    $_clipping = $clip_width;
    return @params;
}

    
sub get_indent
    # given a call_level, get the indent to use based
	# on the call tree at this moment in time, and the
	# file[line] that is making the call.
	#
	# call_level will be one for default callers of display()
	# at this point.  In other words, somebody called display
	# which defaults to call_level 0, and display() added 1 to
	# the call level to 'skip' itself.
	#
	# show_tree() is passed from error_tree and warning_tree
	# to show the entire call chain to the error/warning, as
	# we are traversing the call chain anyways.
	#
	# If anything gets more than INDENT_BIAS levels deep, it
	#     is outdented to zero again.
	# Child process messages, indicated by negative pids ($$) are
	#     indented $CHILD_PROCESS_INDENT
{
    my ($call_level,$show_tree) = @_;
    
    my $first = 1;
    my $indent = 0;
	my $tree = '';
	my $file = '';
	my $line = 0;
	
	# Count the number of callers until we get to
	# an eval, or a null package, remembering the file
	# and line number for the return value.
	#
	# The paramters returned by caller() are the
	# calling package, the filename, line number,
	# and the method being called.
	
    while (1)
    {
        #print STDERR "before call to caller($call_level)\n";
        my ($p,$f,$l,$m) = caller($call_level);
        #print STDERR "caller($call_level) = "._def($p).","._def($f).","._def($l).","._def($m)."\n";

        if (!$p || $m =~ /eval/)
        {
			# handle deeply indented messages and 
            # child process messages are put to the right
			
            $indent -= $INDENT_BIAS if ($indent > $INDENT_BIAS);
            $indent += $CHILD_PROCESS_INDENT if ($$ < 0);

            return ($indent-1,$file,$line,$tree);
        }
        
		# save the values for return
		
		$f ||= '';
        my @parts = split(/\/|\\/,$f);
        my $fl = pop @parts;

		if ($first)
		{
			$file = $fl;
			$line = $l;
		}
		
		# show the call tree if asked (the first one
		# will be displayed by whomsoever) ...
		
        elsif ($show_tree)
        {
            $tree .= "   from ".pad("$fl\[$l\]",30)." ".pad($p,20)." ".$m."()\n";
        }
        $first = 0;
        $indent++;
        $call_level++;
    }
}


#-------------------------------------------------------------
# low level display/log routines
#-------------------------------------------------------------
# debug_level and display_off have already been factored out,
# so these routines invariantly write to the screen or logfile,
# and do not call each other!  The debug $level IS passed for
# display purposes


sub display_low
    # the main 'screen' output routine
{
    my ($level,$indent_level,$msg,$color_const,$call_level,$show_tree) = @_;
    $call_level ||= 0;
	
	$show_tree ||= 0;
    # print STDERR "--> display_low($level,$indent_level,$msg,$call_level,$show_tree) g_alt_output=$g_alt_output\n";

    #print STDERR "before get_indent\n";
    my ($indent,$file,$line,$tree) = get_indent($call_level+1,$show_tree);
    #print STDERR "back from get_indent\n";

	my $tid = threads->tid();;
	my $header = "($tid,$level,$indent_level)$file\[$line\]";


    $indent = 0 if $indent_level < 0;
	$indent_level = 0 if $indent_level < 0;

	my $full_message = $tree.pad($header,40 + ($indent+$indent_level) * 4).$msg;
	$full_message = substr($full_message,0,$_clipping) if $_clipping;

	if ($FROM_SERVER)
	{
		my $color =
			$color_const == $DISPLAY_COLOR_ERROR ? 'red' :
			$color_const == $DISPLAY_COLOR_WARNING ? 'orange' :
			$color_const == $DISPLAY_COLOR_LOG ? 'blue' :
			'black';

		$full_message =~ s/\n/<br>/g;
		$full_message =~ s/ /&nbsp;/g;        
        print "<font color='$color'>$full_message</font><br>\n";
	}
	else
	{
		if ($CONSOLE)
		{
			my $attr =
				$color_const == $DISPLAY_COLOR_ERROR ? $fg_lightred :
				$color_const == $DISPLAY_COLOR_WARNING ? $fg_yellow :
				$color_const == $DISPLAY_COLOR_LOG ? $fg_white :
				$fg_lightgray;
			$CONSOLE->Attr($attr);
		}
		
		if ($g_alt_output)
        {
            print STDERR $full_message."\n";
        }
        else
        {
            print $full_message."\n";
        }
		
		$CONSOLE->Attr($fg_lightgray) if $CONSOLE;

        $app_frame->writeMonitor($full_message."\n",$color_const)
			if ($app_frame);
    }

	write_save_display($full_message)
		if ($SAVE_DISPLAY);
}



sub LOG_LOW
    # the low level LOG routine
    # invariantly LOG the given message to the logfile
	# self corrects inability to open logfile
	# with_indent==0 does not use nesting indentation
{
    my ($with_indent,$indent_level,$msg,$call_level,$show_tree) = @_;
    $call_level ||= 0;
    #print "--> LOG_LOW($indent_level,$call_level,$msg)\n";
	return if !$logfile;
	
    my ($indent,$file,$line,$tree) = get_indent($call_level+1,$show_tree);
	
	my $tid = threads->tid();;
	my $header = "($tid,$indent_level)$file\[$line\]";
	
	$indent = 0 if $indent_level < 0;
	$indent = 0 if !$with_indent;
	$indent_level = 0 if $indent_level < 0;
	
	my $full_message = $tree.
	    pad(today()." ".now()." ".$login_name,28).
    	pad($header,40 + ($indent+$indent_level) * 4).
		$msg;

	$full_message = substr($full_message,0,$_clipping) if $_clipping;
    
	if (!open(LOGFILE,">>$logfile"))
	{
		print "!!! Could not open logfile $logfile for writing !!!\n";
		$logfile = '';
		return;
	}
	print LOGFILE $full_message."\n";
	close LOGFILE;
}



#---------------------------------------------------------------
# High Level Display Routines
#---------------------------------------------------------------


sub display
	# high level display() routine called by clients.
	# Calls LOG_LOW() if $display_off
{
    my ($level,$indent_level,$msg,$call_level,$show_tree) = @_;
	# print STDERR "display() called\n";
	$call_level ||= 0;
	if ($level <= $debug_level)
	{
		if ($display_off)
		{
			LOG_LOW(1,$indent_level,$msg,$call_level+1,$show_tree);
		}
		else
		{
			display_low($level,$indent_level,$msg,$DISPLAY_COLOR_NONE,$call_level+1,$show_tree);
		}
	}
    $_clipping = 0;
	
}


sub LOG
{
    my ($indent_level,$msg,$call_level,$show_tree) = @_;
	$call_level ||= 0;
	if (!$display_off)
	{
		display_low(0,$indent_level,$msg,$DISPLAY_COLOR_LOG,$call_level+1,$show_tree);
	}
	LOG_LOW(0,$indent_level,$msg,1,$show_tree);
	$_clipping = 0;
}
	
	

sub error
    # report an error
    # errors are never clipped.
	# errors are always outdented
	
	# they are written to the screen and the logfile.
{
    my ($msg,$call_level,$show_tree) = @_;
	$call_level ||= 0;
	$_clipping = 0;
	if (!$display_off)
	{
		display_low(0,-1,$msg,$DISPLAY_COLOR_ERROR,$call_level+1,$show_tree)
	}
	LOG_LOW(0,-1,"ERROR: $msg",$call_level+1,$show_tree);

    if (ref($g_alt_output) =~ /HASH/)
    {
        $g_alt_output->{errors} .= "ERROR: $msg\n";
    }

    my $app_frame = appUtils::getAppFrame();    
	$app_frame->showError("Error: ".$msg) if ($app_frame);
    
}


sub warning
    # report a warning.
    # same syntax as display, except uses $warning_level
    # Warnings that are displayed are also LOGGED, and
    # go into the error logfile as well.
{
    my ($level,$indent_level,$msg,$call_level,$show_tree) = @_;
	$call_level ||= 0;
    
    if ($level <= $warning_level)
    {
		if (!$display_off)
		{
			display_low($level,$indent_level,$msg,$DISPLAY_COLOR_WARNING,$call_level+1,$show_tree)
		}
		LOG_LOW(0,-1,"WARNING($level): $msg",$call_level+1,$show_tree);
	
		if (ref($g_alt_output) =~ /HASH/)
		{
			$g_alt_output->{warnings} .= "WARNING: $msg\n";
		}

    }
    
    $_clipping = 0;
}




sub error_tree
{
    my ($msg) = @_;
    error($msg,1,1);
}



	

#---------------------------------------------------------------
# Aggregate Display Routines
#---------------------------------------------------------------

sub myDie
{
	my $msg = shift;
	error("myDie!!! $msg");
	exit 0;
}


sub display_bytes
{
	my $max_bytes = 64000;
	my ($dbg,$level,$title,$packet) = @_;
	return if ($dbg > $debug_level);
	my $indent = "";
	while ($level-- > 0) { $indent .= "    "; }
	print "$indent$title";
	$indent .= "   ";
	my $i=0;
    my $chars = '';
	for ($i=0; $i<$max_bytes && $i<length($packet); $i++)
	{
        if (($i % 16) == 0)
        {
            print "   $chars\n";
            print "$indent";
            $chars = '';
        }

		my $c = substr($packet,$i,1);
		my $d = (ord($c) != 9) && (ord($c) != 10) && (ord($c) != 13) ? $c : ".";
        $chars .= $d;
		printf "%02x ",ord($c);
	}
    print "   $chars\n" if ($chars ne "");
	print "..." if ($i < length($packet));
	print "\n" ;
}



#----------------------------------------
# weird little utilities
#----------------------------------------

sub filterAscii
    # reduce the string to containing only ascii characters from
    # space to 7f.  Used to clean strings before putting them in
    # vfoledb, which does not like international characters.
{
    my ($value) = @_;
    $value =~ s/[^\x20-\x7f]//g;
    return $value;
}


sub allTrim
	# removes trailing spaces from everthing
	# in a hash (for foxbase database records)
{
	my ($r) = @_;
	for my $k (%$r)
	{
		$$r{$k} =~ s/ *$// if ($k && $$r{$k} && !ref($$r{$k}));
	}
}


sub hx
{
    my ($val) = @_;
    # $val = 0 if (!$val);
    return sprintf('%04x',$val);
}


sub pad
{
	my ($s,$len) = @_;
	$len -= length($s);
	while ($len-- > 0)
	{
		$s .= " ";
	}
	return $s;
}


sub pad2
{
	my ($d) = @_;
	$d = '0'.$d if (length($d)<2);
	return $d;
}


sub roundTwo
{
	my ($num) = @_;
	$num = "0.00" if (!defined($num) || ($num eq ""));
	return sprintf("%0.2f",$num);
}

sub round
{
	my ($num,$digits) = @_;
	$num = "0.00" if (!defined($num) || ($num eq ""));
	return sprintf("%0.$digits"."f",$num);
}


sub mergeHash
{
	my ($h1,$h2) = @_;
	return if (!defined($h2));
	foreach my $k (keys(%$h2))
	{
        next if (!defined($$h2{$k}));
		display(9,2,"mergeHash $k=$$h2{$k}");
		$$h1{$k} = $$h2{$k};
	}
}


sub mergeThruHash
{
    my ($rec2,$map,$rec1) = @_;
    for my $key (keys(%$map))
    {
        my $value = $$rec1{$key};
        $value = "" if (!defined($value));
        my $name = $$map{$key};
        if (!$name || $name eq "")
        {
            display(0,0,"no mapping for field '$key' in POS datafile");
        }
        else
        {
            $$rec2{$key} = $value;
        }
    }
}


sub CapFirst
	# changed implementation on 2014/07/19
{
    my ($name) = @_;
    $name = '' if (!$name);
	$name = lc($name);
	$name =~ s/^\s+//;
	$name =~ s/\s+$//;
    my @parts;
	my $new_name = '';
	while ($name =~ s/^(.*?)(\s+|,|-|\.|\")//)
	{
		my ($part,$punc) = ($1,$2);
		$punc = ' ' if ($punc =~ /\s+/);
		substr($part,0,1) = uc(substr($part,0,1))
			if defined($part) && length($part);
		$new_name .= $part;
		$new_name .= $punc;
	}
	substr($name,0,1) = uc(substr($name,0,1))
		if length($name);
	$new_name .= $name;
	return $new_name;
	

	#my @parts = split(/\s+/,$name);
    $name = "";
    for my $part (@parts)
    {
        $part = uc(substr($part,0,1)).lc(substr($part,1));
        $name .= " " if ($name ne "");
        $name .= $part;
    }
    return $name;
}


sub pretty_bytes
{
	my ($bytes) = @_;
    $bytes ||= 0;

	my @size = ('', 'K', 'M', 'G', 'T');
	my $ctr = 0;
	for ($ctr = 0; $bytes > 1000; $ctr++)
	{
		$bytes /= 1000; # 1024;
	}
	my $rslt = sprintf("%.1f", $bytes).$size[$ctr];
    $rslt =~ s/\..*$// if !$size[$ctr];
    return $rslt;
}


#----------------------------------------------------------
# date times
#----------------------------------------------------------


sub today
{
    my $today = unixToDateTime(scalar(localtime()));
    $today =~ s/\s\d\d:\d\d:\d\d$//g;
    return $today;
}


sub gmt_today
{
    my $today = unixToDateTime(scalar(gmtime()));
    $today =~ s/\s\d\d:\d\d:\d\d$//g;
    return $today;
}


sub year_today
{
    my $year_today = '2013';
    $year_today = $1 if (today() =~ /^(\d\d\d\d)/);
	# today in a normalized format
    return $year_today;
}


sub day_of_week_today
{
    my @parts = localtime();
    return $parts[6];
}



sub now
    # returns the current local time in the
    # format hh::mm:ss
{
    my @time_parts = localtime();
	my $time =
		pad2($time_parts[2]).':'.
		pad2($time_parts[1]).':'.
		pad2($time_parts[0]);
    return $time;
}


sub monthDays
{
	my ($mo,$yr) = @_;
	my $days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[$mo-1];
	$days += 1 if ($mo==2 && $yr%4==0);
	return $days;
}


sub shortMonthName
{
    my ($mo) = @_;
    return qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)[$mo-1];
}


sub getTimestamp
	# param = unix format full path to file
	# returns colon delmited GMT timestamp.
    # returns blank if the file could not be stat'd
    # takes an optional parameter local to return
    # local timestamp
{
	my ($filename,$local) = @_;
	my $ts = '';

	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	  	$atime,$mtime,$ctime,$blksize,$blocks) = stat($filename);
    $mtime = '' if (!$mtime);
	if ($mtime ne '')
	{
		my $unix = $local ? localtime($mtime) : gmtime($mtime);
		display(9,0,"mtime=$mtime");
		$ts = unixToTimestamp($unix);
	}
	return $ts;
}


sub setTimestamp
    # takes a colon delimited GMT timestamp
    # and sets the given file's modification time.
    # takes an optoinal parameter to accept a local
    # file modification timestamp
{
	my ($filename,$ts,$local) = @_;
    $filename =~ s/\/$//;
        # for dirs with dangling slashes

	$ts =~ /(\d\d\d\d).(\d\d).(\d\d).(\d\d):(\d\d):(\d\d)/;
	display(9,0,"setTimestamp($filename) = ($6,$5,$4,$3,$2,$1)");
	my $to_time = $local ?
        timelocal($6,$5,$4,$3,($2-1),$1) :
        timegm($6,$5,$4,$3,($2-1),$1);
	utime $to_time,$to_time,$filename;
}


sub timeToGMTDateTime
    # takes the time in seconds since the epoch
    # 00:00 January 1, 1970 GMT, and returns a
    # human readable date.
{
    my ($tm) = @_;
    my $in = gmtime($tm);
    display(9,3,"timeToGMTDateTime($tm) in=$in");
    my $rslt = unixToTimestamp($in);
    $rslt =~ /(\d\d\d\d):(\d\d):(\d\d):(\d\d):(\d\d):(\d\d)/;
	my $rslt2 = "$1-$2-$3 $4:$5:$6";
    display(9,4,"rslt=$rslt2");
    return $rslt2;
}


sub unixToTimestamp
    # takes a 'unix' string time of the format
    # 'Sun Jul 23 14:32:40 2000' and converts it to
    # a colon delmited 'timestamp' format of
    # '2000:07:23:14:32:40
{
	my ($unix) = @_;
	my ($dayname, $moname, $day, $ttime, $year) = split(/\s+/,$unix);
	my $month = $monthnum{$moname};
	$day = "0".$day if ($day < 10);
	$month = "0".$month if ($month < 10);
	my $ts = "$year:$month:$day:$ttime";
	display(9,0,"unixToTimestamp($unix)=$ts");
	return $ts;
}


sub unixToDateTime
    # takes a 'unix' string time of the format
    # 'Sun Jul 23 14:32:40 2000' and converts it to
    # a dash delmited 'DateTime' format of
    # '2000-07-23 14:32:40'
{
	my ($unix) = @_;
	my $ts = unixToTimestamp($unix);
	$ts =~ /(\d\d\d\d):(\d\d):(\d\d):(\d\d):(\d\d):(\d\d)/;
	return "$1-$2-$3 $4:$5:$6";
}


sub isoToGMTTime
    # takes an iso time in the format 2014-07-29 12:31:00(tz),
    # where tz can start with a 'T' or a blank,
    #    has a plus or minus sign, with the hour offset to GMT.
    # if tz is not provided, the time is assumed to already be GMT.
    # does not handle 1/2 hour time zones!
    # returns a GMT time in the formaat 2014-07-29 12:31:00
    #    with the tz, if any, factored out.
{
    my ($iso) = @_;
    $iso = "" if (!defined($iso));
    my $gmt = $iso;
    $gmt =~ s/T/ /;
    if ($gmt =~ /(\d\d\d\d)-(\d\d)-(\d\d).(\d\d):(\d\d):(\d\d)(([+\-])(\d\d):\d\d)+/)
    {
        my ($y,$m,$d,$h,$min,$s,$p,$z) = ($1,$2,$3,$4,$5,$6,$8,$9);
        display(5,1,"isoToGMTTime($y-$m-$d $h:$min  $p$z)");

        if ($z ne "")
        {
            $z = -$z if ($p eq '+');
            ($y,$m,$d,$h) = adjustTime($y,$m,$d,$h,$z);   # to gmt
        }
        $gmt = $y."-".pad2($m)."-".pad2($d)." ".pad2($h).":$min:$s";
    }
    display(5,2,"isoToGMTTime($iso)=$gmt");
    return $gmt
}


sub isoToLocalTime
    # there is no function that takes a time zone
    # this parses a datetime that *may* have a time
    # zone.
{
    my ($iso) = @_;
    my $gmt = isoToGMTTime($iso);
    my $local = gmtToLocalTime($gmt);
    display(5,2,"isoToLocalTime($iso)=$local");
    return $local;
}


sub gmtToLocalTime
    # takes a GMT time in the format 2013-07-05 12:31:22
    # and returns a local date time in the same format.
    # we subtract -5 (add 5) for panama, so resulting
    # date would be 2013-07-05 17:31:22 -05:00, but
    # we DO NOT append the timezone .. client must remember
    # that this is a local time!
{
    my ($gmt) = @_;
    my $local = $gmt;
    my $local_tz = -5;
    if ($gmt =~ /(\d\d\d\d)-(\d\d)-(\d\d).(\d\d):(\d\d):(\d\d)/)
    {
        my ($y,$m,$d,$h,$min,$s) = ($1,$2,$3,$4,$5,$6);
        ($y,$m,$d,$h) = adjustTime($y,$m,$d,$h,$local_tz);
        $local = $y."-".pad2($m)."-".pad2($d)." ".pad2($h).":$min:$s";
    }
    display(5,2,"gmtToLocalTime($gmt)=$local");
    return $local;
}


sub localToGMTTime
    # takes a local time in the format 2013-07-05 12:31:22
    # and returns a gmt date time in the same format.
{
    my ($local) = @_;
    my $gmt = $local;
    my $local_tz = -5;
    if ($local =~ /(\d\d\d\d)-(\d\d)-(\d\d).(\d\d):(\d\d):(\d\d)/)
    {
        my ($y,$m,$d,$h,$min,$s) = ($1,$2,$3,$4,$5,$6);
        ($y,$m,$d,$h) = adjustTime($y,$m,$d,$h,-$local_tz);
        $gmt = $y."-".pad2($m)."-".pad2($d)." ".pad2($h).":$min:$s";
    }
    display(5,2,"localToGMTTime($local)=$gmt");
    return $gmt;
}




sub adjustTime
{
    my ($y,$m,$d,$h,$z) = @_;
    display(5,3,"adjustTime($y-$m-$d  $h += $z)");

    $h += $z;
    if ($h > 23)
    {
        $h -= 24;
        $d++;
        if ($d > monthDays($m,$y))
        {
            $d = 1;
            $m++;
            if ($m > 12)
            {
                $m = 1;
                $y++;
            }
        }
    }
    if ($h < 0)
    {
        $h += 24;
        $d--;
        if ($d == 0)
        {
            $m--;
            if ($m < 1)
            {
                $m = 12;
                $y--;
            }
            $d = monthDays($m,$y);
        }
    }
    display(5,2,"adjusted:($y-$m-$d h=$h)");
    return ($y,$m,$d,$h);
}


sub isoTimeToPrettyTime
    # takes an iso time, assumed to be GMT if no zone,
    # 2013-07-31 12:31:00([T| ][+|-]05:00)*
    # and convert it to a local time in a pretty
    # format '31-Dec 17:31' for display
{
    my ($in) = @_;
    my $local = isoToLocalTime($in);
    if ($in =~ /(\d\d\d\d)-(\d\d)-(\d\d).(\d\d):(\d\d)/)
    {
        my ($y,$m,$d,$h,$min) = ($1,$2,$3,$4,$5,$6,$8,$9);
        $in = $d."-".substr($monthName[$m-1],0,3)." $h:$min";
    }
    return $in;
}




#------------------------------------------------
# dates
#------------------------------------------------
# Date format conversions (without time fields)

sub normalDate
    # create a 'normalDate', which is dash delimited
    # 2013-07-29
{
	my ($y,$m,$d) = @_;
	return $y."-".pad2($m)."-".pad2($d);
}


sub numericToNormalDate
    # takes a date with no delimiters
    # 20130729 and converts it to a normal date
    # 2013-07-29
{
	my ($d) = @_;
	return if (!defined($d));
	$d =~ /(\d\d\d\d)(\d\d)(\d\d)/;
	return normalDate($1,$2,$3);
}


sub usToNormalDate
    # takes date with a four digit year and any
    # delimiters, in the format mm/dd/yyyy, and
    # returns a 'normal date' in the format
    # yyyy-mm-dd
{
	my ($d) = @_;
	return if (!defined($d));
	$d =~ /(\d*).(\d*).(\d*)/;
	return normalDate($3,$1,$2);
}


sub euroToNormalDate
    # takes a date with a four digit year and any
    # delimiters, in the format dd/mm/yyyy, and
    # returns a 'normal date' in the format
    # yyyy-mm-dd
{
	my ($d) = @_;
	return if (!defined($d));
	$d =~ /(\d*).(\d*).(\d*)/;
	return normalDate($3,$2,$1);
}


sub systemToNormalDate  # Windows specific!
    # Given a date in the (Win7) system short date format
    # convert it to a normal date.  Used for interfacing
    # to VFPOLEDB which returns dates in system format.
    # Only supports two formats, my USA and mbe SPANISH
{
	my ($d) = @_;
    if ($system_date_format eq "")
    {
        # use Win32::TieRegistry( TiedHash => \%registry );
        require Win32::TieRegistry;

        my $elim_warning = $Win32::TieRegistry::Registry;
        my $date_key = $Win32::TieRegistry::Registry->{'\HKEY_CURRENT_USER\Control Panel\International'};

        display(9,0,"date_key=$date_key");
        $system_date_format = $date_key->{sShortDate};
        display(9,0,"system_date_format=$system_date_format");
    }

    if ($d eq '12:00:00 AM')  # the empty date in system speak
    {
        return '';
    }
    return "" if ($d =~ /:/);      # don't map times to dates!
    return euroToNormalDate($d) if ($system_date_format eq "dd/MM/yyyy");
    return usToNormalDate($d);
}



sub normalDateToInt
	# returns days since jan 1 1900 (actually Dec 30, 1899) or whatever
	# for use with DBI/FPOLRDB Foxbase ole driver on POS data files
	# with real dates in them. Note that this is NOT the same as
    # the seconds since the epoch 00:00:00 1970-01-01
{
	my ($dt) = @_;
	my $rslt = 0;
	if ($dt =~ /(\d*)-(\d*)-(\d*)/)
	{
		my ($y,$m,$d) = ($1,$2,$3);
		my $base = Date::Calc::Date_to_Days(1899,12,30);
		my $val = Date::Calc::Date_to_Days($y,$m,$d);
		$rslt = $val-$base;
	}
	return $rslt;
}


sub normalDateToEuro
    # takes a normal date in the YYYY-MM-DD format
    # and returns a slash delimited 'euro' date
    # DD/MM/YYYY
{
	my ($dte) = @_;
	$dte =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/;
	my ($y,$m,$d) = ($1,$2,$3);
	return "$d/$m/$y";
}


sub normalDateToDayMonth
    # returns 31-Jan for 2013-01-31
{
	my ($d) = @_;
	my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
	$d =~ /\d\d\d\d-(\d\d)-(\d\d)/;
	return int($2)."-".$months[$1-1];
}


sub charDateToNormalDate
    # converts a date of format '03 Jan 2013', with
    # any delimiters to a normal date '2013-01-03'
{
    my ($dt) = @_;
    if ($dt =~ /(\d\d).(\w\w\w).(\d\d\d\d)/)
    {
        my ($d,$name,$y) = (pad2($1),$2,$3);
        my $m = pad2($monthnum{$name});
        $dt = "$y-$m-$d";
    }
    return $dt;
}


sub emTimeToNormalDate
    # Takes a couple of date time formats I've found in yahoo mail:
	#     Fri, 20 Jan 2012 17:43:46 -0500   or
    #     07 Apr 2013 08:07:56 -0700
    # and returns a normalDate in the local time zone
    #    2012-01-20 17:43:46
    #    2013-04-07 06:07:56
{
	my ($em_time) = @_;
    return "" if (!defined($em_time) || $em_time eq "");

    # parse the em time

	my ($dayname, $day, $moname, $year, $tm, $zone);
    if ($em_time =~ /,/)
    {
        ($dayname, $day, $moname, $year, $tm, $zone) = split(/\s+/,$em_time);
    }
    else
    {
        ($day, $moname, $year, $tm, $zone) = split(/\s+/,$em_time);
    }
	my $month = $monthnum{$moname};
    display(4,3,"tm=$tm zone=$zone");

    # we are in -0500 .. if the mail is not (i.e. -0800)
	# then we have to change the hour (+3) and carry over
	# to day, month, and year.

	my $local_tz = -5;
	my $dif = int($local_tz - ($zone/100));
	if ($dif != 0)
	{
		my ($h,$m,$s) = split(/:/,$tm);
		display(4,3,"adjusting date by $dif based on $tm hour of $h");
		$h += $dif;
		if ($h > 23)
		{
            $h -= 24;
			$day += 1;
			if ($day > monthDays($month,$year))
			{
				$month++;
				$year++ if ($month > 12);
			}
		}

        $h = "0".$h if (length($h)<2);
        $tm = "$h:$m:$s";
	}

	$day = "0".$day if (length($day) < 2);
	$month = "0".$month if (length($month) < 2);
	my $val = "$year-$month-$day $tm";
	display(4,3,"emTimeToNormalDate($em_time)=$val dif=$dif");
	return ($val,$year);
}



sub prettyDate
    # converts a normal date 2013-01-14
    # to a pretty date, January 14, 2013
{
	my $from_date = shift;
	my $ts = $from_date;
    $ts = $monthName[$2-1]." $3, $1" if
        $from_date =~ s/(\d\d\d\d)-(\d\d)-(\d\d)//;
	return $ts;
}


sub prettyShortDate
    # converts a normal date 2013-01-14
    # to a pretty short date, 14-Jan
{
	my $from_date = shift;
    $from_date = "" if (!defined($from_date));
	if ($from_date =~ s/(\d\d\d\d)-(\d\d)-(\d\d)//)
    {
        $from_date = "$3-".substr($monthName[$2-1],0,3);
    }
    return $from_date;
}



sub dateDiffDays
    # given two normal dates, determine number of days between them
    # returns undef if either date does not exist
{
    my ($dt1,$dt2) = @_;
    return if (!$dt1 || !$dt2);

    my $sign = 1;
    if ($dt1 lt $dt2)
    {
        $sign = -1;
        my $dt3 = $dt1;
        $dt1 = $dt2;
        $dt2 = $dt3;
    }

    my $days1 = normalDateToInt($dt1);
    my $days2 = normalDateToInt($dt2);
    return $sign * ($days1 - $days2);
}



sub datePlusDays
{
    my ($dte,$days) = @_;
    return $dte if ($dte !~ /(\d\d\d\d)-(\d\d)-(\d\d)/);
    my ($year,$month,$day) = Date::Calc::Add_Delta_Days($1,$2,$3,$days);
	$day = "0".$day if (length($day) < 2);
	$month = "0".$month if (length($month) < 2);
    return "$year-$month-$day";
}




#----------------------------------------------------------
# File Routines
#----------------------------------------------------------

my $dbg_write_file = 5;

sub writeFileIfChanged
	# write the file if it has changed
	# return 1 if it was written, 0 if not
    # readonly returns 1 IF IT WOULD be ovewritten
{
	my ($filename,$new_text,$read_only) = @_;
    display(9,0,"writeFileIfChanged($filename) new_text=$new_text");
    # display_bytes($dbg_write_file,1,"new_text",$new_text);

	my $needs_write = 0;
	my @new_lines = split(/\n/,$new_text);

    my @old_lines;
	if (open IFILE2,"<$filename")
    {
        @old_lines = <IFILE2>;
        close IFILE2;
    }

    # 2014-04-20 - prh - added this to get songbook
    # to work, hope it doesn't fuck everything else up.

    @old_lines = split("\n",join('',@old_lines));

    #display_bytes($dbg_write_file,1,"old_text",join('',@old_lines));
    #display($dbg_write_file,1,"new_lines=".scalar(@new_lines));
    #display($dbg_write_file,1,"old_lines=".scalar(@old_lines));

	my $line_num = 0;
	while (@old_lines && @new_lines)
	{
		$line_num++;
		my $o = shift @old_lines;
		my $n = shift @new_lines;
		chomp $o;
		chomp $n;
		if ($o ne $n)
		{
            display(5,1,"$filename needs write at line $line_num");
			$needs_write = 1;
			last;
		}
	}
    if (@old_lines || @new_lines)
    {
        display(5,1,"$filename needs write because old_lines=".scalar(@old_lines)." and new_lines=".scalar(@new_lines));
        $needs_write = 1;
    }

    if ($needs_write)
    {
        return 1 if ($read_only);
        display(3,1,"writeFileIfChanged WRITING($filename)");
		if (!open OFILE2,">$filename")
		{
			error("Could not open $filename for writing");
			return;
		}

		print OFILE2 $new_text;
		close OFILE2;
		return 1;
	}
	return 0;
}


sub printVarToFile
{
	my ($isOutput,$filename,$var,$bin_mode) = @_;
	if ($isOutput)
	{
		open OFILE,">$filename" || mydie("Could not open $filename for printing");
		binmode OFILE if ($bin_mode);
		print OFILE $var;
		close OFILE;
	}
}


sub copyTextAndUnlink
{
    my ($ofile,$ifile) = @_;
    my $text = getTextFile($ifile);
    if ($text ne "")
    {
        open OFILE,">>$ofile";
        print OFILE $text;
        close OFILE;
    }
    unlink $ifile;
    return $text;
}


sub getTextFile
{
    my ($ifile,$bin_mode) = @_;
    my $text = "";
    if (open INPUT_TEXT_FILE,"<$ifile")
    {
		#binmode(INPUT_TEXT_FILE, ":utf8");

		binmode INPUT_TEXT_FILE if ($bin_mode);
        $text = join("",<INPUT_TEXT_FILE>);
        close INPUT_TEXT_FILE;
    }
    return $text;
}




sub getTextLines
{
    my ($filename) = @_;
    if (!open(FILE,"<$filename"))
    {
        error("Could not open $filename for reading");
    }
    my @lines = <FILE>;
    close FILE;
    return \@lines;
}


#--------------------------------------------------------
# params
#--------------------------------------------------------


sub parseParams
	# parse the environment query string for args
{
    # if served thru redirect, get query from uri

    my $q = $ENV{REQUEST_URI} || '';
    my $query = (split(/\?/,$q))[1];
    $query = '' if (!defined($query));

   # add regular parameters

    $query .= '&'.$ENV{QUERY_STRING} if $ENV{QUERY_STRING};

	my @args = split(/&/,$query);
	foreach my $arg (@args)
	{
		my ($p1,$p2) = split(/=/,$arg);
		# un-url encode the parameter
        if ($p1 && $p2)
        {
            $p2 =~ s/\+/ /g;
            $p2 =~ s/%(..)/pack("c",hex($1))/ge;
            if ($p1 && $p1 ne "")
            {
                $params{$p1} = $p2;
                display(3,1,"param($p1)=$p2");
            }
        }
	}
}


sub parsePostParams
{
	my $buffer;
	my $len = $ENV{'CONTENT_LENGTH'};
    return if (!$len);
	read(STDIN,$buffer,$len);
	my @pairs = split(/&/,$buffer);
	foreach my $pair (@pairs)
	{
		my ($p1,$p2) = split(/=/,$pair);
		$p1 =~ tr/+/ /;
		$p1 =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C",hex($1))/eg;
		$p2 =~ tr/+/ /;
		$p2 =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C",hex($1))/eg;
		$params{$p1} = $p2;
        display(3,1,"post_params($p1)=$p2")
	}
}

sub parseCookies
{
	my $cookie=$ENV{"HTTP_COOKIE"};
    $cookie = "" if (!defined($cookie));
	$cookie =~ s/\s+//g;			  	# my cookies have no spaces in them
	$cookie =~ s/\n//g;
	my @tcookies = split(";",$cookie);
	foreach my $cook (@tcookies)
	{
		my ($p1,$p2) = split(/=/,$cook);
		$cookies{$p1} = $p2;
	}
}	# parseCookies


sub setCookie
{
    my ($name,$value,$expire_mins) = @_;
    $value = "" if (!defined($value));
    my $expires = "";
    if ($expire_mins)
    {
        my $t = time();
        my $lt = gmtime($t + ($expire_mins * 60));
            # Sun Apr 29 18:58:43 2012
        display(9,0,"lt=$lt");
        $lt =~ /(\w\w\w)\s+(\w\w\w)\s+(\d+)\s+(\d\d:\d\d:\d\d)\s+(\d\d\d\d)/;
        $expires = " Expires=$1, $3 $2 $5 $4 GM;";
    }
    return "Set-Cookie: $name=$value; path=/; $expires\n";
}


sub encode64
    # returns encode_base64
    # WITH the terminating eol
{
    my ($s) = @_;
   	my $retval = encode_base64($s);
    #$retval =~ s/\n$//;
    return $retval;
}


sub decode64
{
    my ($s) = @_;
    return "" if (!defined($s));
   	return decode_base64($s); # ."\n");
}


sub crypt_rc4
{
    my ($msg) = @_;
    my $rc4 = Crypt::RC4->new( "I'll be a monkey's uncle on fridays" );
    return $rc4->RC4( $msg );
}



sub fileExistsRE
{
    my ($dir,$re) = @_;
	if (!opendir IDIR,$dir)
    {
        error("Could not open directory $dir");
        return;
    }
    my @files = readdir IDIR;
	closedir IDIR;

	foreach my $file (sort(@files))
	{
		 return 1 if ($file =~ /$re/i);
    }
}



#----------------------------------------
# obsolete, unused, or interesting routines
#----------------------------------------

sub unused_openDBF
    # unused routines for accessing pos at low level
{
	my ($filename) = @_;
	my $table = new XBase $filename;
	myDie( XBase->errstr ) if (!$table);

	my %hash;
	my @types = $table->field_types();
	my @fields = $table->field_names();
	return ($table,\@fields,\@types);
}


sub unused_getDBF
{
	my %hash;
	my ($table,$r_fields,$rec_num) = @_;
	my @values = $table->get_record($rec_num);
	my $deleted = shift @values;
	if (!$deleted)
	{
		my $num_fields = @$r_fields;
		for (my $i=0; $i<$num_fields; $i++)
		{
			my $val = $values[$i];
			$val = "" if (!defined($val));
			$val =~ s/^\s*|\s$//g;
			display(8,1,"getDBF:: field($i,$$r_fields[$i])=$val");
			$hash{$$r_fields[$i]} = $val;
		}
	}
	return (!$deleted?\%hash:0);
}



sub unused_putDBF
{
	my ($table,$r_fields,$rec_num,$rv) = @_;
	my @values;
	my $num_fields = @$r_fields;
	for (my $i=0; $i<$num_fields; $i++)
	{
		my $val = $$rv{$$r_fields[$i]};
		$val = "" if (!defined($val));
		push @values,$val;
	}
	$table->set_record($rec_num,@values);
}



if (1)
{
    use Symbol;
    sub debug_class
        # interesting routine to figure out what's going
        # with wxWidgets, dumps all of the symbols associated
        # with a class and the class it is inherited from.
        # tricky - the symbol table for the class is in a
        # global hash named %$class::, but turning that string
        # into an actual reference to the hash is not easy
    {
        my ($class) = @_;
        use mro;
        my $mro = mro::get_linear_isa($class);
        for my $subclass (@$mro)
        {
            my $msg = "SUBCLASS";
            my $level = 1;
            if ($subclass eq $class)
            {
                $level = 0;
                $msg = "CLASS";
            }

            display(0,$level,"$msg=$subclass");
            my $ref = qualify_to_ref($subclass.'::');
                # this gives us a glob reference
            my $table = *$ref;
            # dereference the glob to get a reference
            # to the actual hash (the symbol table for
            # the class).
            for my $sym (sort(keys(%$table)))
            {
                display(0,$level+1,pad($sym,30).$$table{$sym});
            }
        }
    }
}


1;
