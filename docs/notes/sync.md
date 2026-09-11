# Sync

Started 2026-09-11.  An interim note describing what the sync feature will
be.  It is absorbed into docs/sync.md when the feature exists, and dies.


## What sync is

A player's library (the tree of mp3 files plus artisan.db and playlists.txt
under _data) is one artifact, produced by a build on the librarian and
trusted by the player as is.  The player never scans it, never repairs it,
and never writes to it except during a sync.

Sync makes a player's artifact equal to the librarian's.  It runs on the
player, in one direction only, librarian to player.  The player pulls; the
librarian only serves what it already serves.  Any browser can start a sync
on a player and watch it; the head unit's browser is expected to do neither.

There is no merge.  A player has no library state of its own.

Sync is a System command, like update, restart, reboot and shutdown.  It
ends the way update ends, with a service restart, and every browser comes
back in INIT.


## The artifact

What sync compares and copies

  - track files, by track id (the stream md5), from the two databases
  - folder.jpg files, by path, compared by size and modification time
  - artisan.db and playlists.txt, compared by md5

What sync preserves

  - each file's modification time, taken from the track record in the
    librarian's database, so that an A/B directory listing of the laptop
    tree against the stick shows no differences after a sync

What sync leaves alone

  - artisan.prefs, the one file under _data that belongs to the player
  - anything under _data that sync did not put there
  - anything outside the mp3 tree


## The diff

Input: the librarian's artisan.db and the player's artisan.db, the two
playlists.txt files, and the two lists of folder.jpg files.

Output, computed by track id and by path:

  - add     tracks whose id is not in the player's database
  - remove  tracks whose id is not in the librarian's database
  - rename  tracks whose id is in both at different paths
  - art     folder.jpg files to copy or remove
  - data    whether artisan.db and playlists.txt differ
  - bytes   the total to transfer (add + art)

Renames transfer nothing.  Folders are derived from the track paths:
sync creates the folders the new paths need and removes folders that end
up empty.  The diff is computed on the player in the tmpfs; the databases
are small.


## The process

Sync runs as a task inside the player's server.  It survives the browser
that started it.  The steps, in order; the poll reports the current one
as sync_step (see The protocol):

  1. fetch     the librarian's artisan.db and playlists.txt into the tmpfs
  2. plan      compute the diff and report it; wait for confirmation
  3. pull      each track and folder.jpg in the add and art lists into
               _data/_staging on the stick; verify each file's md5 against
               the librarian's record; set its modification time
  4. place     move staged files into the tree, creating folders as needed
  5. rename    move tracks in the rename list to their new paths
  6. remove    delete tracks and folder.jpg files in the remove lists, then
               folders that are now empty
  7. data      copy playlists.txt and artisan.db into _data, replacing them
               whole; artisan.db last
  8. done      the summary stays on the page until the operator presses
               restart, however fast or slow the run was
  9. restart   restart the service, as update does

From confirmation to restart the player is BUSY (see The mode).  It stops
its own renderer and refuses stream and playback command requests.

Steps 3 and 4 never change what the old artisan.db describes: new files
are referenced by nothing until step 7.  Steps 5 through 7 take seconds
and involve no network.

A dry run is steps 1 and 2 without a confirmation.


## Failure

On any error sync stops.  It does not restart or reboot: the service stays
up, sync_step stays at the step that failed, sync_error holds the message,
and the mode is lifted so the player is usable with what it has.  Both
fields keep those values until the next sync or restart.

What a failed sync leaves on the stick is always a playable artifact:

  - stopped before step 5: the old artifact, plus new files in the tree
    and in _staging that nothing references
  - stopped in steps 5 to 7: the old artisan.db with some files moved or
    removed; those tracks are reported missing at play time until sync is
    rerun

A power drop during sync is the same as the above with the message lost.

Rerun is the only repair.  The next sync recomputes the diff from what
actually landed, so placed files are not pulled again and renames already
done are not redone.  Staged files whose md5 verifies are kept and reused;
anything else in _staging is deleted as the first step of a sync.  A boot
never touches _staging, because a boot never writes.


## The mode

The player carries the state of a running System command, in RAM, and every
browser polling it mirrors that state.  Before this, the overlay was held
only by the browser that issued the command, and a second browser (the head
unit, playing) never knew.

