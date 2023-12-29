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
# pretend to understand how this Perl code works. My rework
# will be somewhat different, more clunky, but understandable
# to me.


package myMPG123;
use strict 'subs';
use Carp;
require Exporter;
use Fcntl;
use IPC::Open3;
use Cwd;
use File::Spec;
use Errno qw(EAGAIN EINTR);

BEGIN { $^W=0 } # turn off bogus and unnecessary warnings

@ISA = qw(Exporter);

@_consts = qw();
@_funcs = qw();

@EXPORT = @_consts;
@EXPORT_OK = @_funcs;
%EXPORT_TAGS = (all => [@_consts,@_funcs], constants => \@_consts);
$VERSION = '0.63';

$MPG123 = "mpg123";

$OPT_AUTOSTAT = 1;



sub new {
   my $class = shift;
   my $self = bless { @_ }, $class;
   $self->start_mpg123(@{$self->{mpg123args} || []});
   $self;
}

sub start_mpg123 {
   my $self = shift;
   local *DEVNULL;
   open DEVNULL, ">/dev/null" or die "/dev/null: $!";
   $self->{r} = local *MPG123_READER;
   $self->{w} = local *MPG123_WRITER;
   $self->{pid} = open3($self->{w},$self->{r},">&DEVNULL",$MPG123,'-R','--aggressive',@_,'');
   die "Unable to start $MPG123" unless $self->{pid};
   fcntl $self->{r}, F_SETFL, O_NONBLOCK;
   fcntl $self->{r}, F_SETFD, FD_CLOEXEC;
   $self->parse(qr/^\@?R (\S+)/,1) or die "Error during player startup: $self->{err}\n";
   $self->{version}=$1;
}

sub stop_mpg123 {
   my $self = shift;
   if (delete $self->{pid}) {
      print {$self->{w}} "Q\n";
      close $self->{w};
      close $self->{r};
   }
}

sub line {
   my $self = shift;
   my $wait = shift;
   while() {
      return $1 if $self->{buf} =~ s/^([^\n]*)\n+//;
      my $len = sysread $self->{r},$self->{buf},4096,length($self->{buf});
      # telescope the most frequent event, very useful for slow machines
      $self->{buf} =~ s/^(?:\@F[^\n]*\n)+(?=\@F)//s;
      if (defined $len || ($! != EAGAIN && $! != EINTR)) {
         die "connection to mpg123 process lost: $!\n" if $len == 0;
      } else {
         if ($wait) {
            my $v = ""; vec($v,fileno($self->{r}),1)=1;
            select ($v, undef, undef, 60);
         } else {
            return ();
         }
      }
   }
}

sub parse {
   my $self = shift;
   my $re   = shift;
   my $wait = shift;
   while (my $line = $self->line ($wait)) {
      if ($line =~ /^\@F (.*)$/) {
         $self->{frame}=[split /\s+/,$1];
         # sno rno tim1 tim2
      } elsif ($line =~ /^\@S (.*)$/) {
         @{$self}{qw(type layer samplerate mode mode_extension
                     bpf channels copyrighted error_protected
                     emphasis bitrate extension lsf)}=split /\s+/,$1;
         $self->{tpf} = ($self->{layer}>1 ? 1152 : 384) / $self->{samplerate};
         $self->{tpf} *= 0.5 if $self->{lsf};
         $self->{state} = 2;
      } elsif ($line =~ /^\@I ID3:(.{30})(.{30})(.{30})(....)(.{30})(.*)$/) {
         $self->{title}=$1;   $self->{artist}=$2;
         $self->{album}=$3;   $self->{year}=$4;
         $self->{comment}=$5; $self->{genre}=$6;
         $self->{$_} =~ s/\s+$// for qw(title artist album year comment genre);
      } elsif ($line =~ /^\@I (.*)$/) {
         $self->{title}=$1;
         delete @{$self}{qw(artist album year comment genre)}
      } elsif ($line =~ /^\@P (\d+)(?: (\S+))?$/) {
         $self->{state} = $1;
         # 0 = stopped, 1 = paused, 2 = continued
      } elsif ($line =~ /^\@E (.*)$/) {
         $self->{err}=$1;
         return ();
      } elsif ($line !~ $re) {
         $self->{err}="Unknown response: $line";
         return ();
      }
      return $line if $line =~ $re;
   }
   delete $self->{err};
   return ();
}

sub poll {
   my $self = shift;
   my $wait = shift;
   $self->parse(qr//,1) if $wait;
   $self->parse(qr/^X\0/,0);
}

sub canonicalize_url {
   my $self = shift;
   my $url  = shift;
   if ($url !~ m%^http://%) {
      $url =~ s%^file://[^/]*/%%;
      $url = fastcwd."/".$url unless $url =~ /^\//;
   }
   $url;
}

sub load {
   my $self = shift;
   my $url  = $self->canonicalize_url(shift);
   $self->{url} = $url;
   if ($url !~ /^http:/ && !-f $url) {
      $self->{err} = "No such file or directory: $url";
      return ();
   }
   print {$self->{w}} "LOAD $url\n";
   delete @{$self}{qw(frame type layer samplerate mode mode_extension bpf lsf
                      channels copyrighted error_protected title artist album
                      year comment genre emphasis bitrate extension)};
   $self->parse(qr{^\@[SP]\s},1);
   return $self->{state};
}

sub stat {
   my $self = shift;
   return unless $self->{state};
   print {$self->{w}} "STAT\n";
   $self->parse(qr{^\@F},1);
}

sub pause {
   my $self = shift;
   print {$self->{w}} "PAUSE\n";
   $self->parse(qr{^\@P},1);
}

sub paused {
   2 - $_[0]{state};
}

sub jump {
   my $self = shift;
   print {$self->{w}} "JUMP $_[0]\n";
}

sub statfreq {
   my $self = shift;
   print {$self->{w}} "STATFREQ $_[0]\n";
}

sub stop {
   my $self = shift;
   print {$self->{w}} "STOP\n";
   $self->parse(qr{^\@P},1);
}

sub IN {
   $_[0]->{r};
}

sub tpf {
   my $self = shift;
   $self->{tpf};
}

for my $field (qw(title artist album year comment genre state url
                  type layer samplerate mode mode_extension bpf frame
                  channels copyrighted error_protected title artist album
                  year comment genre emphasis bitrate extension)) {
  *{$field} = sub { $_[0]{$field} };
}

sub error { shift->{err} }

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
