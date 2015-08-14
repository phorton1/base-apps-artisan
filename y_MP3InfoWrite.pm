# 2014-07-03 prh - derived from MP3::Info.pm
#
#  _write_tags()
#
#     takes a the member list of V4 tags and writes
#     them to the file, removing the old tags in the
#     process. That's the way it works. If you want to change
#     one tag, read them all in, and write them all out.
#
#     Always writes a V1 and a V2.4 section, creating
#     the V1 section from the V2.4 tags.
#
#     Lots of stuff can be changed opening my MP3
#     files, including losing extended headers and crc,
#     remapping v2 and v3 ids to v4, decoding bytes,
#     etc, etc, etc. See MediaFile.pm, MP3InfoRead.pm
#     and MP3TagList.pm, for a start.

package MP3Info;
use strict;
use warnings;
use Fcntl qw(:seek);
use File::Copy;
use Utils;
use MP3Vars;

	
my $SAVE_OLD_FILE = 1;
    # the previous file will be renamed .mp3.bakNNN.
    # and the routine will work off a new copy.
	# DO NOT CHANGE THIS!
	
my $USE_EXISTING_PADDING = 1;
    # if set, if possible, will use existing V2 space
    # and add padding within the new ID3 tag to fit exactly
    # into it. Otherwise, will compress the MP3 file down
    # to the tag section, when writing smaller tags
    # over previous bigger ones.

my $PADDING_BLOCK_SIZE = 4096; # 1024;
    # This defines a 'block_size' in our MP3 files,
    # used for padding empty space.  If !USE_EXISTING_PADDING
    # or the new tags won't fit into the existing space,
    # then the size of the tag will be rounded up to
    # the next multiple of $PADDING_BLOCK_SIZE, so
    # that we *may* not have to re-write it as often



# the main client API
# 2015-06-18 separated out mp3 writing

sub set_tag_value
    # 2015-06-18 start commenting out write call chain
{
    my ($this,$id,$value) = @_;
    $value ||= '';
    display($dbg_mp3_info+1,0,"set_tag_value($id,$value)");
    my $taglist = $this->{taglist};
    return if !$taglist->set_tag_value($id,$value);
    return 1;
}

#--------------------------------------------------------
# write_tags
#--------------------------------------------------------
# layout of the mp3 file with regards to the ID3 tags.
#
#     0        +-----------------------------------------+
#              | 10 tag byte header, contains data_size  |
#     10       +-----------------------------------------+
#              |             data_size bytes             |
#              |          of frames and padding          |
#              | +------------------------------------+  |
#              | | 10 byte frame header w/frame_size  |  |
#              | +------------------------------------+  |
#              | |           frame_size bytes         |  |
#              | |           of frame data            |  |
#              | +------------------------------------+  |
#              | | 10 byte frame header w/frame_size  |  |
#              | +------------------------------------+  |
#              | |           frame_size bytes         |  |
#              | |           of frame data            |  |
#              | +------------------------------------+  |
#              | |           more frames ...          |  |
#              | +------------------------------------+  |
#              |                                         |
#              |     frames may end exactly at           |
#              |      data size, or there may be         |
#              |     0x00 padding bytes after the        |
#              |                                         |
# data_size+10 +-----------------------------------------+
#              |                                         |
#              |               MP3 data                  |
#              |                                         |
	

