# Redesign1

The basic notion of this redesign is to get rid of 'Playlist Sources',
and to bind Playlists to libraries for compatibility with WMP and
a more general UI.

Also in this re-design effort is the notion that the webUI has a
truly Local Renderer in the embeded HTML music player that is
treated orthogonally as "just another renderer", which is far
more complicated in the JS world than might seem at first blush.

## Eliminate Artisan PLSources

- Wrap playlist generation back into localPlaylist and
  eliminate entire PLSource device hiearchy in Perl
- Eliminate PLSource devices in webUI
- factor uiPLSource into uiLibrary as set of calls
  to localLibrary.

- Present virtual Playlists folder within localLibrary
  in addition to hard 'folders' OR, possibly
- ADD Playlists folder and Playlists to the database.

I want them to always show last in the webUI.

Get all that working so that the playlist buttons
are only populated with playlist that exist by no
longer creating 'empty' playlists with non-useful
buttons.

- add 'dirtype' = 'playlist'

## Make sure it works within ContentDirectory1.pm

As presented to WMP Player UI. Should now be a folder
called 'Playlists' at the end.


## Support in remoteLibrary

So that WMP playlists show as buttons in our UI'
and function with our "Shuffle" and other controls.



# remoteLibrary caching

RemoteLibraries will utilize the following cache scheme.

The first level is to cache the actual XML requests
	to the device before parsing them into a local database.

Only certain interesting requests are cached (Brows & Search).
We don't (make or) cache device capability requests.

	We *should* keep track of the library's UPDATE_ID
	and wipe evertying out if it changes, sheesh.

Then, there are two 'modes' of operation in Artisan based on
	$REINIT_REMOTE_DBS (default 0)

if !$REINIT_REMOTE_DBS and a cachefile is found, this means
	it is already in the database and we then return the
	records from the database, but don't reparese the xml.

if $REINIT_REMOTE_DBS we will wipe out the remote libray's database
	and, in that case, we take any xml, cached or not.









## Truly Local WebUI Renderer

TBD
