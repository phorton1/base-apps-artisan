# Artisan Perl

Artisan Perl is primarily a complete, self contained, system for organizing,
presenting, and playing audio from a local Music Library of consisting of
files, like MP3s, contained in a single folder tree, on a Windows computer.

In addition, it implements, and takes advantage of certain DLNA
and UPNP standards:

- it is a standard DLNA Media Server, providing its Library to a huge
  number of existing devices (Music Players) that can render audio on
  a home network using DLNA standards.
- it can present and play audio from a similarly huge number of
  existing networked Media Servers that implement the DLNA standard.
- it can control any Music Players on the netork that implement the
  standard DLNA Renderer interface, of which there are many. As such
  it can connect any DLNA Media Server to any DLNA Renderer on the
  network to present and play audio from the given Server on the
  given Renderer.
- *it is an OpenHome Playlist Source, providing lists of songs
  that can be played on devices that support the Open Home Playlist
  interface.*

Artisan Perl runs as a Service on the Windows Machine, and provides a
User Interface via an HTTP Server that can be accessed by a Browser
anywhere on the on home network.


## Design Overview

Artisan Perl

- is a DLNA MediaServer
- can access any existing DLNA Media Servers
- can control any existing DLNA Media Renderers

It is **not** a DLNA Renderer.  Artisan itself cannot be
controlled by existing DLNA Control Points.  Internally
it abstracts the existing DLNA Media Servers and Renderers
it finds on the home network down to a much simpler API
for use by the webUI.


### OpenHome Playlist Source

It is not clear at this time if it is useful, or advisable
for Artisan to be an OpenHome Playlist Source.

Artisan certainly implements Playlists and can Render them
and push the songs in them to existing DLNA Renderers, but
at this time, I am not certain that I care enough about
controlling other Renderers to determine whether or not,
and if so, how, typical DLNA Renderers utilize OpenHome
Playlists.   So, at this time, the Playlist Source within
Artisan is purely my own and does not follow any particular
standards.

Nonetheless, I have abstracted the hierarchy of classes so
that Artisan Perl has a localPLSource, and can utilize a
remotePLSource from another instance of Artistan (i.e.
Artisan Android).








## License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License Version 3 as published by
the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

Please see **LICENSE.TXT** for more information.

---- end of readme ----
