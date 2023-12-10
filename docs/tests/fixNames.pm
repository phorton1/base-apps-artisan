#------------------------------------------------------------------
# fixNames.pm
#------------------------------------------------------------------
# Renames certain files

package fixNames;
use strict;
use warnings;
use File::Copy;
use Pub::Utils;

my $DOIT = 1;

my $remove = [
	" Brian's Tunes Rock",
	" Pure 80's Rock",
	" This is Acid Jazz \\[Instinct\\] Jazz",
	" Prince The Hits 2 Rock",
	" Prince The Hits The B-Sides",
	" The Rolling Stones Forty Licks Disc 2 Rock",
	" The Rolling Stones Forty Licks",
	" Duets Soundtrack",
	" Matrix Soundtrack",
	" New Power Generation; Prince; Rosie Gaines The Hits The B-Sides",
	" \\[#\\]",
	"\\[#\\]",
];


my @fix_names;

my $ROOT_DIR = "/mp3s";
my $CONVERT_LOG = "/base_data/temp/artisan/CONVERT_LOG.txt";

# unlink $CONVERT_LOG;


sub convertLog
{
	my ($msg) = @_;
	if (!open(OFILE,">>$CONVERT_LOG"))
	{
		error("Could not open $CONVERT_LOG for appending");
		return 0;
	}
	print OFILE "$msg\n";
	close OFILE;
	return 1;
}



sub matches
{
	my ($filename) = @_;
	my $show = 0; #  $filename =~ /Rolling Stones/;
	print "matches($filename)\n" if $show;
	for my $re (@$remove)
	{
		print "filename=$filename re=$re\n" if $show;
		return 1 if $filename =~ /$re/;
	}
	return 0;
}

sub fixOne
{
	my ($filename) = @_;
	my $old_name = $filename;
	for my $re (@$remove)
	{
		$filename =~ s/$re//;
	}

	warning(0,0,"rename $old_name");
	display(0,1,"to $filename");
	convertLog("renaming '$old_name' to '$filename'");


	if ($DOIT && !move($old_name,$filename))
	{
		error("Could not rename '$old_name' to '$filename'");
		return 0;
	}

	return 1;
}


sub gatherFiles
	# recurse through the directory tree and
	# adds names that match REs to list
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
		elsif (matches($fullname))
		{
			push @fix_names,$fullname;
		}
    }
    closedir $dh;
	return 1;
}




#-------------------------------------------
# main
#-------------------------------------------

display(0,0,"fixNames.pm started");

if (gatherFiles($ROOT_DIR,0))
{
	my $msg = "Found ".scalar(@fix_names)." filenames to fix";
	display(0,1,$msg);
	convertLog($msg);

	for my $filename (@fix_names)
	{
		exit 0 if !fixOne($filename);
	}
}


display(0,0,"fixNames.pm finished");


1;
