# Design (Issues - Ideas)

This document currently describes hopeful or possible incremental
design ideas.  Later it will become an entry point into the overall
design of Artisan Perl.

In this iteration of the design I am thinking about the following things:

- adding volume (mute, balance, eq) controls
- adding album forward and backwards buttons
- elusive and complicated Queue, Tracklist, and Playlist ideas
- explorer text searching



## Overview and Limitations

As it stands right now Artisan can play Playlists by clicking
on a Playlizt Button or Single songs by double clicking on a
Track in the Tracklist in Explorer.  There is currently a
non-functional Context Menu hooked up to the Explorer
Tracklist for individual Tracks that does not work.

The general idea is that I want to implement a Queue
which shows what the current Renderer is playing, and
that you will be able to add Playlists, multiple-selected
Tracks, or Folder (trees) to it from the Explorer.
Eventually, when the text-search is implemented, you
will be able, for example, to search for "Sugar Magnolia",
and add multiple versions of the song to the Queue.

The idea is complicated particularly by the notion that
a Playlist is itself (currently) a flat list of Tracks
and has its own peristent state (Shuffle and Index).

It is also desirable, and a complicating factor, to
factor the implementation such that objects and UI
elements are re-used.  For example a Playlist is
really very similar to what a Queue would be, and
both are similar to the Tracklist currently shown
in Explorer.

Note that when multiple UI instances are accessing
the Artisan (local) Renderer, that would be operating
on the same 'Queue', but that HTML Renderers are
unique not only to the Device that is showing the UI,
but to the instance of it.

### Device Id as currently implemented

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
this scheme would break down for HTML Rendeerers, or would
have to be limited by 'convention', i.e. the user really
should only open ONE instance of the UI on a given device,
and should typically use the SAME browser when accessing
the UI.

This makes the potential implementation even more complicated.

For sanity, then, I will go with the *convention* that

- the user shall open only one instance of the UI on a given device
- different browsers on a given device will be considered different
  HTML Renderers.

with the implicit notion that the user will typically use the same
browser on a given device.


## Queue

- there will be a Queue for each Renderer.
- the Queue will show what IS playing, what WILL play and possibly/hopefully what HAS played.
- the Queue will *at least* hold Tracks and one Playlist
- the user can Navigate through the Queue and the Playlists within it seamlessly
- the user can add multiple-selected Explorer Tracks to the Queue
- the user can add whold branches of the Explorer Tree to the Queue
- the Queue can be Shuffled by None, Track or Album, just like a playlist

One idea is to implement a 'flat' Queue that incorporates a 'source' member
to accomodate tracks from Playlists.  But this belies the ability to treat
a Playlist's state as persistent unto itself.

The other idea is that a Playlist within a Queue is treated as an atomic
item, and, by the way, that Playlists can 'end' when they get to the last
Track in them.  So, in this case, Shuffling the Queue would move the entire
Playlist within the Queue WITHOUT changing the state of the Playlist, in
other words, without changing the Shuffle State state and current Track Index
of the Playlist.

I would like to just 'jump in' and start by re-factoring the webUI JS again,
but I probably should 'think this through' before proceeding to change anything.


## Advanced Ideas - Creating Playlists

It is so very tempting and desirable to think about the ability to create
Playlists from the UI, i.e. to be able to 'Save' a Queue as a Playlist.
This implies recursive Playlists that can contain other Playlists, an
idea that *seems* to be supported by the DLNA standards, but which has
shown to *definitely **not** work in WMP*.

To wit, some of this design effort focuses on the DLNA ContentDirectory's
ability the CREATE playlists.  For what it is worth, WMP does NOT seem
to advertise a "CreateObject" action as being available, so for the
time being any such ideas will be specific to my localLibraries.

This would probably mean there is some notable difference between
my 'standard' Playlists, created via Queries by databaseMain.pm,
and 'user generated' Playlists that might be created using explicit
Tracklists.



## Design Attempt

Highest Level Ideas

- The first attempt will NOT allow for the creation of Playlists.
- The Queue itself will be persistent per Renderer and the closest
  thing to user created Playlist.

Lower Level Ideas