sub _write_tags
	# returns 0 on failure, 1 on success
	# reports errors / warnings as needed
{
    my ($this) = @_;
    LOG(0,"_write_tags($this->{path})");
    if (!$this->{fh})
    {
        error("Implementation Error - file not open in _write_tags() for $this->{path}");
        return;
    }
    if ($this->{readonly})
    {
        error("Implementation Error - attempt to write to readonly mp3 file $this->{path}");
        return;
    }

    return if ($SAVE_OLD_FILE && !$this->renameAndCopy());
    my $fh = $this->{fh};

    # untested remove the old V2 footer if any
    # this preserves the V1 tags, if any

    my $v2f = $this->{v2f}; # _get_v2foot();
    if ($v2f)
    {
        error("Implementation Error - Removal of footers is not tested. Please fix this!");
        return;
		
        LOG(1,"removing old V2 footer");

        seek $fh,0,SEEK_END;
        my $eof = tell $fh;
        my $size = $v2f->{tag_size};
        if ($this->{hasV1})
        {
            my $pos = $size + 128;

            # move 128 bytes from $eof-128 to $eof-$pos

            seek $fh, $eof-128, SEEK_SET;
            my $buffer;
            if ((my $bytes=read($fh,$buffer,128)) != 128)
            {
                error("Could only read $bytes/128 at $eof-128 from $this->{path}");
                return;
            }
            seek $fh, $eof-$pos, SEEK_SET;
            if (!print($fh $buffer))
            {
                error("Could not print 128 bytes at $eof-$pos from $this->{path}");
                return;
            }
        }

        # truncate the file to $eof-$size

        if (!truncate $fh, $eof-$size)
        {
            error("Can't truncate to $eof-$size: $this->{path}");
            return;
        }
    }

    # prh - write the V1 tags
	# PRH !! - non production version DO NOT CHANGE EXISTING V1 Tags!
	
    # return if !$this->_write_v1_tags();

    # which knows how to do v4->v1 mappings
    # return if !$this->_write_v1_tags();
    # build the entire V4 tag section

    my $newtags = $this->_build_tags();
    return if !defined($newtags);

    my $new_bytes = length($newtags);
    LOG(1,"new v2 full tag size = $new_bytes");

    # get the old V2 header if any
    # tag size MUST include the 10 bytes for the
    # tag header itself.

    my $old_bytes = 0;
	my $v2h = $this->{v2h};  # _get_v2head($fh);
    $old_bytes = $v2h->{tag_size} if ($v2h && $v2h->{tag_size});
    LOG(1,"old v2 full tag size = $old_bytes");
    my $off = $new_bytes - $old_bytes;

    # move the whole file backwards from
    # old_bytes to new_bytes

    if ($off)
    {
        my $buffer;
        my $bufsize = 1000000;
        seek $fh, 0, SEEK_END;
        my $end = tell $fh;

        my $pos = $off < 0 ? $old_bytes : $end;
        my $len = $end - $old_bytes;
        LOG(1,"TAG SIZE CHANGED tags grew by $off bytes");

        while ($len)
        {
            my $bytes = $bufsize;
            $bytes = $len if ($bytes > $len);
            my $from = $pos - ($off > 0 ? $bytes : 0);
            my $to = $from + $off;
            LOG(2,"moving $bytes bytes from $from to $to");

            seek $fh, $from, SEEK_SET;
            if (read($fh, $buffer, $bytes) != $bytes)
            {
                error("Could not read $bytes at $from from $this->{path}");
                return;
            }

            seek $fh, $to, SEEK_SET;
            if (!print($fh $buffer))
            {
                error("Could not write $bytes at $to in $this->{path}");
                return;
            }

            $pos = ($off > 0) ? $from : $pos + $bytes;
            $len -= $bytes;
        }
    }

    LOG(1,"writing new tags length=".length($newtags));
    # display_bytes($dbg_mp3_write,3,"newtags",$newtags);

    seek $fh,0,SEEK_SET;
    if (!print($fh $newtags))
    {
        error("Could not write new header $new_bytes at 0 in $this->{path}");
        return undef;
    }

    # prh - need to *could* prevent need for re-read
    # by setting appropriate member variables here:
    #    is_artisan
    #    v2h, etc

    $this->{hasV1} = 1;
    $this->{dirty} = 0;
    return 1;
}


sub renameAndCopy
    # create a backup before writing
{
    my ($this) = @_;
    close $this->{fh};
    delete $this->{fh};

    my $cnt = '000';
    my $new_path = $this->{path}.".BAK$cnt";
    while (-f $new_path)
    {
        $cnt++;
        $new_path = $this->{path}.".BAK$cnt";
    }

    if (!rename $this->{path},$new_path)
    {
        error("Could not rename $this->{path} to $new_path");
        return;
    }
    if (!copy $new_path,$this->{path})
    {
        error("Could not re-copy $this->{path} from $new_path");
        return;
    }
    if (!open($this->{fh},'+<',$this->{path}))
    {
        error("Could not re-open $this->{path} for writing");
        delete $this->{fh};
        return;
    }

    binmode $this->{fh};
    return 1;
}



