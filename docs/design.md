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

Can I, should I, fork my own repo?
Should I create a whole new repo?
This will be exceedingly difficult to test if I don't, inasmuch
as I use Push to get things to the other machine.


I am going to try a checkin, push, and creating a new branch.

How will my gitUI.pm work?



























---- end of design.md ----
