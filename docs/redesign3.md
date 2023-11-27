# Redesign3

## Recap of all HTTP Requests having to do with webUI and Renderers

NOT ContentDirectory1 which will remain unchanged.



handled by HTTPServer.pm

- /media/MY_TRACK_ID.MY_TYPE
- /get_art/MY_FOLDER_ID/folder.jpg

handled by webUI.pm

- /webui/FILENAME.EXT  									- (js|css|gif|png|html|json)
- /webui/getDevicesHTML/(renderers|libraries)
- /webui/getDevice/(renderer|library)-UUID
- /webui/renderer/UUID/COMMAND?PARAMS					- COMMAND and PARAMS passed directly to Renderer
- /webui/library/PATH?PARAMS							- PATH and PARAMS passed to uiLibrary.pm

handled by localRenderer

- /webui/renderer/THIS_UUID/update
- /webui/renderer/THIS_UUID/stop
- /webui/renderer/THIS_UUID/play_pause
- /webui/renderer/THIS_UUID/next
- /webui/renderer/THIS_UUID/prev
- /webui/renderer/THIS_UUID/mute?value=0..1				- not implemented yet
- /webui/renderer/THIS_UUID/loud?value=0..1				- not implemented yet
- /webui/renderer/THIS_UUID/volume?value=0..100			- not implemented yet
- /webui/renderer/THIS_UUID/balance?value=-100..+100	- not implemented yet
- /webui/renderer/THIS_UUID/fade?value= -100..100		- not implemented yet
- /webui/renderer/THIS_UUID/bassLevel?value=0..100		- not implemented yet
- /webui/renderer/THIS_UUID/midLevel?value=0..100		- not implemented yet
- /webui/renderer/THIS_UUID/highLevel?value=0..100		- not implemented yet
- /webui/renderer/THIS_UUID/seek?position=MILLIS
- /webui/renderer/THIS_UUID/play_song?library_uuid=UUID&track_id=TRACK_ID
- */webui/renderer/THIS_UUID/set_playlist?library_uuid=UUID&id=PLAYLIST_ID*
- */webui/renderer/THIS_UUID/playlist_song?index=PL_INDEX*
- */webui/renderer/THIS_UUID/shuffle_playlist?shuffle=SHUFFLE_MODE*

handled by uiLibrary.pm

- /webui/library/LIBRARY_UUID/dir?id=FOLDER_ID
- /webui/library/LIBRARY_UUID/tracklist?id=FOLDER_ID
- /webui/library/LIBRARY_UUID/get_track?id=TRACK_ID
- /webui/library/LIBRARY_UUID/track_metadata?id=TRACK_ID
- /webui/library/LIBRARY_UUID/folder_metadata?id=TRACK_ID
- /webui/library/LIBRARY_UUID/get_track?id=TRACK_ID
- /webui/library/LIBRARY_UUID/get_id_path?id=TRACK_ID
- */webui/library/LIBRARY_UUID/get_playlists?renderer_uuid=UUID*
- */webui/library/LIBRARY_UUID/get_playlist?renderer_uuid=UUID&id=PLAYLIST_ID*
- */webui/library/LIBRARY_UUID/get_playlist_track?renderer_uuid=UUID&id=PLAYLIST_ID&mode=PL_INDEX_MODE&index=PL_INDEX*
- */webui/library/LIBRARY_UUID/shuffle_playlist?renderer_uuid=UUID&id=PLAYLIST_ID&shuffle=SHUFFLE_MODE*

Library and Playlist Routines to support uiLibrary.pm
corresponding to above calls from uiLibrary

- $library->getSubItems('folders', $id)
- $library->getSubItems('tracks', $id)
- $library->getTrack($id)
- $library->getTrackMetadata($id)
- $library->getTrack($id)
- *$library->getPlaylists($renderer_uuid)*
- *$library->getPlaylist($renderer_uuid,$id)*
  - *$playlist->getPlaylistTrack($renderer_uuid,$$mode,$index)*
  - *$playlist->sortPlaylist($renderer_uuid,$shuffle)*


I think this backwards revision starts with removing the $renderer_uuid from the library playlist calls
and (?) versioning the playlists.   Renderer::update() would then re-get the playlist on every request,
(and/or keep a version number of their own) and know to 're-start' the playlist if anyone else changed it.

So, effectively, for example, playing a playlist in the HTML Renderer on one machine and the localRenderer
simultaneously, if either one switched sorted, it makes sense to have them both change.  But the notion
that Renderers advance tracks is tricky.     Youve got two Renderers playing the same thing with a race
condition ... either one could advance the track_index, or be in the process of doing so.  So either/both
might get a version increment, and possibly two advances.

So, the renderers pass the Version they are using, and only one of them gets to advance it. An
advance with the wrong Version would be ignored (?) and the result would be that renderer would
get a changed version.  I almost have to implement this just to see how it would work.


## Changes

- eliminate the whole 'copy playlists' scheme from databases
- remove the renderer_uuid from the playlist call chain
- sort the records into the named_db files

- add the Version to the playlist call chain


FUCKING GO FOR IT.




























## BLAH

- Playlists are per Library
- Playlists can be sorted and shuffled and have a persistent track_index
- Any device that plays a Playlist advances the index and/or changes the sort order at it's will
- Any other devices currently playing that same Playlist will get notified of the changes
- The named.db file gets the sorted records for persistency across devices.


- A Renderer has (may have) a Playlist from a particular library
- The playlist state may change out from under the Renderer by another Renderer
- Therefore they must be versioned.

This goes to the notion of the UI accepting generalized JSON and acting accordingly.

It also goes to the notion of knowing whether or not a library is 'alive'.

This change should be initially do-able without changing the webUI API.

It's a big change (again).

How does another renderer know when we have seeked within a song within a playlist.

That's a characteristic of a Renderer, not a Library.


ARGHHH



// End of redesign3.md