Two fields in the poll (/webUI/update):

  server_start   the time the service started.  A page remembers the value
                 from its first poll; when a later poll reports a different
                 one, the server has restarted and the page reloads.  Every
                 browser, issuing or not, awake or asleep, comes back in
                 INIT with the current JavaScript after any restart, update,
                 reboot or sync.

  busy           the System command in progress: sync, update, or nothing.
                 While set, every browser shows its overlay and stops its
                 own renderer.  The issuing browser also gets the standard
                 countdown as today.

The mode is Artisan's, in Artisan's poll and artisan.js.  standard_system.js
is shared with apps that are used from one browser at a time, and keeps its
single-browser overlay unchanged.  Its real clients are Artisan and
myIOTServer.  If myIOTServer comes to run on an rPi it will need the same
mode, and the mode is lifted into standard_system.js then, not before.

The mode dies with the restart.  A player always boots with no mode, no
error and no sync in progress, as it always boots to INIT.


## The protocol

On the librarian (read only, served by the ordinary player):

  GET /sync/db                 artisan.db
  GET /sync/playlists          playlists.txt
  GET /sync/art/<folder path>  a folder.jpg
  GET /media/<id>.mp3          a track, whole (exists today)

On the player:

  GET /sync/plan     fetch from MASTER_LIBRARY_IP, diff, return the lists
                     and totals, or the reason it cannot
  GET /sync/start    run the plan just computed
  GET /sync/cancel   stop after the current file
  GET /sync/restart  after done: restart the service

While busy the player answers stream and playback command requests with an
error naming the command in progress.

In the poll, besides server_start and busy, a sync block:

  sync_step      the step in progress: fetch | plan | pull | place |
                 rename | remove | data | done | restart; empty when no
                 sync has run since the service started
  sync_files     files done / files total
  sync_bytes     bytes done / bytes total
  sync_current   the file being transferred
  sync_error     empty, or the message of the error that stopped the sync
                 at sync_step

Finished is sync_step done with sync_error empty, the player still busy
until the operator's restart.  Failed is sync_error set, with sync_step
saying where.


## The UI

One item, Sync, in the System submenu of a player.  It is Artisan's item,
in artisan.html and artisan.js; standard_system.js is not involved.

Sync opens one small page: the plan (counts per list and the byte total)
and a confirm.  On confirm the page keeps a log, one line per step as it
happens, and the progress of the pull, until sync_step reaches done (a
restart button) or sync_error is set.  The page is meant to be used from a laptop
browser pointed at the player.  Every other browser polling that player,
including the head unit, shows the overlay from the busy field and nothing
else.


## Configuration

MASTER_LIBRARY_IP in the player's artisan.prefs: the address of the
librarian, port 8091 implied.  The plan page shows the address it is about
to use.  Its absence, and the librarian not answering at it, are reported
to the user as such; both are things the user can fix.

This is the first real preference on a player.  A browser UI to set it
(the Preferences accordion, removed as dead in September, coming back
because there is now a preference) is a sanctioned write to the stick; it
may come with sync or later, and until then the line is edited over ssh.

Sync needs only that the player can reach the librarian's address over
HTTP.  On a different subnet that is a routing question, not a sync one;
where there is no route, the stick is carried to the laptop.


## Not in this step

  - the stick mounted on the laptop: the same diff applied by a file copy;
    this is the librarian's, later
  - the boat: no measurement yet through the CPE210 bridge
  - any UI beyond the plan and confirm page
  - a library version: not needed while every library change on a player
    ends in a restart
  - fileServer: update pulls /base/Pub but nothing restarts the running
    fileServer, so after an update that changed Pub the rPi is rebooted.
    Known and accepted; sync never pulls Pub


## Measured 2026-09-11

Over the AX55 on 2.4 GHz, both Pis at -42 dBm, a 60 MB track pulled by a
Pi from the laptop's player arrived at 2.5 to 5.4 MB/s.  Written to the
stick and verified, 25 s for 60 MB.  The stick itself writes at 31 MB/s and
verifies 60 MB in a quarter second.  Playback needs 40 KB/s.  A classical
album is about half a minute; the whole library about five hours.
