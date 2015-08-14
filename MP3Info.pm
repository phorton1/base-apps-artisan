#---------------------------------------------------------
# MP3Info - my do-all shell for MP3 files.
#---------------------------------------------------------
#
# All tags are decoded and updated to ID3v2.4
# The object may be dirty as a result of new().
#
# BASICS:
#
#     my $mp3 = MP3Info->new(readonly);             # benign constructor
#     return if (!$mp3);                            # errors reported
#       # readonly param is optional,
#       # otherwise file opened r/w
#       # opens the file, reads the tags
#
#     my $title = $mp3->get_tag_value('TIT2');
#       # title will be undef if the tag passed
#       # in is not a ID3v2.4 tag id in our format.
#       # otherwise, is failsafe for known 2.4 ids,
#       # and will return '' if there is no tag
#     return if !$mp3->set_tag_value('TIT2','duh'); # errrors reported
#       # access the title tag
#       # setting a tag value to '' will remove it
#       # is failsafe for known tag ids
#
#     return if !$mp3->close(abort_changes)       # errors reported
#        # close the mp3
#        # don't write it if abort_changes
#        # gives a level 0 warning if the tags
#        #    are dirty and abort_changes
#        # and should have been written.
#        # Called automatically with abort_only
#        #    on destruction.
#
#     my $tag_ids = $mp3->get_tag_ids()
#        # return a list of the existing
#        # tag_ids in the object.  This
#        # allows for filtering the tags, by
#        # then calling set_tag_value('')
#
#     for my $id (@$tag_ids)
#     {
#        $mp3->set_tag_value($id,'') if ($id =~ /^PRIV/);
#     }
#
# TAG VALUES $tag->{value}
#
#   artisan works entirely with ID3v2.4 (v4) tags.  As such
#   when it encounters (releatively infrequent) v2.2 (v2) tags,
#   or (very common) v2.3 (v3) tags, it must update them to
#   the new standard (yech).
#
#   Many tags are decoded to useful values, particularly
#   those that decode to flat text, like TXXX tags.
#   get_tag_value() will return a hash for many tags.
#   this hash may be decoded to a meaningful state,
#   or not, depending on how much I've implemented.
#   The content of a tag depend on the particular tag_id.
#
#   All tags contain an {id} and a {value} field.
#
#   The {value} may contain a {bytes} field if the
#   the tag has not been decoded, which contains the
#   raw data to re-write to the file, to preserve tags.
#   Or the {value} field may be a scalar (like for
#   TXXX fields), or it may have other members,
#   depending on the the particular tag id.
#
#   In general, I only decoded enough of the tags
#   to (a) support the functionality I want,
#   (b) to allow for correct reading and writing
#   of the tags, including (c) updating from
#   v2.2 and/or v2.3 to v.24.
#
#   This includes decoding at least enough
#   of any and all multiple id tags to get their
#   subids, resulting in MY FORMAT for TAG IDs,
#   which itself encodes information.
#
#   It is a relatively simple, though time consuming,
#   task to further decode tags.  See the taglist
#   object for more details on how to implement
#   decoding/encoding of tags you may require.
#
# AUTOMATIC TAG UPDATING (and warnings/errors)
#
#   updating v3 to v4 will try to follow the spec and map
#   any changes in tag structure and eliminate any illegal
#   tags as a result of the version change.
#
#   all this happens in the call to open_mp3(). Which means
#   that the file structure could change on a simple read.
#   There is a bit on the object, $mp3->{dirty} that gets
#   set if such a mapping occurs (or if the user changes
#   a value with set_tag_value. There is a level 0 warning
#   if the $mp3->close(abort_changes) is called with
#   abort_changes==1, and the object is dirty.
#
#   Which brings up the whole issue about warnings versus
#   errors when dealing with MP3 files in the wild. Hard
#   errors, like the inability to open or read a file are
#   always reported, and *should* mostly, always result
#   in the object failing.  Cases where this is allowed
#   like the absence of an ID section are coded appropriatly.
#
#   But while parsing frames, at some point, we have to
#   lighten up, and accept what data we can, and give warnings
#   when we cannot deal with it.
#
#   warnings
#     -2 = haven't seen it yet, but will let it slip for now
#          the warning will be reported
#     -1 = have decided to report it at all time, outdented
#      0 = have decided to report it at all times, indented
#      1 = things I am accepting, though I know they're wrong
#      2 = things I am accepting, that were brain dead to begin with


package MP3Info;
use strict;
use warnings;
use Fcntl qw(:seek);
use Utils;
use MP3InfoRead;
use MP3TagList;
# 2015-06-18 Comment these in for writing
# use y_MP3InfoWrite;
# use y_MP$TagListWrite;



