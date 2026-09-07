# Re-design - September 2026

This redsign effort comes as I am putting a Raspberry PI running Artisan,
and the Essgoo 7" Android car stereo on the boat.

There are a few highest level directions behind this effort, all intended
to make Artisan, and its javascript web UX more robust, simpler, and flexible,
while at the same time retaining its general usefulness, ability to run
on Windows as well as Linux (rpi) machines, and continuing to support the
various UX surfaces: the laptop firefox browser, car stereo android chrome
browser, iPad IOS chrome browser, and phone android chrome browser.

Although the implementation of this redesign may be incremental, in essence
it is a sweeping refactoring - nearly a rewrite - of much of the code in the
system.


## Highest Level Objectives

This section presents the highest level design concepts to be achieved.
It is not an ordered list - an implementation plan - it is a summary of
what is hoped to be acheived.  It is presented in two subsections -
Perl and Javascript - even though there are heavy interdependencies
between the two.


### Highest Level Perl Objectives

Perhaps the highest level objective of the whole re-design is to make
the Perl code running on the rPi essentially read-only with regards
to the operating system SDCard and the USB data stick, in the normal
day to day operation. The general requirement is perhaps best stated
as a requirement that, in normal day to day operations, that the rPI
shall allow for abprupt shutdown by removal of its power supply without
any damage occuring to the OS sdcard and the USB data stick.

In addition to this robustness against sudden power losses, another
major requirement - at this time completely unaddressed in the current
code - has to do with guided automatic synchronization of the data
(library) on the sticks versus the master data (library) stored and
maintained on the laptop.  This is in addition to the similar concept,
already moderately implemented, of updating the source code for Artisan itself
on the rPI via a similar guided process that largely currently already
works.

This effort will be facilitated by removing large swaths of vestigial
Perl code and corresponding UX functionality having to do with the
long implemented, but never really used, support for the DNLA protocol,
as well as Artisan's ability to poll SSDP for DNLA libraries and renderers.
It may remain a "nicety" for Artisan to be able to advertise itself via
SSDP.  DLNA and SSDP polling are two things that currently make extensive
use of caching information to the SDCard - writing to it - that will thus
be eliminated helping with the read-only objective.

Presented as bullet items, the above are:

- remove DNLA code, caching, and complexity
- remove SSDP searching and device caching
- make Artisan Read-Only with regards to SD and USB storage devices
- design and implement the master library synchronization scheme

There are many details of how these goals will be reached,
particularly with regards to making Artisan read-only, that
will be defined in more detail in subsequent sections of this
document, but some other desirable goals for the Perl code
include:

- bringing Artisan up to using Pub::Database rather than direct SQLite access
- improving, correcting, and re-organizing the existing documentation
- segregating library and playlist database construction on the master
  from the day-to-day operations of an instance of the service/server.



### Javascript UX

The most general objective for the Javascript UX application is to
make it more responsive and less memory intensive for use in the
various browsers, but particularly the very limited Essgoo chrome
browser.

It will likely continue to use jquery and jquery layout, but a
felt goal will be to remove the fancyTree js component in favor
of roll-your-own javascript libraries, although, at this point
there is a chance that the entire UX will be replaced with more
modern native javascript functionality.

The interaction between the javascript and the perl server will
be analyzed for correctness and re-designed and optimized as
extensively as needed to arrive at a more consistent and responsive
UX experience across the board.

There is much unstated as of yet in this section, particularly
the fact that the current JS and CSS incorporate many hard learned
lessons about browser interopability, device scaling and usability
on the variious browser platforms and surfaces the app encouters.

There is also likely an important role for browser persistent
storage vis-a-vis the Perl Read-Only requirement.















---- end of redesign.md ----
