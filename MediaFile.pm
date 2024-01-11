#------------------------------------------
# MediaFile
#------------------------------------------


package MediaFile;
use strict;
use warnings;
use Digest::MD5 'md5_hex';
use Audio::WMA;
use artisanUtils;
use MP3Info;
use MP3Vars;
use MP4::Info;
use Database qw($HAS_FOLDER_ART $HAS_TRACK_ART);


my $dbg_mediafile  = 1;


# The stream_md5 is mapped to the id by this module

our @required_fields = qw(
	id
	artist
    album_title
    title
    duration
    file_md5
    album_artist );

# $dbg_mediafile = 0;
use utf8;


sub new
    # See Utils.pm for a definition of the error constants.
{
    my ($class,$rel_path,$force) = @_;
    $force ||= 0;

    display($dbg_mediafile,0,"MediaFile::new($rel_path) force=$force");
    my $utf_path = "$mp3_dir/$rel_path";

    # 2015-07-02 Had to add handling of UTF filenames presumably from database.
    # For windows, we have to utf8:downgrade the string, which is apparently not
    # really utf encoded, but which thinks it is?
    # For android we have to encode the non-encoded filename from the database
    # cuz unix is using utf-8 filenames.
    # At least the filename seems to come out of the database the same
    # on both platforms, sheesh.

    my $path = $utf_path;

    if (0)
    {
		# if running on the car stereo, I found I needed this
        $path = Encode::encode("utf-8",$path);
    }
    else
    {
		# and otherwise, I guess I need this
        utf8::downgrade($path);
    }

   	my @fileinfo = stat($path);
	my $size = $fileinfo[7];
	my $timestamp = $fileinfo[9];

    if (!(-f $path))
    {
        display(0,0,"fileinfo=@fileinfo size=$size timestamp=$timestamp");
        error("File not found: $path");
        return;
    }

    my $this = {};
    bless $this,$class;

    $this->{id} = '';
    $this->{path} = $path;
    $this->{has_art} = 0;
    $this->{file_md5} = '';
    $this->{errors} = undef;
    $this->{error_codes} = '';

    if ($path =~ /\.mp3$/i)
    {
        $this->{type} = 'mp3';
        return if !$this->fromMP3($path);
    }
    elsif ($path =~ /\.wma$/i)
    {
        $this->{type} = 'wma';
        return if !$this->fromWMA($path);
    }
    elsif ($path =~ /\.(m4a)/i)
    {
        $this->{type} = 'm4a';
        return if !$this->fromM4A($path);
    }
    elsif ($path !~ /\.wav$/i)
    {
        error("Unknown file type: $path");
        return;
    }
    else
    {
        $this->{type} = 'wav';
    }

    # tags may return {track} field which contain
    # dot something.  This code removes it.

    if ($this->{track} && !$this->{tracknum})
    {
        $this->{tracknum} = $this->{track};
        $this->{tracknum} =~ s/\/.*$//;
    }

    # defaults override almost everything from the tags
    # including the genre.  TODO: Set the genres into
    # all single/albums MP3s and start using the tag version,
    # and give a warning when it overrides the folder version.

    $this->set_default_info($utf_path);
        # distinction between the path used in perl,
        # which has been utf8:downgraded, and the one
        # passed to set_default_info, which sets up displayable
        # fields.

    # the genre for /unresolved items will be taken from the tags.
    # as set_default_info() will get a genre of '' which will not
    # overwrite an existing value, so only /unresolved songs with
    # no genre tag will end up as 'undefined' genre.

    my $genre = $this->{genre} || 'undefined';
    bump_stat("genre($genre)");

    # get the file_md5

    my $fh;
    if (!open ($fh, '<', $path))
    {
        error("FATAL ERROR - Could not get file_md5 (could not open file) for $path: $!");
    }
    else
    {
        binmode ($fh);
        my $file_md5 = Digest::MD5->new->addfile($fh)->hexdigest();
        display(9,0,"file_md5($path) = $file_md5");
        $this->set('mediaFile',$path,'file_md5',$file_md5);
        close($fh);

        if (!$file_md5)
        {
            error("FATAL ERROR - no file_md5 for $path");
            return;
        }

        # get the stream_md5 and, while at it, use the duration from
        # fpcalc if there was not one in the tags.  The fpcalc_info
        # will be cached to text files by the file_md5.

        my $info = $this->get_fpcalc_info($force);
        if (!$info)
        {
            # error already reported in get_fpcalc_info
            return;
        }
        elsif (!$info->{stream_md5})
        {
            error("FATAL - no stream_md5 for $this->{file_md5}=$path");
            return;
        }
        else
        {
            $this->set('mediaFile',$path,'id',$info->{stream_md5});

			# think fpcalc returns decimal seconds
			# which we convert to milliseconds here

            if (!$this->{duration} &&
                $info->{duration} &&
                $info->{duration} =~ /^[\.\d]+$/)
            {
                $this->set("mediaFile",$path,'duration',$info->{duration} * 1000);
            }
        }
    }

    # debugging and warnings

    if (1)
    {
        display($dbg_mediafile,0,"FINAL from MediaFile");
        for my $k (sort(keys(%$this)))
        {
            my $val = $$this{$k};
            display($dbg_mediafile,1,pad($k,15)."= '"._lim($val,60)."'")
                if (defined($val) && $val ne '');
        }
    }

    my @missing_required;
    for my $field (@required_fields)
    {
        push @missing_required,$field
            if (!$this->{$field});
    }

    $this->set_error('md',
        "Missing required metadata '".join(',',@missing_required).'"')
        if (@missing_required);

    # separate cosmetic error for tracks missing a year

	$this->set_error('my',"No YEAR_STR")
		if (!$this->{year_str});

    return $this;
}



