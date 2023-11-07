#!/usr/bin/perl
#---------------------------------------
# A program to do whatever I want to mp3s

our %genres;
our %extensions;

our %done_files;
our %undone_files;
our %error_files;

# unknown ID3V2 Tag Version V2.0
# unknown ID3V2 Tag Version V4.0


#------------------------------------------
# audioFile
#------------------------------------------

package audioFile;
use strict;
BEGIN { push @INC,'../'; }
use artisanUtils;

use MP3::Tag;
use Audio::WMA;
use Music::Tag;


our $dbg_level = 2;
    # 1 = warnings
    # 2 = details
    # 3 = gruesome

our $warning = ($dbg_level > 0) ? 0 : 1;
our $details = ($dbg_level > 1) ? 0 : 1;
our $gruesome = ($dbg_level > 2) ? 0 : 1;


sub spad
    # debug display routine
{
    my ($s,$len) = @_;
    $s = '' if (!defined($s));
    if (length($s) > $len)
    {
        $s = substr($s,0,$len-3);
        $s .= "...";
    }
    return pad($s,$len);
}


sub set
{
    my ($this,$field,$val) = @_;
    $val = '' if (!defined($val));
    $val = '' if ($field eq 'genre' && $val eq 'Other');
    $val =~ s/\s*$//;

    my $old = $this->{$field};
    return if ($old eq $val);
    if ($old && $val && $val ne $old)
    {
        display($warning+1,0,"not overwriting $old with $val");
        return;
    }
    $this->{$field} = $val;
    display($details+1,1,pad($field,15)."='$val'") if ($val);
}


sub set_frame   # for MP3 id3v2 sections
{
    my ($this,$id2,$frame,$field) = @_;
    my ($val) = $id2->getFrame($frame);
    set($this,$field,$val);
}




sub new
{
    my ($class,$path) = @_;
    my $rslt = -1;
    my $this = {};
    bless $this,$class;

    if ($path =~ /\.mp3$/i)
    {
        # $rslt = $this->fromFileType($path,'MP3');
        $rslt = $this->fromMP3($path);
    }
    elsif ($path =~ /\.wma$/i)
    {
        $rslt = $this->fromWMA($path);
    }
    elsif ($path =~ /\.(m4a|m4p|mk4)$/i)
    {
        # $rslt = $this->fromWMA($path);
        $rslt = $this->fromFileType($path,'M4A');
    }

    if ($rslt && $rslt == -1)
    {
        $undone_files{$path} = $this;
    }
    elsif ($rslt)
    {
        $done_files{$path} = $this;
    }
    else
    {
        $error_files{$path} = 1;
    }
    return $this;
}




sub fromFileType
{
    my ($this,$path,$type) = @_;
    $this->{type} = lc($type);
    my $data = Music::Tag->new($path, { quiet => 1 }, $type);
    if (!$data)
    {
        error("Could not open $type $path");
        return;
    }

    $data->get_tag();
    display($details,1,"$type($path) data=$data");

    # no genre or year!

    set($this,'artist',$data->artist());
    set($this,'album',$data->album());
    set($this,'track',$data->track());
    set($this,'num_tracks',$data->totaltracks());
    set($this,'title',$data->title());
    set($this,'comment',$data->comment());

    display(0,1,$this->{type}.' '.
        spad($this->{genre},15).' '.
        spad($this->{year},4).' '.
        spad($this->{artist},24).' '.
        spad($this->{album},24).' '.
        spad($this->{track},2).' '.
        spad($this->{title},24).' ');

    use Data::Dumper;
    print Dumper($data) if ($gruesome == 0);

    my $known_m4a_info = join('|',qw(
        artist album title comment track totaltracks
        disc totaldiscs tempo encoder composer
        copyright lyrics _options _plugins data
        bitrate duration picture ));



    return 1;
}


sub fromWMA
{
    my ($this,$path) = @_;
    $this->{type} = 'wma';
    my $wma  = Audio::WMA->new($path);
    if (!$wma)
    {
        error("Could not open WMA $path");
        return;
    }

    my $info = $wma->info();
    my $tags = $wma->tags();
    display($gruesome,1,"WMA($path) info=$info tags=$tags");

    my $known_tags = join('|',qw(
        ALBUMARTIST ALBUMTITLE GENRE TRACKNUMBER YEAR TITLE
        AUTHOR COMPOSER
        COPYRIGHT PROVIDER PROVIDERSTYLE PUBLISHER TRACK
        UNIQUEFILEIDENTIFIER VBR PROVIDERRATING SHAREDUSERRATING
        RATING WMCOLLECTIONGROUPID WMCOLLECTIONID WMCONTENTID
        DESCRIPTION LYRICS ENCODINGTIME MCDI
        MEDIACLASSPRIMARYID MEDIACLASSSECONDARYID MEDIAPRIMARYCLASSID ));
    my $known_info = join('|',qw(
        bitrate bits_per_sample channels codec
        creation_date creation_date_unix data_packets fileid_guid
        filesize flags flags_raw max_bitrate max_packet_size min_packet_size
        playtime_seconds play_duration preroll sample_rate send_duration ));

    set($this,'artist',$$tags{ALBUMARTIST});
    set($this,'album',$$tags{ALBUMTITLE});
    set($this,'genre',$$tags{GENRE});
    set($this,'track',$$tags{TRACKNUMBER});
    set($this,'year',$$tags{YEAR});
    set($this,'title',$$tags{TITLE});

    display($details,1,'wma '.
        spad($this->{genre},15).' '.
        spad($this->{year},4).' '.
        spad($this->{artist},24).' '.
        spad($this->{album},24).' '.
        spad($this->{track},2).' '.
        spad($this->{title},24).' ');

    foreach my $key (sort(keys(%$info)))
    {
        next if ($key =~ /^($known_info)$/);
        display(0,2,"info($key)=$$info{$key}");
    }
    foreach my $key (sort(keys(%$tags)))
    {
        next if ($key =~ /^($known_tags)$/);
        display(0,2,"tags($key)=$$tags{$key}");
    }
    return 1;
}


