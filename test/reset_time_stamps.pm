#!/usr/bin/perl
#---------------------------------------
# 2015-06-21
#
# For any media files in current tree with date time stamps of 2015,
# get the MediaFile object to get the fpcalc_id, which *should* be
# the same as artisan_id is the same as the given file in
# C:\mp3s_backups\2014-12-18-deployed_to_car_stereo, get the
# date_timestamp from the old database and apply it to the
# file.
#
# Before we do that, we would like to start keeping a "tagging history"
# in the files that indicate the year, month, and day of any tag
# or MP3Diag changes. 

use strict;
use warnings;
use Utils;
use SQLite;
use History;
 

my $dbg_reset = 0;



#--------------------------------
# routines
#--------------------------------

sub get_files_by_field
    # get all the track records from the given database
    # inlcuding the md5 fpcalc id, which is given by the
    # $id_field parameter, and the full_path to the file,
    # and put them in a hash by that fpcalc id, noting any
    # duplicates as warnings.
{
    my ($dbh,$id_field) = @_;
    my $recs_by_id = {};
    my $recs_by_fullname = {};
    
    display(0,0,"get_files_by_field($id_field)");
    
    my $recs = get_records_db($dbh,"select $id_field,FULLNAME,TIMESTAMP from TRACKS");
    return if !$recs;
    
    if (!@$recs)
    {
        error("no records found for id_field=$id_field");
        return;
    }
    
    my $num_dups = 0;
    for my $rec (@$recs)
    {
        my $id = $rec->{$id_field};
        my $exists = $recs_by_id->{$id};
        if ($exists)
        {
            $num_dups++;
            display(2,1,"id($id) for($rec->{FULLNAME}) already exists in $exists->{FULLNAME}");
        }
        $recs_by_id->{$id} = $rec;
        $recs_by_fullname->{$rec->{FULLNAME}} = $rec;
    }
    
    warning(0,1,"$num_dups duplicate IDs found") if ($num_dups);
    return ($recs_by_id,$recs_by_fullname);
}
 
 
sub compare_strings
    # compare two strings and return their common
    # portion, and any differences
{
    my ($s1,$s2) = @_;
    my $l = length($s1)>length($s2) ? length($s1) : length($s2);
    my $i;
    for ($i=0; $i<$l; $i++)
    {
        last if substr($s1,$i,1) ne substr($s2,$i,1);
    }
    my $diff1 = $s1;
    my $diff2 = $s2;
    my $common = '';
    
    if ($i && $i < $l)
    {
        $common = substr($s1,0,$i);
        $diff1 = $i < length($s1) ? substr($s1,$i) : '';
        $diff2 = $i < length($s2) ? substr($s2,$i) : '';
    }
    
    return ($common,$diff1,$diff2);
}



#-----------------------------------
# do_initial_analysis
#------------------------------------

sub do_initial_analysis
{
    my ($new_by_name,$old_by_id) = @_;
    
    for my $new_path (sort(keys(%$new_by_name)))
    {
        my $new_rec = $new_by_name->{$new_path};
        my $id = $new_rec->{FPCALC_ID};
        my $old_rec = $old_by_id->{$id};
        my $add_event = 0;        
        
        # note any changes
        
        if (!$old_rec)
        {
            error("Could not find old_rec($id) for $new_path");
        }
        elsif ($old_rec->{TIMESTAMP} ne $new_rec->{TIMESTAMP})
        {
            $add_event = 1;
            warning(0,1,"TIMESTAMP($id,$old_rec->{TIMESTAMP},$new_rec->{TIMESTAMP} for $new_path");
        }
        elsif ($old_rec->{FULLNAME} ne $new_rec->{FULLNAME})
        {
            my ($common,$diff1,$diff2) = compare_strings($old_rec->{FULLNAME},$new_rec->{FULLNAME});
            display(2,1,"CHANGE($common,$diff1) changed to $diff2");
        }


        # see if there's a history and validate it if there is
        

        my $ts = get_most_recent_track_change_history_timestamp($id);
        if ($ts)
        {
            display(2-$add_event,2,"got history timestamp-".History::dateToLocalText($ts));
            if ($ts != $new_rec->{TIMESTAMP})
            {
                error("history($id.txt)=".
                      History::dateToLocalText($ts).
                      " is not the same as current timestamp=".
                      History::dateToLocalText($new_rec->{TIMESTAMP}))
            }

            # if there is a history, and there's a change_event, go ahead and
            # reset the timestamp on the file and generate another event.

            elsif ($add_event)
            {
                my $local_str = History::dateToLocalText($old_rec->{TIMESTAMP});
                LOG(1,"Setting timestamp($local_str) for $id=$new_rec->{FULLNAME})");
                exit 1 if !My::Utils::setTimestamp("$mp3_dir/$new_rec->{FULLNAME}",$local_str,1);
                exit 1 if !add_track_change_history_event($id,$old_rec->{TIMESTAMP}."from initial reset_timestamps.pm");
            }
        }
        else  # otherwise, create a new history
        {
            exit 1 if !new_history_from_textdates($id,"2015-06-10 12:00:00","2015-06-21 13:00:00",$new_rec->{TIMESTAMP},"initial setting");
        }
    }
}





sub set_initial_notes
{
    my ($new_by_id) = @_;
    display(0,0,"setting initial notes");
    for my $id (sort(keys(%$new_by_id)))
    {
        my $rec = get_track_change_history($id);
        if (!$rec)
        {
            error("Could not get histor for $id");
            exit 1;
        }
        
        display(0,1,"setting initial notes on($id)");
        
        my $num = 0;
        my $history = $rec->{history};
        for my $found_at (sort{ $a <=> $b} keys(%$history))
        {
            my $item = $history->{$found_at};
            $item->{note} = $num++ ? "from initial reset_timestamps.pm" : "initial setting";
        }
        exit 1 if !History::write_track_change_history($id,$rec);
    }
}

    
#--------------------------------
# main
#--------------------------------
# oops, forgot to add meaningful notes

display(0,0,"reset_time_stamps.pm started ...");

my $old_dbh = sqlite_connect("/mp3s_backups/2014-12-18-deployed_to_car_stereo/_data/artisan.db",'artisan','');
my $new_dbh = sqlite_connect("$cache_dir/artisan.db",'artisan','');
my ($old_by_id,$old_by_name) = get_files_by_field($old_dbh,"ARTISAN_ID");
my ($new_by_id,$new_by_name) = get_files_by_field($new_dbh,"FPCALC_ID");


if ($old_by_id && $new_by_id)
{
    do_initial_analysis($new_by_name,$old_by_id);
    #set_initial_notes($new_by_id,$old_by_id);
}



# finished

sqlite_disconnect($old_dbh);
sqlite_disconnect($new_dbh);
display(0,0,"reset_time_stamps.pm finished ...");

1;
