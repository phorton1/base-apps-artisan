# rPi - Artisan Perl Experiments on Raspberry Pi's

Although this starts as an Artisan specific experiment,
it really has to do with being able to generally develop
applications on the rPi using my base/Pub architecture.

As of this writing I have a pretty good solution for bringing
rPi's up with my old base/My architecture and apps/file client.

I thus will want to bring /Pub up to run on the rPi, make sure
that Pub/FS/fileServer.pm can run on it, and advance apps/fileClient
to have the unix commands (mode, ownership, etc) as per the old
apps/file client, while still merely relying on unencrypted
communications over the local network.  Then eventually
going the last 20% of the way (80% of the effort) to somehow
get it to work over HTTPS and/or SSH tunnels for access
from the internet at large.

There are a lot of ideas here, but they all start with getting
/base/Pub/Utils.pm working on the rPi.  And then Artisan Perl
serves as a good test case for running a headless server application
on the rPi.

Other candidates include the base/My/IOT server which already
supports SSH/HTTPS, but in that case I am tempted to rewrite the
whole Arduino/libraries/myIOT architecture because I don't
particularly like the use of WebSockets which is really
complicated to support and doesn't work, for instance, via
HTTPS on the iPad due to Apples inherent arrogance.

In any case, I have gotten a pretty good start at setting
rPi's up to run my Perl Stuff. As it stands, I can already
use the rPi's Chromium browser, with output to HDMI (or the
rPi's audio output port), to hit Artisan Perl running on the
Laptop and play music on the rPi.



## rPi Setup, Observations, and Issues

See **/zip/_rpi/_setup/rpi_Setup.docx** for steps
to boot up an rPi to the point where it can access
my GIT repositories, clone base/My, and run the old
base/My/FS fileServer.pm for access from the laptop.

### Observations (rPi Browser to Artisan Perl on Windows machine)

- Had real problems with 64bit OS on 4B(1).
- Works well in 3B(0) with old 32bit OS
- Works well on 4B(2A) with 64bit OS

Somewhat better with 4B1 on 32bits

- seems to spend a LOT of time hitting the SDCard
- audio interrupted by browser stuff
- might be a RAM limitation (swapping) particular to 4B vs 3B

Had problems with existing (git_repos) PAT (personal access token)
Creating and using a new (rPi) specific PAT fixed it.

### Decision

The rpi 4B(0) 1GB is a bit slow for practical use.
I will leave it configured, as far as fileServer, with the SD
in it, but will do future Artisan experiments only on the 2GB 4B(2A)




## Ideas

### Boat Car Stereo

I'm not loving the idea of bringing the Artisan Android
project up-to-date with the changes I have made to the
database in Artisan Perl. Although that little part would
be pretty straight forward, I would want to add the webUI
and deal with the removal of the PLSources concept to allow
for consistent remote control of the Car Stereo, and then
the issue becomes that I am not sure it is a good idea to
put so much effort into an Android 4.2 device.

An alternative that comes to mind is to turn an rPi into
an Artisan Seerver and Renderer, and then have that output
analog audio to the existing Car Stereo head unit, or some
other amplifier, to provide sound on the boat.

That could then, in turn, be combined with the myIOT Server
and/or other UI's, with a 7" or 10" touch screen and the
new Boat Electrical Panel, and at the extreme, it is even
worth considering moving all of the Boat instruments to
an open-source rPi solution, esp due to the fact that the
RayMarine chart plotters are old and failing, and something
will need to be done, likely a major rework of the boat's
instruments, at some point anyways.

### Home (apartment) Music System

Although I think I can simply plug a bluetooth device
into the PA Amplifier and use it to play music from
Artisan Perl on the Laptop, which would probably be
sufficient for the Apartment, I also have a tendency
to think about using an rPi as a dedicated Music
Server/Renderer, with an amplifier besides the PA.
The broken Bose thing from Mark comes to mind.

This is another case where moving base/Pub, and then
base/apps/Artisan to the rPi (unix) comes to mind.

The first issue I note with this approach (and with
the Boat Car Stereo rPi above) is that I don't see a
good way to implement the localRenderer in Perl on
linux.  Whereas I have OLE on Windows, and can access
the Windows Media Player as a Renderer, there is no
equivilant on linux.

