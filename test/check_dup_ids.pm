#!/usr/bin/perl
#---------------------------------------

use strict;
use warnings;
use Utils;
use Database;


my $REMOVE_EXTRA_FPCALC_INFO_FILES = 1;


sub show_non_unique_ids
{
    my ($field) = @_;
    
    my $dbh = db_connect();
    my $ids = get_records_db($dbh,"select $field, count($field) as count from TRACKS group by $field");
    
    display(0,0,"found ".scalar(@$ids)." $field");
    for my $id (@$ids)
    {
        if ($id->{count} > 1)
        {
            my $recs = get_records_db($dbh,"select FULLNAME from TRACKS where $field='$id->{$field}' order by FULLNAME");
            display(0,1,"$field($id->{$field}) count=$id->{count}");
            for my $rec (@$recs)
            {
                display(0,2,"$rec->{FULLNAME}");
            }
        }
    }
    
    db_disconnect($dbh);
}




#-------------------------------------------
# look for fpcalc files that are unused 
#-------------------------------------------

sub check_artisan_ids
{
    my %artisan_id_used;

    display(0,0,"get_existing_fpcalc_filenames()");
    if (!opendir(DIR,"$cache_dir/fpcalc_info"))
    {
        error("Could not open fpcalc_info dir");
        exit 1;
    }
    while (my $entry = readdir(DIR))
    {
        next if ($entry !~ s/\.txt$//);
        $artisan_id_used{$entry} = 1;
    }
    closedir(DIR);


    display(0,0,"mark_fpcalc_filenames_used()");
    my $num_missing = 0;
    my $dbh = db_connect();
    my $recs =   get_records_db($dbh,"select ARTISAN_ID from TRACKS");
    for my $rec (@$recs)
    {
        my $artisan_id = $rec->{ARTISAN_ID};
        if (!$artisan_id_used{$artisan_id})
        {
            display(0,1,"NO FPCALC file for ARTISAN ID=$artisan_id  path=$rec->{FULLNAME}");
            $num_missing++;
        }
        else
        {
            $artisan_id_used{$artisan_id} = 2;
        }
    }
    error("MISSING $num_missing FPCALC FILES") if $num_missing;
    db_disconnect($dbh);


    display(0,0,"show_unused_fpcalc_filenames()");
    my $num_extra = 0;
    for my $artisan_id (sort(keys(%artisan_id_used)))
    {
        next if $artisan_id_used{$artisan_id} == 2;
        display(0,1,"unused fpcalc file($artisan_id.txt) found!");
        unlink "$cache_dir/fpcalc_info/$artisan_id.txt" if $REMOVE_EXTRA_FPCALC_INFO_FILES;
        $num_extra++;
    }
    error("FOUND $num_extra EXTRA FPCALC FILES") if $num_extra;

}




#------------------------------------------
# main
#------------------------------------------

display(0,0,"test.pm started");

db_initialize();

show_non_unique_ids('ARTISAN_ID');
show_non_unique_ids('FPCALC_ID');
check_artisan_ids();

# finished

display(0,0,"test,pm finished");


1;
