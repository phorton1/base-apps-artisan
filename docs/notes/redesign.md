# Re-design - September 2026

This redesign effort comes as I am putting a Raspberry Pi running Artisan,
and the Essgoo 7" Android car stereo, on the boat.

This document states the highest level goals of the effort.  It is not a
plan.  The plan, the ordered list of specific changes, what is done and
what is open, lives in plan.md next to this file and is expected to change
every session.  This document should change rarely.  Both are interim,
unofficial notes; the official documentation is what gets written in docs/.

Although the implementation may be incremental, in essence this is a
sweeping refactoring - nearly a rewrite - of much of the code in the
system, and a ground-up rewrite of the javascript UX.


## The Shape of the System

Two distinctions, which I had not made clearly before, frame everything
below.

The first is the UX SURFACE.  Artisan is used from four kinds of devices:
the laptop, the Essgoo head unit on the boat, an iPad, and a phone.  Each
is a resolution, an orientation policy, and an input precision.  The laptop
and the head unit are fixed landscape; the iPad and the phone have to work
in either orientation.  The laptop is the only pointer surface - a mouse
that clicks within a few pixels, hover, right-click, and a real keyboard
that makes typing cheap.  The other three are touch surfaces, with
fingertip targets and typing that is onerous.  The touch surfaces are the
compatibility floor for anything the javascript does: the iPad for its
non-standard html5 support, and the head unit for its slowness.  The head
unit runs Chrome 138, the newest its Android 9 allows, so its browser is
current enough; its 2 GB and two cores are not.

The second is the SERVER ROLE.  Every Artisan server is a PLAYER.  Exactly
one of them, the one on the laptop, is also the LIBRARIAN: it ingests
music, builds the library and its database, and synchronizes the result
onto the sticks that the Pis play from.  The two axes are independent.
A laptop browser pointed at the boat Pi is a large pointer surface talking
to a player; a phone pointed at the laptop is a small touch surface talking
to the librarian.  The UX is built for the surface and asks the server what
its role is.


## Highest Level Perl Objectives

The single most important objective is that the Perl code running on a Pi
be essentially READ-ONLY with regards to the SD card and the USB data
stick in normal day to day operation.  Stated as a requirement: a Pi shall
tolerate abrupt shutdown by removal of its power supply, at any time,
without damage to the OS card or the data stick.  Power drops several times
a month in Bocas and I have lost days to corrupted cards.

Read-only is the STEADY STATE.  The exceptions are a few well known
maintenance and configuration processes in which a Pi does write: updating
the source from the repo, synchronizing the library onto the stick, writing
its preferences.  They are few enough to be menu items.  A Pi that writes
outside of them has a bug.

The second major objective is guided, automatic SYNCHRONIZATION of the
library on the sticks against the master library maintained on the laptop.
This is in addition to the already moderately working guided update of the
Artisan source code itself onto a Pi.  Synchronization is, at this time,
completely unaddressed in the code.

The third is the LIBRARIAN WALL: the code that builds the library is
structurally separated from the code that plays it, so that a Pi never
loads, and never can run, any of it.  The library database ships with the
library, and a Pi opens it read-only.

Behind these three is a general objective of leanness.  It is easier to
add a capability to a lean system than to maintain futures that never get
used.  A thing stays only if a Pi or the laptop uses it today.  Things are
named for what they ARE, not for what they used to be.


## Highest Level Javascript Objectives

The most general objective for the javascript UX is that it be responsive
and light enough for the very limited Essgoo browser.  Today's UX carries
some 131K lines of vendored jquery, jquery-ui, jquery-layout and fancytree,
and the head unit's slowness is largely that.  The UX will be rewritten
from the ground up in plain html5 javascript, with no vendored frameworks.

The current javascript and CSS incorporate many hard learned lessons about
browser interoperability, device scaling, and touch usability on the
surfaces described above.  Those lessons must survive the rewrite.  The
existing UX, running as-is from a frozen copy of the repo, is the reference
against which the new one is checked on each device.

The interaction between the javascript and the Perl server - the HTTP
protocol - will be defined as a document before either side is rebuilt to
it, so that the Perl is collapsed to serve exactly that and the new
javascript consumes exactly that.

Browser persistent storage has an important role vis-a-vis the read-only
Pi.  What a Pi cannot write, the browsers that use it remember for it.


## Documentation

The old documentation, half stale and describing things that no longer
exist, has been moved aside whole.  New documentation describes WHAT IS,
never the path taken to get there, and is organized by subject, with the
same shape at every level: a readme for workflow and usage, a design page
for architecture, and further pages for implementation.  Pages are written
when their subject exists, not before.


## Goals Not Yet Reached or Scheduled

- Library synchronization, master to stick to Pi.  Stated above; no design
  yet.
- Moving Artisan from direct SQLite access to Pub::Database.  Still a goal;
  not yet decided when, or whether, it happens within this redesign.
- The desktop surface.  artisanWin is an abandoned stub; whether the laptop
  wants anything beyond a browser is undecided.
