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
# I wish I could force SQLite to use 1252 (or essentially NO encoding)










# Attempt to put to rest filename encoding issues.
#
# 1. As far as I can tell, raw filenames gotten from the directory
#    work, when passed back in, on both platforms.
# 2. The string constant $test_leaf needed to be encoded to utf-8
#    on linux because THIS file is encoded with 1252 ...
#
# We can either use sqlite_unicode=>1 in SQLite.pm, or not.
# Directory scan on Windows returns 1252 encoded strings.
# Directory scan on Linux returns utf8 encoded strings.
#
# The issue arises when we try to use the database created on
# windows on the linux machine. If I DONT use sqlite_unicode=>1,
# and re-run the scan on Linux, everything seems to work with
# no other decoding needed, but the database cannot be copied
# and used.
#
# If I DO use sqlite_unicode=>1, then, on windows, I need to
# know when a path comes from the database as opposed to a scan,
# and if it comes from the database, call utf8::downgrade on it.
#
# I have attempted to encapsulate this by creating artisanUtils::
# fixDBFilename() in the case of sqlite_unicode=>1, BUT there
# is still a call to MediaFile->new() using a database, rather
# than a scanned path name.

#
# If I dont use , then everything works
# on windows, but I will have a host of problems on linux, not only
# with filenames, but all displayable strings.
#
# So, the simplest solution is to (continue to) use sqlite_unicode=>1
# in the database, and 'demote' the utf8 filenames upon usage in
# windows.

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
my $default_db = "$temp_dir/testFilenames_default.db";
my $unicode_db = "$temp_dir/testFilenames_unicode.db";


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
	utf8::downgrade($found_leaf) if is_win();

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
my $utf8_dir_leaf = Encode::encode("utf-8",$dir_leaf);
my $iso_dir_leaf = Encode::encode('iso-8859-1',$dir_leaf);
showString("orig dir_leaf",$dir_leaf);
showString("utf8 dir_leaf",$utf8_dir_leaf);
showString("iso  dir_leaf",$iso_dir_leaf);


$SQLite::SQLITE_UNICODE = 1;


# my $dbh = db_connect($test_db);
# create_table($dbh,"tracks");



#
# my $dbpm_leaf = database_leaf($dbh,'pm',$pm_leaf);
# my $dbdir_leaf = database_leaf($dbh,'dir',$dir_leaf);
#
# test('pm',$pm_leaf);
# test('dir',$dir_leaf);
# test('dbpm',$dbpm_leaf);
# test('dbdir',$dbdir_leaf);


display(0,0,"testFilenames.pm finished");


1;










1;
