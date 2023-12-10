# Artisan Perl

Artisan Perl is primarily a complete, self contained, system for organizing,
presenting, and playing audio from a local Music Library of consisting of
files, like MP3s, contained in a single folder tree, on a Windows computer.

In addition, it implements, and takes advantage of certain DLNA
and UPNP standards:

- it is a standard DLNA Media Server, providing its Library to a huge
  number of existing devices (Music Players) that can render audio on
  a home network.
- it can present and play audio from a similarly huge number of
  existing networked Media Servers that implement the DLNA standard.

Planned (possible) enhancements:

- it can control any Music Players on the netork that implement the
  standard DLNA Renderer interface, of which there are many. As such
  it can connect any DLNA Media Server to any DLNA Renderer on the
  network to present and play audio from the given Server on the
  given Renderer.

Artisan Perl runs as a Service on the Windows Machine, and provides a
User Interface via an HTTP Server that can be accessed by a Browser
anywhere on the on home network.


## Design Overview

Artisan Perl

- is a DLNA MediaServer
- can access any existing DLNA Media Servers
- **can control any existing DLNA Media Renderers**

It is **not** a DLNA Renderer.  Artisan itself cannot be
controlled by existing DLNA Control Points.  Internally
it abstracts the existing DLNA Media Servers **and Renderers**
it finds on the home network down to a much simpler API
for use by the webUI.


## Standardization on MP3 files

As of today, 2023-12-10, I have decided to standardize my Library
to MP3 files, and will use ffmpeg_prebuilt_6.1.exe to convert
all of my WMA and M4A files to MP3's at 124kps using the command
line:

	ffmpeg_prebuilt_6.1.exe -i blah.m4a -acodec libmp3lame blah.mp3

and to cleanup the database, removing all unused fpcalc_info files.
To begin with, I added ffmpeg_prebuilt_6.1.exe from

	/zip/apps/ffmpeg/ffmpeg-6.1-essentials_build.z7 ffmpeg.exe

to the /bin folder. Then I made a copy of /mp3s to /mp3s_save (there is
already a vestigial copy in /junk/maybe_save) and wrote and tested
a script /docs/tests/convertAllToMP3.pm that does the conversions,
removing the old files in the process.

This is specifically to solve the fact that HTML Renderers cannot
play WMA files, but will eventually lead to other simplifications
in the code by eliminating other Media File Types.



## Design Details

In reference to previous Artisan Perl and
currently un-modified Artisan Android.

**Playlists are 'persistent' per Library**

- The system able to play through a sorted-random-by-album playlist
  on multiple different devices sequentially so that I don't hear the
  same albums/song twice and yet I hear all of them once.
- I can select anything from the explorer tree and
  play it immediately (interrupting the current playlist).


**Got rid of 'Playlist Sources'**

Playlists are bound to libraries for compatibility with WMP and
a more general UI.

- added a new 'dirtype' = 'playlist'
- redesigned playlists.db and namedb.files (they are now incompatible
  with Artisan Android).

I *think* the main artisan.db file remains compatible.

**Webui HTML Renderer**

The webUI has a truly Local Renderer in the embeded HTML music player
that can play music on the Browsing, as opposed to the Serving, device.

Artisan Android does not currently serve the webUI.  It should.


**WebUI FancyTree now entirely JSON based**

I no longer send HTML from the Server to the webUI.

The understanding starts by realizing that if the 'source:' or 'lazyLoad:' options
of the tree return Hashes, those hashes are used to form Ajax requests
to get the data, which is then loaded into the tree from the 'success'
of the Ajax call.  BUT, if source: or lazyLoad: return Arrays, those
arrays ARE the data.   See explorer.js for more info.



## License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License Version 3 as published by
the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

Please see **LICENSE.TXT** for more information.


---- end of readme.md ----
