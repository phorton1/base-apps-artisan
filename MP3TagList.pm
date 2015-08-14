#----------------------------------------------------
# 2014-07-03 prh - derived from MP3::Info.pm
#----------------------------------------------------
# MP3TagList
#
# The taglist is an object, that has, amongst
# other things, the main ordered list of tags,
# where (internal detail) each element in the
# list is a hash containing *at least* a ID3v2.4
# 'id', a 'version', and a 'value' field.
#
#     my $tag = $tag_list->tag_by_id('TIT2')
#     return if !$tag;
#     display(0,0,"TITLE($tag->{id}) = $tag->{value}");
#
# version = 1,2,3, or 4 for the original version
#    of the tag.
#
# id = TIT2, TALB, TXXX_SUBID, etc
#
#    The ID3v2.N tag_id for the tag.
#    where N is given by $WRITE_VERSION.
#    Multiple instance tags, like (TXXX,
#    PRIV, and WXXX) will already be decoded
#    and will already have their have their
#    SUBID (also already decoded) set.
#
#    SUBID is used to create/enforce the spec
#    that certain tags may appear multiple times
#    but 'only if they differ by' things like
#    an identifer, owner_id, language, etc.
#
#    The SUBID(s) will be postpended to the v4 tag_id
#    delineated by tabs, after escaping any non-printing
#    characters in the tag.
#
# value = scalar or hash
#
#    The fields in the {value} are dependent on
#    the tag (see implementation for more info).
#    Certain tags have (like TXXX) will be decoded
#    all the way to scalars. Otherwise {value} is a hash.
#
#    Either way, the scalar, or the hash may contain
#    the raw {bytes} for the tag. We leave many tags
#    alone and just read and write their bytes.
#
#    If find yourself wanting information out of {bytes},
#    then you *really* should add a decode_format to the
#    taglist object and let the taglist decode/encode it.
#    particularly since changing the bytescan also change
#    the SUBID of a tag.
#
# TEXT
#
#    Some tags explicitly allow carriage returns
#    in their text, and we are unclear about other
#    white space (0x09 tab, 0x0a). The spec also,
#    generally, allows text fields to be multiple
#    items (delineated by 0x00).
#
#    By my convention, all characters not in the
#    range 0x20-0xff and \ itself in text fields
#    are escaped to\xNN.
#
#    This may result in un-pretty output, but allows
#    for orthogonal reconstruction of the raw bytes.
#    It is up to the client to properly escape the
#    tags (Utils::escape_tag()) when setting text
#    with \'s or non-printable characters.
#
#    Note that ALL subid's are text, and escaped.
#
#    You should never modify the $tag directly.
#    always call set_tag_value(), which will escape
#    strings as necessary.

package MP3TagList;
    # Essentially the decoder-encoder for
    # raw tag bytes, with some other stuff.
use strict;
use warnings;
use Utils;
use MP3Vars;
use MP3Encoding;

our %formats;
    # The encode/decode formats for the tags
    
#-----------------------------
# new() and utilities
#-----------------------------

sub new
{
    my ($class,$parent) = @_;
    my $this = {};
    bless $this,$class;

    $this->{parent} = $parent;
    $this->{next_index} = 0;
    $this->{tags} = {};
        # hash of indexes by decoded ID (which may include
        # a subid, ie TXXX_ARTISAN_UNIQUEID) into the tags
        # array.

    return $this;
}


sub set_error
{
    my ($this,$code,$msg) = @_;
    $this->{parent}->set_error($code,$msg);
}


sub _set_dirty
{
    my ($this) = @_;
    $this->{parent}->set_dirty();
}


sub tag_by_id
    # called by MP3Info->get_tag_value
{
    my ($this,$id) = @_;
    return  $this->{tags}->{$id};
}


sub get_tag_ids
    # return a list of the tag id's sorted
    # by the index member of the tags. Used to
    # get the tags in 'priority' order.
{
    my ($this) = @_;
    my $tags = $this->{tags};
    my @ids = keys (%$tags);
    @ids = sort { $tags->{$a}->{index} <=> $tags->{$b}->{index} } @ids;
    return @ids;
}



