#  Queues, Selection, and Explorer

A Queue is list of items that are playing, and will play in a
particular Renderer.

Queues are like Playlists in that they can be flat lists of
Tracks, and can be Shuffled.

Unlike Playlists, however, Queues have the following characteristics.

- can contain Tracks from different Libraries
- are maintained in Perl memory rather than in database files.
- can be built from the Explorer UI by selecting and Adding or Playing selections
- use the http POST method to send the selection from the
  UI to the Perl.  The Queue is modfied and sent back to the
  UI via the update command, which then further re-populates
  the Home Queue Tracklist.

In the end I decided that the UI will allow you to switch between
the Queue and a single playling Playlist, with orthogonal transport
controls, including Sorting.


## Todo

- WTF does select scroll the Tracklist?

- clear current_track when Queue is stopped

- library indicator column for Queue Tracklist
  nice to know if it's from a different library

- implement HTML Renderer with new Scheme
- test with (revisit) RemoteArtisan
- double check Update_id and Versions on Playlist Track Advancement
- Remove from Queue button
- touch UI - multiple selection
- Volume Control(s)


## Future

### Save Queue to Playlist

In future incarnations Queues may possibly be able to be saved as
new Playlists to a given Library, filterered to contain only Tracks
from that Library.

For saveable Queues, we will need to NOT delete the entire playlist
directory for localPlaylists when playlists.db goes away, and include
the ability to rebuild the playlists.db record for non-default Playlists
from the named.db file, with the idea that if I change the database
structure I explicitly remove the /plyalists subdirectory.


## Repeat Button?

I *might* want a repeat button on a track, or part of one, if I was learning a song
but generally 'repeat' is a lame notion and does not semantically fit in with a
Queue that empties itself.




---- end of queue.md ----