#-------------------------------------
# utilities
#-------------------------------------

sub set_error
    # Add the error code to the error_codes variable.
    # Add the error to the list of errors for display by UI.
    # If the error mapps to $HIGH or more, report it immediately,
    # but note that MediaFile->new() is only called on files that
    # date-time stamps changed in Library scanning.
{
    my ($this,$code,$msg,$call_level) = @_;
    my $severity = code_to_severity($code);
    my $severity_str = severity_to_str($severity);

    $call_level ||= 0;

    bump_stat("SET_ERROR($severity_str,$code)".error_code_str($code));

    my $in_msg =  "in ".
        ($this->{file_md5} ? "file_md5($this->{file_md5}) ":'').
        ($this->{id} ? "id($this->{id}) ":'').
        "path=$this->{path}";
    if ($severity >= $ERROR_HIGH)
    {
        error("$severity_str($code) - $msg $in_msg",$call_level);
    }
    else
    {
        my $warning_level = $ERROR_MEDIUM - $severity + 1;
        warning($warning_level,0,"$severity_str($code) - $msg $in_msg",$call_level);
    }

    if ($code ne 'note' && $this->{error_codes} !~ /(^|,)$code(,|$)/)
    {
        my @parts = split(/,/,$this->{error_codes});
        push @parts,$code;
        $this->{error_codes} = join(',',sort(@parts));
    }

    $this->{errors} = [] if (!$this->{errors});
    push @{$this->{errors}},[$severity,$msg];
}


sub get_errors
{
    my ($this) = @_;
    return $this->{errors};
}