sub unused_set_tag_value
    # 2015-06-18 start commenting out write call chain
    # called by MP3Info->set_tag_value
    # sets dirty if the value changes
{
    my ($this,$id,$value) = @_;
    my $old_tag = $this->{tags}->{$id};

    # prh - validate params
    # remove the tag if it exists and no value

    if (!$value)
    {
        if ($old_tag)
        {
            display(_clip $dbg_mp3_tags,0,"set_tag_value(deleting $id) value=$old_tag->{value}");
            delete $this->{tags}->{$id};
            $this->_set_dirty();
        }
    }

    # at this time value is expected to be perfect
    # when passed in.  This works for text values,
    # and TXXX with well formed ids.
    # does NOT do hash member comparisons
    # so ONLY call this with complex objects
    # if they have indeed changed!

    else
    {
        my $old_value = $old_tag ? $old_tag->{value} : '';
        if ($value ne $old_value)
        {
            display(_clip $dbg_mp3_tags,0,"set_tag_value($id) new=$value old=$old_value");
            $this->_set_dirty();
            my $tag = { id=>$id, value=>$value, update=>1, version=>$WRITE_VERSION };
            return $this->_push_tag($tag);
        }
        else
        {
            display($dbg_mp3_tags+1,0,"set_tag_value($id) unchanged value=$value");
        }
        return 1;
    }
}



#--------------------------------------
# add_tag & tag version mapping 
#--------------------------------------

sub add_tag
    # high level api called directly from MP3InfoRead
    # returns one if the tag was set, 0 if not (empty)
    # or undef for an error (though we don't check
    # the return result at this time).
    #
    # all multiple instance v2 tags must be decoded
    # even if it's just far enough to get the
    # multiple instance id.
    #
    # an error is given, and add_tag returns 0, if
    # an attempt is made to subsequently set a v2 tag
    # over another one (unless per spec, the header's
    # update bit is set, which we do when artisan calls
    # set_tag_value programatically).
{
    my ($this,
        $v2h,               # the v2 header, undef for v1
        $id,                # the 3 or 4 character id of the tag
        $value ) = @_;      # the raw bytes from the

    my $version = $v2h ? $v2h->{major_version} : 1;
    display(_clip $dbg_mp3_tags,0,"add_tag($version,$id) len=".length($value)." bytes=$value");

    my $item = {
        id      => $id,
        version => $version,
        value   => { bytes => $value },
    };

    $item->{update} = 1 if $v2h && $v2h->{update} ? 1 : 0;

    # no multipart strings allowed in v1!

    if ($version == 1)
    {
        my $text = MP3Encoding::decode_text($this,-1,$value);
        $text =~ s/\x00+$/ /;
        $text =~ s/\s+$//;

        # check for change due to decoding

        $value =~ s/\x00+$//;
        $value =~ s/\s+$//;
        $this->_set_dirty() if ($value ne $text);

        # we don't set empty V1 tags ...
        # but we do set_dirty if they became empty
        # as a result of decoding

        if (!$text)
        {
            display($dbg_mp3_tags+1,1,"not setting empty V1 tag");
            return 0;
        }

        display($dbg_mp3_tags+1,1,"text=$text");
        $item->{value} = $text;
    }
    elsif (!defined($value))
    {
        $this->set_error('ta',"undefined value passed to _add_tag($item->{id})");
        return 0;
    }
    else
    {
        return if !$this->update_to_write_version($item);
            # value may have been dropped during conversion
        if (!defined($item->{value}))
        {
            $this->set_error('tb',"add_tag dropping item $item->{id}");
            return 1;
        }

        # decode it and continue

        my $format = $this->_find_format($item);
        return if $format && !$this->_decode_tag($item,$format);
    }

    return $this->_push_tag($item);
}




sub _flatten
    # flatten debug/error reporting value
{
    my ($init_value) = @_;
    if (ref($init_value))
    {
        my @keys = keys %$init_value;
        $init_value = $init_value->{$keys[0]} if (scalar(@keys) == 1);
    }
    return $init_value;
}


