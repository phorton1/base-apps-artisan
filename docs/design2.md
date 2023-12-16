# Design2

I have GOT to make some progress on this.

- re-implement persistent playlists, sheesh,
  without the old playlit info pane
- renderer pane gets Shuffle OFF ALBUMS TRACKS buttons
- renderer gets a Tracklist that shows the current tracks in the Playlist
  along with the position.  Clicking on an item changes to that position.
- a Playlist can be 'suspended' as before, with items being played 'immediately'.

- Add Play and Add buttons to the Explorer Album Info
- rename Album Info to Folder Info. These will act on Selected Items
- Explorer gets the notion of 'cur_tree' to help
- Selection is handled synchronously as needed, including
  loading child folders and tracks.


The 'Queue' will be a thing managed by the Javascript and
NOT persistent.



## Phase 1

Without UI artifacts, try to implement the Queue in Javascript.





---- end of design2.md ----
