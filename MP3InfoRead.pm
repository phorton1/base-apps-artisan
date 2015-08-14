#------------------------------------------------------
# MP3InfoRead.pm
#------------------------------------------------------
# 2014-07-03 prh - derived from MP3::Info.pm
#
# _get_v1_tags()
#
#     read v1 tags from file, if any, and
#     pre-populate the taglist with
#     the v1 tags already mapped to v4 fields.
#
# _get_v4_tags()
#
#     read the v2+ tags from the file and
#     fixup as necessary to v4.
#
#     More or less expects _get_v1_tags to already have
#     been called. In particular, V1 tags are pre-merged
#     into the V4 tags, and the larger of the two will
#     be taken, with a warning, and marking the file
#     diry if the V1 is not a substring of the V4 tags.
#
#     There is a warning, and the file is marked
#     to dirty if the file was V2 (thus all
#     tags had to be fixed up), or if it was V3 and
#     any tags had to be changed to bring it up to V4.
#
#     These raw tags are ready to be written out
#     as an v4 ID3 section, and there is a straight
#     forward mapping to a v1 ID3 section.

package MP3Info;  # continued ...
use strict;
use warnings;
use Fcntl qw(:seek);
use Utils;
use MP3Vars qw(@mp3_genres %all_v2_tag_names $WRITE_VERSION);


#-------------------------------------------------------------------------------
# get v1 tag
#-------------------------------------------------------------------------------

sub _get_v1_tags
	# return 0 on hard errors
	# or 1 for anything else.
	# Client may check hasV1 to determine if there was a tag
{
	my ($this) = @_;
    display($dbg_mp3_read,0,"_get_v1_tags()");
    my @v1_tag_names = qw(TIT2 TPE1 TALB TDRC COMM TRCK TCON);
		# note that TDRC assumes a V4 mapping ...
	$v1_tag_names[3] = 'TYER' if ($WRITE_VERSION == 3);
		
    # use the V23 tag names for the appropriate fields
    # title, artist, album, year, comment, tracknum, & genre
    # but put them in a separate hash to begin with

    my $fh = $this->{fh};
    if (!$fh)
    {
        error("Implementation Error - File not open in _get_v1_tags for $this->{path}");
        return;
    }

    my $buffer;
	seek $fh, -128, SEEK_END;
	if ((my $bytes = read($fh, $buffer, 128)) != 128)
    {
        $this->set_error('ra',"_get_v1_tags() could only read $bytes/128");
        return;
    }

    # return success if section was not found
    # set member variable hasV1 if it was found

	return 0 if !defined($buffer);
	if ($buffer !~ /^TAG/)
	{
		$this->set_error('note',"No ID3v1 tags found in $this->{path}");
		return 1;
	}
	$this->set_error('note',"ID3v1 tags found in $this->{path}");
    $this->{hasV1} = 1;

    # unpack the fields into the working array

    # prh - found a number of files with the comment
    # jammed up against what was obviously a track
    # number with no preceding \000, so second part
    # if checks for tracknumber < 32 (space) ...
    # possible chnage: the 28 could be a 29, and the
    # \x00 will get stripped off elsewhere.

	my %hash;
    if (substr($buffer, -3, 2) =~ /\000[^\000]/) #   ||
        # substr($buffer, -2, 1) =~ /[\x01-0x1f]/)
    {
		(undef, @{\%hash}{@v1_tag_names}) =
			(unpack('a3a30a30a30a4a28', $buffer),
			ord(substr($buffer, -2, 1)),
			$mp3_genres[ord(substr $buffer, -1)]);
	}
    else
    {
		(undef, @{\%hash}{@v1_tag_names[0..4, 6]}) =
			(unpack('a3a30a30a30a4a30', $buffer),
			$mp3_genres[ord(substr $buffer, -1)]);
	}
    for my $key (keys %hash)
    {
        my $value = $hash{$key} || '';

        # 'Other' from ID3 tags doesn't count.
        # my 'Other' is an explicit string in the v2+ tags
        # or the outer folder name from get_default_info()

        $value = '' if ($key eq 'TCON' && $value eq 'Other');
		
		# map V1 comment tags to V2 format
		# by adding a subid of 'V1';
		
        next if !defined($value) || !length($value);
        my $rslt = $this->{taglist}->add_tag(undef,$key,$value);
        return if (!defined($rslt));
    }
	return 1;
}



