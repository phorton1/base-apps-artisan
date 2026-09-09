# Design - Queue, Playlists, and Tracks

This document currently describes hopeful or possible incremental
design ideas.

At this time I am thinking about the following things:

- adding volume (mute, balance, eq) controls
- adding album forward and backwards buttons
- Queue, Tracklist, and Playlist ideas
- explorer text searching

This document will focus on the Queue, Tracklist, and Playlist ideas.


### Note about Device Id as currently implemented

The device ID as currently implemented is really a
Browser ID, inasmuch as multiple instances on the
same physical device, from the same Browser, will
use the same localStorage, and hence have the same
(random) 'device_id'. First, this means that different
browsers on the same device will have different device_ids,
but, more importantly, it means that each of the intances,
from any Browser, will have their own HTML \<audio> element
and effectively be 'different' (and not very persistent)
things.

This is pertintent because my tendency has been to think
that the Server would be able to maintain the Queue for
a given Renderer ... including HTML Renderers, but in reality
this scheme would break down for HTML Renderers, or would
have to be limited by 'convention', i.e. the user really
should only open ONE instance of the UI on a given device,
and should typically use the SAME browser when accessing
the UI.

For sanity, then, I will go with the *convention* that

- the user shall use the HTML Renderer from only one instance
  of the UI on a given device
- different browsers on a given device will be considered different
  HTML Renderers.

with the implicit notion that the user will typically use the same
browser on a given device.


## No More Persistent Playlists, Queue is Flat

- Tracklists are ordered list of Tracks
  - Albums 'have' or 'are' Tracklists
  - Playlists are just Tracklists with their Nominal (original) ordering
- The Queue can be Shuffled and maintains a State

Adding Tracks/Trees to a Queue (at top?, current position, or end)
does NOT resort the tracks.  So a particular Album could be added
to the Queue, in its track order, while the rest of the tracklist
could already be randomly sorted by Track.

This simplifies the whole conceptual approach.
Now there are ONLY flat lists of Tracks involved.



## Implemetation Steps

I created a new_playlists BRANCH in git.

- copied all files that mentioned playlists to /base/apps/artisan_obs
- removed Playlist.pm and remotePlaylist.pm
- reworked localPlaylist.pm to be the only 'playlists' in the system.
- localPlaylists are currently only accessible via Explorer




## iPad (IOS) and Context Menus (added JS 'is_ios' variable)

The idea is that I can now multiple-select a number of Explorer Tracks,
or any branch of the Explorer Tree and add them to the Queue.  The UI
artifice for this is, in all worlds worlds exept the iPad, the Context Menu,
which is always brought up with a right click from a mouse, or a long
press on a touch screen, according to HTML STANDARDS ....
EXCEPT FOR THE STUPID IPAD.

ON EVERYONE ELSE:

- a click on a folder will expand or contract it and show it in the database and page header
- a click on a track will show it in the database
- a long or right click will bring up the context menu
- a double click will play the thing immediately
- multiple selection of Tracks *should* be supportable


ON IPAD:

Maybe the best approach is to simply add a right most column to the
tree and tracklist that has a [...] button to bring up the context menu.
when running on IOS ...


To wit, I added init_utils() to artisan.js and 'is_ios' to utils.js
to be able to have different behaviors specific to the iPad/iPhone.



## NEW JQUERY

Please see jquery.md for details on How I got all new jQuery stuff
so that I could support Multiple Selection in the Tracklist.








---- end of design.md ----
