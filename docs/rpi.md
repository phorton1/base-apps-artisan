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



## Got Pub::FS::fileServer.pm working on rPi

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


## Added support for ansi colors to Pub::Utils.pm

Just did it, thought I'd add a note to this ongoing MD file.


## Try truncated Artisan Perl on rPi

At a minimum I'm gonna need

- don't construct the localRenderer if is_win()
- a bit of an /mp3s directory on the rPi (less than 1GB)

push to test is gonna be a hassle.
wondering about commits from rPi then
fetch-rebase on Windows.

I think I will start with git clone for artisan
followed by old fileClient xfer of main pm direcotry.

CHECKING THIS FILE IN (Artisan totally checked in)

The USB drive plugged into rPi is mounted as

	/media/pi/USB_16

and the mp3s directory on it can probably be had at

	/media/pi/USB_16/mp3s

To start with, however, was able to copy it to /mp3s
with a bunch of sudo mkdirs, chmod 0777, chown, and
an explicit cp -r command from a terminal window.

### Installed additional Perl Libraries

see /zip/_rpi/_setup/rPi_Setup.docx


### Needed changes

The following stuff is not valid on linux:

- artisanUtils.pm way of getting server IP by calling Windows ip_config.exe
- ENABLE_MOUSE_INPUT at artisan.pm line 83
- STD_INPUT_HANDLE at artisan.pm 82
- ENABLE_WINDOW_INPUT
- something about block or sub at artisan.pm 231

All of that fixed, and a few more minor things, got as far as SSDP
having errors not being able to call $sock->mcast_send() which returns
undefined $bytes.  But the ipAdress thing needs to be solved first.

I will start by just making it a constant (modify source on the
rPi now). ABLE TO HIT SERVER, BRING UP UI, EXPLORE, and PLAY A SONG!!



The sock->mcast_send that is returning undef $bytes appears to have
worked, to the degree that I can see the rPi device in Windows Explorer
Network as see it from SSDP in Artisan running on the windows machine,
and can even open its library.

I wonder if Windows Artisan will see it?


It does, and in fact, after I changed SSDP::sendResponses() to use
the selected $sock and my hand written _mcast_send(), it works on
both platforms.

In fact, at this point, the only thing not working for sure
is getting the ipAddress of the device.

In fact, if I added:

- the ability to get the ipAddress
- a preference for the location of the library
- a service descriptor ala myIOTServer and fileServer

I could just boot the machine, open a browser, and it
would be effectively working (over HDMI or rPi audio).













## Other Possibilties

- Resolve rPi fileServer vs laptop fileClient issues?
- Put Unix Commands into Pub::FS and base/apps/fileClient??

Eventually

I will need to address the fact that the whole Pub::FS thing
assumes a single drive that is the same as the one the code
is running on.  I will need a different drive for MP3s on
the rPis, and it is quite possible to have different drives
on Windows.