#-------------------------------------------------------------------------------
# _get_v2_tags, headers, footers, and data
#-------------------------------------------------------------------------------

sub _get_v2_tags
	# return undef if any hard errors
	# return 1 if there are tags or not.
	# client can check $this->{v2h} for existence of tags
{
	my ($this) = @_;
    display($dbg_mp3_read,0,"_get_v2_tags()");

    my $fh = $this->{fh};
    if (!$fh)
    {
        error("_get_v2_tags() called with no file handle for $this->{path}");
        return;
    }

    # this whole thing is weird.
    # According to my reading of the spec about the 'update' bit
    # in the extended header, it means that, if set, any tags found
    # 'later in the file or stream' overwrite the earlier ones, that
    # were otherwise presumed to be unique ala spec. So, that means
    # that we should read the header before the footer, and I moved
    # the call here from below ... I suspect that there may be
    # multiple ID3v2 tags in a stream and not just at the beginning,
    # end, or -128 of the file, and that someone someplace expects
    # us to scan the whole file for a header signature ... epecially
    # as there is a frame called 'SEEK', that appears specifically
    # to suggest that one go traipsing around the file, sheesh.

	my $v = $this->_get_v2_data();
	return if (!defined($v));

	# Check the end of the file for any footer

    seek $fh, ($this->{hasV1}) ? -128 : 0, SEEK_END;
    my $eof = tell($fh);
	my $v2f = $this->_get_v2_foot();
	return if (!defined($v2f));
	
	if ($v2f)
    {
		$eof -= $v2f->{tag_size};
		$v = $this->_get_v2_data($eof);
		return if (!defined($v));
	}

	# return to caller

    display($dbg_mp3_read,1,"_get_v2_tags() returning 1");
	return 1;
}




