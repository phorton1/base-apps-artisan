#----------------------------------------------------
# 2015-06-18 separating out mp3 writing
#----------------------------------------------------
# Contains the portions of the taglist that pertain
# to writing MP3 files to avoid loading them in
# memory for artisan.

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
    

sub set_tag_value
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



sub encode_tag
    # 2015-06-18 start commenting out write call chain
    # called directly by MP3InfoWrite
    # if there is no format, just return
    # the bytes, otherwise, really decode it

{
    my ($this,$tag) = @_;

    display($dbg_mp3_tags+1,0,"encode_tag($tag->{id},$tag->{value})");

    my $format = $this->_find_format($tag);
    if (!$format)
    {
        display($dbg_mp3_tags+2,1,"no format found for $tag->{id}");
        $tag->{value} = $tag->{value}->{bytes}
            if (ref($tag->{value}));
        return 1;
    }

    # do the opposite of _decode_tag
    # builds a backwards set of byte string

    my @bytes;
    my $delim = "\x00";
    my $id = $tag->{id};
    for my $action (reverse(@$format))
    {
        my ($data_len, $field, $mod) = (@$action);
        $mod ||= '';
        display($dbg_mp3_tags+2,1,"_encode($data_len,$field,$mod)");

        my $data = '';
        if ($field eq '_encoding')
        {
            $data = 0;
        }
        elsif ($field =~ /_subid/)
        {
            if ($id !~ s/\t(.*?)$//)
            {
                # if we were passed bad data, like a V1 comment, duh
                # just let it go into the output by returning 1 here ..
                
                $this->set_error('va',"no subid in $id");
                return 1;
            }

            $data = $1;
            display($dbg_mp3_tags+2,2,"pulled subid=$data NEW ID='$id'");
        }
        else
        {
            if (!ref($tag->{value}))
            {
                $data = $tag->{value};
                display($dbg_mp3_tags+2,2,"pulled scalar($field) len=".length($data)."=$data");
            }
            else
            {
                $data = $tag->{value}->{$field};
                display($dbg_mp3_tags+2,2,"pulled field($field) len=".length($data).($field eq 'data'?'':$data));
            }
        }


        # unapply apply any mods
        # note that we do not re-encode genres (TCON)
        # They stay as words in our version ..

        if ($mod eq 'byte')
        {
            $data = chr($data);
        }
        elsif ($mod eq 'byte_string')
        {
            my @bytes;
            my $len = 0;
            while ($len++<4 || $data)
            {
                push @bytes,$data & 0xff;
                $data >>= 8;
            }
            $data = join('',reverse(@bytes));
        }
        elsif ($mod eq 'encoded' || $mod =~ /_encoded/)
        {
            # we don't encode our strings
            # but we do escape them

            $data = unescape_tag($data);
       }

        # add the data element to bytes

        if ($data_len == -2)
        {
            # no data (subid_inc)
        }
        elsif ($data_len <= 0)
        {
            # zero terminated
            $data .= "\x00" if ($data_len == 0);
            push @bytes,$data;
            display(_clip $dbg_mp3_tags+2,2,"adding string($data_len,len=".length($data).")=$data");
        }
        else
        {
            if (length($data) != $data_len)
            {
                $this->set_error('vb',"encoding error: length($data) != $data_len");
                return;
            }
            display(_clip $dbg_mp3_tags+2,2,"adding $data_len bytes=$data");
            push @bytes,$data;
        }
    }

    $this->set_error('vc',"unexpected id length after decoding($id)")
        if (length($id) != 4);

    $tag->{id} = $id;
    $tag->{value} = join('',reverse(@bytes));

    # add a null terminator for TEXT frames

    $tag->{value} .= "\x00" if ($id =~ /^T/);
    display(_clip $dbg_mp3_tags+1,0,"encode returning len=".length($tag->{value})." value=$tag->{value}");
    return 1;

}


1;
