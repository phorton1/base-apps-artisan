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



## Truly Local WebUI Renderer

TBD
