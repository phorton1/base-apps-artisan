#!/usr/bin/perl
#---------------------------------------
# analyze_library.pm
#
# Look at the folder tree in albums,singles, and unresolved,
# and note certain folder error conditions.

use strict;
use warnings;
use artisanUtils;
use Database;

my $CHECK_ARTISTS = 1;
    # give an error if album in albums/singles does not
    # have corresponding artist textfile in /mp3s/_data/artists
my $REMOVE_UNUSED_FPCALC_INFO = 1;
    # remove unused /mp3s/_data/fpcalc_info files
my $RENAME_MISCAPPED_FOLDER_JPG = 1;
    # rename miscapitlized folder.jpg files
my $RENAME_UPPERCASE_FILEXT = 1;
    # rename .MP3 to .mp3, etc



my @scan_dirs = (
    '/mp3s/albums',
    '/mp3s/singles',
    '/mp3s/unresolved',
    );
    
my $audio_file_re = '\.(mp3|wma|wav|m4a)$';
    # actual types in my library
    
    

#------------------------------------------
# scanner
#------------------------------------------

sub scan_dir
{
    my ($dir) = @_;
    display(2,0,"scan_dir($dir)");

    my $has_folder_jpg = 0;
    my @tracks;
    my @files;
    my @subdirs;
    
    if (!opendir(DIR,$dir))
    {
        error("Could not opendir $dir");
        return;
    }
    while (my $entry=readdir(DIR))
    {
        next if ($entry =~ /^\./);
        my $filename = "$dir/$entry";
        if (-d $filename)
        {
            push @subdirs,$entry;
        }
        elsif ($entry =~ /folder\.jpg/i)
        {
            $has_folder_jpg = 1;
            if ($entry ne 'folder.jpg')
            {
                if ($RENAME_MISCAPPED_FOLDER_JPG)
                {
                    LOG(0,"renaming $dir/$entry to folder.jpg");
                    rename "$dir/$entry","$dir/folder.jpg";
                }
                else
                {
                    report_error($dir,"$entry not capitalized correctly");
                }
            }
        }
        elsif ($entry =~ /$audio_file_re/i)
        {
            if ($RENAME_UPPERCASE_FILEXT &&
                $entry !~ /$audio_file_re/)
            {
                my $new_entry = $entry;
                $new_entry =~ s/$audio_file_re//i;
                my $ext = lc($1);
                $new_entry .= ".$ext";

                LOG(0,"renaming $entry to $new_entry");
                rename("$dir/$entry","$dir/$new_entry");
                $entry = $new_entry;
            }
                
            push @tracks,$entry;
            mark_as_used("$dir/$entry");
        }
        else
        {
            push @files,$entry;
        }
    }
    
    closedir DIR;

    my $album_or_single = $dir =~ /^\/mp3s\/(albums|singles)/ ? 1 : 0;

    if (@tracks)
    {
        report_error($dir.
            "\nfiles:\n".join("\n",@files).
            "\nsubdirs:\n".join("\n",@subdirs),
            'album has unknown files or subdirecties:') if (@files || @subdirs);
        
        report_error($dir,'no album art') if $album_or_single && !$has_folder_jpg;
        
        my @parts = split(/\//,$dir);
        my $artist_album = pop(@parts);
        my $is_dead = $dir =~ /\/Dead\// ? 1 : 0;
        my @name_parts = split(/ - /,$artist_album);

        if ($is_dead)
        {
            report_error($dir,'dead album title with a dash in it') if (@name_parts > 1)
        }
        else
        {
            if (@name_parts != 2)
            {
                report_error($dir,'album title does not have exactly one dash in it');
                
                # onetime code to toss 2nd dash and following text in unresolved items
                
                if (0 && !$album_or_single)
                {
                    my $new_name = join('/',@parts).'/'.$name_parts[0].' - '.$name_parts[1];
                    LOG(0,"renaming '$dir' to $new_name");
                    rename $dir,$new_name;
                }
            }

            # note substitution of 'and' for '&' in artist names
            
            if ($album_or_single)
            {
                my $artist = $name_parts[0];
                $artist =~ s/^\s*//;
                $artist =~ s/\s*$//;
                $artist =~ s/&/and/;
                report_error($dir,"artist($artist) text file not found")
                    if ($CHECK_ARTISTS &&
                        $artist !~ /^(various|Original Soundtrack)$/i &&
                        !(-f "$cache_dir/artists/$artist.txt"));
            }
        }
        
    }
    else
    {
        report_error($dir,'non-album has dashes in path') if ($dir =~ /-/);
        report_error($dir,'leaf folder should be an album') if (!@subdirs);
        report_error($dir,'non-album should not have tracks or files in it') if (@tracks || @files);
        
        for my $subdir (sort(@subdirs))
        {
            scan_dir("$dir/$subdir");
        }
    }
   
}


sub report_error
{
    my ($dir,$msg) = @_;
    display(0,-1,"$msg: $dir");
}



#------------------------------------------
# fpcalc infos
#------------------------------------------

my %fpcalc_used;
my $fpcalc_dir = "$cache_dir/fpcalc_info";

sub fpcalc_filename
{
    my ($filename) = @_;
    $filename =~ s/^\/mp3s\///;
    $filename =~ s/\//\./g;
    $filename .= ".txt";
    return $filename;
}

    
sub mark_as_used
{
    my ($filename) = @_;
    my $fpcalc_filename = fpcalc_filename($filename);
    display(9,0,"used($fpcalc_filename)");
    $fpcalc_used{$fpcalc_filename} = 1;
}


sub get_existing_fpcalc_infos
{
    if (!opendir(DIR,$fpcalc_dir))
    {
        error("Could not opendir $fpcalc_dir for reading");
        exit 1;
    }
    while (my $entry = readdir(DIR))
    {
        next if $entry !~ /\.txt$/;
        $fpcalc_used{$entry} = 0;
    }
}

sub remove_unused_fpcalc_infos
{
    for my $fn (sort(keys(%fpcalc_used)))
    {
        next if $fpcalc_used{$fn};
        display(0,0,"unused fpcalc file: $fn");
        unlink "$fpcalc_dir/$fn" if $REMOVE_UNUSED_FPCALC_INFO;
    }
}



#-------------------------------------------
# check for duplicate ARTISAN_IDs
#-------------------------------------------

sub show_non_unique_artisan_ids
{
    db_initialize();
    
    my $dbh = db_connect();
    my $ids = get_records_db($dbh,"select ARTISAN_ID, count(ARTISAN_ID) as count from TRACKS group by ARTISAN_ID");
    
    display(0,0,"found ".scalar(@$ids)." ARTISAN_IDs");
    for my $id (@$ids)
    {
        if ($id->{count} > 1)
        {
            my $recs = get_records_db($dbh,"select FULLNAME from TRACKS where ARTISAN_ID='$id->{ARTISAN_ID}' order by FULLNAME");
            
            # don't show duplicates in /albums/Work
            
            my $skipit = 0;
            for my $rec (@$recs)
            {
                if ($rec->{FULLNAME} =~ /albums\/Work\//)
                {
                    $skipit = 1;
                    last;
                }
            }
            next if ($skipit);
            
            display(0,1,"$id->{ARTISAN_ID} count=$id->{count}");
            for my $rec (@$recs)
            {
                display(0,2,"$rec->{FULLNAME}");
            }
        }
    }
    
    db_disconnect($dbh);
}




#------------------------------------------
# main
#------------------------------------------

display(0,0,"analyze_library.pm started");

# build a hash of the existing fpcalc-infos = 0

get_existing_fpcalc_infos();

# scan the files

for my $dir (@scan_dirs)
{
    display(0,0,"---------------------------------------------");
    display(0,0,"scanning $dir");
    display(0,0,"---------------------------------------------");
    scan_dir($dir);
}


# note, and/or remove, unused fpcalc info files

remove_unused_fpcalc_infos();

# show non-unique artisan ids

show_non_unique_artisan_ids();

# finished

display(0,0,"analyze_library,pm finished");


1;
