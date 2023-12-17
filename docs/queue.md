#  Queues, Selection, and Explorer

A Queue is list of items that are playing, and will play in a
particular Renderer.

Queues are like Playlists in that they can be flat lists of
Tracks, and can be Shuffled.

Unlike Playlists, however, Queues have the following characteristics.

- the 0th item in the list is the currently playing item
- as items play they are removed from the Queue
- can contain Tracks from different Libraries
- can contain Playlists
- are maintained in Perl memory rather than in database files.
- can be built from the Explorer UI by selecting and Adding or Playing selections


In this paradigm Playlists are 'Played' when a Home Menu Playlist Button is
pressed by placed at the selected Playlist at the top of the Queue

In future incarnations Queues may possibly be able to be saved as
new Playlists to a given Library, filterered to contain only Tracks
from that Library.



## Observations

- this design approach obviates the necessity that the UI loads
  children folders or Tracklists, so the need for the explorer.js
  code that does Recursive track loading is obviated and that should
  be simplified.
- for saveable Queues, we need to NOT delete the entire playlist directory
  for localPlaylists when playlists.db goes away, and include the ability
  to rebuild the playlists.db record for non-default Playlists from the
  named.db file, with the idea that if I change the database structure I
  explicitly remove the /plyalists subdirectory.
- There is now a notion of a Playlist 'ending' when it has played all
  of its tracks. Sorting a Playlists resets ITS pointer to ITS top.
- There will need to be a UI command to Clear the Queue
- Navigating do an item in the Queue effectivly shifts all of the
  items above the new selection point off of the Queue.
- the UI List (fancytree table) showing the Queue will allow Playlists
  to be expanded and contracted, and show ITS Shuffle State, commands,
  and current Track Index.
- Queues will use the http POST method to send the selection from the
  UI to the Perl.  The Queue will be modfied and sent back to the
  UI via the update command.  Q
- Queues will be Versioned like Playlists so that only one UI at
  a time can add items to the list.  There will be a visible user
  error in the unlikely event that a UI doesn't have the current
  version of the Queue (for 1/2 second) when they add their selection
  to the Queue.


## Implementation Plan

The Queue will be initially be somewhat intimately tied to the
localRenderer.

- DONT start by removing Playlists ability to be played
- DONT start by removing recursive explorer.js directory loading

Initial implementation will overload what the renderer track
metadata to allow the Renderer to show the correct item in the
Queue.

- build the feature from the Explorer UI selection down to the
  localRenderer first, so that the localRenderer can play selected
  items and shift them out of the Queue as they are played.
- Add new Perl File Queue.pm which will initially contain both the
  HTTP handler AND the queue implementation.
- possibly factor uiQueue.pm out of Queue.pm
- Remove the explorer.js code that does recursive loadFolders()

CHECKIN

- figure out how to do this for HTML Renderers which will
  now include the device_id in their uuid.

CHECKIN

- add the ability to Play a Playlist

CHECKIN

- create the Home Renderer UI


## HTTP Command Syntax

	/webui/queue/add|play

Post Params

	renderer_uuid
	library_uuid

	tracks = comma delimited list of track ids
	folders = comma delimited list of folder ids
	playlist = a playlist id

Note that if a parent and child folder are both in
the selection, the child folder will be filtered
out so that only the parent folder is actually
enqueued.











---- end of queue.md ----
