#--------------------------------------
# myMPG123.pm
#--------------------------------------
# Copied and modified from https://metacpan.org/pod/Audio::Play::MPG123.pm
# Also see the manpage for mpg123 executable at https://linux.die.net/man/1/mpg123
#
# Credit and respect to Marc Lehmann <schmorp@schmorp.de>..
#
# The mpg123 execuatable supports a number of commands that I would like to
# use that were not available in the module as published on CPAN.
# Denormalizing it also makes my installation process easier and
# gives me an opportunity to add commaents, etc, in my own style.
#
# Basically it works by opening a process for the mpg123 executable
# using the -R command line parameter, capturing its STDOUT and
# allowing commands to be sent to it via it's STDIN. I will not
# pretend to understand how this Perl code works. My rework will
# be somewhat different, more clunky, but understandable to me
#
# (1) start by changing squiggle styles, adding comments, and
# 	  regrouping all of the "commands" into one part of the source.
# (2) add full use strict and use warnings & get no errors in Komodo
#     - remove Exporter stuff ... it doesn't export anything.
#     - add 'my' to $MPG123
#     - add "no warnings 'once';" to start_mpg123()
# (3) don't get (or like too much) the use of custom
#     symbols.  Changing them to hash members.
#
# CLOSE BUT NO CIGAR mpg123 does NOT support seeking (backwards)
# on http streams.
#


package myMPG123;
use strict;
use warnings;
use Fcntl;
use IPC::Open3;
use Cwd;
use File::Spec;
use Errno qw(EAGAIN EINTR);
use artisanUtils;


my $dbg123 = 0;


my $MPG123 = "mpg123";


#---------------------------------------------
# ctor, start, and stop the module
#---------------------------------------------

sub new
{
	my $class = shift;
	my $this = bless {}, $class;
	$this->start_mpg123();
	return $this;
}


sub start_mpg123
{
	my $this = shift;
	display($dbg123,0,"start_mpg123()");

	local *DEVNULL;
	open DEVNULL, ">/dev/null" or die "/dev/null: $!";
	no warnings 'once';
	$this->{r} = local *MPG123_READER;
	$this->{w} = local *MPG123_WRITER;
	$this->{pid} = open3($this->{w},$this->{r},">&DEVNULL",$MPG123,'-R','--aggressive',@_,'');
	if (!$this->{pid})
	{
		error("Unable to start $MPG123");
		return;
	}
	fcntl $this->{r}, F_SETFL, O_NONBLOCK;
	fcntl $this->{r}, F_SETFD, FD_CLOEXEC;
	if (!$this->parse(qr/^\@?R (\S+)/,1))
	{
		error("Unable to start MPG123: $this->{err}");
		return;
	}
	$this->{version} = $1;
	display($dbg123,0,"start_mpg123() returning version($this->{version}");
}


sub stop_mpg123
{
	my $this = shift;
	display($dbg123,0,"stop_mpg123()");
	if (delete $this->{pid})
	{
		print {$this->{w}} "Q\n";
		close $this->{w};
		close $this->{r};
	}
	display($dbg123,0,"stop_mpg123() finished");
}


#--------------------------------------------

# state accessors
#--------------------------------------------

# sub error
#    # is this an API method, or is it called magically
#    # from within the code somehow?
# {
#    shift->{err}
# }



# sub paused
#    # I don't call this
# {
#    2 - $_[0]{state};
# }


# sub IN
#    # I don't call this
# {
#    $_[0]->{r};
# }


sub tpf
   # in my experience, this tpf (seconds per frame) is off by a factor of 2
{
	my $this = shift;
	return $this->{tpf};
}



#---------------------------------------------
# line() and parse()
#---------------------------------------------

sub line
{
	my ($this,$wait) = @_;
	while()
	{
		return $1 if $this->{buf} =~ s/^([^\n]*)\n+//;
		my $len = sysread $this->{r},$this->{buf},4096,length($this->{buf});
		# telescope the most frequent event, very useful for slow machines
		$this->{buf} =~ s/^(?:\@F[^\n]*\n)+(?=\@F)//s;
		if (defined $len || ($! != EAGAIN && $! != EINTR))
		{
			error("connection to mpg123 process lost: $!")
				if $len == 0;
		}
		else
		{
			if ($wait)
			{
				my $v = ""; vec($v,fileno($this->{r}),1)=1;
				select ($v, undef, undef, 60);
			}
			else
			{
				return ();
			}
		}
	}
}