sub update_to_write_version
    # subids have not yet been added.
    # $item is the raw tag from MP3InfoRead
    # we need to update/downdate it to $WRITE_VERSION
    # as needed.
{
    my ($this,$item) = @_;
    my $init_id = $item->{id};
    my $init_version = $item->{version};
    my $init_value = _flatten($item->{value}) || '';
    my $v2_name = $all_v2_tag_names{$init_id};

    # 2014-07-10 all MP3 tags are now known to me
    # These errors were carefully analyzed for my initial pass.
    # Any new errors found means the code needs to change to handle
    # the tag mapping, or the file will be skipped (return 0).
    # Otherwise, report any errors, do not add the tag, and stop processing

    if (!$v2_name)
    {
        $this->set_error('tc',"Unknown tag($init_id) value='$init_value'");
        return 0;
    }
    elsif ($init_version > 1)
    {
        if (length($init_id) == 3  && $init_version != 2)
        {
            $this->set_error($ERROR_MEDIUM,"v2 tag($init_id) found in v3+ file in $this->{parent}->{path} value='$init_value'");
            $init_version = $item->{version} = 2;
            # return 1;
        }

        # 2014-07-10 i haven't had any of these mismatched tags

        elsif (length($init_id) == 4)
        {
            # a v3/4 tag was found in a v2 file
            
            if ($init_version == 2)
            {
                $this->set_error('td',"v3+ tag($init_id) found in v2 file - value='$init_value'");
                return 0;
            }
            
            # a v2 version specific tag was found that does not
            # match the version of the tags it was found in ...
            
            elsif ($v2_name =~ /^v(\d) / && $1 != $init_version)
            {
                $this->set_error('te',"V$1 specific frame($init_id) found in V$init_version file - value='$init_value'");
                return 0;
            }
        }
    }

    # ok, so at this point we are reasonably sure
    # it is a mappable tag.
    # map tags to ID3v2.$WRITE_VERSION

    if ($WRITE_VERSION == 4 && $init_version == 3)
    {
        return 0 if !$this->v3_to_v4_tag($item);
        return 1 if (!defined($item->{value}));
            # v3 tag dropped
    }
    elsif ($init_version == 2)
    {
        return 0 if !$this->v2_to_v3_tag($item);
        return 1 if (!defined($item->{value}));
            # v2 tag dropped
            
        if ($WRITE_VERSION == 4)
        {
            return 0 if !$this->v3_to_v4_tag($item);
            return 1 if (!defined($item->{value}));
                # v3 tag dropped
        }
    }
    elsif ($WRITE_VERSION != 4 && $init_version == 4)
    {
        # $WRITE_VERSION must == 3
        # it's ok, we'll just change the version, if it's
        # not an 2.4 specific tag
        
        my $v3_name = $v23_tag_names{$init_id};
        if ($v3_name)
        {
            $this->set_error('note',"changing v4 tag($init_id) directly to v3($v3_name) tag");
            $item->{version} = $WRITE_VERSION;
        }
        elsif ($init_id eq 'TDRC')
        {
            $item->{id} = 'TYER';
            $item->{value} = $1 if ($init_value =~ /^(\d+)/);
            $this->set_error('note',"mapping vr TDRC($init_value) directly to v3 TYER($item->{value}");
        }
        else
        {
            # yikes ... need to downdate version 4 tags !?!
            error("Dropping V4 tag($v2_name) while writing V3 file value=$init_value in $this->{parent}->{path}");
            $this->set_error('tf',"Dropping V4 tag($v2_name)='$init_value' while writing V3 file");           
            $item->{value} = undef;
            return 1;
        }
    }

    # else $init_version == 4

    return 1;
}


sub v2_to_v3_tag
{
    my ($this,$item) = @_;
    my $init_id = $item->{id};
    my $v2_name = $v22_tag_names{$init_id};

    if (!defined($v2_name))
    {
        $this->set_error('tg',"unknown tag in v2_to_v3_tag($init_id)");
        return 0;
    }

    my $new_id = $v22_to_v23_id{$init_id};
    if (!defined($new_id))
    {
        my $init_value = _flatten($item->{value});
        $this->set_error('th',"no mapping in v2_to_v3_tag($init_id) value=$init_value");
        return 0;
    }
    if (!$new_id)
    {
        my $init_value = _flatten($item->{value});
        $this->set_error('ti',"dropping v2 tag($init_id) value=$init_value");
        $item->{value} = undef;
        return 1;
    }

    display($dbg_mp3_tags+1,0,"mapping v2($init_id) to $new_id");
    $item->{id} = $new_id;
    $item->{version} = 3;
    return 1;
}


