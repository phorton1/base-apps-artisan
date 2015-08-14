#------------------------------------------
# MediaFile
#------------------------------------------
# This file contains routines that are no longer
# used in the Mediat file

package MediaFile;
use strict;
use Digest::MD5 'md5_hex';
use Audio::WMA;
use Utils;
use MP3Info;
use MP3Vars;
use MP4::Info;


our %artisan_to_mp3;
our @required_fields;

#-----------------------------------------------------
# old artisan id stuff
#-----------------------------------------------------


sub unused_update_to_artisan
{
    my ($this,$mp3,$path) = @_;
    if (!$this->{artisan_id})
    {
        LOG(0,"Updating to ARTISAN: $path");
        $this->clean_tags($mp3,$path) if (1); # // $CLEAN_NEW_MP3_);

        # note that mp3->get_unique_id() *should* have
        # access to $this to call set_error itself, so the
        # below set_error call *may* be redundant
        
        my $artisan_id = $mp3->get_unique_id();
        if (!$artisan_id)
        {
            $this->set_error($ERROR_HIGH,"Could not get artisan_id");
            # abort changes to the mp3!!
            $mp3->close(1);
            return;
        }

        $this->set("fromMP3",$path,'artisan_id',$artisan_id);
        $mp3->set_tag_value($artisan_to_mp3{artisan_id},$this->{artisan_id});
            # failsafe given a known id

        my $timestamp = appUtils::getTimestamp($path,1);
        my $tz = "-05:00";
        $timestamp =~ s/^(\d\d\d\d):(\d\d):(\d\d):(\d\d):(\d\d):(\d\d)/$1-$2-$3 $4:$5:$6 $tz/;
        $mp3->set_tag_value("TXXX\x09ARTISAN_UPDATE_".today()." ".now(),"prev=".$timestamp);

        # Get the fingerprint, which also gives the duration if we need it.
        # get_fingerprint does not call set_error, so we call it here

        my $info = $this->get_fingerprint($path);
        if (!$info)
        {
            $this->set_error($ERROR_HIGH,"call to get_fingerprint() returned false!!");
            # abort changes to the mp3
            $mp3->close(1);
            return;
        }
        elsif ($info->{duration} &&
               $info->{duration} =~ /^\d+$/)
        {
            $this->set("fromMP3",$path,'duration',$info->{duration});
            $mp3->set_tag_value($artisan_to_mp3{duration},$info->{duration} * 1000);
        }
        else
        {
            $this->set_error($ERROR_HIGH,"no duration from get_fingerprint()!");
            # abort changes to the mp3
            $mp3->close(1);
            return 0;
        }
        
        bump_stat("zzzz_UPDATED_TO_ARTISAN");
    }
}
 
 
 
 
# ones that are cleaned up

my $cleanup_re = join('|',(
    'COMM',    # any comments
    'ENCR',    # encryption method registration
    'GEOB',    # any embedded objects
    'GRID',    # any group identification frames
    'MCDI',    # Music CD identifier
    'NCON',    # any unkonwn ncon frames
    'PCNT',    # any play counters
    'POPM',    # any popularity meaters
    'PRIV',    # any user defined privs
    'TBPM',    # any beats per minute
    'TCMP',    # any itunes TCMP flags
    'TENC',    # any encoded by
    'TFLT',    # any 'file types'
    'TKEY',    # initial key
    'TLAN',    # any langauges
    'TMED',    # any media types
    'TPOS',    # any part of set

    # 'TXXX',    # any user text
    # any non_artisan user defined text
    'TXXX\x09(?!ARTISAN)',

    'UFID',    # any unique ids
));
$cleanup_re =~ s/|$//;

# Ones I am effectively keeping from my initial files:
# if they don't show up in this list, the program will
# error and you need to decide which list to add them to.

my $expected_re = join('|',(
    'APIC',     # pictures
    'TALB',     # -> album
    'TDRC',     # -> year
    'TCOM',     # composer
    'TCON',     # -> genre
    'TCOP',     # copyright messages
    'TIT1',     # content group description -  meta-genre?
    'TIT2',     # -> title
    'TIT3',     # Subtitle/Description refinement
    'TLEN',     # -> duration
    'TOPE',     # Original artist/performer
    'TPE1',     # -> artist
    'TPE2',     # -> album_artist
    'TPE3',     # Conductor/performer refinement
    'TPUB',     # Publisher
    'TRCK',     # -> track
    'TSSE',     # Software/Hardware and settings used for encoding
    'TYER',     # Year
    #'TXXX\x09Album Artist',    # text version of Album Artist

));
$expected_re =~ s/|$//;



sub unused_clean_tags
    # remove any weird id's with question marks in them
    # which means, I think that they were v2 tags in v3+ id3 sections
    # or explicit id's by regular expression
{
    my ($this,$mp3,$path) = @_;
    LOG(0,"CLEANING UP EXISTING TAGS($path)");
    my @ids = $mp3->get_tag_ids();
    for my $id (@ids)
    {
        display(3,0,"id=$id");

        # clean up W (urls) and embedded lyrics (USLT)
        # only on my first pass

        my $re = $cleanup_re;
        $re .= "|$1" if (0);  # $CLEAN_NEW_MP3_ > 1 && $id =~ /^(W|USLT)/);

        if ($id =~ /$re/)
        {
            LOG(1,"DELETE id=$id");
            $mp3->set_tag_value($id,'');
            bump_stat("zzz_DELETED($id)");
        }
        elsif ($id !~ /$expected_re/)
        {
            $this->set_error($ERROR_MEDIUM,"Unexpected cleanup_tag($id) in $path");
        }
    }
}


sub unused_toMP3
{
    my ($this) = @_;
    display(2,0,"toMP3()");
    my $mp3 = $this->{_fh};

    for my $dont_change_field (@required_fields)
    {
        my $field = $dont_change_field;
        my $value = $this->{$field};
        $value *= 1000 if ($field eq 'duration');

        # map tracknum to track
        # using old number of tracks if available

        if ($field eq 'tracknum')
        {
            $field = 'track';
            my $old = $mp3->get_tag_value($artisan_to_mp3{$field});
            $value =~ s/^0+//;
            $value .= "/$old" if ($old && $old =~ s/.*\///)
        }

        # map recording time to year
        # skip it if it's not \d\d\d\d

        if ($field eq 'year')
        {
            next if $value !~ /^(\d\d\d\d)/;
            $value = $1;
        }

        display(1,1,"to_mp3() setting $field=$artisan_to_mp3{$field} to '$value'");
        $mp3->set_tag_value($artisan_to_mp3{$field},$value);
    }
}




1;
