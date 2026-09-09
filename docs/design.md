# Artisan - Design

**[Home](readme.md)** --
**Design** --
**[Playlists](playlists.md)**

Artisan is a music server and player for one person's library.  One copy
runs on the laptop that owns the library, and one copy runs on each
Raspberry Pi that plays it.  Every copy serves a browser user interface
and plays audio itself.  This page describes the shape of the system: the
surfaces it is used from, the roles a server can have, the rules that keep
a Pi safe from a power failure, what has identity, and what persists.


## Surfaces

Artisan is used from four kinds of device.  Each is a resolution, an
orientation policy, and an input precision, and the user interface is
built for the surface, not for the server behind it.

    surface     screen      orientation      input
    laptop      1920x1080   landscape        mouse and keyboard
    head unit   1024x600    landscape        touch
    iPad        large       either           touch
    phone       small       either           touch

The laptop is the only pointer surface.  A mouse clicks within a few
pixels, hover and right-click exist, and typing is cheap.  The other three
are touch surfaces: fingertip targets, no hover, long-press and swipe, and
typing that is possible but costly.  Nothing on the ordinary listening
path requires typing; search is the one place it is asked for.

The touch surfaces are the compatibility floor for the javascript.  The
iPad's Safari for its html5 quirks, and the head unit for its speed: a
2015 MediaTek with two cores and 2 GB, running Chrome 138 on Android 9,
the newest browser it will ever have.  A page for the head unit loads in
a couple of seconds, carries very little javascript, and re-synchronizes
with the server after Android thaws it rather than trusting its own
timers.  Whatever the laptop gets, it gets on top of what works on the
floor.


## Server roles

Every Artisan server is a PLAYER: it holds a copy of the library, serves
the user interface, and plays audio through its own output.  Exactly one
server is also the LIBRARIAN.  It runs on the laptop, it is the only
server that can build a library, and it is where music enters.

The two axes are independent.  A laptop browser pointed at the boat's Pi
is a large pointer surface talking to a player.  A phone pointed at the
laptop is a small touch surface talking to the librarian.  The user
interface asks a server which role it has and shows the librarian's
controls only when the server is the librarian, never because the screen
is large.

Both Pis run identical code.  The laptop runs the same code, plus the
librarian.


## Steady state

A Pi is a fixed appliance in a place where the power fails several times a
month.  In its steady state a Pi never writes to its SD card or to the
USB stick that holds the library.  Pulling the power at any moment does
no damage, because nothing is ever half written.

This holds because:

- The library database is opened read-only on a Pi.
- Everything a server writes in normal operation, its log and its pid
  file, lives under /base_data/temp, which on a Pi is a RAM disk.  It is
  empty after every boot.
- The state that matters across a power failure, which playlist was
  where and how loud the player was, lives in RAM on the Pi and in the
  browsers that use it.  See "What persists" below.

The exceptions are a few well known maintenance and configuration
processes in which a Pi does write: updating its code from the repo,
synchronizing the library onto its stick, and writing its preferences
file.  They are few enough to be menu items.  A Pi that writes outside of
them has a bug.

The laptop has no such rule.  It is the librarian, it writes the library,
and it has a battery.


## Identity

- A TRACK is identified by the MD5 of its audio stream, as computed by
  fpcalc.  The id follows the audio, not the file: a renamed or moved
  file is the same track, a re-encoded one is a different track.
- A FOLDER is identified by the MD5 of its path within the library.
- A SERVER, and the library and renderer it owns, is identified by
  ArtisanPerl- followed by its hostname.  Every Pi on a LAN therefore
  needs a distinct hostname.
- A BROWSER identifies itself with a random id it keeps in its own
  storage.  Browser storage is per origin, that is per server IP and
  port, so a Pi's IP is reserved in the router: a Pi that changed address
  would look like a different server to every browser.

An mp3 file is never modified once it is in the library, and no metadata
is stored in its tags.  Genre is the folder structure, artist is the
filename convention, and everything else is in the library database.


## The library

A server has exactly one library, at a fixed path: /mp3s on the laptop,
the stick's mp3s folder on a Pi.  Beside the music, the library's own
_data folder holds what a player needs and nothing else:

    artisan.db       the database: one row per track and per folder
    artisan.prefs    the server's preferences
    playlists.txt    the playlist definitions, see playlists.md

All three travel with the library when it is synchronized.  The
librarian's working data, fingerprints, artist lists, ingest areas, is
not part of the library and never reaches a Pi.


## Playing

A server has one DEVICE RENDERER, which plays through the machine's own
audio output: the PiFi hat on a Pi, Windows Media Player on the laptop.
Every browser that opens the user interface also has a BROWSER RENDERER,
an html5 audio element that plays through the browser's device.  The user
picks which renderer a page controls.

A renderer plays either its QUEUE or a PLAYLIST.  The queue is a list the
listener builds by hand from the explorer, for active listening; it is
transient, it can end, and it belongs to one renderer.  A playlist is a
named, standing selection of the library that wraps around and remembers
where it was.  Playlists are the subject of playlists.md.


## What persists

The only state that survives a power failure or a restart is small, and
none of it is on a Pi's card:

    what                                  where
    the library and its _data             the stick (written only by sync)
    the code                              the card (written only by update)
    per playlist: shuffle mode, seed,     RAM on the server; mirrored into
      current track                         every browser that uses it
    the device renderer's volume and mute  same
    a browser's own renderer volume,       that browser's storage
      chosen renderer, page layout

The playlist and volume state is one set per server, shared by every
renderer of that server.  A server boots with none, and takes the first
copy a browser offers it.  The mechanism is described in playlists.md.

A server always boots to INIT and never plays on its own.  Someone
presses play.
