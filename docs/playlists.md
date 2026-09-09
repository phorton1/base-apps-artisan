# Artisan - Playlists

**[Home](readme.md)** --
**[Design](design.md)** --
**Playlists**

A playlist is a named, standing selection of the library that plays in a
chosen order, wraps around when it reaches the end, and remembers where
it was.  Three separate things make one up, and keeping them separate is
the whole design:

    the DEFINITION   what belongs in it        a text file in the library
    the TRACK LIST   which tracks that is now   derived from the database
    the STATE        how it is ordered and      RAM on the server, mirrored
                       where it is                by the browsers

Nothing about a playlist is ever written to a Pi's card or stick.


## Definitions

The definitions live in playlists.txt in the library's _data folder,
beside artisan.db.  They are library data, not code: they change when the
library changes, or when I feel like it, and they travel with the library
when it is synchronized.  Every server reads the file when it starts.

The file is line oriented.  Blank lines and lines starting with # are
ignored.  The first line gives the file's version.  A playlist starts
with a header line and is followed by one or more indented query lines:

    version 1

    # id  name       default shuffle
    playlist 014 rock track
        albums/Rock
        albums/SanDiegoLocals
        singles/Rock

    playlist 007 classical album
        albums/Classical minus /Baroque
        singles/Classical minus /Baroque

- The VERSION is an integer I bump whenever the ids change meaning.  A
  saved state set (below) records the version it was saved under, and a
  server discards any set whose version is not the file's.  Forgetting
  to bump it is harmless: a stale position is a track id checked against
  the derived list, so it either restarts the playlist or lands a few
  tracks off.
- The ID is three digits.  Ids ORDER THE PLAYLISTS in the user interface,
  and saved positions are keyed by them.  To reorder the menu, renumber
  and bump the version.
- The NAME is what the user interface shows, one word, unique.
- The DEFAULT SHUFFLE is none, track or album, and is the order a
  playlist starts in the first time a server ever plays it.  Album for
  the long listening lists, track for "just random music", none for a
  list that is an album in itself.
- Each QUERY LINE selects every track whose path CONTAINS the text
  before "minus" and, if "minus" is present, does not contain the text
  after it.  Paths are relative to the library root and use forward
  slashes.  The match is a substring match, so "albums/Rock" also
  matches "albums/Rock/..." and would match "albums/RockAndRoll"; the
  folder names are chosen so that this does not bite.
- The track list is the union of the query lines.  A track matched by
  more than one line appears once.

The order of playlists in the file means nothing; ids order them.  The
file is edited by hand in a text editor.  A server that finds
the file missing has no playlists, which is an error worth noticing, not
a condition to paper over.


## The track list

A server derives a playlist's track list from artisan.db the first time
the playlist is asked for, and keeps it in RAM after that.  Deriving the
largest list, rock at some 2300 tracks, takes about 50 ms on the laptop.
There are no per-playlist database files.

The derived list is in DEFAULT ORDER: by the track's path with the
leading albums/ or singles/ removed, then by track number, then by
title.  Since a path is genre, then artist and album, this groups the
list by album within genre and plays albums in track order.  Every
shuffle is a permutation of this list, so the default order is also
what "no shuffle" means.

On the laptop, a library scan invalidates every derived list, since the
scan may have changed what matches.  On a Pi the library never changes
between synchronizations, so a derived list is good until the next
restart.


## Order and shuffle

A playlist's order is fully described by its shuffle mode and a SEED.
Given the same derived list, the same mode and the same seed, every
server, on Windows or on Linux, produces the same order.  That is what
lets the order survive a restart without being stored anywhere: the seed
is stored, the order is recomputed.

- NONE: the default order.  The seed is unused.
- TRACK: the tracks in a random order.
- ALBUM: the albums in a random order, each album's tracks in default
  order.  An album is identified by its album title, or by its parent
  folder when it has none, the same rule the queue uses.

The random order is a Fisher-Yates shuffle driven by a small
pseudo-random generator written in Perl integer arithmetic, not by
Perl's rand(), which differs between platforms.  The generator is
specified by its code and is not changed once positions depend on it.

Choosing shuffle in the user interface picks a new seed from the clock,
recomputes the order, and starts the playlist from the first track of
the new order.  A playlist that has never been played on a server starts
in its default shuffle mode with a seed of the moment.


## Position

A playlist's position is the ID OF THE CURRENT TRACK, not an index.  The
index is recomputed from the track id and the order whenever it is
needed.  If the current track no longer exists, because the library
changed under a saved position, the playlist starts from the beginning
of its order.  That is the only case in which a position is lost.

Moving within a playlist is relative to the order: next and previous
track, next and previous album, or an absolute index chosen from the
track list in the user interface.  Playlists wrap at both ends.


## State

The state of a playlist on a server is three values:

    shuffle    none, track or album
    seed       the integer that fixes the order
    track_id   the current track, or empty

plus a VERSION, an integer that goes up on every change, which the user
interface uses to notice that something moved.  Every request that
changes a playlist's position carries the version the requester last
saw; a request with a stale version is ignored.  This is what keeps two
renderers, or two browsers, from fighting over one playlist.

The server holds one state set, shared by every renderer that plays on
it: the version of playlists.txt it belongs to, the three values for
each playlist that has ever been played, plus the device renderer's
volume and mute.  This is the whole of what a server remembers across a
restart, and it is a few hundred bytes.  A set whose version is not the
file's is discarded, positions and all; volume and mute are kept.


## Persistence

A Pi never writes its state.  Instead:

- Every browser that polls a server receives the server's state set in
  the poll response, and stores its own copy, keyed by the server's
  origin.
- A server boots with an EMPTY state set and reports so.
- The first browser to poll a server that reports an empty set, and that
  has a stored copy for that origin, hands its copy over.  The server
  accepts a handover only while its set is still empty, and keeps only
  the volume and mute from a copy saved under another file version.
  Every later browser takes the server's set.
- The device renderer's volume and mute are applied when the set arrives.

This is FIRST BROWSER WINS.  Two browsers can hold copies that differ by
however many tracks played between their last polls; whichever polls
first after a boot decides.  The worst case is a playlist that resumes a
few tracks off from where it was.  There is no versioning of the set, no
merge, and no resume button.

The laptop keeps its state the same way.  It could write a file, but one
mechanism is better than two.

A server always boots to INIT and never plays on its own.  Receiving a
state set does not start anything.


## The queue

The queue is the other thing a renderer can play.  It is a list the
listener builds by hand from the explorer, held in RAM on the server, one
per renderer, and it is not part of the state set: a power failure
empties it and nothing brings it back.  It can end, where a playlist
wraps.  Shuffling the queue reorders it in place with the same generator
and album rule as playlists.


## What this replaces

The definitions were a Perl structure in the source, deployed with the
code; a change of taste needed a commit and an update.  Each playlist was
materialized into its own SQLite file, and a playlists.db held the
positions, both under _data on the stick, written on every track change.
The device renderer's volume was written to a file on every change.  All
of that ceases to exist.  The library database is untouched by playlists;
it is only read.