I am in the nascent stages of thought on this but some
ideas come up that mostly revolve around using existing
DLNA Renderers on the rPi. A quick Google search reveals
that *some* sort of DLNA Renderer comes with, or is
installable on the rPi.

- https://github.com/hzeller/gmrender-resurrect/
- gstreamer


## rPi initial implementation not4es

### Got Pub::FS::fileServer.pm working on rPi

I was able to get base/Pub/FS/fileServer.pm to work on the
rPi fairly easily.  There were a number of minor issues,
some yet to be fully resolved, that were necessary to address.

### Perl executable bit in GIT

I discovered that my long-forgotten GIT pre-commit script
was not being called. I solved that by both (a) moving it
to it's own directory /base/bat/git_hooks, and by setting
the hook path correctly in /Users/Patrick/.gitconfig.
See /base/bat/git_hooks/pre-commit for git config command
line.

To wit, I also wrote a script /base/bat/fix_git_exe_bits.pm
to be run on a per-repo basis to update the exe bit on PM,
PL, and CGI files.   For consistency, I also ran it on
base/My and checked those changes in.

### Unix Line Endings and Perl Script Headers

I needed to include "#!/usr/bin/perl" as the first line
of /base/Pub/FS/fileServer.pm.  I did not need to do this
on any other files, so likely this is only needed for
main "program" perl scripts.

Before I did that, I modified the line endings from
Windows \r\n to Unix \r and checked it in and pushed it.
I did not need to modify any other files in this way,
so maybe this was not needed. A subsquent test revealed
that this is NECESSARY for main script files because
otherwise BASH does not interpret the first
"#!/usr/bin/perl" line correctly.

So, once again, these requirements only apply to
Perl scripts that will be executed via bash:

- they must start with "#!/usr/bin/perl"
- they must use UNIX \r line endings.

### Comment one line out of FS::FileInfo.pm

After using the exising (new) /base/apps/fileClient.pm
I was able to hit the rPi by creating a 'connection'
to the IP (10.237.50.152) and port (5872) with starting
directories of /base/Pub on both sides. On this
client side  I got an error

	bad FS::FileInfo size(4096)

for the initial directory listing of /base/Pub.
I am guessing that I presumed because Windows
stat returned a zero size for directories, that
0 would always be returned, and in fact, on
linux I get an actual size for the directory
(entries) of 4096 bytes.  For now, commenting
that error check out of FileInfo.pm seems to
work.

At this point I GOT DIRECTORY LISTINGS AND
WAS ABLE TO TRAVERSE the rPi from the new
fileClient.pm running on the laptop !!!

### Changed the rPi hostname to rpi4B-2A

I noticed a unititialized var in the Perl output
from the fileServer on the rPi. Pub::Utils.pm::getMachineId()
was not implemented for linux. I implemented it to use
the hostname command if not on windows.

For good measure I changed the hostname of the rPi
to **rpi4B-2A**.  Now it shows up in fileClient as
and identifiable machine.

However, there are problems with the Wifi on the rPi,
perhaps having to do with signal strangth, particularly
to THX59, it seems to hang and not connect, re-asking
for authentication.  It works 'better' on THX50, which
is physically in line of sight, so I'm just going with
that for now, but it may be an issue to explore (i.e.
an antenna for the rPI?)

### First File Transfer Failed

Then I tried to transfer a file from Windows to the rPi.
Got an error on Win32::DriveInfo::DriveSpace at Utils.pm 910
in method diskFree() as called by Session.pm::_file() method.
Implemented diskFree() and pushed it. It seemed to work.

### rpi fileServer to laptop fileClient is inconsistent

Sometimes it works, sometimes it doesn't.

Is this a fools errand?   To try to get fileServer working
well on rPi's, as a potential replacement for existing,
proven /apps/file client?  Do I want to make this public?

BTW, mkdir and file delete seemed to work OK, but still
seem to have some kind of issue with a final getPacket.
Could be a socket issue, blocking, etc.

Seems to work a lot better with small directory listings
(when I made /junk/testFS and /home/pi/testFS and worked
between those two directories).

Large file (3M) Cancel didn't work, but the xfer did.
Transferred a 'tree' worked to the rPi, but nothing
on the way back.  Ahhh the fileinfo size problem.
I'm gonna check that change in.

