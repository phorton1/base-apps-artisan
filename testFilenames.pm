#---------------------------------------
# testFilenames.pm
#---------------------------------------
# Attempt to put to rest filename encoding issues

package testFilenames;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Encode;

my $test_path = $mp3_dir.'/albums/Blues/Soft/Marc Broussard - Momentary Setback';
my $test_leaf = '04 - French Café.mp3';
my $test_file = "$test_path/$test_leaf";


sub getLeafFromDir
{
    opendir(DIR,$test_path);
    while (my $entry=readdir(DIR))
    {
        return $entry if $entry =~ /^04 - French/;
	}
	return '';
}


sub testLeaf
{
	my ($what,$leaf) = @_;
	my $path = "$test_path/$leaf";
	display(0,0,"test $what $leaf");

   	my @fileinfo = stat($path);
	my $size = $fileinfo[7];
	display(0,1,"$what size=$size");

	if (open(IFILE,"<$path"))
	{
		display(0,1,"$what OPENED");
		close IFILE;
	}
	else
	{
		display(0,1,"$what COULD NOT OPEN");
	}
}




# main

display(0,0,"testFilenames.pm 2 started");

display_bytes(0,1,"test_leaf",$test_leaf);
display(0,0,"huh");
testLeaf('test',$test_leaf);

my $dir_leaf = getLeafFromDir();
display_bytes(0,1,"dir_leaf",$dir_leaf);
testLeaf('dir',$dir_leaf);


display(0,0,"testFilenames.pm finished");


1;










1;