sub parse
{
	my ($this,$re,$wait) = @_;

	while (my $line = $this->line ($wait))
	{
		if ($line =~ /^\@F (.*)$/)
		{
			$this->{frame} = [split /\s+/,$1];
			# sno rno tim1 tim2
		}
		elsif ($line =~ /^\@S (.*)$/)
		{
			@{$this}{qw(type layer samplerate mode mode_extension
						bpf channels copyrighted error_protected
						emphasis bitrate extension lsf)}=split /\s+/,$1;
			$this->{tpf} = ($this->{layer}>1 ? 1152 : 384) / $this->{samplerate};
			$this->{tpf} *= 0.5 if $this->{lsf};
			$this->{state} = 2;
		}
		elsif ($line =~ /^\@I ID3:(.{30})(.{30})(.{30})(....)(.{30})(.*)$/)
		{
			$this->{title}=$1;   $this->{artist}=$2;
			$this->{album}=$3;   $this->{year}=$4;
			$this->{comment}=$5; $this->{genre}=$6;
			$this->{$_} =~ s/\s+$// for qw(title artist album year comment genre);
		}
		elsif ($line =~ /^\@I (.*)$/)
		{
			$this->{title}=$1;
			delete @{$this}{qw(artist album year comment genre)}
		}
		elsif ($line =~ /^\@P (\d+)(?: (\S+))?$/)
		{
			$this->{state} = $1;
			# 0 = stopped, 1 = paused, 2 = continued
		}
		elsif ($line =~ /^\@E (.*)$/)
		{
			$this->{err}=$1;
			error($this->{err});
			return ();
		}
		elsif ($line !~ $re)
		{
			$this->{err}="Unknown response: $line";
			return ();
		}
		return $line if $line =~ $re;
	}
	delete $this->{err};
	return ();
}


#---------------------------------------------
# utilities
#---------------------------------------------

