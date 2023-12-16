#  The Queue, Selection, and Explorer Behavior

There is/will be a Queue for the Renderer.

The implementation is very complicated due to fancytree tree
lazy loading, sequential selection sessions, and the fact
that the Queue itself is moving.


Initial implementation

- the UI maintains the Queue
- the Queue is not persistent
- no Shuffling or Sorting

Later:

- Shuffling and Sorting
- Persistence per Renderer


## Requirements

Much of this has to do with the Explorer tree and getting
Tracks from it to the Queue while ma


There are numerous, possibly conflicting, requirements




 // There appear to be conflicting requirements.
//
// - clear the selection and return immediately from the double click
//   or context menu (play) and (add) commands
// - add tracks as soon as possible to the queue, especially in the
//   case of (play) immediate.
// - maintining responsiveness in the explorer tree
//
// especially when combined with the notions:
//
// - sequential selection sessions must remain in order
// - the user may separately expand the tree, causing loads
// - the difference between (add) and (play)
// - the queue is moving on it's own as it is played.
//
// Ordering wise, Plays should come before Adds
// User Loads should have priority over Selection Loads
// This combined with Tracklist loading

// It seems like things need to be done in chunks.
//
// - A Play selection has highest priority until the queue
// 	 gets at least one Track from the selection and it
//   starts playing.
// - A user Tracklist has the next highest priority as
//   they may want to proceed directly to selection and
//   have explicitly selected an Album or Playlist.
// - A user Expand has the next highest priority
//
// And THEN we still have to deal with persistence of Queues
// per renderer ... yikes.

// I think the persistence of the Queue is the lowest priority
// and can be handled when everything settles down.














---- end of queue.md ----