After that checkin, it sort-of-worked to transfer
a tree from rPi to Windows.  But it has that same
problem that it hangs at the end waiting for a packet
of some kind.  I think this may be because the protocol
is very complex and recursive but it also may be a
basic socket problem.

One way or the other, though, this is a path
for the future. I'm not gonna continue trying
to get fileServer/fileClient working on the
rPi today.


### Added support for ansi colors to Pub::Utils.pm

Just did it, thought I'd add a note to this ongoing MD file.

### Other Possibilties

- Resolve rPi fileServer vs laptop fileClient issues?
- Put Unix Commands into Pub::FS and base/apps/fileClient??

Eventually

I will need to address the fact that the whole Pub::FS thing
assumes a single drive that is the same as the one the code
is running on.  I will need a different drive for MP3s on
the rPis, and it is quite possible to have different drives
on Windows.




## Back to Artisan

Got Artisan working on the rPi, mostly.

### mp3s directory

It is currently using a subset of /mp3s directory.

The USB drive plugged into rPi is mounted as

	/media/pi/USB_16

and the mp3s directory on it can probably be had at

	/media/pi/USB_16/mp3s

To start with, however, was able to copy it to /mp3s
with a bunch of sudo mkdirs, chmod 0777, chown, and
an explicit cp -r command from a terminal window.


### Installed additional Perl Libraries

see /zip/_rpi/_setup/rPi_Setup.docx


### Addressed the following issues initially

- put a fixed ip address 192.237.50.152 into artisanUtils.pm
- fixed bareword usages in artisan.pm by fully qualifiying them to methods:
  - ENABLE_MOUSE_INPUT
  - STD_INPUT_HANDLE
  - ENABLE_WINDOW_INPUT
- changed SSDP send_responses() to use selected $sock and my
  hand coded _mcast_send() method

The $recv_sock->mcast_send() was returning undef $bytes but
appears to have worked, to the degree that I ccould see the rPi
device in Windows Explorer Network as see it from SSDP in
Artisan running on the windows machine, and could even open
its library.

At this point, the only things not working for sure
was getting the ipAddress of the device.

In fact, if I added:

- the ability to get the ipAddress
- a preference for the location of the library
- a service descriptor ala myIOTServer and fileServer

I could just boot the machine, open a browser, and it
would be effectively working (over HDMI or rPi audio).


### mpMPG123.pm for linux localRenderer.

I thought I was close.  Did a chunk of work factoring out mpXXX.pm
from localRenderer, created mpMPG123.pm, and even copied and modified
my own version of myMPG123.pm, only to finally discover that mpg123
does not support backward seeks in http streams.

MPG123 was a fairly simple solution.  All the other ones I'm seeing are
tremendously complicated, old, or both.  The most current alternative
seems to be MPD (Media Player Daemon), which has a Perl Binding,
but is super a complicated full feature Media pipeline. One called
MOC is old and barely documented. There's another old one called
gStreamer.

The problem in all of these cases is that I have to serious work
to even TRY them as solutions for a localRenderer on Unix.
It would almost be easier for me to make the HTML Renderer
work like a real Renderer, such that it could be accessed
and controlled from other devices.

I subsequently tried the mpHTML.pm approach below, but in
the end decided to go forward with the MPG123 solution on
the rPi using by mapping http://$surver_ip:$server_port urls
to direct local file paths to address the 'can't slider backwards'
issue.



### mpHTML.pm

Implemented and messed with a braindead substitute for mpWin.pm
to be used on the rPi that uses a browser <audio> device for
the localRenderer.  After implementation and testing I decided
it was far too complicated, and did not resolve any real issues.
I am keeping it around for now in the following files, with the
following changes

- mpHTML.pm - unused pm file
- localRendeer.pm - use mpHTML commented out with an
  unused chunk of code in doCommand() and a line in
  checkMPStart() that are not called.
- html_audio.js - unsued js file
- artisan.js - minor uncalled code in idle_loop()
- artisan.html - include of html_audio.js is commented out


### Instability issues

I don't know what was going on, but I was getting a lot of SIGPIPE
terminations on the rPi.  I added a warning, and a return in
artisan.pm handle_signals(), but I have not seen it called since,
so I don't really know what caused the problem.