sub _get_v2_data
    # return undef for hard errors
	# return 0 for no section
	# return 1 for section found
{
	my ($this, $start) = @_;
    display($dbg_mp3_read,0,"_get_v2_data()");

    #--------------------------------------
    # get, check, and save off the header
    #--------------------------------------
    # return failues if version<2 or compression

    my $fh = $this->{fh};
    if (!$fh)
    {
        error("Implemetation Error - _get_v2_data() called with no file handle for $this->{path}");
        return;
    }

	my $v2h = $this->_get_v2_head($start);
    return 1 if (!$v2h);
	if ($v2h->{major_version} < 2)
    {
		$this->set_error('rb',"ID3v2 versions older than ID3v2.2.0 not supported");
		return 0;
	}
	if ($v2h->{major_version} == 2 && $v2h->{compression})
    {
        $this->set_error('rc',"Version 2 compression was never supportable");
        return 0;
    }

    # save the header as {v2h} and the footer as {v2f}

    if (!$start)    # at beginning of file
    {
        $this->{v2h} = $v2h;
    }
    else
    {
        $this->{v2f} = $v2h;
    }

    #------------------------------------------
    # Read the frames (wholetag) into memory
    #------------------------------------------
    # sheesh, why did he read the header in again?
	# as original:
    #    my $end = $v2h->{tag_size} + 10; # should we read in the footer too?
	#    my $off = $v2h->{ext_header_size} + 10;

	my $end = $v2h->{tag_size} - 10;    # tag_size is different than data_size
                                        # so we subtract it the header ...
    my $byte_start = $v2h->{offset} +   # the offset of the header (0 at front) in file
        10 +                            # past the header
        $v2h->{ext_header_size};        # and the extended header
	my $size = -s $fh;

    # make sure the end is less than eof

	if ( $byte_start + $end > $size )
    {
        $this->set_error('rd',"_get_v2_data() byte_start=$byte_start + end($end) past eof($size) reading less bytes");
		$end = $size - $byte_start;
	}

    # read in the buffer

	my $wholetag;
    seek $fh, $byte_start, SEEK_SET;
	if (read($fh, $wholetag, $end) != $end)
    {
        $this->set_error('re',"Could not read $end bytes tags");
        return;
    }

    # unsync whole tag if needed
    # not in version 4

	if ($v2h->{major_version} == 4)
    {
		$v2h->{unsync} = 0
	}
	$wholetag =~ s/\xFF\x00/\xFF/gs if $v2h->{unsync};

    #--------------------------------------
    # LOOP THRU FRAMES
    #--------------------------------------
    # while there is room for one more header
	# my_seek returns undef for mp3 structure errors
	# (and reports them) or 0 to terminate the loop

    my $off = 0;
    while ($off < $end - $v2h->{header_len} )
    {
		my ($id, $size, $flags) = $this->_myseek($v2h,$wholetag, $off, $end);
        if (!defined($id))
		{
			$this->set_error('rf',"loop thru frames got id=undef in $this->{path}");
			return 1;  # let it go?
		}
        last if (!$id);

        my $use_desc = $all_v2_tag_names{$id} || 'unknown';
        bump_stat("$id($use_desc)");

        my $dbg_location = "in frame($id) at off=$off(+$v2h->{header_len})";

        # as returned by _mysee(), $off is beginning of header,
        # and size includes the header, so we advance here ...

        display($dbg_mp3_read+1,1,"frame($id) off=$off size=$size");

        $off += $v2h->{header_len};
        $size -= $v2h->{header_len};

        if ($off + $size > $end)
        {
            $this->set_error('rg',"tag($id) attempt to read $size bytes past end($end) $dbg_location");
            last;
        }

		# (NOTE: Wrong; the encrypt comes after the DLI. maybe.?)
		# Encrypted frames need to be decrypted first
    	# We don't actually know how to decrypt anything,
        # so we'll just push the entire frame, as is.

		my $bytes = substr($wholetag, $off, $size);
		if ($flags->{frame_encrypt})
        {
			my $encrypt_method = ord(substr($bytes, 0, 1));
            $this->set_error('rh',"Encrypted($encrypt_method) $dbg_location");
            $id .= "_ENCRYPT($encrypt_method)";
                # alter the id to prevent potential misuse
                # of the data associated with this tag.
		}

        # same with zlib compression, though I could probably
        # handle this, I don't ...

        elsif ($flags->{frame_zlib})
        {
            $this->set_error('ri',"Zlib compressed frame($id) $dbg_location");
            $id .= "_ZLIB";
        }
        else
        {
            my $data_len;
            if ($flags->{data_len_indicator})
            {
                $data_len = 0;
                my @data_len_bytes = reverse unpack 'C4', substr($bytes, 0, 4);
                $bytes = substr($bytes, 4);
                for my $i (0..3)
                {
                    $data_len += $data_len_bytes[$i] * 128 ** $i;
                }
            }

            display($dbg_mp3_read+2,2,"got $id, length ".length($bytes).
                " frameunsync: ".($flags->{frame_unsync}?1:0).
                " tag unsync: ".($v2h->{unsync}?1:0));

            # perform frame-level unsync if needed (skip if already done for whole tag)

            if ($flags->{frame_unsync} && !$v2h->{unsync})
            {
                display($dbg_mp3_read+2,2,"frame_unsync len before=".length($bytes));
                $bytes =~ s/\xFF\x00/\xFF/gs;
                display($dbg_mp3_read+2,2,"frame_unsync len after=".length($bytes));
            }

            # Decompress now if zlib decompression implemented.
            # if we know the data length, sanity check it now.

            if ($flags->{data_len_indicator} && defined $data_len)
            {
                if ($data_len != length($bytes))
                {
                    $this->set_error('rj',"size mismatch on frame($id). skipping $dbg_location");
               		$off += $size;
                    next;
                }
            }

            # Apply small sanity check on text elements - they must end with :
            #     a 0 if they are ISO8859-1
            #     0,0 if they are unicode
            # (This is handy because it can be caught by the 'duplicate elements'
            # in array checks)
            # There is a question in my mind whether I should be doing this here - it
            # is introducing knowledge of frame content format into the raw reader
            # which is not a good idea. But if the frames are broken we at least
            # recover.

            if (($v2h->{major_version} == 3 || $v2h->{major_version} == 4) && $id =~ /^T/)
            {
                my $encoding = substr($bytes, 0, 1);

                # Both these cases are candidates for providing some warning
                # ISO-8859-1 or UTF-8 $bytes

                if (($encoding eq "\x00" || $encoding eq "\x03") && $bytes !~ /\x00$/)
                {
                    $bytes .= "\x00";
					# this is so frequent, that I'm going to ignore it!
                    # $this->set_error('rk',"Malformed ISO-8859-1/UTF-8 text $dbg_location");
                }

                # # UTF-16, UTF-16BE

                elsif ( ($encoding eq "\x01" || $encoding eq "\x02") && $bytes !~ /\x00\x00$/)
                {
                    $bytes .= "\x00\x00";
                    $this->set_error('rl',"Malformed UTF-16/UTF-16BE text $dbg_location");

                }
                else
                {
                    # Other encodings cannot be fixed up (we don't know how 'cos they're not defined).
                }
            }

        }   # not encrypted

        my $rslt = $this->{taglist}->add_tag($v2h,$id,$bytes);
        return if (!defined($rslt));
		$off += $size;

	}

    # these are file offsets
    # prh - note that I had to change end to make it work

    if ($off < $end)
    {
        $v2h->{padding} = $end-$off;
        display($dbg_mp3_read+1,1,"found padding bytes from $off to $end = $v2h->{padding}");
    }

	return 1;

}   # _get_v2_data()