sub v3_to_v4_tag
    # we know item has to be mapped, item
    # is definitely a v3 tag whose v2_tag_name
    # has a leading "v3 " in it.
    #
    # 2014-07-10 - the only deprecated v3 tag I found in
    # my files was TYER which maps to TDRC, 'Recording time'.
    # Otherwise, add them one at a time or develop a scheme.

{
    my ($this,$item) = @_;
    my $init_id = $item->{id};
    my $v2_name = $v23_tag_names{$init_id};

    # make sure it's a known v3 tag

    if (!$v2_name)
    {
        $this->set_error('tj',"unknown tag in v3_to_v4_tag($init_id)");
        return 0;
    }
    if ($v2_name !~ /^v(\d) /)
    {
        $item->{version} = 4;
        return 1;
    }
    if ($1 != 3)
    {
        $this->set_error('tk',"v3_to_v4_tag($init_id) called on version $1 tag!");
        return 0;
    }

    # prh 2014-07-10
    #
    # A mess. V3 fields TYER, TDAT, TIME, and multi_string TRDA
    # all map to V4 TRDC 'Recording time'.
    #
    # Thus we have to build the TDRC a piece at a time as
    # we find it. For now, I am going to warn and just
    # drop everything except for TYER

    # prh - change this to an error 0 or implement it correctly
    # after initial pass

    if ($init_id =~ /^(TDAT|TIME|TRDA)/)
    {
        my $use_value = _flatten($item->{value});
        $use_value =~ s/\x00//g;
        $use_value =~ s/\s+$//;
        $use_value =~ s/^\s+//;
        $this->set_error('tl',"dropping v3($init_id)->v4(TRDC) mapping value='$use_value'");
        $item->{value} = undef;
        return 1;
    }

    # otherwise, the only supported v3->v4 mapping is
    # TYER->TDRC

    if ($init_id eq 'TYER')
    {
        display($dbg_mp3_tags+1,0,"mapping v3(TYER) to TDRC");
        $item->{id} = 'TDRC';
        $item->{version} = 4;
        return 1;
    }

    my $init_value = _flatten($item->{value});
    $this->set_error('tm',"v3_to_v4_tag($init_id,$v2_name) can't map tag value='$init_value'");
    $item->{value} = undef;
    return 1;
}



#--------------------------------------
# _push_tag
#--------------------------------------

