# webUI API recap

## Recap of all HTTP Requests having to do with webUI and Renderers

NOT ContentDirectory1 which will remain unchanged.

handled by HTTPServer.pm

- /media/MY_TRACK_ID.MY_TYPE
- /get_art/MY_FOLDER_ID/folder.jpg

handled by webUI.pm

- /webUI/FILENAME.EXT  									- (js|css|gif|png|html|json)
- /webUI/getDevicesHTML/(renderers|libraries)
- /webUI/getDevice/(renderer|library)-UUID
- /webUI/renderer/UUID/COMMAND?PARAMS					- COMMAND and PARAMS passed directly to Renderer
- /webUI/library/PATH?PARAMS							- PATH and PARAMS passed to uiLibrary.pm
- /webUI/update?renderer_uuid=UUID&update_id=UPDATE_ID  - allows for changes to device 'online' state and buttons to appear/disappear

handled by localRenderer

- /webUI/renderer/THIS_UUID/update						- obsolete

- /webUI/renderer/THIS_UUID/stop
- /webUI/renderer/THIS_UUID/play_pause
- /webUI/renderer/THIS_UUID/next
- /webUI/renderer/THIS_UUID/prev
- /webUI/renderer/THIS_UUID/mute?value=0..1				- not implemented yet
- /webUI/renderer/THIS_UUID/loud?value=0..1				- not implemented yet
- /webUI/renderer/THIS_UUID/volume?value=0..100			- not implemented yet
- /webUI/renderer/THIS_UUID/balance?value=-100..+100	- not implemented yet
- /webUI/renderer/THIS_UUID/fade?value= -100..100		- not implemented yet
- /webUI/renderer/THIS_UUID/bassLevel?value=0..100		- not implemented yet
- /webUI/renderer/THIS_UUID/midLevel?value=0..100		- not implemented yet
- /webUI/renderer/THIS_UUID/highLevel?value=0..100		- not implemented yet
- /webUI/renderer/THIS_UUID/seek?position=MILLIS
- /webUI/renderer/THIS_UUID/play_song?library_uuid=UUID&track_id=TRACK_ID
- */webUI/renderer/THIS_UUID/set_playlist?library_uuid=UUID&id=PLAYLIST_ID*
- */webUI/renderer/THIS_UUID/playlist_song?index=PL_INDEX*
- */webUI/renderer/THIS_UUID/shuffle_playlist?shuffle=SHUFFLE_MODE*

handled by uiLibrary.pm

- /webUI/library/LIBRARY_UUID/dir?id=FOLDER_ID
- /webUI/library/LIBRARY_UUID/tracklist?id=FOLDER_ID
- /webUI/library/LIBRARY_UUID/get_track?id=TRACK_ID
- /webUI/library/LIBRARY_UUID/track_metadata?id=TRACK_ID
- /webUI/library/LIBRARY_UUID/folder_metadata?id=TRACK_ID
- /webUI/library/LIBRARY_UUID/get_track?id=TRACK_ID
- /webUI/library/LIBRARY_UUID/get_id_path?id=TRACK_ID
- */webUI/library/LIBRARY_UUID/get_playlists?renderer_uuid=UUID*
- */webUI/library/LIBRARY_UUID/get_playlist?renderer_uuid=UUID&id=PLAYLIST_ID*
- */webUI/library/LIBRARY_UUID/get_playlist_track?renderer_uuid=UUID&id=PLAYLIST_ID&mode=PL_INDEX_MODE&index=PL_INDEX*
- */webUI/library/LIBRARY_UUID/shuffle_playlist?renderer_uuid=UUID&id=PLAYLIST_ID&shuffle=SHUFFLE_MODE*

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


---- end of webUI_API.md ----