sub new
	# Returns 0 for lack of information, or
	# undef if there was a hard error.
{
    my ($class,$path,$readonly,$parent) = @_;
    $readonly ||= 0;
    display($dbg_mp3_info,0,"MP3Info::new($readonly,$path)");

    my $this = {};
    bless $this,$class;

    $this->{path} = $path;
    $this->{readonly} = $readonly;
	$this->{parent} = $parent;
    $this->{fh} = undef;
    $this->{hasV1} = 0;
    $this->{v2h} = undef;
    $this->{v2f} = undef;
    $this->{taglist} = MP3TagList->new($this);
    $this->{dirty} = 0;
	
    # get the timestamp of the file, in case
    # we save it with preserve_timestamp
    
	my @fileinfo = stat($path);
    $this->{fileinfo} = [(@fileinfo)];
	display($dbg_mp3_info+1,1,"new() - open mp3 file");
    
	my $mode = $readonly ? '<' : '+<';
    if (!open($this->{fh},$mode,$path))
    {
        error("Could not open $path in $mode mode");
        delete $this->{fh};
        return;
    }

    binmode $this->{fh};

    display($dbg_mp3_info+1,1,"new() - get tags");

	# get_v12_tags() ONLY return false if there
	# was a hard error.  Otherwise, client can
	# check hasV1, v2H, or access the TagList to
	# see if there was any information.
	
    if (!$this->_get_v1_tags() ||
        !$this->_get_v2_tags())
    {
        close($this->{fh});
        delete $this->{fh};
		error("some kind of a hard error in _get_v12_tag calls");
        return;    # a hard error was encountered
    }

    $this->dump_tags("MP3Info::new() returning ($this)");
    return $this;
}


sub DESTROY
{
    my ($this) = @_;
    $this->close(1);
}


sub close
{
    my ($this,$abort_changes,$preserve_timestamp) = @_;
    $abort_changes ||= 0;
    $preserve_timestamp ||= 0;

	# 2015-06-18 safety check to make sure we never call
	# with !abort_changes and dirty

	if (!$abort_changes)
	{
		close($this->{fh});
		delete $this->{fh};
		error("Implementation Error - MP3Info::close(!abort_changes not supoorted)");
		return 0;
	}
	
    my $rslt = 1;
    if ($this->{fh})
    {
		my $written = 0;
        display($dbg_mp3_info+1,0,"close(abort=$abort_changes,dirty=$this->{dirty},preserve=$preserve_timestamp,$this->{path})");
        if ($this->{dirty} && !$abort_changes)
        {
			$written = 1;
            $rslt = $this->_write_tags();
        }
        elsif ($this->{dirty})
        {
            $this->set_error('ia',"MP3Info::close(abort_changes & DIRTY)");
        }

        close($this->{fh});
        delete $this->{fh};

		# reset the timestamp if asked to
		# 8==access time, 9==modified time

		if ($rslt && $written and $preserve_timestamp)
		{
			my $fileinfo = $this->{fileinfo};
			my $atime = $$fileinfo[8];
			my $mtime = $$fileinfo[9];
			
			display($dbg_mp3_info,0,"setting timestamp to $atime & $mtime");
			if (!utime $atime,$mtime,$this->{path})
			{
				$this->set_error($ERROR_HARD,"Could not set timestamp on $this->{path}!");
				$rslt = 0;
			}
			
			# set the timestamp back on the file
		}
    }
    return $rslt;
}



sub set_dirty
{
    my ($this) = @_;
    display($dbg_mp3_info,0,"MP3Info::set_dirty()");
    $this->{dirty} = 1;
}



sub get_tag_value
{
    my ($this,$id) = @_;
    my $taglist = $this->{taglist};
    my $tag = $taglist->tag_by_id($id);
    my $value = $tag ? $tag->{value} : '';
    display($dbg_mp3_info+1,0,"get_tag_value($id) = $value");
    return $value;
}



sub get_tag_ids
{
    my ($this) = @_;
    my $taglist = $this->{taglist};
    my @ids = $taglist->get_tag_ids();
    return @ids;
}




sub set_error
{
	my ($this,$severity,$msg) = @_;
	if ($this->{parent})
	{
		$this->{parent}->set_error($severity,$msg,1);
	}
	elsif ($severity >= $ERROR_HIGH)
    {
        error(_clip $msg,1);
    }
    else
    {
        my $warning_level = $ERROR_MEDIUM - $severity + 1;
        warning(_clip $warning_level,0,$msg,1);
    }
}



sub dump_tags
{
    my ($this,$msg) = @_;
    display($dbg_mp3_info+1,0,$msg);
    my $taglist = $this->{taglist};
    my @tag_ids = $taglist->get_tag_ids();
    for my $tag_id (@tag_ids)
    {
        my $tag = $taglist->tag_by_id($tag_id);
        display($dbg_mp3_info+1,1,"tag($tag->{index},$tag->{id})='$tag->{value}'");
    }
}



1;