sub _myseek
    # If we /knew/ there would be something special in the tag which meant
    # that the ID3v2.4 frame size was broken we could check it here.
{
    my ($this,$v2h,$wholetag,$off,$end) = @_;

    # setup for v2 versus v3/v4 tags

    my $header_len = $v2h->{header_len};
    my $num_bytes = $v2h->{major_version} == 2 ? 3 : 4;
    my $bytesize = $v2h->{major_version} == 4 ? 128 : 256;
    my $bytes = substr($wholetag, $off, $header_len);

    # iTunes is stupid and sticks ID3v2.2 3 byte frames in a
    # ID3v2.3 or 2.4 header. Ignore tags with a space in them.

    my $dbg_location = "at off=$off(+$v2h->{header_len})";

    if ($bytes !~ /^([A-Z0-9\? ]{$num_bytes})/)
    {
        # error ending
        if ($bytes !~ /^\000\000\000\000/)
        {
            $this->set_error('rm',"invalid frame $dbg_location");
            display_bytes(0,0,"bytes",$bytes);
            return;
        }
        # normal ending
        return ('','','');
    }

    # unpack the id and size, and
    # take the ?'s out of v2 id's in v3+ files

    my ($id, $size) = ($1, $header_len);
    $id =~ s/\?$//;

    my @bytes = reverse unpack "C$num_bytes", substr($bytes, $num_bytes, $num_bytes);
    for my $i (0 .. ($num_bytes - 1))
    {
        $size += $bytes[$i] * $bytesize ** $i;
    }

    $dbg_location = "in frame($id,$size) $dbg_location";

    # Check for broken frame sizes
    # Provide the fall back for the broken ID3v2.4 frame size
    # (which will persist for subsequent frames if detected).
    # Part 1: If the frame size cannot be valid according to the
    # specification (or if it would be larger than the tag
    # size allows). !frame_size_broken means we haven't detected
    # brokenness yet

    # if there are high order bits set in size
    # or frame size would excede the tag end

    if ($v2h->{major_version}==4 &&
        !$v2h->{frame_size_broken} &&
        ((($bytes[0] | $bytes[1] | $bytes[2] | $bytes[3]) & 0x80) != 0 ||
         $off + $size > $end)
        )
    {
        $this->set_error('rn',"Bad frame size(1) $dbg_location");  # using broken behavior

        # The frame is definately not correct for the specification,
        # so drop to broken frame size system instead.
        # header_len has alread been added, so take that off again
        # convert spec to non-spec sizes

        $bytesize = 128;
        $size -= $header_len;
        $size = (($size & 0x0000007f)) |
                (($size & 0x00003f80)<<1) |
                (($size & 0x001fc000)<<2) |
                (($size & 0x0fe00000)<<3);

        # and re-add header len so that the entire frame's size is known

        $size += $header_len;
        $v2h->{frame_size_broken} = 1;
    }

    # Part 2: If the frame size would result in the following
    # frame being invalid. This basically checks every frame
    # over 0x80 in size (ignores frames that are too short
    # to ever be wrong)

    if ($v2h->{major_version}==4 &&
        !$v2h->{frame_size_broken} &&
        $size > 0x80+$header_len &&
        $off + $size < $end)
    {
        display($dbg_mp3_read+3,0,"Checking frame size($size) for validity");

        my $morebytes = substr($wholetag, $off+$size, 4);
        if (! ($morebytes =~ /^([A-Z0-9]{4})/ ||
               $morebytes =~ /^\x00{4}/) )
        {
            # The next tag cannot be valid because its name is wrong, which means that
            # either the size must be invalid or the next frame truly is broken.
            # Either way, we can try to reduce the size to see.
            # remove already added header length
            # convert spec to non-spec sizes
            # and re-add header len so that the entire frame's size is known

            my $retrysize;
            warning(1,1,"Following frame invalid $dbg_location");

            $retrysize = $size - $header_len;
            $retrysize = (($retrysize & 0x0000007f)) |
                         (($retrysize & 0x00003f80)<<1) |
                         (($retrysize & 0x001fc000)<<2) |
                         (($retrysize & 0x0fe00000)<<3);

            $retrysize += $header_len;

            if (length($wholetag) >= ($off+$retrysize+4))
            {
                $morebytes = substr($wholetag, $off+$retrysize, 4);
            }
            else
            {
                $morebytes = '';
            }

            if (! ($morebytes =~ /^([A-Z0-9]{4})/ ||
                   $morebytes =~ /^\x00{4}/ ||
                   $off + $retrysize > $end) )
            {
                # With the retry at the smaller size, the following frame still isn't valid
                # so the only thing we can assume is that this frame is just broken beyond
                # repair. Give up right now - there's no way we can recover.

                $this->set_error('ro',"Bad frame size(2,retrysize=$retrysize); giving up $dbg_location");
                return;
            }

            warning(1,1,"Bad frame size(3) $dbg_location");  # reverting to broken behavior

            # We're happy that the non-spec size looks valid to lead us to the next frame.
            # We might be wrong, generating false-positives, but that's really what you
            # get for trying to handle applications that don't handle the spec properly -
            # use something that isn't broken.
            # (this is a copy of the recovery code in part 1)

            $size = $retrysize;
            $bytesize = 128;
            $v2h->{frame_size_broken} = 1;
        }
        else
        {
            display($dbg_mp3_read+3,0,"valid frame; keeping spec behaviour");
        }
    }

    # Done checking for broken frame sizes.
    # unpack the flags and return

    my $flags = {};
    if ($v2h->{major_version} == 4)
    {
        display_bytes($dbg_mp3_read+3,6,"frame_header_bits",$bytes);
        my @bits = split //, unpack 'B16', substr($bytes, 8, 2);
        display($dbg_mp3_read+2,0,"bits=".join(',',@bits));

        $flags->{frame_zlib}         = $bits[12]; # need to know about compressed
        $flags->{frame_encrypt}      = $bits[13]; # ... and encrypt
        $flags->{frame_unsync}       = $bits[14];
        $flags->{data_len_indicator} = $bits[15];
    }

    # version 3 was in a different order

    elsif ($v2h->{major_version} == 3)
    {
        my @bits = split //, unpack 'B16', substr($bytes, 8, 2);
        $flags->{frame_zlib}         = $bits[8]; # need to know about compressed
        $flags->{data_len_indicator} = $bits[8]; #    and compression implies the DLI is present
        $flags->{frame_encrypt}      = $bits[9]; # ... and encrypt
    }

    return ($id, $size, $flags);

};





