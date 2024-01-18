#!/usr/bin/perl
#---------------------------------------
# testFilenames.pm
#---------------------------------------
# This is so damned complicated.
# Just dealing with filenames is a pain.
# There is also MP3 metadata decoding, and the webUI to consider.
#
# Windows scans filenames in 1252 (Latin)
#		accented e == 0xE9
# Linux scans filenames in UTF8
#		accented e = 0xC3 0xA9
# Currently, the webUI is expecting 1252 encoding
#		after being variously json and/or url encoded
#
# Default SQLite encoding is platform specific, with
# 	windows 1252 and linux UTF???
# and can be forced to UTF8 (unicode)
#
# Various methods compare filenames.  Some can be 'known'
# 	to be using scan or database filenames, but others
#   cannot.
#
# 1. As far as I can tell, raw filenames gotten from the directory
#    work, when passed back in, on both platforms.
# 2. The string constant $test_leaf needed to be encoded to utf-8
#    on linux because THIS file is encoded with 1252 ...

package testFilenames;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Database;
use Encode;
use Time::HiRes qw(stat);


my $test_path = $mp3_dir.'/albums/Blues/Soft/Marc Broussard - Momentary Setback';



# $pm_leaf = fix1252String($pm_leaf) is the same, I think, as:
# utf8::downgrade($pm_leaf);



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
	display_bytes(0,0,"$what($leaf)",$leaf);

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



# main
# Comments are 'is_utf8' char code(s) for accented e

display(0,0,"testFilenames.pm started");

my $pm_leaf = '04 - French Café.mp3';
my $utf8_pm_leaf = Encode::encode("utf-8",$pm_leaf);
my $iso_pm_leaf = Encode::encode('iso-8859-1',$pm_leaf);
showString("orig pm_leaf",$pm_leaf);
showString("utf8 pm_leaf",$utf8_pm_leaf);
showString("iso  pm_leaf",$iso_pm_leaf);


my $dir_leaf = getLeafFromDir();
	# windows: 0xE9  linux: 0xC3 A9
	# in neither case is the utf8 flag set automagially

# utf8::upgrade($dir_leaf);
	################################################################
	# ONE - calling this turns the utf-8 flag on without
	#       changing the string from C3 A9 on linux
	################################################################

my $utf8_dir_leaf = Encode::encode("utf-8",$dir_leaf);
my $iso_dir_leaf = Encode::encode('iso-8859-1',$dir_leaf);
	################################################################
	# TWO - this DOES NOT WORK to change ONE to E9
	################################################################


showString("orig dir_leaf",$dir_leaf);
showString("utf8 dir_leaf",$utf8_dir_leaf);
showString("iso  dir_leaf",$iso_dir_leaf);



my $decode_dir_leaf = Encode::decode("utf-8",$dir_leaf);
showString("iso  decode_dir_leaf",$decode_dir_leaf);



$SQLite::SQLITE_UNICODE = 0;


sub getdbh
{
	my ($unicode) = @_;
	my $db_name = "$temp_dir/test_".($unicode?"unicode":"default").".db";
	unlink $db_name;
	$SQLite::SQLITE_UNICODE = $unicode;
	my $dbh = db_connect($db_name);
	# $dbh->{sqlite_string_mode} = DBD_SQLITE_STRING_MODE_BYTES
	#	if !$unicode;
	create_table($dbh,"tracks");
	return $dbh;
}



my $default_dbh = getdbh(0);
my $unicode_dbh = getdbh(1);

my $default_pm_leaf  = database_leaf($default_dbh,'pm',$pm_leaf);
my $default_dir_leaf = database_leaf($default_dbh,'dir',$dir_leaf);
my $unicode_pm_leaf  = database_leaf($unicode_dbh,'pm',$pm_leaf);
my $unicode_dir_leaf = database_leaf($unicode_dbh,'dir',$dir_leaf);

showString("default_pm_leaf",	$default_pm_leaf);
showString("unicode_pm_leaf",	$unicode_pm_leaf);
showString("default_dir_leaf",	$default_dir_leaf);
showString("unicode_dir_leaf",	$unicode_dir_leaf);


# test('pm',$pm_leaf);
# test('dir',$dir_leaf);
# test('dbpm',$dbpm_leaf);
# test('dbdir',$dbdir_leaf);


display(0,0,"testFilenames.pm finished");


1;










1;
