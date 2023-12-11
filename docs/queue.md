# New Architecture - Queues, Playlists, and Tracklists

This is the **new_playlists** branch of the base-apps-artisan repo.

This is a **major change** to the architecture.

- get rid of **playlists.db** file(s)
- get rid of **Playlist Buttons**
- Playlists are not given any special treatment in remoteLibraries
  - they are just like Albums - merely lists of Tracks
- localPlaylists are JUST named.db file that contain copies
  of Track records from the main database.
- Renderers now have a Queue where they used to have Playlists
- The Renderer has the Shuffle and Index States
- *Things* from Explorer can be added to the Queue
  - multiple selected Tracks
  - any branch of the Explorer Tree via SQL query

The use of major screen real estate to select Renderer and Library is overkill.
The UI prefs have never been re-utilized.

This will initially be implemented only for the localRenderer,
This will eventually be implemented for HTML Renderers.

- I will do the work on the (local) Perl objects first
- I will then incorporte those changes into the Javascript
- It will take at least several days to get the UI working again.
- There will be vestigial issues with remoteLibraries, particularly
  around the WMP Servers finicky need to be accessed in order to work.


## Initial Architectural Changes

There are now ONLY localPlaylists.
These probably get wrapped into Playlists.pm, possibly with
PlaylistsInit.pm as a separate file.

I *think* that the named.db files have to be named by ID
for the system to work, or, possibly the ID of a playlist
IS it's name.  Yeah, that might be better.

I think I will start by removing all references to Playlists
from the Repo (saved to an alternate location) and getting
the UI to work with the double-click play a song ONLY and
then rebuild the code from there.














---- end of queue.md ----
