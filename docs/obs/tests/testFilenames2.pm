#!/usr/bin/perl
#---------------------------------------
# testFilenames2.pm
#---------------------------------------
# Strategy:
#
# (1) the database is NOT utf8 encoded on either platform
#     so we should get the same BYTES on both platforms.
# (2) On windows, EVERYTHING is iso-8859-1 (win-1252) and
#     NO DECODING OR ENCODING IS NECESSARY
# (3) On linux the scan takes place in utf8 filenames,
#     the database contains 1252, and we have to KNOW
#     whether we are dealing with a path from the scan,
#     or one from the database, and convert one to the
#     other as needed (grrrr).

package testFilenames2;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Database;
use Encode;
use Time::HiRes qw(stat);


my $test_path = $mp3_dir.'/albums/Blues/Soft/Marc Broussard - Momentary Setback';


sub getLeafFromDir
{
    opendir(DIR,$test_path);
    while (my $entry=readdir(DIR))
    {
        return $entry if $entry =~ /^04 - French/;
	}
	return '';
}


sub database_leaf
{
	my ($dbh,$what,$leaf) = @_;
	my $rec = {
		id => $what,
		path => $leaf };
	insert_record_db($dbh,'tracks',$rec);
	my $found = get_record_db($dbh,"SELECT * FROM tracks WHERE id = '$what'");
	my $found_leaf = $found->{path};

	# paths retreived from the database need to use utf8::downgrade() at some point.
	# utf8::downgrade($found_leaf) if is_win();

	return $found_leaf;
}



sub test
{
	my ($what,$leaf) = @_;
	my $path = "$test_path/$leaf";
	showString("TESTING $what($leaf)",$leaf);

   	my @fileinfo = stat($path);
	my $size = $fileinfo[7];
	if ($size)
	{
		display(0,1,"$what size=$size");
	}
	else
	{
		error("$what could not get size");
	}

	if (open(IFILE,"<$path"))
	{
		display(0,1,"$what OPENED");
		close IFILE;
	}
	else
	{
		error("$what could not open");
	}

}



sub showString
{
	my ($what,$string) = @_;
	# my $is_utf8 = utf8::is_utf8($string) ? 1 : 0;
	my $is_utf8 = Encode::is_utf8($string) ? 1 : 0;
	my $valid =  utf8::valid($string);
	display_bytes(0,0,"$what($is_utf8,$valid) $string",$string);
}


sub getdbh
{
	my $db_name = "$temp_dir/test.db";
	unlink $db_name;
	my $dbh = db_connect($db_name);
	create_table($dbh,"tracks");
	return $dbh;
}




# main
# Comments are 'is_utf8' char code(s) for accented e

display(0,0,"testFilenames.pm started");
my $dbh = getdbh();

my $pm_leaf = '04 - French Café.mp3';
showString("pm_leaf",$pm_leaf);

my $use_pm_leaf = is_win() ? $pm_leaf : Encode::encode("utf-8",$pm_leaf);;
test('use_pm_leaf',$use_pm_leaf);
	# should work on either platform
	# as we convert THIS file's 1252 to utf on linux

my $dir_leaf = getLeafFromDir();
test('dir_leaf',$dir_leaf);
	# shouild work on either platform as we
	# use the native encoding from the directory scan

my $save_dir_leaf = is_win() ? $dir_leaf : Encode::decode("utf-8",$dir_leaf);
showString("save_dir_leaf",$save_dir_leaf);
	# for storing in databzse, convert utf8 to 1252 on linux
my $db_dir_leaf = database_leaf($dbh,'save_dir_leaf',$save_dir_leaf);
showString("db_dir_leaf",$db_dir_leaf);
	# should get back exactly what we stored

my $use_leaf = is_win() ? $db_dir_leaf : Encode::encode("utf-8",$db_dir_leaf);;
test('use_leaf',$use_leaf);
	# should work on either platform as we convert the 1252 from
	# the database to utf8 on linux


display(0,0,"testFilenames.pm finished");


1;










1;
