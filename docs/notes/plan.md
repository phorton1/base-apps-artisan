# Plan - September 2026

Started 2026-09-09.  This is the working plan for the redesign whose goals
are stated in redesign.md.  Both are interim, unofficial notes.  This one
lists the specific changes I want to, and need to, make, in the order I
currently intend to make them.  Sections are not numbered; reordering is
moving a section.  It changes every session and is supposed to shrink: when
a step is done and its subject is documented in docs/, it comes off.

The approach is nudges.  Each of the next three steps can be seen working
on the bench Pi before the next one starts, and none of them forecloses
the larger questions (a separate librarian repo, ingest, sync), which wait
until I have lived with the results.


## Documentation

docs/design.md (the axes, the roles, steady state and its exceptions, the
identity model, what persists and where) and the docs/rpi folder (the
human workflow for making a Pi, with build and config underneath).  Their
content is decided.  Every other docs/ page is written when its subject
exists, not before; until then the design lives here.


## Playlists into RAM

The playlist definitions leave the Perl source and become a text file in
/mp3s/_data next to artisan.db.  It is library data, not code: it changes
when the library changes, or at my whim, and it ships with the library.
Written up as docs/playlists.md before the Perl.

- A definition is id, name, path-prefix query lines (with minus), and a
  default shuffle mode (album, track, none).  Ids are explicit in the file
  and never change, because saved positions are keyed by them.
- A server reads the file at startup.  Track lists are derived from
  artisan.db on demand and held in RAM.  playlists.db and the per-playlist
  .db files cease to exist.
- Shuffle order comes from a seed and a small Perl PRNG, the same on
  Windows and Linux.  Album shuffle groups by folder.  Position is
  restored by track id.
- Persistent state is one set per server: a position per playlist plus
  the device renderer's volume and mute.  Nothing else persists.
- A Pi holds that state in RAM.  Every browser mirrors it from the poll
  into localStorage (per origin, so reserved IPs matter).  First browser
  wins: the first browser to poll a Pi in INIT hands over its copy.
  Worst case a playlist resumes a few tracks off.  No versioning.
- A server always boots to INIT and never auto-plays.
- The queue is transient: RAM on the Pi, no mirror.
- The browser side of the mirror is plain javascript, no jquery.  It is
  the first piece of the new UX and lives on through the rewrite.
- renderer_defaults.txt goes; the state absorbs volume and mute.


## The Pi stops scanning

With playlists no longer built at startup, the scan is the only thing left
in a Pi's startup path that touches the library.  Skip it on a Pi and open
artisan.db read-only.  The few seconds go away and the Pi is read-only in
fact.  The laptop still scans; fpcalc_info and artists stay where they are
for now.


## Then look at it

What remains of librarian code on a Pi after the two steps above is dead
files, which hurt nothing.  Whether it becomes a separate private repo
(forced eventually by ingest, which cannot enter this public repo), where
its data folder lives, and how sync works, are decided after living with
the first two steps.  The dependency runs one way regardless: the
librarian needs Artisan's library model, Artisan never needs the
librarian.


## After that, in rough order

- Tip of the iceberg cleanups: the Libraries section of the home menu goes
  (there is only one library); the dead explorer error-mode preference and
  the Preferences accordion go (re-implement when there is a preference;
  artisan.prefs via Pub::Prefs stays as the Perl-side file).
- The uuid-in-every-request protocol and the DeviceManager registry go.
- The protocol document, docs/protocol.md: every endpoint, its JSON, the
  update poll, the state blob.  Starts from docs/obs/webUI_API.md.  Written
  before the rewrite; the Perl is collapsed to serve exactly this.
- The javascript rewrite, ground up, plain html5, no vendored frameworks,
  checked page by page against artisanOld on all four surfaces.  Explorer
  first (read-only library endpoints, where fancytree lives and the head
  unit hurts), home second (the new state protocol), search with whichever
  it fits.  Until then, changes to the old javascript are deletions only.
  The old webUI directory is deleted when the new one covers it.  The
  apartment Pi may stay on the frozen commit as a second reference.
- The class collapse: Library, Renderer, Playlist; the platform seam at
  the player layer (winPlayer, mpg123Player).  The laptop keeps its
  Windows Media Player renderer.  linuxAudio and the audio device
  endpoints go; the PiFi hat is pinned at install.  Done as the code is
  touched, not as a step of its own.
- Library synchronization, master to stick.  No design yet.  Update, sync
  and prefs are a few menu items in the webUI.
- Pub::Database: within this redesign, after it, or not at all.


## Already done

- DLNA server and client, and SSDP searching, removed (2d58645).  SSDP
  advertising kept as a UPnP Basic device.
- Temp files in the standard temp dir (c207751); a tmpfs on the Pi.
- Both Pis rebuilt zero-touch from blank cards by rpi_card.pl and
  rpi_setup.sh on Trixie Lite (71d0854).  No backup cards or master
  images; the scripts are the master.
- Old docs moved whole to docs/obs (1477e94).
- Frozen reference copy of the repo at 1477e94 at /base/apps/artisanOld,
  port 8092.  Never edited, never deployed.
- Head unit's Chrome raised from 101 to 138, the newest its Android 9 can
  run (2026-09-09).  Termux with ssh on the unit for the next time.
