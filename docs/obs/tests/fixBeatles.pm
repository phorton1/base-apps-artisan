#------------------------------------------------------------------
# fixBeatles.pm
#------------------------------------------------------------------
# Renames certain files

package fixBeatles;
use strict;
use warnings;
use File::Copy;
use Pub::Utils;

my $DOIT = 1;


my @beatles_files;

my $ROOT_DIR = "/junk/Beatles";



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
		else
		{
			push @beatles_files,$fullname;
		}
    }
    closedir $dh;
	return 1;
}


sub doOne
{
	my ($filename) = @_;
	my $oldname = $filename;

	my @parts = split(/\//,$filename);
	my $root = pop(@parts);

	if ($root eq 'Folder.jpg')
	{
		$root = 'folder.jpg';
	}
	else
	{


		$root =~ s/The Beatles - //;
			# remove redundant group name

		# convert 'NN.' track numbers to 'NN - '
		# 04.I Need You

		$root =~ s/^(\d+)(\.| )/$1 - /
			if $root !~ /^(\d+) - /;

		$root =~ s/  / /g;
	}

	push @parts,$root;
	$filename = join('/',@parts);

	if ($oldname ne $filename)
	{
		warning(0,0,"rename $oldname");
		display(0,1,"to $filename");
		if ($DOIT && !move($oldname,$filename))
		{
			error("Could not rename '$oldname' to '$filename'");
			return 0;
		}
	}

	return 1;
}


#-------------------------------------------
# main
#-------------------------------------------

display(0,0,"fixBeatles.pm started");

if (gatherFiles($ROOT_DIR,0))
{
	my $msg = "Found ".scalar(@beatles_files)." Beatles filenames";
	display(0,1,$msg);

	for my $filename (@beatles_files)
	{
		exit 0 if !doOne($filename);
	}
}


display(0,0,"fixBeatles.pm finished");


1;