- a Tracklist is a list of Tracks which can include references to Playlists
- a Playlist is a Tracklist that does not include other Playlists
- a Queue is a Tracklist that can contain Playlists
- Queues and Playlists have Shuffle States and current Indexes
- A Renderer will get a Queue where it currently has a Playlist
- A Queue defers Navigation to the Playlist under certain conditions.


One idea here is to present the Queue as a two level Tree
where Playlists can be Expanded and Contracted to show
their internal tracks and current state so that the Queue
is able to be Navigated across Playlists and Added Tracks
seemlessly.

Example

	  Source	Track Title			Album			TrackNum	Artist	Genre

	- Track		Title				Album_Title		NN
	- Track		Title				Album_Title		NN
	- Playlist  Name				Shuffle_Mode	Current_Index
	-			Title				Album_Title		Orig_Position
	-			Title				Album_Title		Orig_Position
	-			Title				Album_Title		Orig_Position
	-			Title				Album_Title		Orig_Position
	-			Title				Album_Title		Orig_Position
	-			Title				Album_Title		Orig_Position
	- Track		Title				Album_Title		NN
	- Track		Title				Album_Title		NN
	- Track		Title				Album_Title		NN
	- Playlist  Name				Shuffle_Mode	Current_Index
	-			Title				Album_Title		Orig_Position
	-			Title				Album_Title		Orig_Position
	-			Title				Album_Title		Orig_Position
	-			Title				Album_Title		Orig_Position
	-			Title				Album_Title		Orig_Position
	-			Title				Album_Title		Orig_Position

In this example, the >> forward button would advance through the
sourced Tracks, then in the Playlist it would jump to the Current
Index and advance though those.

This 'breaks' the current concept of a Playlist which 'wraps'
after advancing past the end, so the Queue would have to maintain
a state indicating that IT played the last track in the Playlist
and that the Playlist had properly Ended.

Or we would have to do away with the idea that a Playlist has
a persistent state of its own across all Renderers.

I am tending to think that in this conceptualization a Playlist
itself no longer maintains state, but rather it is the Renderer
Queue that maintains the state.    Playlists would get added to
the Queue as a list of flat tracks, and the tracks and albums
within it would be treated orthogonally with regards to sorting.

That would essentially eliminate the idea of the Playlist buttons,
or more properly, would turn them into mere shortcuts to going
to the Explorer and adding the same Playlist to the Queue.


## Design Stab 2

- Tracklists are ordered list of Tracks
  - Albums 'have' or 'are' Tracklists
  - Playlists are just Tracklists with their Nominal (original) ordering
- The Queue can be Shuffled and maintains a State

I'm liking this approach.

Adding Tracks/Trees to a Queue (at top?, current position, or end)
does NOT resort the tracks.  So a particular Album could be added
to the Queue, in its track order, while the rest of the tracklist
could already be randomly sorted by Track.

This simplifies the whole conceptual approach.
Now there are ONLY flat lists of Tracks involved.


### Implementation Approach

- Likely a playlists.db file is no longer required
- named.db files ARE the playlists, and they are never sorted
- all the functionality for Sorting and Indexing now resides
  in a single Queue per Renderer.

This supports the idea of persistent state to a degree,
allowing all instances that access the localRenderer
to 'see' the same state and not repeat, BUT no longer
means that I can 'listen to all dead tunes without repeating',
UNLESS I never resort the Renderer's Queue. It also means that
each time I decide to 'switch' playlists, I have to resort them
if I want them random.

But then this facilitates much more consistent navigation
and presentation, simplifying the whole thing.

Its a big step.


It will likely also facilitate the idea of creating
Playlists from the UI, which, in turn, sort of 're-implements'
the idea of maintaining a consistent persistent order
to listenting to Playlists.

- Playlist Buttons are now just shortcuts to adding
  the Tracks from a Playlist to the Queue which could
  be done exactly the same via Explorer.
- In fact, in this regard, I might want to GET RID
  of PLAYlIST BUTTONS ...

The Queue itself is 'just another playlist', and
could be saved and restored.

Man, I almost have to implement this to see how it would work.

I suspect I go back to the implementation that Playlists
are made of full Tracks duplicated from the root database.


## Carrying On

- Playlists are Just Containers for Tracks
- The named.db files contain copies of the Track Records from the main database
- Playlists no longer exist as separate entities in remoteLibraries. In other
  words, Playlist Buttons don't show up anymore and the Queue is ALWAYS built
  from the Explorer.