sub _push_tag
    # push a new, or overwrite an existing tag.
    # The tag shall be a V1 tag that has been
    # mapped to non-deprecated v2.3 (version 3
    # OR 4), or a tag that has been correctly
    # mapped to $WRITE_VERSION.  In otherwords,
    # it's ready to go.
    #
    # v2 text tags with content are allowed to overwrite
    # v1 tags, but give a level 0 warning if the v1 text
    # is not a proper substring of the v2 text.
{
    my ($this,$item) = @_;

    # collapse items with single field

    my $value = $item->{value};
    if (ref($value))
    {
        my @keys = keys %$value;
        if (scalar(@keys) == 1) # && $keys[0] eq 'text')
        {
            $value = $value->{$keys[0]};
            $item->{value} = $value;
        }
    }

    # only deal with known tags of the correct version

    my $version = $item->{version};
    my $clean_id = $item->{id};
    $clean_id =~ s/\t.*$//;
        # remove any subid
        
        
    my $v2_name = $WRITE_VERSION == 3 ?
        $v23_tag_names{$clean_id} :
        $v24_tag_names{$clean_id} ;

    if (!$v2_name)
    {
        $this->set_error('tn',"Unknown tag($clean_id) for version($WRITE_VERSION)".
                " tag version=$version value='".substr($value,0,60).(length($value)>60?'...':'')."'");
        return 0;
    }
    if ($version != $WRITE_VERSION && $version != 1)
    {
        $this->set_error('to',"Bad version($version) for tag($clean_id,$v2_name) value='$value'");
        return 0;
    }

    # give warning if v1 tag being overwritten is
    # not proper substring of same v2 tag ...

    my $exists = $this->{tags}->{$item->{id}};
    if ($exists && $exists->{version} == 1)
    {
        if (index($value,$exists->{value}) == -1)
        {
            $this->set_error('tp',"overwriting v1($item->{id}) with '$value'  old='$exists->{value}'");
            display($dbg_mp3_tags+1,0,"old='$exists->{value}'");
        }
    }

    # give warning if v2 tag being updated to different value
    # weird if hashes, etc ... but, so, for now will give the
    # warning on ANY updates of non-text fields.

    elsif ($exists && $item->{update})
    {
        # overwriting existing value
        # give a warning if it changed

        $this->set_error('note',"updating v2 tag with different value: old=$exists->{value} new=$value")
            if ($value ne $exists->{value});
    }
    elsif ($exists)
    {
        # error attempt to set multiple unique_ids
        # in the same MP3 file without update bit
        # return 1 to let it slide
        
        $this->set_error('tq',"attempt to set same tag($item->{id}) to more than one value. old=$exists->{value}  new=$value");
        return 1;
    }

    # overwrite the existing one or create a new index

    my $use_id = $item->{id};
    $use_id = "TXXX\tARTISAN_UPDATE" if $use_id =~ /TXXX\tARTISAN_UPDATE/;
    bump_stat($use_id);

    if ($exists)
    {
        display($dbg_mp3_tags+1,0,"_push_tag(overwriting($item->{id})) = $value");
        $item->{index} = $exists->{index};
        $this->{tags}->{$item->{id}} = $item;
    }
    else
    {
        $item->{index} = $this->{next_index}++;
        display($dbg_mp3_tags+1,0,"_push_tag($item->{index},$item->{id}) = $value");
        $this->{tags}->{$item->{id}} = $item;
    }

    return 1;
}



#-----------------------------------------------
# decode/encode
#-----------------------------------------------

sub _find_format
{
    my ($this,$item) = @_;
    my $use_id = substr($item->{id},0,4);
    my $format = $formats{$use_id};
    if (!$format && $use_id =~ /^(T|W)/)
    {
        $use_id = $1;
        $format = $formats{$use_id};
    }
    return $format;
}



