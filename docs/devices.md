# Artisan Perl Devices

Artisan Perl Devices abstract the DLNA interfaces into a more
easily understood set of APIs that are then used by the WebUI
to effect the presentation, controlling, and playing of music.

There is a deviceManager class that presents a list of all known
devices in the system.  It can be asked to find a certain device
by its uuid, or to return a list of devices of a given type,
in a certain order.

## Devices

Devices consist of a base class and the following derived classes

- Renderer
  - localRenderer
  - remoteRenderer
- Library
  - localLibrary
  - remoteLibrary
- PLSource
  - localPLSource
  - remotePLSource

The three base deviceTypes provide orthogonal APIs.

Local devices implement these APIs in terms of things like
	SQLLite Databases and the Windows Media Player COM object.
	Local devices **advertise* and **serve** their Services
	via SSDP and the HTTP Server to other network devices.

Remote devices implement these API's in terms of HTTP requests,
	to the Services that they advertise via SSDP and serve
	via HTTP.


## Device API

The Device API consists of the following members

- uuid
- name
- type
- services (hash by serviceType)

It provides the following methods:

- addService()
- findService()


## Renderer API

The Renderer API adds the following members that describe
its capabilities

- maxVol - 100 indicates can adjust volume from 1 to 100
- canMute - 1 indidates supports Mute button, implied by maxVol with Mute being volume 0
- canLoud - 1 indicates supports Loudness button
- maxBal - 100 indicates can balance from -100 to 100
- maxFade - 100 indicates can fade from -100 to 100
- maxBass - 100 indicates EQ control available
- maxMid - 100 indicates EQ control available
- maxHigh - 100 indicates EQ control available

The following members that describe its overall state

- state - NONE, INIT, STOPPED, TRANSITIONING, PLAYING, PAUSED, ERROR
- muted
- volume
- balance
- fade
- bassLevel
- midLevel
- highLevel

And the following members which describe the song which
is currently loaded and/or playing:

- position - non zero MS while PLAYING
- duration - non sero MS while a song is loaded

- uri - the uri the renderer used to get the song
- song_id - our song_id, if any
- type - the type (MP3, M4A, etc) of the song
- artist name
- title (song title)
- album (album title)
- track_num (track number within album)
- art_uri - where to get the picture to show
- genre (including sub-genres)
- date (our best guess for teh
- size in bytes

The Renderer provides a single entry point, doCommand()
which supports the following commands and parameters

- update
- stop
- play
- pause
- play_pause
- next
- prev
- mute value => 0 or 1
- loud value => 0 or 1
- volume value => 0..100
- balance value => -100..+100
- fade value => -100..100
- bassLevel value => 0..100
- midLevel value => 0..100
- highLevel value => 0..100
- seek position => ms
- playlist_song index => index to use
- set_playlist
  - plsource_uuid => uuid
  - name => name
- play_song
  - library_uuid => uuid
  - id => id{

Mute, volume, balance, fad, bass, mid, and high levels,
should only be called if the device says it can do those
things and may report errors on devices that cannot.

Songs can be set into a renderer using a fully qualified
URI, or in the case of songs that have my known id
(chromaprint fingerprint) by their id.  Playing
individual songs will interrupt, but not stop
a Playlist that is in progress.  After the song
the Playlist will resume at the position it was
at in the Playlist song being played.


Renderers generally provide two Services, either
publishing them as a localRenderer, or consuming
them as a remoteRenderer.  Those services are
enapsulated in two final member variables that
are generally intended for private use:

- transportURL
- controlURL

### localRenderer notes

It *should* be possible for the localRenderer to play
STREAMS from various DLNA Servers by using the appropriate
URI.




## Library API


## PLSource API

A PLSource is a source of Playlists.

A Playlist has a Name, and a number of Tracks and is
associated with a particular Library.

A Track can be identified in two different ways:

- the path to the track within any Library
- its unique_id within an Artisan Library

A Renderer can be set to automatically play a Playlist,
continuing even without the UI being present.

The special case of a Playlist that refers to the
localLibrary being played on the localRenderer can
be easily implemented.


### PLSource Methods

- **getPlaylists** - returns a list of the names of the
  playlists within the PLSource, which is all that's generally
  required for the UI.
- **getPlaylistJson(name)** - returns a subset of the members
  of a Playlist, specifically including the
  - the number of tracks within the playlist
  - current track index within the playlist, one based
  - the shuffle mode
- **shufflePlaylist(name,off|tracks|albums)** - sets the
  shuffle mode and sorts the tracks in the playlist,
  resetting the current track index to 1. It is the
  UI's responibility to re-call Renderer::setPlaylist()
  after a shuffle.












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