I almost want to approach this as a BRANCH iin the current Repo so that
I can back out of it if I want.  Hmmmmm.....

Getting my head around it.

## New Repo Branch 'new_playlists'

Cannot fork my own repo.
Not creating a whole new repo.

- Did a checkin and push of 'master' branch
- Deleted some old branches from GitHub
- Saved off and Re-cloned my artisan from GitHub
- Added a branch new_playlists via the normal gitUI.
- Added the new_playlists branch to my git_repositories.tst
- Manually added the new_playlist branch to artisan/.git/config

my gitUI now appears to work.  I *think* I am on new branch
and that I can go back to 'master' if I need to, and that I will
someday, somehow, be able to Merge this back into the master branch.


## Ripped out old Playlists and created new ones

- copied all files that mentioned playlists to /base/apps/artisan_obs
- removed Playlist.pm and remotePlaylist.pm
- reworked localPlaylist.pm to be the only 'playlists' in the system.

I am checking this in.

I am now re-confronted with the fact that there's no good way to do
a context menu on the stupid iPad, which is at the core of this
re-design.

The idea is that I can now multiple-select a number of Explorer Tracks,
or any branch of the Explorer Tree and add them to the Queue.  The UI
artifice for this, in al worlds worlds exept the iPad, the Context Menu,
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



## jquery Experiments with Multiple Selection (in Tracklist)

Once again I find myself in another digression.

fancyTree multiple selection did not work as advertised.
Particularly there is no "multi" extension in my (old) version
of fancyTree.  Some testing showed that the current versions
of jquery stuff basically work and support "multi" extension
and multiple selection in the Tracklist, so I am updating
to the latest versions of all jquery related JS.

The underlying collections of jquery related 'sources' files
can now be found in my /zip/js folder

- /zip/js/_artisan_js_old
- /zip/js/_artisan_js_new

I am/was using old versions of everything, dating back 8 or more years:

- jquery 1.11.1
- jquery-ui 1.11.2
- jquery-layout 1.4.3
- jquery.fancytree 2.6.0

and a few other one-of-a-kind files:

- jquery.layout.resizeaneAccordians (from callbacks folder of jquery-layout 1.4.3)
- jquery.touchSwipe - from https://github.com/mattbryson/TouchSwipe-Jquery-Plugin
- jquery.ui-contextmenu - from https://github.com/mar10/jquery-ui-contextmenu
- jquery.touch-punch - unversioned single repo at https://github.com/furf/jquery-ui-touch-punch


### _artisan_js_new Versions and Notes

Here's what I found as the current, latest available sources on 2023-12-11.
These files are downloaded to _artisan_js_new/sources before unzipping or
re-organizing:

- [jquery](https://jquery.com/) 3.7.1 released 2023-08-28
  - downloaded regular and min versioned JS files via browser from
    first two links on https://jquery.com/download/
  - [github source](https://github.com/jquery/jquery)
- [jquery-ui](https://jqueryui.com/) 1.13.2, released 2023-07-14
  - says it is compatible with jquery upto 3.6
  - downloaded https://jqueryui.com/resources/download/jquery-ui-1.13.2.zip
    which contains unversioned regular, min, and css files
  - [github source](https://github.com/jquery/jquery-ui)
- [jquery layout](https://plugins.jquery.com/layout) 1.4.3, released 2014-09-07
  - same version I was already using
  - download link returns layout_master.zip which contains unversioned
    regular and min js files under the source/stable folder
  - [github source](https://github.com/allpro/layout)
- [jquery.fancytree](https://github.com/mar10/fancytree) 2.38.3, released 2023-02-01
  - downloaded 2.38.3 zip from the 'releases' link on the github site
- [jquery.touch-punch](https://github.com/furf/jquery-ui-touch-punch) - unversioned
  - single repo at https://github.com/furf/jquery-ui-touch-punch
  - downloaded entire repos as jquery-ui-touch-punch-master.zip file
- [jquery.touchSwipe](https://github.com/mattbryson/TouchSwipe-Jquery-Plugin) 1.6, from 2018-09-17
  - version implied from github readme
  - downloaded TouchSwipe-Jquery-Plugin-master.zip
  - small doc appears at http://labs.rampinteractive.co.uk/touchSwipe/demos/index.html
- [jquery.ui-contextmenu](https://github.com/mar10/jquery-ui-contextmenu) 1.18.1, from 2017-08-28
  - downloaded jquery-ui-contextmenu-1.18.1 from releases link on github site


That leaves me with the following files in _artisan_js_new/sources


- jquery-3.7.1.js
- jquery-3.7.1.min.js
- jquery-3.7.1.min.map
- jquery-ui-1.13.2.zip
- layout-master.zip
- fancytree-2.38.3.zip
- jquery-ui-touch-punch-master.zip
- TouchSwipe-Jquery-Plugin-master.zip
- jquery-ui-contextmenu-1.18.1.zip

I then built a 'new' version of the /webui_jquery folder from that stuff.

- jquery-3.7.1.js - copied bare file
- jquery-3.7.1.min.js - copied bare file
- jquery-3.7.1.min.map - copied bare file
- subfolder jquery-ui-1.13.2 - from zip file
- subfolder layout-1.4.3 - copied and versioned from 'stable' folder from zip file
- subfolder fancytree-2.38.3 - copied and versioned from 'dist' folder from zip file
- jquery.ui.touch-punch.js - copied unversioned file from root of zip file
- jquery.ui.touch-punch.min.js - copied unversioned file from root of zip file
- jquery.touchSwipe-1.6.js - copied and versioned from root folder from zip file
- jquery.touchSwipe-1.6.min.js - copied and versioned from root folder from zip file
- jquery.ui-contextmenu-1.18.1.js - copied and versioned from root folder from zip file
- jquery.ui-contextmenu.min-1.18.1.js - copied and versioned from root folder from zip file
- jquery.ui-contextmenu.min-1.18.1.js.map - copied and versioned from root folder from zip file


And I am **finally** ready to try modifying artisan.html to call the
new JS.  I will start by

- renaming webui/jquery to webui/jquery_old
- inserting the new webui/jquery folder
- modifying artisan.html to make it easier to change whole group of includes
- create a whole 'new' section of includes

Also note that I have
- temp modification to webUI.pm to NOT deliver MIN files
- sitting on temp mods to explorer.js and explorer.css to highlight selections

This *should* enable me then to track down the needed CSS changes,
and once I have those, and am satisfied, I can remove the old
stuff and check it in.


## Jquery Problems

After correcting the following two problems, the UI came up,
albeit with pretty major CSS problems.


### (1) TypeError: v.selector is undefined

When I got it all hooked up, I ran into this problem:

	http://10.237.50.101:8091/webui/jquery/layout-1.4.3/jquery.layout.js:123: TypeError: v.selector is undefined

A search on the web found a page at

	https://stackoverflow.com/questions/39513448/jquery-layout-throws-error-because-n-selector-is-undefined

that said the following

	For jquery.layout 1.4.4 just comment row 1831: sC.selector = $N.selector.split(".slice")[0];
	and all works normally (tested on jQuery v3.3.1)

So I am temporarily making that change. I must remember to unmake it,
then checkin the virgin jquery layout, then make the change on my own.

**THIS CHANGE MUST ALSO BE MADE TO THE MINIFIED JS**


### (2) Error: ui-contextmenu: Missing required option `delegate`.

Temporarily removing context menus from my code (explorer.js),
especially as I will be entirely changing the way I call
context menus, using on('context_menu') rather than the
context_menu.js extension ...


## Testing Multiple Selection

Hmmmm ... I thought it just worked in my earlier tests with
just the added explorer.css styles

	.fancytree-selected > td,
	.fancytree-partsel > td
	{
		background: green;
		background-color: #74992e !important;
	}

But I'm not getting a selected status on these.

### Try1 - add explicit selection mode to Tracklist

No joy.

### Try2 - add "multi" extension to Tracklist

It works.


## Noted problems before checkin

- The Renderer and Library Buttons are styled incorrectly, with checkboxes, in center
- The top menu Home/Explorer/Full Screen buttons are styled incorrectly, light grey with tiny print
- The Renderer Transport buttons are likewise styled incorrectly
- Explorer tree has a node that says "No Data" at top


# Checking in

- Undo the change to jquery.layout.js for TypeError: v.selector is undefined
-






---- end of design.md ----
