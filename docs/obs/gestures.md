# Gestures

Among the key UI factors are the concepts involved
in navigating the Explorer Tree and Tracklist, selecting
items, and acting upon the selection.

I didnt't like the way fancytree does Multiselect.
It has been modified to do it the way I like.


## TrackLists on Laptop

SHIFT-CLICK only ADDS items to the selection

Queue Context Menu

- Remove
  - selected items are removed from Queue
  - if playing item is removed, next item starts playing

Explorer Context Menu

- Play
  - items are insterted into the Queue at the current location
  - first selected item begins playing
 - Add
  - items are added to the end of the Queue


Tracklist

- CLICK on an unselected item
  - clears the selection
  - item becomes selected
  - item becmes the anchor
- CLICK on a selected item
  - clears the selection
  - clears the anchor
- CTRL_CLICK on unselected item
  - item becomes selected
  - item becomes the anchor
- CTRL_CLICK on selected item
  - item becomse unselected
  - clears the anchor
- SHIFT-CLICK with no anchor
  - same as CLICK on the item
- SHIFT-CLICK with anchor
  - anchor to item become selected
- DOUBLE-CLICK on selected item
  - selected items are Played
  - clears the selection
- DOUBLE-CLICK on unselected item
  - same as CLICK on unselected item
  - item is Played
- RIGHT-CLICK on selected item
  - Play,Add Context Menu
- RIGHT-CLICK on unselected item
  - same as CLICK on unselected item
  - Play,Add Context Menu


## Explorer Tree on Laptop

Expansion is separate from Selection and involves
clicking on the Expander Only

Selecting a branch of the tree is synonymous with selecting
all of its children, even if they are unexpanded.

Implementation wise this will mean that we need to get children
recursively upon any action (Play, Add) and that, while in
explorer mode, expand will need to inherit the selection
mode to children if they have not been previously loaded.

Experience-wise, this should be done asynchronously
on a thread until all selected children have been loaded.

Note that an anchor can start at any level and end at any level.



## Desired Behavior - Touch Device

Likewise, Explorer Tree Expansion is separate from selection
and only happens on the Expander.

On non-IOS devices we will take advantage of the context-menu
event (long press) to bring up the Context Menu.  On all
devices there will be a Context Menu Button ([...])
that shows up in the 'Folder Display Area' that brings up
the Contex menu if any items are selected.

Once again, care must be taken to work within existing
SCROLL and SWIPE behaviors.

- Touch will toggle selected state of item
- Multi Touch will toggle selected state between touched items
- There will be no concept of Multiple selected Ranges
- Double Touch will Play whatever is Double Touched









---- end of gestures.md ----
s