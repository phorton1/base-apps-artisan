#----------------------------------------------------
# 2014-07-03 prh - derived from MP3::Info.pm
#----------------------------------------------------
package MP3Encoding;
use strict;
use warnings;
use Utils;
use Encode;
use Encode::Guess;

my $dbg_encode = 2;


#--------------------------------------------
# client api
#--------------------------------------------


sub decode_text
{
    my ($parent,$encoding,$text) = @_;
    return '' if (!defined($text) || !length($text));
    # display_bytes(0,0,"decode_text($text)",$text);
    
    if ($encoding > 0 || (
        $encoding < 0 && $text =~ /[^\x0d\x0a\x00\x20-\xff]/ ))
    {
        display(_clip $dbg_encode,0,"decode_text($encoding,$text)");

        my $val = '';
        if ($encoding == 1)
        {
            $val = eval { Encode::decode('UTF-16', $text) } ||
                Encode::decode('UTF-16BE', $text);
        }
        elsif ($encoding == 2)
        {
            $val = Encode::decode('UTF-16BE', $text);
        }
        elsif ($encoding == 3)
        {
             $val = Encode::decode('UTF-8', $text);
        }

        # any other encoding (v1 -1) and non-printable
        # characters, try to guess it

        else
        {
            my $icode;
            my $eater = $text;
            while (!ref($icode) && length($val))
            {
                $icode = Encode::Guess->guess($eater);
                last if ref($icode);
                $eater =~ s/(.)$//;
            }

            # note that value is invalid here
            # call the decoder with the $icode,
            # trim any trailing nulls

            if (ref($icode))
            {
                $val = Encode::decode($icode->name,$text);
            }
        }

        if (length($val))
        {
            if ($val =~ /[^\x0d\x0a\x00\x20-\xff]/)
            {
                $parent->set_error('pa',"decoded result($val) still has non printable characters");
            }
            else
            {
                display(_clip $dbg_encode,1,"decoded_text=$val");
                $text = $val;  # Encode::encode('iso-8859-1',$val);
                $text =~ s/\x00+$//;
            }
        }
    }

    if ($text =~ /[^\x0d\x0a\x00\x20-\xff]/)
    {
        # prh - change this to level 0 warning after initial pass thru my mp3 files
        $parent->set_error('pb',"replacing non-printable chars in $text with .'s");
        #display_bytes($dbg_encode,1,"text",$text);
        $text =~ s/[^\x0d\x0a\x00\x20-\xff]/./g;
    }

    return $text;
}


1;