sub fromMP3
{
    my ($this,$path) = @_;
    $this->{type} = 'mp3';
    my $mp3 = MP3::Tag->new($path); # create object

    my $show_path = $path;
    $show_path =~ s/.*\///g;

    if (!$mp3)
    {
        error("Could not open mp3 file $show_path");
        return;
    }
    my @tags = $mp3->getTags(); # read tags
    if (!@tags)
    {
        display($warning,2,"WARNING: No tags in $show_path");
        return;
    }
    my $id1 = $mp3->{ID3v1};
    if (!$id1)
    {
        display($warning+1,2,"WARNING: No id3v1 in $show_path");
    }
    else
    {
        set($this,'year',$id1->year());
        set($this,'genre',$id1->genre());
        set($this,'artist',$id1->artist());
        set($this,'album',$id1->album());
        set($this,'track',$id1->track());
        set($this,'title',$id1->song());        # stupid
        set($this,'comment',$id1->comment());
    }

    my $id2 = $mp3->{ID3v2};
    if (!$id2)
    {
        display($warning+1,2,"WARNING: No id3v2 found in $show_path");
    }
    else
    {
        my ($track_info) = $id2->getFrame('TRCK');
        if ($track_info)
        {
            if ($track_info =~ /^(\d+)\/(\d+)$/)
            {
                my ($track,$of) = ($1,$2);
                set($this,'track',$track);
                set($this,'num_tracks',$of);
            }
            else
            {
                set($this,'track',$track_info);
            }
        }

        set_frame($this,$id2,'TPE1','artist');
        set_frame($this,$id2,'TSSE','settings');
        set_frame($this,$id2,'TYER','year');
        set_frame($this,$id2,'TCON','genre');
        set_frame($this,$id2,'TIT2','title');
        set_frame($this,$id2,'TALB','album');
    }

    display($details+1,1,'mp3 '.
        spad($this->{genre},15).' '.
        spad($this->{year},4).' '.
        spad($this->{artist},24).' '.
        spad($this->{album},24).' '.
        spad($this->{track},2).' '.
        spad($this->{title},24).' ');

    my $genre = $this->{genre};
    $genres{$genre} = 0 if (!$genres{$genre});
    $genres{$genre}++;

    # show any other unused non-private frames for debugging

    if ($id2)
    {
        my @frame_ids = $id2->getFrameIDs();
        foreach my $frame (@frame_ids)
        {
            next if ($frame =~ /^(TRCK|TPE1|TSSE|TYER|TCON|TIT2|TALB)/);

            my ($info, $name) = $id2->getFrame($frame);
            if (ref $info)
            {
                if (!keys(%$info))
                {
                    display($warning-1,2,"NOTE!! $name($frame) - NO KEYS");
                    next;
                }
                for my $key (sort(keys(%$info)))
                {
                    display($warning-1,2,"NOTE!! $name($frame} $key => $$info{$key}");
                }
            }
            else
            {
                display($warning-1,2,"NOTE!! $name($frame) = $info");
            }
        }
    }

    return 1;

}   # audioFile::fromMP3()




#------------------------------------------
# audioLibrary
#------------------------------------------


package audioLibrary;
use strict;
BEGIN { push @INC,'../'; }
use artisanUtils;


my $audio_file_re = '\.(mp3|wma|wav|m4a|m4p|mk4|aif|aif)$';
    # actual types in my library

#------------------------------------------
# scanner
#------------------------------------------

sub scan_dir
{
    my ($dir) = @_;
    display(0,0,"scan_dir($dir)");

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
            #next if ($entry =~ /^_/);
            push @subdirs,$entry;
            next;
        }

        if ($entry =~ /.*\.(.*?)$/)
        {
            my $ext = lc($1);
            $extensions{$ext} = 0 if (!$extensions{$ext});
            $extensions{$ext}++;
        }

        if ($entry =~ /$audio_file_re/i)
        {
            my $file = audioFile->new($filename);
        }
    }
    closedir DIR;

    for my $subdir (sort(@subdirs))
    {
        scan_dir("$dir/$subdir");
    }
}




#------------------------------------------
# main
#------------------------------------------

display(0,0,"mp3Scanner started");

scan_dir('/mp3s'); # /Classical');

display(0,0,"---------------------------------------------");
display(0,0,"extensions");
display(0,0,"---------------------------------------------");
for my $ext (sort(keys(%extensions)))
{
    display(0,1,"$extensions{$ext} $ext");
}

display(0,0,"---------------------------------------------");
display(0,0,"genres");
display(0,0,"---------------------------------------------");
for my $genre (sort(keys(%genres)))
{
    display(0,1,"$genres{$genre} $genre");
}

display(0,0,"---------------------------------------------");
display(0,0,scalar(keys(%done_files))." files done");
display(0,0,scalar(keys(%undone_files))." files not procssed");
display(0,0,scalar(keys(%error_files))." files with errors");
display(0,0,"mp3Scanner finished");


1;
