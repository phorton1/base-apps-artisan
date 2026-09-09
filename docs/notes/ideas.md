# Ideas

Patrick's standing list of things that are not planned.  Parked, not
rejected.  Seeded 2026-09-09 from the plan; owned by Patrick from here on.

- Loudness measurement in the librarian (ReplayGain / EBU R128, once per
  track and album, like fpcalc), stored in artisan.db, applied as a gain at
  play time.  Album gain for album-shuffle lists, track gain for
  track-shuffle lists.  Would retire the _normalized folders.
- A "note this track" button while listening ("too loud", "needs a look")
  that keeps track id and a word in the browser for the librarian to
  collect later.
- A size cap on the Pub logger.  Nice, not should.
- Spotify on the boat as raspotify (librespot) on the Pi: the Pi shows up as
  a Spotify Connect speaker, the phone picks the music, the hat plays it,
  the head unit stays off the internet.  Needs a hand-off with Artisan for
  the hat, a cache on the tmpfs or disabled, and a Premium account.
- Block the head unit's WAN at the router (both routers) once it needs no
  more downloads.  It is a 2021-patched Android 9 with vendor firmware.
- Start Termux's sshd on the head unit at boot (Termux:Boot add-on) if
  restarting it by hand ever becomes a nuisance.
- A second repo.  Considered and rejected 2026-09-09; the Perl is nudged in
  place.