sub _write_v1_tags
    # prh !!!
{
    my ($this) = @_;
    display($dbg_mp3_write,0,"_write_v1_tags()");
    my @v1_tag_names = qw(TIT2 TPE1 TALB TDRC COMM TRCK TCON);
    my @v1_tag_width =   ( 30,  30,  30,   4,  28,   2,    1);

    my $dbg_str = 'TAG';
    my $buffer = 'TAG';

    for (my $i=0; $i<@v1_tag_names; $i++)
    {
        my $tag_id = $v1_tag_names[$i];
        my $width = $v1_tag_width[$i];
        my $value = $this->get_tag_value($tag_id) || '';

        $value =~ s/^\s+//g;
        $value =~ s/\s+$//g;

        if ($tag_id eq 'TRCK')          # TRCK
        {
            $value =~ s/\/.*$//;        # get rid of /4
            $value =~ s/^0+//;          # get rid of leading zeros
            $value = 0 if $value !~ /^\d+/ || $value > 127;
            $dbg_str .= ",$value";
            $value = "\x00".chr($value);
        }
        elsif ($tag_id eq 'TCON')       # map text genre to mp3 genre if it exists
        {
            my $use_genre = 0xff;
            for (my $j=0; $j<@mp3_genres; $j++)
            {
                if ($value =~ /^$mp3_genres[$j]/)
                {
                    $use_genre = $j + 1;
                    last;
                }
            }
            $dbg_str .= ",$use_genre";
            $value = chr($use_genre);
        }
        else
        {
            # probably should encode any strings with anything
            # as there are possible sync patterns in full charset
            # but, fuck it.

            $value = substr($value,0,$width);
            $dbg_str .= ",$value";
            while (length($value) < $width) {$value .= "\x00"};
        }

        $buffer .= $value;
    }

    my $fh = $this->{fh};
    my $off = $this->{hasV1} ? -128 : 0;
	seek $fh, $off, SEEK_END;

    LOG(0,"_write_v1_tags($off)=$dbg_str");

    if (!print($fh $buffer))
    {
        error("Could not write 128 bytes at $off in $this->{path}");
        return;
    }
    $this->{hasV1} = 1;
    return 1;
}