sub set
{
    my ($this,$parser,$file,$field,$val) = @_;
    $val = '' if (!defined($val));
    $val =~ s/\s*$// if ($field ne 'picture');

    my $old = $this->{$field};
    return if ($old && $old eq $val);
    $old = '' if (!defined($old));

    $this->set_error('mx',"!! Stupid '^bob ' in album_artist")
        if ($field eq 'album_artist' && $val =~ /^bob /);

	# find tracks named 01 - Track.mp3, etc

    if ($field eq 'title' && $parser eq 'default_info')
    {
        my $check_title = $val;
        while ($check_title =~ s/(\s|new|afro|track|_|-|\d)//ig) {};
        $this->set_error('mt',"Bad Track Title")
            if (!$check_title);
    }

    # values that I just don't want in my database

    $old =~ s/http:\/\/music\.download\.com//;
    $val =~ s/http:\/\/music\.download\.com//;

    if ($old && $val && $old ne $val)
    {
        # special overwrite track number to clear the track number

        $val = '' if ($val eq '0000' && $field eq 'tracknum');

        # for now, I'm highlingting when album (name) or album_artist
        # minus all punctuation and white space is different than tags
        # also remove "featuring" from artist name's and leading "the "

        my $error_code = 'note';
        if ($field !~ /^(track|tracknum|duration|genre)$/)
        {
            my $check_val = lc($val);
            my $check_old = lc($old);

            # disk 1 of 2

            $check_old =~ s/(\(|\[)(\d)\/(\d)(\)|\])/($2 of $3)/ if ($field =~ /^(album_title)$/);

            # various extra junk specific to a few albums

            $check_old =~ s/featuring.*$//i if ($field =~ /^(artist|album_artist)$/);
            $check_old =~ s/\(duet.*$//i if ($field =~ /^(title)$/);
            $check_old =~ s/\(with.*$//i if ($field =~ /^(artist)$/);

            # general conversions

            $check_val =~ s/\s+&\s+/and/;
            $check_old =~ s/\s+&\s+/and/;
            $check_val =~ s/^the\s+//i;
            $check_old =~ s/^the\s+//i;
            $check_val =~ s/\s|_|!|>|:|-|'|"|\.|,|\?|\/|\(|\)|\[|\]//g;
            $check_old =~ s/\s|_|!|>|:|-|'|"|\.|,|\?|\/|\(|\)|\[|\]//g;

            if ($check_val ne $check_old)
            {
                $error_code = ($field eq 'album_title') ? 'mi' : 'mj';
            }
        }

        $this->set_error($error_code,"$parser overwriting $field old=$old with new=$val");
        display($dbg_mediafile+1,0,"  **set($parser,$field)='"._lim($val,80)."'");
        $this->{$field} = $val;
    }
    elsif ($val)
    {
        $this->set_error('note',"$parser initial set $field=$val");
        display($dbg_mediafile+1,0,"set($parser,$field)='"._lim($val,60)."'");
        $this->{$field} = $val;
    }
}


#------------------------------------------------
# default info
#------------------------------------------------

sub set_default_info
    # set default values
    # based on filename
{
    my ($this,$path) = @_;
    display($dbg_mediafile+1,0,"set_default_info($path)");

    my $split = split_dir(1,mp3_relative($path));

    $split->{tracknum} ||= '0000';
        # special overwrite track number to clear the track number

    $this->set("default_info",$path,'genre',$split->{class});
    $this->set("default_info",$path,'artist',$split->{artist})
        if $split->{artist} ne 'Various';
    $this->set("default_info",$path,'album_artist',$split->{album_artist})
        if $split->{album_artist} ne 'Various' &&
           $split->{album_artist} ne 'Original Soundtrack';
    $this->set("default_info",$path,'album_title',$split->{album_title})
        if $split->{album_title} ne 'Unknown';
    $this->set("default_info",$path,'tracknum',$split->{track});
    $this->set("default_info",$path,'title',$split->{title});
    $this->set("default_info",$path,'year_str',$split->{year_str});
}



#------------------------------------------------
# M4A
#------------------------------------------------

sub fromM4A
{
    my ($this,$path) = @_;
    display($dbg_mediafile,0,"fromM4A()");

    my $tags = get_mp4tag($path);
    if (!$tags)
    {
        error("FATAL ERROR - Could not get M4A tags from $path");
        return;
    }
    my $info = get_mp4info($path);
    if (!$info)
    {
        error("FATAL ERROR - Could not get M4A tags from $path");
        return;
    }

    $this->{raw_tags} = {
        info => $info,
        tags => $tags };

    $this->set("fromM4A",$path,'has_art',$HAS_TRACK_ART)
        if ($tags->{COVR});

    $this->set("fromM4A",$path,'title',$$tags{TITLE});
    $this->set("fromM4A",$path,'artist',$$tags{ARTIST});
    $this->set("fromM4A",$path,'album_title',$$tags{album_title});
    $this->set("fromM4A",$path,'genre',$$tags{genre});
    $this->set("fromM4A",$path,'track',$$tags{tracknum});
    $this->set("fromM4A",$path,'year_str',$$tags{year_str});
    $this->set("fromM4A",$path,'duration',$$info{SECS} * 1000);

    return 1;

    my $known_tags = join('|',qw(
        ALB APID ART CMT COVR CPIL CPRT DAY DISK
        GNRE GRP NAM RTNG TMPO TOO TRKN WRT
        TITLE ARTIST ALBUM YEAR COMMENT GENRE tracknum ));
    my $known_info = join('|',qw(
        VERSION LAYER BITRATE FREQUENCY SIZE SECS
        MM SS MS TIME COPYRIGHT ENCODING ENCRYPTED ));

    foreach my $key (sort(keys(%$tags)))
    {
        next if ($key =~ /^($known_tags)$/);
        display($dbg_mediafile+1,1,"tags($key)=$$tags{$key}");
        display(0,1,"tags($key)=$$tags{$key}");
    }
    foreach my $key (sort(keys(%$info)))
    {
        next if ($key =~ /^($known_info)$/);
        display($dbg_mediafile+1,1,"info($key)=$$info{$key}");
        display(0,1,"info($key)=$$info{$key}");
    }

    return 1;

}



#------------------------------------------------
# WMA
#------------------------------------------------

sub fromWMA
{
    my ($this,$path) = @_;
    display($dbg_mediafile,0,"fromWMA()");
    my $wma  = Audio::WMA->new($path);
    if (!$wma)
    {
        error("FATAL ERROR - Could not open WMA $path");
        return;
    }

    my $info = $wma->info();
    my $tags = $wma->tags();
    $this->{raw_tags} = {
        info => $info,
        tags => $tags };

    my $artist = $$tags{AUTHOR};
    $artist = $$tags{ALBUMARTIST} if (!$artist);
    $this->set("fromWMA",$path,'title',$$tags{TITLE});
    $this->set("fromWMA",$path,'artist',$artist);
    $this->set("fromWMA",$path,'album_title',$$tags{ALBUMTITLE});
    $this->set("fromWMA",$path,'album_artist',$$tags{ALBUMARTIST});
    $this->set("fromWMA",$path,'genre',$$tags{genre});
    $this->set("fromWMA",$path,'track',$$tags{tracknumBER});
    $this->set("fromWMA",$path,'year_str',$$tags{year_str});
    $this->set("fromWMA",$path,'duration',$$info{playtime_seconds} * 1000);

    return 1;

    my $known_tags = join('|',qw(
        ALBUMARTIST ALBUMTITLE GENRE tracknumBER YEAR TITLE
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

    foreach my $key (sort(keys(%$info)))
    {
        next if ($key =~ /^($known_info)$/);
        display($dbg_mediafile+1,1,"info($key)=$$info{$key}");
    }
    foreach my $key (sort(keys(%$tags)))
    {
        next if ($key =~ /^($known_tags)$/);
        display($dbg_mediafile+1,1,"tags($key)=$$tags{$key}");
    }

    return 1;
}


#----------------------------------------------------
# MP3
#----------------------------------------------------
# This method serves as an abstraction layer between the
# low level MP3Info routines and the high level MediaInfo
# object, which expects back, at this time, only a simple
# hash containing the following fields:
#
#     title
#     artist
#     album_title
#     album_artist
#     genre
#     year_str
#     track
#     duration (integer seconds)
#
# Below this has been a bewildering array of choices starting
# with ffmpeg.exe, which the original pdlna.pm callled, much
# time figuring out perls MP3::Tag::ID2v1 and v2 stuff, then
# hitting on fpcalc.exe from AcousticID.com, which led me to
# really need to write a fingerprint tag, which took me back
# to MP3::Info, which is better than MP3::Tag, but which still
# required a lot of umph to get it where I want it. The results
# of all this effort are in the MP3*.pm files.

# map artisan tags to ID3v2.4
# Comma delimited prefered tags

our %artisan_to_mp3= (
    title       => 'TIT2',
    artist      => 'TPE1',
    album_title => 'TALB',
    year_str    => "TORY,TXXX\toriginalyear,TYER,TDRC",  # TORY=original year, release TYER=v3, TDRC=v4
    track       => 'TRCK',
    genre       => 'TCON',
    album_artist => "TPE2,TXXX\tAlbum Artist",
    duration    => 'TLEN',
);


sub fromMP3
    # return value is ignored
{
    my ($this,$path) = @_;
    display($dbg_mediafile,0,"fromMP3()");

    # construct the mp3info object, and
    # return if it doesn't construct.
    # errors already reported appropriately

    my $mp3 = MP3Info->new($path,0,$this);
    if (!$mp3)
    {
        error("FATAL ERROR - no MP3 returned from MP3Info->new($path)");
        return;
    }
    $mp3->close(1);    # abort changes

    # populate raw_tags for debugging/webUI
    # and set has_art boolean on the fly

    $this->{raw_tags} = {};
    my @ids = $mp3->get_tag_ids();
    for my $id (@ids)
    {
        my $val = $mp3->get_tag_value($id) || '';
        $this->{raw_tags}->{$id} = $val;

		if ($id =~ /^APIC/)
        {
            my $tag = $mp3->{taglist}->tag_by_id($id);
            if (!$tag)
            {
                error("Implementation Error - Could not get APIC tag from mp3-taglist");
                return;
            }
            elsif (!$tag->{data})
            {
                $this->set_error('mq',"APIC has no data");
            }
            elsif ($tag->{mime_type} !~ /^(JPG|image\/(jpg|jpeg))$/i)
            {
                $this->set_error('mm',"unknown picture MIME type($tag->{mime_type})");
            }
            else
            {
                $this->set("fromMP3",$path,'has_art',$HAS_TRACK_ART);
            }
        }
    }

    # populate mediaFile (this) for Library

    for my $field (keys(%artisan_to_mp3))
    {
        for my $tag_id (split(/,/,$artisan_to_mp3{$field}))
        {
            my $value = $mp3->get_tag_value($tag_id);
            if ($value)
            {
                $this->set("fromMP3",$path,$field,$value);
                last;
            }
        }
    }
    return 1;
}



#-----------------------------------------------------
# cache getters
#-----------------------------------------------------

sub get_fpcalc_info
    # Get the fpcalc_info for this mediaFile object.
    # Uses info as cached by $file_md5 if possible.
    # Uses this->{path} to call fpcalc.exe.
{
    my ($this,$force) = @_;
    $force ||= 0;

    my $file_md5 = $this->{file_md5};
    if (!$file_md5)
    {
        error("Implementation Error - No file_md5 in get_fpcalc_info($this->{path})");
        return;
    }

    bump_stat("get_fpinfo called");

    my $dir = "$data_dir/fpcalc_info";
    mkdir $dir if (!(-d $dir));
    my $cache_file = "$dir/$file_md5.txt";

    my $text = '';
    if (!$force && -f $cache_file)
    {
        display(9,0,"getting fp_calc_info from cache($cache_file)");
        $text = getTextFile($cache_file);
        bump_stat("get_fpinfo got from cache");
    }
    elsif (0)
    {
		# Calling fpCalc was not last supported on Android
		# Though it works, too slow ...
        error("FATAL ERROR - Android could not find cache_file: $cache_file");
    }
    else
    {
        bump_stat("get_fpinfo called prh_calc");
        my $path = $this->{path};
        $path =~ s/\//\\/g;

        # call to fpcalc.exe does not work reliably when library run as a thread.
        # See artisan.pm where we scan library once in the main thread as a workaround
        # my $exe_path = "$artisan_perl_dir/bin/fpcalc_orig.exe";

        my $exe_path = "$artisan_perl_dir/bin/fpcalc_linux_win.0.09.exe";
        $exe_path =~ s/\//\\/g;
        display(0,-1,"calling '$exe_path' -md5 -stream_md5 '$path'") if (!$force);
        $text = `$exe_path  -md5 -stream_md5 "$path" 2>&1`;

        if (!$text)
        {
            error("FATAL ERROR - Could not call prhcalc_win.exe for $path");
            return;
        }
        printVarToFile(1,$cache_file,$text) if ($force != 1);
    }

    my $info = {};
    my @lines = split(/\n/,$text);
    my $num_errors = 0;

    for my $line (@lines)
    {
        $line =~ s/\s+$//;
        chomp($line);
        my $pos = index($line,"=");

        # unknown_stream seems to be related to files
        # i've received with DRM management in them.

        if ($line =~ /asf skip 9 \(unknown stream\)/)
        {
            $this->set_error('mu',"Unknown stream (DRM)");
            return;
        }

        if ($line =~ /^\[/)
        {
            # 2014-12-18 - eliminate lines that have FILE= in them
            # as 'errors' ...

            if ($line !~ /FILE=/)
            {
                $num_errors++;
                $this->set_error('mf',"fpcalc error($line)");
                if ($line =~ s/^\[(.*) \@ 0x.*?\] //)
                {
                    my $what = $1;
                    $info->{"$what $line"} ||= 0;
                    $info->{"$what $line"}++;
                }
                else
                {
                   $this->set_error('mr',"fpcalc cant parse($line)");
                }
            }
        }
        elsif ($pos > 1)
        {
            my $lval = lc(substr($line,0,$pos));
            my $rval = substr($line,$pos+1);
            next if ($lval eq 'file');
            display($dbg_mediafile+2,1,_lim("$lval <= $rval",100));
            $info->{$lval} = $rval;
        }
    }

    $this->set_error('mz',"more than five fpcalc errors")
        if ($num_errors > 5);
    display($dbg_mediafile+2,0,"get_fpcalc_info returning $info");
    return $info;
}



#------------------------------------------------
# get_pictures
#------------------------------------------------

sub unused_get_pictures
    # return any jpegs found in the file as an array
{
    my ($this) = @_;
    my @retval;

    if (!$this->{has_art})
    {
        error("attempt to call get_pictures on mediaFile with !has_art");
    }
    elsif ($this->{type} eq 'mp3')
    {
		my $raw_tags = $this->{raw_tags};
		for my $k (sort(keys(%$raw_tags)))
		{
			if ($k =~ /^APIC/)
			{
                my $tag = $raw_tags->{$k};
                my $data = $tag->{data} || '';
                my $data_len = length($data);
                my $mime_type = $tag->{'mime_type'} || '';

				display(0,0,"get_picture(MP3) found tag($k)=$mime_type");
                if ($mime_type !~ /^(JPG|image\/(jpg|jpeg))$/i)
                {
                    error("unknown picture MIME type($mime_type) in $this->{path}");
                }
                elsif (!$data)
                {
                    use Data::Dumper;
					$Data::Dumper::Indent = 1;
					$Data::Dumper::Sortkeys = 1;
                    print Dumper($tag);
                    error("zero length picture found in $this->{path}");
                }
                else
                {
                    push @retval,$data;
                }

			}	# found APIC
        }   # for every tag
    }   # in MP3 file

    elsif ($this->{type} eq 'm4a')
    {
        my $data = $this->{raw_tags}->{tags}->{COVR};
        if (!$data)
        {
            error("zero length picture found in $this->{path}");
        }
        else
        {
            push @retval,$data;
        }
    }
    else
    {
        error("huh? unsupported type $this->{type} in get_picture");
    }

    return @retval;
}



1;
