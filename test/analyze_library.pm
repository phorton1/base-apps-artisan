#!/usr/bin/perl
#---------------------------------------
# analyze_library.pm
#
# We never touch track files. No tagging!
#
# Each file gets a md5 checksum which is it's artisan_id.
#
# There may only be one file in the system with a given artisan_id.
#
# DLNA is bifurcated in that there is a concept of an album that shows
# in folder listings, and a separate track object that shows in the
# now_playing window.  For instance, a folder might be a complication
# which contains tracks from a number of different albums.
#
# In our system there are three highest level outer diretories:
#
#    albums 
#    singles
#    unclassified
#
# The only difference between albums and singles being that leaf folders
# found in albums tend to be a more complete collection, playable as
# a whole, wheras singles tend to be one or a few songs that don't really
# constitute a playable collection.
#
# Unclassified means that I have not yet categorized the music into
# albums/singles, for whatever reason.  Unclassified items do not
# automatically get added to initial "stations", wheras albums and
# singles do.
#
# Within the albums/singles directories, there are several
# sub-leaf nodes that do not, per se, confer the authorative
# classification of an artist.
#
#      Christmas - only used authoratively as the
#          artist genre if there are not other
#          classifications within the system.
#      Compliations - should be eliminated with folders
#          categorized to best-fit highest level artist
#          classification.
#
# The following diretories DO constitute authorative classifications,
# but, for instance, in the case of Theo, and Billy and the Swap Critters,
# there must be a way to override the classification so that they get
# included in the Zydeco Radio station.
#
#      Friends
#      Productions
#
# Besides "Various", every artist, as given by the album name,
# in the Albums/Singles directories is "known" and "valid".
#
# In fact, a first order assumption is that ALL FOLDERS THAT
# CONTAIN MUSIC FILES use the ARTIST - ALBUM_TITLE convention,
# where ARTIST and/or ALBUM_TITLE may be VARIOUS (which is a
# synonym for "unknown").  Therefore every genre *could* have
# a catch all folder VARIOUS - VARIOUS, but this should be
# sparingly used, but will be handy under Unclassified for dumping
# MP3s that we have no clue about.
#
#  Taxonomy
#
#    unclassified
#    artist_genre
#        folder_album_artist - folder_album_title
#            folder.jpg
#            artisan_folder_info.txt = override_artist_genre
#            [file_track_num - ]file_track_title[ - file_track_artist]
#                 my track meta information
#                      artisan_id - md5 file checksum
#                      fpcalc_id - checksum of fpcalc fingerprint
#                      fpcalc_duration - duration returned by fpcalc
#                      override_tag_duration
#                      override_tag_album_artist
#                      override_tag_album_title
#                      override_tag_track_date
#                 tags
#                      tag_track_num
#                      tag_track_title
#                      tag_track_artist

#                      tag_album_artist
#                      tag_album_title
#                      tag_genre
#                      tag_track_date (which can be leading year only, or year-month, or year-month-day)
#                      tag_duration
#                      tag_folder_art
#
#
# Where the tag_items theselves undergo their own format-specific 
# bubble up process (i.e. mp3 TXXX_ALBUM_ARTIST will be used
# if there is no mp3 TPE2 tag).
#
# So, we see a hierarchial structure where higher levels "override"
# what is found at lower levels, generally, to provide more consistency.
# To where a "track" generally ends up with"
#
#      track_num = file_track_num | tag_track_num
#      title = file_track_title
#      album = folder_album_title
#      album_artist = folder_album_artist
#      artist = file_track_artist | tag_track_artist
#      genre = [ artist_genre | override_artist_genre ] [+ override_tag_genre | tag_genre ]
#
# And generally, the tags are not displayed
#
# This is where the bifurcation with DLNA comes in.
#
#  /Compliations/Various - Bobs Party Mix/01 - PartyAllNight - Betsy Cline.mp3
#        tag_album_title = Betsy Goes to Heavan
#        tag_album_artist = The Betsy's
#
# So what do we show for the Album Title / Artist in Now Playing?
# Since the folder_album_artist is Various, it is not useful.
# I think I would like would show:
#
#       album = Bobs Party Mix + Betsy Goes To Heaven
#       artist = Betsy Cline + The Betsy's
#
# and presume that the file_track_title always overrides the tag_track_title,
# and would only show
#
#      artist = Various
#
# if there is no override_album_artist, file_track_artist.
# override_tag_album_artist, tag_album_artist, or tag_track_artist
# to fall back on.
#
# It is a thorny issue with near same spellings, etc, to combine the
# folder_album_artist, tag_album_artist, file_track_artist, tag_album_artist,
# and tag_album_artist into a single displayable artist to show in now playing.
# Same for combining tag_album_title, and folder_album_title.
# And even weirder when you throw in the folder view, which HAS to be
# "Various - Bobs Party Mix"
#
# And appears as if there may need or want to be "modes" to
# display lists by genre
#
#    artist_genre | override_album_genre | override_track_genre | tag_track_genre
#
# Same thing, a "mode" that allows track_folder_art to "override"
# folder.jpg (as well as the usual behavior to create it if needed).
# Sheesh, this is just for DLNA.
#
# ENHANCED EXPERIENCE (PLEX LIKE) VIEW
#    with artist information, bio, other photos, etc
# AUTOMATIC GENRATION OF META INFORMATION
#    - folder.jpg vs. track_folder_art on a case by case basis (i.e. for Complications)
#    - track_num, track_title, and track_artist can be set into the filename.
#      but any other tags must have overrides:
#          override_track_album_artist
#          override_track_artist
#
# Makes me want to consider just re-tagging the stupid audio files.



use strict;
use warnings;
use artisanUtils;
use Database;
use Digest::MD5;



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

    my @tracks;
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
        elsif ($entry =~ /$audio_file_re/i)
        {
            push @tracks,$entry;
        }
    }
    
    closedir DIR;

    for my $subdir (sort(@subdirs))
    {
        scan_dir("$dir/$subdir");
    }

    for my $track (sort(@tracks))
    {
        do_track($dir,$track);
    }
   
}



sub file_checksum
{
    my ($filename) = @_;
    my $fh;
    if (!open ($fh, '<', $filename))
    {
        error("Can't open '$filename': $!");
        return;
    }
    binmode ($fh);
    my $md5 = Digest::MD5->new->addfile($fh)->hexdigest();
    close($fh);
    return $md5;
}


my $count = 0;

my %checksums;

sub do_track
{
    my ($dir,$track) = @_;
    my $filename = "$dir/$track";
    display(0,0,$count) if ($count++ % 100 == 0);
    display(2,1,"do_track($track)");

    my $checksum = file_checksum($filename);
    display(2,1,"checksum=$checksum");

    my $exists = $checksums{$checksum};
    if ($exists)
    {
        display(0,0,"WARNING: file($filename) has same checksum as '$exists'");
    }
    else
    {
        $checksums{$checksum} = $filename;
    }
}


#------------------------------------------
# main
#------------------------------------------

display(0,0,"analyze_library.pm started");

for my $dir (@scan_dirs)
{
    display(0,0,"---------------------------------------------");
    display(0,0,"scanning $dir");
    display(0,0,"---------------------------------------------");
    scan_dir($dir);
}

# finished

display(0,0,"analyze_library,pm finished");


1;
