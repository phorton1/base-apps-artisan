#!/usr/bin/perl
#---------------------------------------
# testFilenames.pm
#---------------------------------------
# Attempt to put to rest filename encoding issues.
#
# 1. As far as I can tell, raw filenames gotten from the directory
#    work, when passed back in, on both platforms.
# 2. The string constant $test_leaf needed to be encoded to utf-8
#    on linux because THIS file is encoded with 1252 ...
# 3. artisan/SQLite.pm uses 'sqlite_unicode=>1'.
#    I create a test database /$temp_dir/testFilenames.db",
#    with a 'tracks' table, and insert records into it
#    and then retrieve them.

package testFilenames;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Database;
use Encode;

my $test_db = "$temp_dir/testFilenames.db";
my $test_path = $mp3_dir.'/albums/Blues/Soft/Marc Broussard - Momentary Setback';
my $pm_leaf = '04 - French Café.mp3';

unlink $test_db;

# $pm_leaf = fix1252String($pm_leaf) is the same, I think, as:
# utf8::downgrade($pm_leaf);
# $pm_leaf = Encode::encode("utf-8",$pm_leaf);

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
	# utf8::downgrade($found_leaf);

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




# main

display(0,0,"testFilenames.pm 2 started");
my $dir_leaf = getLeafFromDir();

my $dbh = db_connect($test_db);
create_table($dbh,"tracks");

my $dbpm_leaf = database_leaf($dbh,'pm',$pm_leaf);
my $dbdir_leaf = database_leaf($dbh,'dir',$dir_leaf);

test('pm',$pm_leaf);
test('dir',$dir_leaf);
test('dbpm',$dbpm_leaf);
test('dbdir',$dbdir_leaf);


display(0,0,"testFilenames.pm finished");


1;










1;