sub _get_v2_head
    # _get_v2_head(file handle, start offset in file);
    # The start offset can be used to check ID3v2 headers anywhere
    # in the MP3 (eg for 'update' frames).
{
    my ($this,$start) = @_;
	$start ||= 0;
    display($dbg_mp3_read,0,"_get_v2_head($start)");

    my $fh = $this->{fh};
    if (!$fh)
    {
        error("Implementation Error - _get_v2_head() called with no file handle for $this->{path}");
        return;
    }

    # init empty header record

	my $v2h =
    {
		offset   => $start || 0,
		tag_size => 0,
        padding  => 0,
	};

	# check first three bytes for 'ID3'

    my $header;
	seek($fh, $v2h->{offset}, SEEK_SET);
	if (read($fh, $header, 10) != 10)
    {
        $this->set_error('rp',"Could not read 10 bytes at $v2h->{offset} from $this->{path}");
        return;
    }

	# Footers are dealt with in v2_foot
	# Check for special headers if we're at the start of the file.

	my $tag = substr($header, 0, 3);
    if ($v2h->{offset} == 0)
    {
		if ($tag eq 'RIF' ||
            $tag eq 'FOR')
        {
			return if !$this->_find_id3_chunk($tag) or return;
			$v2h->{offset} = tell $fh;
          	if (read($fh, $header, 10) != 10)
            {
                $this->set_error('rq',"Could not read RIFFOR 10 bytes at $v2h->{offset}");
                $tag = substr($header, 0, 3);
            }
		}
	}

	if ($tag ne 'ID3')
    {
        $this->set_error('rr',"no ID3v2 tag found") if (!$start);
        return 0;
    }
 
	# get version

	my ($major, $minor, $flags) = unpack ("x3CCC", $header);
	$v2h->{version} = sprintf("ID3v2.%d.%d", $major, $minor);
    $this->set_error('note',"$v2h->{version} tag found at $start in $this->{path}");

	if ($major < 2 || $major > 4)
    {
        $this->set_error('rs',"unsupported major version number $major");
        return 02;
    }
    if ($minor != 0)
    {
        $this->set_error('rt',"unsupported minor version number $major.$minor in $this->{path}");
        return 0;
    }
	$v2h->{major_version} = $major;
	$v2h->{minor_version} = $minor;


	# get flags

	my @bits = split(//, unpack('b8', pack('v', $flags)));
	if ($v2h->{major_version} == 2)
    {
        $v2h->{header_len}   = 6;
		$v2h->{unsync}       = $bits[7];
		$v2h->{compression}  = $bits[6]; # Should be ignored - no defined form
		$v2h->{ext_header}   = 0;
		$v2h->{experimental} = 0;
        $v2h->{header_len}   = 6;
	}
    else
    {
        $v2h->{header_len}   = 10;
		$v2h->{unsync}       = $bits[7];
		$v2h->{ext_header}   = $bits[6];
		$v2h->{experimental} = $bits[5];
		$v2h->{footer}       = $bits[4] if $v2h->{major_version} == 4;
	}

	# get ID3v2 tag length from bytes 7-10

	my $rawsize = substr($header, 6, 4);
	for my $b (unpack('C4', $rawsize))
    {
		$v2h->{tag_size} = ($v2h->{tag_size} << 7) + $b;
	}
	$v2h->{tag_size} += 10;	# include ID3v2 header size
	$v2h->{tag_size} += 10 if $v2h->{footer};

	# get extended header size (2.3/2.4 only)
	# This is improperly implemented for version 2.3, under
    # which it should by unsynchronized before unpacking, whereas
    # it need not be, by spec under 2.4, which has designed
    # out any possible false syncs.
    #
    # Even under 2.3, the size (6, or 10) and the flags
    # are syncsafe, however, the crc, if it exists, is
    # probably not, so this may fail if a program
    # has properly uncync'd the extended header AND it
    # contained a CRC with FF in any of it's four bytes.
    # We will read a false 0x00 here, and the rest of the
    # data will be 'pushed' back.
    #
    # This should either be broken out into a sub() and
    # called twice or implemented twice ...

	$v2h->{ext_header_size} = 0;
	if ($v2h->{ext_header})
    {
		my $filesize = -s $fh;
		read $fh, my $bytes, 4;
		my @bytes = reverse unpack 'C4', $bytes;

		# use syncsafe bytes if using version 2.4

		my $bytesize = ($v2h->{major_version} > 3) ? 128 : 256;
		for my $i (0..3)
        {
			$v2h->{ext_header_size} += $bytes[$i] * $bytesize ** $i;
		}

		# Bug 4486
		# Don't try to read past the end of the file if we have a
		# bogus extended header size.

		if (($v2h->{ext_header_size} - 10 ) > -s $fh)
        {
            $this->set_error('ru',"Bogus extended header size=$v2h->{ext_header_size}");
			return $v2h;
		}

		# Read the extended header
        # On ID3v2.3 the extended header size excludes the whole header
		# On ID3v2.4, the extended header size includes the whole header

		if ($v2h->{major_version} == 3)
        {
            my $byte_len = 6 + $v2h->{ext_header_size};
			if (read($fh, $bytes, $byte_len) != $byte_len)
            {
                $this->set_error('rv',"Could not read $byte_len bytes of ver3 extended header");
                return;
            }

			my @bits = split //, unpack 'b16', substr $bytes, 0, 2;
			$v2h->{crc_present} = $bits[15];
			my $padding_size;
			for my $i (0..3)
            {
				if (defined $bytes[2 + $i])
                {
					$padding_size += $bytes[2 + $i] * $bytesize ** $i;
				}
			}
			$v2h->{ext23_padding_size} = $padding_size;
                # this is the number of padding bytes
                # after all frames and headers within
                # the tag ... the freespace amount.
		}
		elsif ($v2h->{major_version} == 4)
        {
            my $byte_len = $v2h->{ext_header_size} - 4;
			if (read($fh, $bytes, $byte_len) != $byte_len)
            {
                $this->set_error('rw',"Could not read $byte_len bytes of ver4 extended header");
                return;
            }

			my @bits = split //, unpack 'b8', substr $bytes, 5, 1;
			$v2h->{update}           = $bits[6];
			$v2h->{crc_present}      = $bits[5];
			$v2h->{tag_restrictions} = $bits[4];

             $this->set_error('rx',"update bit found ... it may not be handled correctly")
                if ($v2h->{update});

            # according to v4 spec,
            # for each bit set, there is data following (within the bytes
            # already read, consisting of a length byte and a number of
            # bytes of data (update has a zero length byte, crc has a
            # length of 5, and tag restrictions has a length of 1)

		}
	}

    # debug and return

    for my $k (sort(keys(%$v2h)))
    {
        display($dbg_mp3_read+1,1,"v2h($k)=$$v2h{$k}");
    }
	return $v2h;

}   # _get_v2_head




sub _get_v2_foot
    # We assume that we have seeked to the expected EOF (ie start of the ID3v1 tag)
    # The 'offset' value will hold the start of the ID3v1 header (NOT the footer)
    # The 'tag_size' value will hold the entire tag size, including the footer.
	# Returns undef for hard errors, 0 for no footer, or a populated
	# v2f object.
{
	my ($this) = @_;
    display($dbg_mp3_read,0,"_get_v2_foot()");

    my $fh = $this->{fh};
    if (!$fh)
    {
        error("Implementation Error - _get_v2_foot() called with no file handle for $this->{path}");
        return;
    }

	# check first three bytes for 'ID3'

	my($v2h, $bytes, @bytes);
	my $eof = tell $fh;
	seek $fh, $eof-10, SEEK_SET; # back 10 bytes for footer
    if (read($fh, $bytes, 10) != 10)
    {
        $this->set_error('ry',$ERROR_HARD,"Could not read 10 bytes of footer from $this->{path}");
        return;
    }

	if (substr($bytes,0,3) ne '3DI')
	{
		# it's not an ID3v2 footer, but it's not
		# an error either.  Return 0.
		return 0;
	};

	# get version

	$v2h->{version} = sprintf "ID3v2.%d.%d",
		@$v2h{qw[major_version minor_version]} =
			unpack 'x3c2', $bytes;

	# get flags

	my @bits = split //, unpack 'x5b8', $bytes;
	if ($v2h->{major_version} != 4)
    {
		# This should never happen - only v4 tags should have footers.
		# Think about raising some warnings or something ?
		# print STDERR "Invalid ID3v2 footer version number\n";
		$this->set_error('rz',"Footer found in non v4 ID3 section");
		return 0;
	}
    else
    {
		$v2h->{unsync}       = $bits[7];
		$v2h->{ext_header}   = $bits[6];
		$v2h->{experimental} = $bits[5];
		$v2h->{footer}       = $bits[4];
		if (!$v2h->{footer})
		{
            # This is an invalid footer marker; it doesn't make sense
            # for the footer to not be marked as the tag having a footer
            # so strictly it's an invalid tag.
			
			$this->set_error('r1',"invalid footer marker in ID3 section");
			return 0;			
		}
	}

	# get ID3v2 tag length from bytes 7-10

	$v2h->{tag_size} = 10;  # include ID3v2 header size
	$v2h->{tag_size} += 10; # always account for the footer
	@bytes = reverse unpack 'x7C4', $bytes;
	foreach my $i (0 .. 3)
    {
		$v2h->{tag_size} += $bytes[$i] * 128 ** $i;
	}

	# Note that there are no extended header details on the footer; it's
	# just a copy of it so that clients can seek backward to find the
	# footer's start.

	$v2h->{offset} = $eof - $v2h->{tag_size};

	# Just to be really sure, read the start of the ID3v2.4 header here.

	seek $fh, $v2h->{offset}, 0; # SEEK_SET

    if (read($fh, $bytes, 3) != 3)
    {
        $this->set_error('r2',"Could not read three byte id3 footer recheck");
        return;
    }
	if ($bytes ne "ID3")
    {
        $this->set_error('r2',"invalid id3 footer");
        return 0;
	}

	# We could check more of the header. I'm not sure it's really worth it
	# right now but at some point in the future checking the details match
	# would be nice.

	return $v2h;

}   # _get_v2_foot




sub _find_id3_chunk
{
	my ($this, $filetype) = @_;
	my ($bytes, $size, $tag, $pat, @mat);

	# 10 bytes are read, not 3, so reading one here hoping to get
    # the last letter of the tag is a bad idea, as it always fails...

	if ($filetype eq 'RIF')             # WAV
    {
		$pat = 'a4V';
		@mat = ('id3 ', 'ID32');
	}
    elsif ($filetype eq 'FOR')          # AIFF
    {
		$pat = 'a4N';
		@mat = ('ID3 ', 'ID32');
	}

    # prh - not gonna error check this,
    # it either works or it doesn't

    my $fh = $this->{fh};
    if (!$fh)
    {
        error("Implementation Error - _find_id3_chunk() called with no file handle for $this->{path}");
        return;
    }

	seek $fh, 12, SEEK_SET;  # skip to the first chunk
	while ((read $fh, $bytes, 8) == 8)
    {
		($tag, $size)  = unpack $pat, $bytes;
		for my $mat ( @mat )
        {
			return 1 if $tag eq $mat;
		}
		seek $fh, $size, SEEK_CUR;
	}
	return 0;
}



1;