sub _decode_tag
    # format has already been checked for non-null
    # set dirty if text decoding changes anything
{
    my ($this,$item,$format) = @_;
    my $value = $item->{value};
    my $bytes = $value->{bytes};
    delete $value->{bytes};
        # value is now an empty hash, owned by item
    display(_clip $dbg_mp3_tags+1,0,"_decode_tag($item->{id}) bytes=$bytes");

    # actions consist of three parts
    # data_len tells how much to chew off of bytes
    # field is either a special underscore field
    #    _encoding or _subid, used by the loop, or a
    #    field  that will get added to the value hash
    # mod is a (comma delimited?) list of things to do
    #    in between

    my $encoding = 0;
    my $delim = "\x00";
    for my $action (@$format)
    {
        my ($data_len, $field, $mod) = (@$action);
        $mod ||= '';
        display(_clip $dbg_mp3_tags+2,1,"_decode($data_len,$field,$mod) bytes=$bytes");

        # get the data ..

        my $data = '';
        if ($data_len == -2)        # no data (subid_inc)
        {
        }
        elsif ($data_len == -1)     # to end
        {
            $data = $bytes;
            $bytes = '';
        }
        elsif ($data_len == 0)      # to delim
        {
            my $pos = index($bytes,$delim);
            if ($pos == -1)
            {
                $data = $bytes;
                $bytes = '';
            }
            else
            {
                $data = substr($bytes,0,$pos);
                $bytes = substr($bytes,$pos+length($delim));
            }
        }
        else  # certain length
        {
            $data = substr($bytes,0,$data_len);
            $bytes = substr($bytes,$data_len);
        }
        $data = '' if !defined($data);

        # apply any mods

        if ($mod eq 'byte')
        {
            $data = ord($data);
        }
        elsif ($mod eq 'byte_string')
        {
            my $value = 0;
            while (length($data))
            {
                $value = $value << 8 + ord(substr($data,0,1));
                $data = substr($data,1);
            }
            $data = $value;
        }
        elsif ($mod eq 'encoded' || $mod =~ /_encoded/)
        {
            my $new_data = MP3Encoding::decode_text($this,$encoding,$data);
            $new_data =~ s/\x00+$//;
            $new_data =~ s/\s+$//;

            # remove any extra null terminators found after decoding
            # do same with pre-decoded data for compare

            $data =~ s/\x00+$//;
            $data =~ s/\s+$//;
            if ($new_data ne $data)
            {
                $this->_set_dirty();
                $this->set_error('tr',"setting dirty due to decode($encoding,$item->{id},$field) new='$new_data' old='$data'");
            }
            $data = $new_data if ($new_data);
        }

        if ($mod =~ /^genre/)
        {
            my $save_data = $data;
            
            # do all the stuff to substitute words for numeric
            # genres.  We will write the words back!
            # change text genres that had escaped parens into ##<>## symbols
            
            $data =~ s/\(\((.*?)\)\)/##<$1>##/g;
            $data =~ s/\(RX\)/ Remix /g;
            $data =~ s/\(CR\)/ Cover /g;

            # change paranthesized genre numbers to strings
            
            while ($data =~ s/\((\d+)\)/ ###HERE### /)
            {
                my $num = $1;
                my $genre = $mp3_genres[$1] || 'undefined';
                $data =~ s/###HERE###/$genre/;
            }

            # change parens back

            $data =~ s/##</\(/g;
            $data =~ s/>##/\)/g;

            # get rid of doubled and leading/trailing spaces
            
            $data =~ s/^\s+//;
            $data =~ s/\s+$//;
            while ($data =~ s/\s\s/ /) {};
            
            # for now, bail with an error if there's still a number!
            
            if ($data ne $save_data)
            {
                $this->set_error('note',"genre[$save_data] mapped to '$data'");
            }
            if ($data =~ /\d/)
            {
                $this->set_error('ts',"there's still a number in genre");
            }
               
        }
        
        # there is still a question about whether
        # strings may slip thru here with null terminators,
        # and/or we might want to cleanup trailing and/or leading whitespace
        # so we *may* want to differentiate -1 'get data till end' from
        # -3 get string till end in the getting of the data above.

        if ($field eq '_encoding')
        {
            $encoding = $data;
            $delim = "\x00\x00" if ($encoding);
            display($dbg_mp3_tags+2,2,"encoding=$encoding");
        }
        elsif ($field eq '_subid')
        {
            my $subid = escape_tag($data);
            $item->{id} .= "\t$subid";
            display($dbg_mp3_tags+2,2,"subid=$subid  NEW ID='$item->{id}'");
        }
        elsif ($field eq '_subid_inc')
        {
            my $subid = '000';
            my $try_id = $item->{id}."\t".$subid;
            while ($this->{tags}->{$try_id})
            {
                $subid++;
                $try_id = $item->{id}."\t".$subid;
            }
            display($dbg_mp3_tags+2,2,"subid_inc  NEW ID='$item->{id}'");
            $item->{id} = $try_id;

        }
        elsif ($field)
        {
            display(_clip $dbg_mp3_tags+2,2,"value($field) len(".length($data).") = $data");
            $value->{$field} = $data;
        }
    }

    return 1;
}



#---------------------------------------------------
# encoding table
#---------------------------------------------------
# 2.4 tags, at least all the multi-instance ones
#
# it was ok when the subid's appeared to be well
# understood but when you get into cases where the
# whole tag, or known multi_strings are the sub_id,
# even urls, it becomes unwieldy to look at, or
# to access them by ID .. as well, the records lose
# their detail.
#
# Thus some items have subid_inc, which creates
# an incremented id (i.e. WCOM001) to manage
# them in the list, and it becomes set_tag's
# responsibility to ensure appropropriate uniquness
# for these.
#
# The file is assumed to be correct with uniqueness
# to begin with, although subid_inc could be implemented
# to check that as well.

my $enc        = [  1, '_encoding',         'byte' ];
my $subid      = [  0, '_subid' ];
my $subid_enc  = [  0, '_subid',            'encoded' ];
my $subid_byte = [  1, '_subid',            'byte' ],
my $subid_lang = [  3, '_subid' ],
my $subid_inc  = [ -2, '_subid_inc' ],
my $subid_all  = [ -1, '_subid' ],
my $data       = [ -1, 'data' ];

my $text       = [ -1, 'text' ];
my $text_enc   = [ -1, 'text',              'encoded' ];
my $url        = [ 0, 'text' ];
my $genre_enc  = [ -1, 'text',              'genre_encoded' ];
                  

my $descrip    = [  0, 'descrip',           'encoded' ];
my $mime_type  = [  0, 'mime_type' ];
# my $pic_type   = [  1, 'pic_type',          'byte' ];
my $lang       = [  3, 'language' ];
my $ts_format  = [  1, 'timestamp_format',  'byte' ];
my $cont_type  = [  1, 'content_type',      'byte' ];
my $eq_method  = [  1, 'eq_method',         'byte' ];
my $filename   = [  0, 'filename',          'encoded' ];
my $rating     = [  1, 'rating',            'byte' ];
my $counter    = [ -1, 'counter',           'byte_string' ];
my $frame_id   = [  4, 'frame_id' ];
my $group_sym  = [  1, 'group_sym' ];
my $method_sym = [  1, 'method_sym' ];



# unused


# TLEN is DURATION in milliseconds!
# TCON (genre) has a multi string with text_numbers or actual genres.
# in order of 2.4 spec

%formats = (
    'UFID'  => [ $subid, $data ],
    'T'     => [ $enc, $text_enc ],
    'TCON'  => [ $enc, $genre_enc ],
    'TXXX'  => [ $enc, $subid_enc, $text_enc ],
    'W'     => [ $subid_all ], # $url ],
    'WXXX'  => [ $subid_all ],


    # just for me

    WCOP => [ $text_enc ],  # 2015-06-19 
    TENC => [ $text_enc ],  # 2015-06-19 $subid_all ],
    TIT1 => [ $subid_all ],

    'USLT'  => [ $subid_inc, $enc, $lang, $descrip, $text_enc ],
        # subid is language and content descriptor
    'SYLT'  => [ $subid_inc, $enc, $lang, $ts_format, $cont_type, $descrip, $data ],
        # subid is language, content_descriptor
        # not fully decoded
    'COMM'  => [ $enc, $subid_lang, $subid, $text_enc ],
        # subid is language:short description
    'RVA2'  => [ $subid, $data ],
        # not fully decoded
    'EQU2'  => [ $eq_method, $subid, $data ],
        # not fully decoded
    'APIC'  => [ $enc, $mime_type, $subid_byte, $descrip, $data],
        # subid is the picture_type (byte)
    'GEOB'  => [ $enc, $mime_type, $filename, $subid_enc, $data ],
        # the subid is the content description
    'POPM'  => [ $subid, $rating, $counter ],
        # the subid is the email address
    'AENC'  => [ $subid, $data ],
        # the subid is the owner identifer
        # not fully decoded
        # "If a $00 is found directly after the 'Frame size' and the audio
        # file indeed is encrypted, the whole file may be considered useless"
    'LINK'  => [ $subid_inc, $frame_id, $url, $text ],
        # the subid is the whole object
    'USER'  => [ $enc, $subid_lang, $text_enc ],
        # the subid is the language
    'COMR'  => [ $subid_inc, $data ],
        # the subid is the whole object
        # not fully decoded
    'ENCR'  => [ $subid_inc, $url, $method_sym, $data ],
        # the subid is the whole object
    'GRID'  => [ $subid_inc, $url, $group_sym, $data ],
        # the subid is an OR!!
        # 'but only one containing the same owner identifer AND
        # on containing the same method symbol'!! sheesh .
    'PRIV'  => [ $subid, $data ],
        # the subid is the owner identifier
    'SIGN'  => [ $subid_inc, $group_sym, $data ],
        # the subid is the whole object
        
    # supported v2 tags

    'COM'  => [ $enc, $subid_lang, $subid, $text_enc ],
        # subid is language:short description


);




1;