I still get problems where the system won't exit on CTRL-C,
and/or fails on startup (probably during mpg123 process
creation coincident with a network access like getting
LENOVO2 WMP 'fake' playlists).


## SoundCard

After installing it as a service that I can start and stop
with "sudo systemctl start/stop artisan" I now want to add
a soundcard so I don't have to use the 12V monitor HDMI
output.

The only USB Sound Devices I had handy are the old ones from
my guitar-effects days. After digging up some 1/4" to 1/8"
adapters and plugs, I was astonished when it just worked
when I plugged it into the rPi, using artisan from a terminal
window.

There was a bit of a battle, then, to get stuff working
from the service, which is running as 'root'.  The mixer
control in the rPi UI only applies to the user shell.

There are three programs of interest that I messed around
with on the rPi:

- amixer - was already being called with 'amixer sset 'PCM' 20%'
  to set the volume to 20% for running out of the 12V monitor
  HDMI outputs (which are speaker output) to the audio in
  of the small USB speakers.
- the command 'aplay -l' will list the sound cards in the
  system, each of which has a 'card numbers' and typically
  a single 'device number' of 0
- the command 'pactl list sinks short' is a way to set the
  default audio device from the command line. It gives
  a list of devices with space delimited fields including
  the long name that can be passed back to set the device
  with the command 'pactl set-default-sink $long_name'.
  However, it does not work from root because it is a
  command line method, requires a XDG_RUNTIME_DIR environment
  variable.

In the end, I merely set the default device in /etc/asound.conf,
and merely set the volume to 100% in the artisan startup code.


# Setting default device in /etc/asound.conf

