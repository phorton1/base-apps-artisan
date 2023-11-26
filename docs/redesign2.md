# Redesign1

I would like to

- factor the Perl and webUI code better
- introduce Tracklist, from which Queue and existing Playlist is derived.

## Functional Issues and Changes

The main issues seem to revolve around the following:

- I want to be able to play through a sorted-random-by-album playlist
  on multiple different devices sequentially so that I don't hear the
  same albums/song twice and yet I hear all of them once.
- I want to be able to select anything from the explorer tree and
  play it immediately (interrupting the current playlist), or
  by adding it the 'queue' to be played afterwards

And I was thinking about making that happen by adding a Queue thing

- each Renderer to have it's own Queue which is persistent
  between invocations.
- Ability to save a Queue as a new Playlist for a given library

This implies a whole 'Playlist Management UI.  Playlists with Queries
(can be generated from my explorer approach) but Playlists with Items
are all we get from remoteLibraries (WMP).  So you kind of have this
query-vs-list based differentiation of playists.  Then you need all
this functionality for Playlist Managment

- Save Queue as Playlist
- Edit Playlist
- Rename Playlist
- Delete Playlist
- Save as New Playlist

And gets more complicated if you note that

- Playlists can contain references to tracks in other libraries (WMP does this)
- WMP does not publish ENTRIES in playlists that reference other libraries.
- WMP does not support nested containers but the DLNA
  spec implies this should be do-able.

Which then leads to cross-library playlist manipulation.  DLNA supports writing
things, yikes, or it could be just for 'my' playists/queues.


## Presentation changes

Then I would like to present this via the UI in a way somewhat similar to WMP,
where you can see the list of Tracks in the Queue, and sort and shuffle them.
The 'playlist' info thing is really only specific to my stored playlists, which
are like stored, pre-sorted Queues, and theoretically I would then only Sort
the playlists occasionally, somehow, from the Explorer UI ?!?

While at the same time factoring the webUI code (having already factored the
Perl in my dreams).



## GRRRR Implementation Goals

- UI to use Json (no HTML) exclusively
- Tracklist base class - represented in Perl and UI
- Playlist and new Queue - things represented orthogonaly in Perl and UI


## GRRRR Implementation details

- go back to sorting playlists to namedb.files

This means that anyone who sorts a playlist will
affect all users that are using that playlist.
Have to figure out how UI knows whether or not
it needs to re 'Play' the playlist, making it
the sole thing in the Queue, as, for example,
the next time the UI asks for a track in the PL,
it will get a new sort order or completely different
set of tracks.


## Continuing

I don't think a Renderer Queue should be persistent from invocation to invocation.
When you invoke a renderer, basically you START playing things from it.

What does 'invoke' mean?    If you 'attach' to a Renderer that is playing
stuff, you should see it's current state.  Remember that Renderers can
continue playing with no UI attached.

- One idea was a UI shortcut that when you Play a playlist, it replaces
  the Queue for the Renderer.  This *may* be consistent.  Stop, Pause,
  Clear, etc all seem to make sense per-Renderer across devices.

- Since each HTML Renderer gets its own device_id, this means that
  if you play the items on the HTML Renderer, each gets its own
  Queue, and you cannot do the 'playlist-thru-random-albums' thing
  sequentially on different devices.

I think there's a cross-dependency between these ideas.

- sequentially playing through a sorted playlist on multiple devices
- each renderer having its own Queue

Ideas which *would* work if each Renderer had s simple Playlist, and
those were consistently owned by a single Library, and sorted for
all Renderers.  As if the 'Queue' has a REFERENCE to a playlist,
and if it happens to be playing, it gets the LATEST state from the
Library, or next time it plays a new Playlist, it uses the same
normalized Library playlist.

Also there are real issues to the whole idea of being able to modify
the set of Playlists in a Library (via the UI in a more general manner).
There is no 'notification' mechanism in the UI.  This *might* be solvable
with a thourough revisit and complete change to Json where the Perl could
send a complicated record that was parsed for everything from the Device
Lists, list of Playlists, individual Playlists, and then, of course,
the Explorer Tree, which should *already* be modified to really lazyLoad
things that don't fit on the screen.  It gets wonky with remoteLibraries
with 1000's of items in a container and tracking changes to external
libraries in my code.

Generaly I assume that I will stop and restart the server, doing
a disk scan, if I change anything in the mp3's directory.   I would
now need a similar process (in the background, on a thread) to
update any remoteLibraries (that are online, and/or when referenced).


## So I have these few biggest ideas

- Get the webUI working well on the iPad and phones
- Have reasonable and useful behaviors on all combinations of Renderers and Libraries,
  especially with regards to Playlists and selecting things to play via the Explorer.
- Improve the Presentation with things like Appropriately Sized Renderers, etc.


And I can't even get to a place where

- there is a single <body> with the appMenu and 'pages' that fit within that

The code is really a mess.  JQuery/UI/Layout are bastards.   Surely there's
a clean way to do it all with Json.  Maybe I should start there.


### Where the Perl currently returns HTML to the webUI

- webUI.pm - homeMenu Device buttons
- uiLibrary.pm - homeMenu Playlist buttons
- Library.pm - uses a smidgen of HTML within Json to the explorerDetails 'errors' section
  which is only called by localLibrary for the 'medialFileErrors' in the UI














// End of redesign2.md
