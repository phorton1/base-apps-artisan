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


## Changes

This backwards revision starts with removing the $renderer_uuid from the library playlist calls.

- eliminate the whole 'copy playlists' scheme from databases
- remove the renderer_uuid from the playlist call chain
- sort the records into the named_db files


## Synchronization of Playlist across multiple Renderers

As long as I use different Renderers sequentially (not at the same time) on a Playlist,
it would work as expected.  However, when Renderers are responsible for advancing the
Track, the situation occurs where, with two Renderers playing Track N.

- At the end of Track N - Renderer A advances to Track N+1
- At the end of Track N - Renderer B advances to Track N+2

The solution is to Version the Playlists, and allow only one Renderer to
advance the track.

*getPlaylistTrack($version,$PLAYLIST_RELATIVE,0)*

So, when both Renderer's start, they get the same Version 'V1'

- Renderer A Playing Track N on Verion V1
- Renderer B Playing Track N on Verion V1

- Renderer A ends first and requests getPlayListTrack(V1,RELATIVE,1)
  This advances the playlist version to V2 and returns Track N+1

- When Renderer B gets to the point where it wants to advance the index,
  it calls getPlaylistTrack(), but since it does not own the current
  version, the existing playlist, with no changes, is returned
  so it starts playing V2 Track N+1


## Implementation

- We keep the current trackId in the playlists.db as well as the version number,
  starting with creation, and updated when sorting.  It may be a blank.

- sortPlaylist() always bumps the Version number, resets the track
  index to 1, and sets the initial trackId.

- getPlaylistTrack() will take a Version as a parameter.  It will
  not do anything if the version does not match the database, but
  merely will return the current Versioned playlist at its current
  index with its current trackId.

- sortPlaylist() and getPlaylistTrack() now return full playlists
  incuding the track_id and version. call, so that should just work.

This causes the Renderers to synchronize on the Playlist at each
transition where it gets a new song to play.

I had initially thought that I would make update() re-get the playlist
each second, and notice when the version changed, and try to make them
simultaneously react to sorts and index changes, but it seems like completely
reasonable behavior for the the 2nd renderer to just kind of 'catch' up
to the first one.  It works ok in practice.


## Fixed Device/Browser Characteristics

All Devices

- cookies(true)

All Mobile Devices

- WITH_SWIPE(true)

Firefox on Laptop (fixed)

- WITH_SWIPE(false) with explicit set to true for testing
- platform(Win32)
- appVersion(5.0 (Windows))
- ua(Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0)



Chrome on Samsung Galaxy S21

- platform(Linux armv81)
- appVersion(5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36)
- ua(Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36)

Chrome on iPad

- platform(MacIntel)
- appVersion(5.0 (Macintosh; Intel Mac OS X 10_13_5) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/118 Version/11.1.1 Safari/605.1.15)
- ua(Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_5) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/118 Version/11.1.1 Safari/605.1.15)

Firefox on iPad

-platform(MacIntel)
-appVersion(5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15)
-ua(Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15)

Safari on iPad

- platform(MacIntel)
- appVersion(5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1.1 Safari/605.1.15)
- ua(Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1.1 Safari/605.1.15)


The platform/ua/appVersion all appear to overlap.  I'm not sure how much useful information
can be derived from these.




## Device Scaling / Orientation Issues

I notice that the screen width and height swap per orientation on android,
but fixed on the ipad.

I notice that a 'pixel' is signifcantly smaller on my Android phone,
and a somewhat smaller on the iPad.

Laptop (fixed with var sized window)

- orientation(landscape-primary)	screen(1920,1080) iwindow(936,476) owindow(948,554) body(936,0)

Note the body height of zero?!?


Chrome on Android

-orientation(landscape-primary)		screen(854,384) iwindow(779,304) owindow(779,304) body(779,304)
-orientation(portrait-primary)		screen(384,854) iwindow(384,723) owindow(384,723) body(384,723)

definitely had an anomolous orientation(portrait-primary) screen(384,854) iwindow(384,1350) owindow(384,1350) body(384,1350)
on the Android-Chrome


Chrome on iPad

-orientation(landscape-primary)		screen(834,1112) iwindow(1112,707) owindow(1112,706) body(1112,707)
-orientation(portrait-primary)		screen(834,1112) iwindow(834,985)  owindow(834,984) body(834,985)

Firefox on iPad

-orientation(landscape-primary)		screen(834,1112) iwindow(1112,695) owindow(1112,695) body(1112,695)
-orientation(portrait-secondary)	screen(834,1112) iwindow(834,973)  owindow(834,973) body(834,973)

Safari on iPad:

-orientation(landscape-primary)		screen(834,1112) iwindow(1112,753) owindow(1112,834) body(1112,753)
-orientation(portrait-primary)		screen(834,1112) iwindow(834,1031) owindow(834,1112) body(834,1031)


### Summary of Device Scaling / Orientation

- Android swaps screen width/height based on orientation.  iPad doesn't.
- the innerWidth and innerHeight seem to reliably reflect the orientation sizes.
- my buttons are generally accessible on all devices
- explorer tree, tracklist, details are too small to work with on phone and barely usable on iPad

Other Issues:

- Infinite combinations. Lots of other phones could be tried.
- I can only imagine how this is going to get back on the Car Stereo in the Android version.

// End of redesign3.md
