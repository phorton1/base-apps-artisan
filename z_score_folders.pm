#---------------------------------------
# score_folders.pm
#---------------------------------------
use strict;
use warnings;
use Utils;
use Database;
use x_mbUtils;
use x_mbScoreFolder;


$debug_level = 0;
$warning_level = 0;
$debug_packages = join('|',(
    'utils',    # needed to see stats
    'z_score_folders',
    'x_mbScoreFolder',
    'x_mbUtils',
));

    
$logfile = "$log_dir/score_folder.log";
unlink $logfile;
unlink $error_logfile;


#----------------------------------------------------
# utilities
#----------------------------------------------------


sub pad_right
{
    my ($s,$len) = @_;
    while (length($s) < $len) {$s = ' '.$s; }
    return $s;
}

sub roundTwoRight
{
    my ($num,$len) = @_;
    return pad_right(roundTwo($num),$len);
}
        


#----------------------------------------------------
# unused utilities
#----------------------------------------------------


sub my_compare
    # for debugging only at this time
    # compare two (resolved) artisan ids
    # to sort them by medium_position and track_position
{
    my ($artisan_ids,$a,$b) = @_;
    my $rec1 = $artisan_ids->{$a};
    my $rec2 = $artisan_ids->{$b};

    my $val1 =
        $rec1->{medium}->{position} * 10000 +
        $rec1->{track}->{position};
    my $val2 =
        $rec2->{medium}->{position} * 10000 +
        $rec2->{track}->{position};
        
    return $val1 <=> $val2;
}


sub display_artisan_ids_by_media_tracknum
    # for debugging only at this time
{
    my ($dbg,$level,$artisan_ids) = @_;
    my @sorted = sort { my_compare($artisan_ids,$a,$b) } 
        keys(%$artisan_ids);
        
    for my $artisan_id (@sorted)
    {
        my $rec = $artisan_ids->{$artisan_id};
        display($dbg,$level,"$artisan_id   medium($rec->{medium}->{position})  track($rec->{track}->{position})  '$rec->{track}->{title}'");
    }
}



#------------------------------------------------------------
# the test routine
#------------------------------------------------------------


sub test_folders
{
    my ($dbh,$path) = @_;
    display(0,0,"test_folders path=$path");
    my $albums = get_records_db($dbh,"SELECT * FROM FOLDERS WHERE DIRTYPE='album' ORDER BY FULLPATH");

    # for each album (folder), get it's tracks (files)
    # and score the folder using musicBrainz
    
    for my $album (@$albums)
    {
        next if substr($album->{FULLPATH},0,length($path)) ne $path;
        my $tracks = get_records_db($dbh,"SELECT * FROM TRACKS WHERE PARENT_ID='$album->{ID}' ORDER BY FULLNAME");
        my $num_tracks = scalar(@$tracks);
        bump_stat("num_tracks",$num_tracks);
        bump_stat("num_albums");

        # score the folder
        
        display(1,0,"------------------------------------------------------------------------------------------------");
        my $tree = mb_score_folder($album,$tracks);
        next if (!$tree);
        
        # display the results
        # heeader
        
        display(_clip 0,0, 
            roundTwoRight($tree->{score},7).
            " | ".
            pad($tree->{match_count},4).
            pad(scalar(@$tracks),4).
            #" | ".
            #roundTwoRight($tree->{match_pct},7).
            #roundTwoRight($tree->{fill_match_pct},7).
            #" | ".
            #roundTwoRight($tree->{score_count},7).
            #roundTwoRight($tree->{score_pct},7).
            #roundTwoRight($tree->{fill_score_pct},7).
            #" | ".
            pad($album->{PATH},40)." ".
            "$album->{ARTIST} - $album->{TITLE}");
            #$album->{NAME});
        
        # show the releasegroups, releases and mediums
        # in the result sset

        if ($tree->{releasegroups})
        {
            my $rgid = '';
            for my $releasegroup (@{$tree->{releasegroups}})
            {
                my $rid = '';
                for my $release (@{$releasegroup->{releases}})
                {
                    my $artist = mb_get_object_artist($release);
                    for my $medium (@{$release->{mediums}})
                    {
                        my $tracks = $medium->{tracks};
                        my $num_tracks = scalar(@$tracks);
                                            
                        my $left = $releasegroup->{id} eq $rgid ? '   ' : 'rg ';
                        $left .= $release->{id} eq $rid ? '  ' : 'r ';
                        $left .= "m ".pad($num_tracks,3)." ".pad(scalar($medium->{track_count}),3)." ";
                        my $title = $release->{title};
                        my $addl_title = '';
                        if ($medium->{title})
                        {
                            $addl_title = '#:'.$medium->{title};
                        }
                        elsif ($release->{medium_count}>1)
                        {
                            $addl_title = '#:# '.$medium->{position};
                        }
                        
                        $artist =~ s/[^\x20-\xff]/#C#/g;
                        $title =~ s/[^\x20-\xff]/#C#/g;
                        $addl_title =~ s/[^\x20-\xff]/#C#/g;
                        display(_clip 0,0,pad('',42).pad($left,16)." $artist - $title.$addl_title");
    
                        $rid = $release->{id};                
                        $rgid = $releasegroup->{id};
                    }
                }
            }
        }

        # show errors
        
        if (1 && $tree->{errors})
        {
            for my $msg (@{$tree->{errors}})
            {
                display(_clip 0,0,pad('',8).pad('mb_error',10).$msg);
            }
        }
        
        # show the members of the resulting tree
        
        for my $k (sort(keys(%$tree)))
        {
            display(2,1,pad($k,20)." = $tree->{$k}")
                if !ref($tree->{$k});
        }
    }
}

    

#---------------------------------------------
# main
#---------------------------------------------


sub test_main
{
    #my $path = '/mp3s/albums/Blues/New/Blue By Nature - Blue To The Bone';
    #my $path = '/mp3s/albums/Blues/New';
    #my $path = '/mp3s/albums/Blues/Soft/Keb Mo - Keb Mo';
    #my $path = '/mp3s/albums/Classical';
    #my $path = '/mp3s/albums/Blues';
    #my $path = '/mp3s/albums';
    my $path = '/mp3s';
    
    LOG(0,"fix_library.pm started");
    
    db_initialize();
    my $dbh = db_connect();
    test_folders($dbh,$path);
    db_disconnect($dbh);
    dump_stats('');
    
    LOG(0,"fix_library.pm finished");
}


test_main();

1;