sub _build_tags
    # build a new entire ID3v2.4 tag section,
    # including the tag header from the given
    # tags.
{
    my ($this) = @_;
    my $taglist = $this->{taglist};
    my @tags_ids = $taglist->get_tag_ids();
	
	# geez windows doesn't seem to recognize ID3v2.4 !!!
	
	# PRH !!!! Try writing it out as version 2.3
	# which means we do the unsync on the whole thing
	# (and for now, we ignore everything else different)
	# IF THIS WORKS, I NEED TO THINK ABOUT USING 2.3 as
	# MY STANDARD AND DROPPING or downdating 2.4 frames.
	
    LOG(0,"build_tags(ID3v2.$WRITE_VERSION)");
    my $off = 10;   # for display only, size of tag header

	# Version 2.4 expects the main header sync bit to be 0
	# if ANY frame is not unsynced, which should almost always
	# happen, even though it is somewhat reduntant with the
	# frame sync bit.
	#
	# Version 2.3 never sets the frame sync bit, and expects
	# the header sync bit to be set if it's unsynced, which
	# should almost always happen.
	
    my $data = '';
    my $not_unsynced = 0;
        # set to one if any frame is not unsynced
		# weird hard to understand semantic

    for my $tag_id (@tags_ids)
    {
        my $tag = $taglist->tag_by_id($tag_id);
        my $t = $this->_build_one_tag($tag,\$not_unsynced,$off);
        return if (!defined($t));
        $data .= $t;
        $off += length($t);
    }

	# so, for version three if we DO sync it, we set 
	# not_unsynced to 0 if we DID sync it, so that the
	# sync bit will get set by logic below ...
	
	if ($WRITE_VERSION == 3)
	{
		$not_unsynced = ($data =~ s/\xFF/\xFF\x00/gs) ? 0 : 1;
	}
	
    # determine the size we want for our whole tag block

    my $size = length($data);
	my $existing_size = 0;
	$existing_size = $this->{v2h}->{tag_size}
		if ($this->{v2h} && $this->{v2h}->{tag_size});
    my $avail_padding = $existing_size  - 10 - $size;
    display($dbg_mp3_write,1,"build_tags() raw size=".$size);
    display($dbg_mp3_write,2,"existing size=$existing_size");
    display($dbg_mp3_write,2,"available=$avail_padding");

    # if it will fit into the existing tags, and $USE_EXISTING_PADDING
    # we will create a chunk exactly the right size to replace the
    # existing one

    if ($avail_padding >= 0 && $USE_EXISTING_PADDING)
    {
        if ($avail_padding > 0)
        {
            display($dbg_mp3_write,1,"adding $avail_padding bytes for USE_EXISTING_PADDING");
            $size += $avail_padding;
            $data .= "\x00" x $avail_padding;
        }
        else
        {
            display($dbg_mp3_write,0,"new tags fit exactly into old tags.");
        }
    }

    # otherwise, round the padding up to the next
    # blocksize if $PADDING_BLOCK_SIZE

    elsif ($PADDING_BLOCK_SIZE)
    {
        my $num_blocks = int(($size + $PADDING_BLOCK_SIZE - 1) / $PADDING_BLOCK_SIZE);
        my $new_size = $num_blocks * $PADDING_BLOCK_SIZE;
        my $add_padding = $new_size - $size;

        if ($add_padding)
        {
            display($dbg_mp3_write,1,"adding $add_padding bytes for PADDING_BLOCK_SIZE=$PADDING_BLOCK_SIZE");
            $data .= "\x00" x $add_padding;
            $size = $new_size;
        }
    }


    # build the header last
    # unsync for the whole tags (v2.4)
    # should ONLY be set if there are
    # no frames that DONT have the bit set

    if ($size > (1 << 28))
    {
        error("size of ID3 data too big in $this->{path}");
        return;
    }
    display($dbg_mp3_write,1,"building header for $size bytes");
	
	# so, the sync bit gets set if it was 
	# version 3 and we unsynced the whole tag, or
	# if was version 4 and all the frames were
	# unsynced ...
	
    my $flags = $not_unsynced ? 0x00 : 0x80;
    my $header = 'ID3'.chr($WRITE_VERSION).chr(0).chr($flags);
    $header .= chr(($size>>21) & 0x7f);
    $header .= chr(($size>>14) & 0x7f);
    $header .= chr(($size>>7) & 0x7F);
    $header .= chr($size & 0x7F);
    # display_bytes($dbg_mp3_write,1,"tag_header",$header);

    return $header.$data;
}



sub _build_one_tag
{
    my ($this,$tag,$no_sync,$off) = @_;

    # have the taglist encode the tag to raw bytes in {value}

    return if !$this->{taglist}->encode_tag($tag);
    my $id = $tag->{id};
    my $bytes = $tag->{value};

    # debug

    display(_clip $dbg_mp3_write+1,0,"build_one_tag($id) off=$off len=".
        length($bytes)." data=$bytes");

    # unsync as needed and create the header
    # the only flag we *may* use is unsync
    # report to caller if we have any !unsync'd frames

    my $unsync = 0x00;
	if ($WRITE_VERSION == 4)
	{
		$unsync = ($bytes =~ s/\xFF/\xFF\x00/gs) ? 0x02 : 0x00;
	}
    my $size = length($bytes);
    display($dbg_mp3_write+1,1,"unsynced size=$size") if ($unsync);
    $$no_sync = 1 if (!$unsync);

    # build the header
	# version 4 uses syncsafe frame size
	# version 3 uses full bytes

    my $data = $id;
    if ($WRITE_VERSION == 4)
    {
        $data .= chr(($size>>21) & 0x7f);
        $data .= chr(($size>>14) & 0x7f);
        $data .= chr(($size>>7) & 0x7F);
        $data .= chr($size & 0x7F);
    }
    else
    {
        $data .= chr(($size>>24) & 0xFF);
        $data .= chr(($size>>16) & 0xFF);
        $data .= chr(($size>>8) & 0xFF);
        $data .= chr($size & 0xFF);
    }

    $data .= chr(0);
    $data .= chr($unsync);
    display_bytes($dbg_mp3_write+3,5,"frame_header",$data);

    # add the bytes and return to caller

    $data .= $bytes;
    return $data;
}



1;
