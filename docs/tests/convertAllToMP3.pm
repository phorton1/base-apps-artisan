#------------------------------------------------------------------
# convertAllToMP3.pm
#------------------------------------------------------------------
# This program is intended to be run once to convert all my
# existing WMA and M4A files to MP3's at 128kbs using ffmpeg.
# It uses /bin/ffmpeg_prebuilt_6.1.exe that I extracted from
# /zip/apps/ffmpeg/ffmpeg-6.1-essentials_build.z7 ffmpeg.exe.
#
# The conversion will reset the datetime stamp on the file
# to what it previoiusly was to retain this bit of information.
#
# It can be run more than once with $DELETE_FILES=0
# It stops dead in it's tracks if it cannot convert a file.


package convertAllToMP3;
use strict;
use warnings;
use Pub::Utils;

my $dbg_cvt = 0;


my $TEST_MODE = 1;
	# will do ONE wma and ONE m4a
my $DELETE_FILES = 0;
	# will delete the wma and m4a files


my $ROOT_DIR = "/mp3s";
my $EXE  = "c:\\base\\apps\\artisan\\bin\\ffmpeg_prebuilt_6.1.exe";
my $ARGS = '-hide_banner -acodec libmp3lame -b:a 128';
my $CONVERT_LOG = "/base_data/temp/artisan/CONVERT_LOG.txt";

# unlink $CONVERT_LOG;


my @convert_files;
my $wma_done = 0;
my $m4a_done = 0;


sub convertLog
{
	my ($msg) = @_;
	if (!open(OFILE,">>$CONVERT_LOG"))
	{
		error("Could not open $CONVERT_LOG for appending");
		return 0;
	}
	print OFILE "\n$msg\n\n";
	close OFILE;
	return 1;
}


sub gatherFiles
	# recurse through the directory tree and
	# add WMA and M4A files to @convert_files array
{
	my ($dir,$level) = @_;
	$level ||= 0;

	my $dh;
    if (!opendir($dh,$dir))
    {
        error("Could not opendir $dir");
        return;
    }
    while (my $entry=readdir($dh))
    {
        next if ($entry =~ /^\./);
        my $fullname = "$dir/$entry";
		if (-d $fullname)
        {
			return if !gatherFiles($fullname,$level+1);
        }
        elsif ($fullname =~ /\.(wma|m4a)$/i)
        {
			push @convert_files,$fullname;
		}
    }
    closedir $dh;
	return 1;
}



sub filenameToWin
{
	my ($filename) = @_;
	$filename =~ s/\//\\/g;
	return "C:$filename";
}


sub convertOne
{
	my ($filename,$ext) = @_;
	display(0,0,"CONVERTING $filename");
	my $ts = getTimestamp($filename);
	display($dbg_cvt,1,"timestamp=$ts");
	my $new_filename = $filename;
	$new_filename =~ s/\.$ext$/\.mp3/;
	display($dbg_cvt,1,"new_filename=$new_filename");
	unlink $new_filename;

	my $oldname = filenameToWin($filename);
	my $newname = filenameToWin($new_filename);

	my $command = "$EXE -i \"$oldname\" $ARGS \"$newname\"";
	# print "\n\ncommand=$command\n\n";

	my $result = `$command 2>&1`;
	if ($result =~ /error/i)
	{
		error($result);
		return 0;
	}
	return if !convertLog($result);

	# print "\n\nresult=$result\n\n";

	setTimestamp($new_filename,$ts);

	unlink $filename if $DELETE_FILES;

	$wma_done++ if $ext eq 'wma';
	$m4a_done++ if $ext eq 'm4a';
	return 1;
}


#-------------------------------------------
# main
#-------------------------------------------

display(0,0,"convertAllToMP3.pm started");

if (gatherFiles($ROOT_DIR,0))
{
	display(0,1,"Found ".scalar(@convert_files)." to convert to MP3");

	for my $filename (@convert_files)
	{
		my $ext = $filename =~ /\.(wma|m4a)$/i ? $1 : '';
		$ext = lc($ext);
		if (!$ext)
		{
			error("Could not get extension from $filename");
			exit 0;
		}

		next if $TEST_MODE && $wma_done && $ext eq 'wma';
		next if $TEST_MODE && $m4a_done && $ext eq 'm4a';
		exit 0 if !convertOne($filename,$ext);
	}

	display(0,0,"Converted $wma_done WMA and $m4a_done M4A files");
}


display(0,0,"convertAllToMP3.pm finished");


1;