sub canonicalize_url
{
	my ($this,$url) = @_;
	if ($url !~ m%^http://%)
	{
		$url =~ s%^file://[^/]*/%%;
		$url = fastcwd."/".$url unless $url =~ /^\//;
	}
	return $url;
}



#----------------------------------------------
# commands
#----------------------------------------------
# poll() is not a command, per-se. It just calls
# parse() with some magic.  All the other commands
# print something to the process and then call parse().

sub poll
{
	my ($this,$wait) = @_;
	$this->parse(qr//,1) if $wait;
	$this->parse(qr/^X\0/,0);
}


sub load
{
	my ($this,$url) = @_;
	display($dbg123,0,"load($url)");
	$url  = $this->canonicalize_url($url);
	$this->{url} = $url;
	if ($url !~ /^http:/ && !-f $url)
	{
		$this->{err} = "No such file or directory: $url";
		return ();
	}
	print {$this->{w}} "LOAD $url\n";
	delete @{$this}{qw(frame type layer samplerate mode mode_extension bpf lsf
					   channels copyrighted error_protected title artist album
					   year comment genre emphasis bitrate extension)};
	$this->parse(qr{^\@[SP]\s},1);
	display($dbg123,0,"load() returning state($this->{state})");
	return $this->{state};
}



sub stat
	# I don't call this. Maybe I should
{
   my $this = shift;
   return unless $this->{state};
   print {$this->{w}} "STAT\n";
   $this->parse(qr{^\@F},1);
}


sub pause
{
   my $this = shift;
   display($dbg123,0,"pause in state($this->{state})");
   print {$this->{w}} "PAUSE\n";
   $this->parse(qr{^\@P},1);
}



sub jump
{
   my ($this,$arg) = @_;
   display($dbg123,0,"jump($arg)");
   print {$this->{w}} "JUMP $arg\n";
}


sub statfreq
	# I don't call this. Maybe I should
{
   my ($this,$arg) = @_;
   print {$this->{w}} "STATFREQ $arg\n";
}


sub stop
{
   my $this = shift;
   print {$this->{w}} "STOP\n";
   $this->parse(qr{^\@P},1);
}


# I use direct hash members rather than named symbols

# I think this inline code somehow creates a bunch of 'fields'
# on the $this object.
#
# Is there a reason this inline Perl code comes near the
# end of the file, or before error() ?

#	for my $field (qw(title artist album year comment genre state url
#	                  type layer samplerate mode mode_extension bpf frame
#	                  channels copyrighted error_protected title artist album
#	                  year comment genre emphasis bitrate extension))
#	{
#	  *{$field} = sub { $_[0]{$field} };
#	}



1;



# Full list of commands available in my version of the mpg123 executable
# installed to an rPi with
# to STDIN when started with -R, obtained by typing "help" after
# executing >mpg123 -R from a linux terminal.
#
#	HELP/H: command listing (LONG/SHORT forms), command case insensitve
#	LOAD/L <trackname>: load and start playing resource <trackname>
#	LOADPAUSED/LP <trackname>: load but do not start playing resource <trackname>
#	LOADLIST/LL <entry> <url>: load a playlist from given <url>, and display its entries, optionally load and play one of these specificed by the integer <entry> (<0: just list, 0: play last track, >0:play track with that position in list)
#	PAUSE/P: pause playback
#	STOP/S: stop playback (closes file)
#	JUMP/J <frame>|<+offset>|<-offset>|<[+|-]seconds>s: jump to mpeg frame <frame> or change position by offset, same in seconds if number followed by "s"
#	VOLUME/V <percent>: set volume in % (0..100...); float value
#	MUTE: turn on software mute in output
#	UNMUTE: turn off software mute in output
#	RVA off|(mix|radio)|(album|audiophile): set rva mode
#	EQ/E <channel> <band> <value>: set equalizer value for frequency band 0 to 31 on channel 1 (left) or 2 (right) or 3 (both)
#	EQFILE <filename>: load EQ settings from a file
#	SHOWEQ: show all equalizer settings (as <channel> <band> <value> lines in a SHOWEQ block (like TAG))
#	SEEK/K <sample>|<+offset>|<-offset>: jump to output sample position <samples> or change position by offset
#	SCAN: scan through the file, building seek index
#	SAMPLE: print out the sample position and total number of samples
#	FORMAT: print out sampling rate in Hz and channel count
#	SEQ <bass> <mid> <treble>: simple eq setting...
#	PITCH <[+|-]value>: adjust playback speed (+0.01 is 1 % faster)
#	SILENCE: be silent during playback (no progress info, opposite of PROGRESS)
#	PROGRESS: turn on progress display (opposite of SILENCE)
#	STATE: Print auxiliary state info in several lines (just try it to see what info is there).
#	TAG/T: Print all available (ID3) tag info, for ID3v2 that gives output of all collected text fields, using the ID3v2.3/4 4-character names. NOTE: ID3v2 data will be deleted on non-forward seeks.
#	   The output is multiple lines, begin marked by "@T {", end by "@T }".
#	   ID3v1 data is like in the @I info lines (see below), just with "@T" in front.
#	   An ID3v2 data field is introduced via ([ ... ] means optional):
#	    @T ID3v2.<NAME>[ [lang(<LANG>)] desc(<description>)]:
#	   The lines of data follow with "=" prefixed:
#	    @T =<one line of content in UTF-8 encoding>
#	meaning of the @S stream info:
#	S <mpeg-version> <layer> <sampling freq> <mode(stereo/mono/...)> <mode_ext> <framesize> <stereo> <copyright> <error_protected> <emphasis> <bitrate> <extension> <vbr(0/1=yes/no)>
#	The @I lines after loading a track give some ID3 info, the format:
#	     @I ID3:artist  album  year  comment genretext
#	    where artist,album and comment are exactly 30 characters each, year is 4 characters, genre text unspecified.
#	    You will encounter "@I ID3.genre:<number>" and "@I ID3.track:<number>".
#	    Then, there is an excerpt of ID3v2 info in the structure
#	     @I ID3v2.title:Blabla bla Bla
#	    for every line of the "title" data field. Likewise for other fields (author, album, etc).
#