Use `aplay -l' to get a listing of devices. you will see something
like this:

	card 3: Device [USB PnP Sound Device], device 0: USB Audio [USB Audio]

One then sets the USB sound card as the default by editing
/etc/asound.conf (sudo geany blah) with the card and devoce number
from above:

	defaults.pcm.card 3
	defaults.pcm.device 0

I struggled a while with the volume, which seemed stuck at 20%
for root.  It seemed to work after I stopped the service, ran
it NO_SERVICE from a terminal with 'amixer sset 'MASTER' 100%',
and/or via 'sudo /base/apps/artisan/artisan.om' as a SERVICE
with 'amixer sset 'PCM' 100%' in the code.

I'm not really sure how the volume got turned back up, or
how it got turned down permanently, in the first place,
however, it is working right now, and I want to move on.



### Code I wrote, then removed from Artisan

In testing the above I wrote a chunk of code so I could
see and try things, particularly when running as 'root'
from a real service at machine startup. I am keeping that
code here in this document for posterities sake:


	if (0 && !is_win())
	{
		my $sinks = `pactl list sinks short`;
		LOG(0,"pactl sinks=$sinks");
		my $cards = `aplay -l`;
		LOG(0,"aplay cards=$cards");
		my $controls = `amixer scontrols`;
		LOG(0,"amixer controls= $controls");
		# exit(0);   # if you just want to see debugging
	}

	# use pactl to set default audio device
	# comment out && $AS_SERVICE for debugging

	if (0 && !is_win() && $AS_SERVICE)
	{
		my $usb_dev = '';
		my $sinks = `pactl list sinks short`;
		for my $line (split(/\n/,$sinks))
		{
			if ($line =~ /usb/)
			{
				my @parts = split(/\s+/,$line);
				$usb_dev = $parts[1];
			}
		}

		if ($usb_dev)
		{
			LOG(-1,"setting USB AUDIO DEVICE to $usb_dev");
			my $rslt = `pactl set-default-sink $usb_dev`;
			error($rslt) if $rslt;
		}
	}

	# set volume

	if (0 && !is_win() && $AS_SERVICE)
	{
		my $volume = '100%';
		my $device = $AS_SERVICE ? 'PCM' : 'Master';

		my $rslt = `amixer sset '$device' $volume`;
		LOG(-1,"amixer sset '$device' $volume rslt=$rslt");
	}


### USB Audio Card stopped working

Dunno why. Left it on for a day, came back, no more USB audio.
Switched to rPi headphone jack (device 2) in /etc/asound.conf.



## Volume Control

My idea here is that on screens that are big enough to handle it,
there will be a vertical slider to the right in the renderer pane,
with a mute button, and on smaller screens, there will be a speaker
button that brings up a popup control with a slider and a mute
button.

It may be best to just implement it orthogonally, in which case
it *might* be a playback button, like the shuffle button.

The phone has the smallest real estate.

I really don't like the media_query heuristic approach to
different screen sizes and layouts. For instance, I get
different results on the phone if it's fullscreen, or
in a chrome browser window.   And the fact that I have to
match the media query in my layout code, because jquery
ui-layout does not work from CSS.



## BLUETOOTH AUDIO - With new cheap BT audio device.

There are two possible scenarios for BT audio on the rPI

- using the rPi as a BT speaker from Windows Machine is an intereesting
  experiment, especially if this system becomes "the boat stereo".
- output from the Artisan service to the BT audio device.

The latter case is the one we delve into here.

### BLS-B11  Mac: 06:E4:81:E9:0E:07

Is the model of the BT speaker device.

Switching pairings between rPi and Windows seems to work fine.
Inasmuch as, at least, the rPi pairing was done via the GUI.


### /etc/asound.conf

When I add the following the rPi /etc/asound.conf file, the
BT speaker becomes the default rPi output device, though not
for the Artisan service

	defaults.bluealsa.interface "hci0"
	defaults.bluealsa.device "XX:XX:XX:XX:XX:XX"
	defaults.bluealsa.profile "a2dp"
	defaults.bluealsa.delay 10000

	# defaults.pcm.card = 2
	# defaults.pcm.device = 0


### /etc/group

EXPERIMENT: in middle with using PACTL from artisan.pm
getting "pactl pa_context_connect() failed connection refused"
error. Added user pi to /etc/group file for
group "pulse" and "pulse-access"

	pulse:x:117:pi
	pusle-access:x:118:pi

I think I already added pi to the audio group with
a command line while trying something else

	audio:x:29:pi,pulse


### Working from command line but not AS_SERVICE

At this point I have implemented webUI/set_audio_device(AVJack|HDMI|BLSB11)
and it works when Artisan is running from the command line, but not when
Artisan is running as a service.


### Trying to run from terminal window on startup

I have tried several ways to run Artisan from a terminal window
upon startup

- add /base/apps/artisan/artisan.pm to /etc/rc.local -
  I get no output to artisan.log, which I do not understand
  Even if it did work, presumably the forked child would be
  killed when rc.local exits
- I don't want to try /base/apps/artisan/artisan.pm NO_SERVICE
  as this might freeze startup, rendering the machine u-nusable.

I could not get the terminal to come up automatically at all,
after trying to add '@lxterminal' to all these files:

- /etc/xdg/lxsession/LXDE/autostart -
  changes left in place, commented out
- /etc/xdg/lxsession/LXDE-pi/autostart -
  changes left in place, commented out
- created /home/pi/.config/lxsession/LXDE-pi/autostart -
  renamed to prh-autostart-did-not-work)


### linux audio is VERY confusing

- I think I am using 'pipewire' which emulates 'pulseaudio'
- pipewire itself does not appear to support setting a current, or defaul, audio device
- There are many different commands and approaches to setting the audio device
- There is something different about a SERVICE's audio than an application.
- myMPG123.pm crashes if I try to add -o alsa:bluealsa to the command line

Note that even though the audio is not changed when running as a service,
the WebUI::set_audio_device command DOES change the system default audio
device.


## Environment Variables

It turns out to be some kind of an issue with environment variables.

I changed the service description file to make the service SIMPLE and
include all the environment variables that are seen by the command line
version, and, in addition, changed serverUtils.pm to not fork, but rather
to merely write an (unused) PID file, and it started working.

I'm not sure exactly how to proceed at this point.

- Do I want a 'simple' non-forking Unix Service? or,
- Do I want to go back to a forking process and try it with environment variables.

I don't really want to change serverUtils.pm ... it is also the basis of the
fileServer service, myIOT Service, and eventually other services.  But it
is nice, in a sense, that I don't need to call serverUtils at all to create
unix services.   initUtils(1) (AS_SERVICE) *may* still be required to turn
off screen output.

I will *still* want to narrow down exactly WHICH environment variables
are important for this.
