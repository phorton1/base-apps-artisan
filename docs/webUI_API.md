# webUI API recap

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
- /webui/update?renderer_uuid=UUID&update_id=UPDATE_ID  - allows for changes to device 'online' state and buttons to appear/disappear

handled by localRenderer

- /webui/renderer/THIS_UUID/update						- obsolete

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


---- end of webUI_API.md ----
