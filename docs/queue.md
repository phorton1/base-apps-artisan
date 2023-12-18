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
from that Library. Note that to save Playlists it will be necessary
to Pause the Renderer after the 0th Add.



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


## Implementation Done

- starts with Explorer UI selection sending Post(/webui/queue/add|play)
  with list of folder or trackids in post_data.
- gets passed via HTTPServer and webUI to Queue::queueCommand(add|play)
  which builds list of tracks and adds them to renderer specific Queue.
- localRenderer modified to play from the queue if any tracks in it.
- Removed the explorer.js code that does recursive loadFolders()

- implement transport next,prev controls on Queue
- X shall stop and clear queue


## To Do

- test/flush out support in remoteArtisan
- remove current way of playing playlists (for a while)
- Playlist Buttons to 'Play' Playlist(s) to Queue
- Playlists have the ability to 'end' now


The next steps kind of have to be completed in a chunk, and will require
reworking the way I currently do playlists.

This begs the question of 'Adding' a playlist to the Queue as opposed to play immediate.
It is tempting to think of Playlists in explorer as the same thing, but they can also
be thought of as initially-ordered lists of Tracks, without state.

In any case, this change will require moving Playlist APIs consistenty to Libraries,
and granting ownership of the Playlists to the Queue.

Will probably want some changes to the webUI Renderer API to indicate
that we are playing from the Queue or a Playlist within the Queue.

- webUI Queue 'Tracklist'
- sort and shuffle Queue verus Playlist (Transport Controls)
- create the Home Renderer UI
- figure out how to do this for HTML Renderers which will
  now include the device_id in their uuid.
- multi-selection on touch devices



## Future

- I *might* want a repeat button on a track, or part of one, if I was learning a song
  but generally 'repeat' is a lame notion and does not semantically fit in with a
  Queue that empties itself.
- Save as Playlist





---- end of queue.md ----
