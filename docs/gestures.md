# Gestures

Among the key UI factors are the concepts involved
in navigating the Explorer Tree and Tracklist, selecting
items, and acting upon the selection.

To date I have tried to rely on the mouse and touch handling
offerred by jquery, jquery-ui, and fancytree.  My initial
thought was that these modules *probably* handle mice and touch
interactions well on desktop browsers and Android mobile devices,
but that they break down on IOS devices, and so, most of of
my efforts to date have focused on finding substitute solutions
for running the webUI on IOS.

The main interactions are:

- expanding and contracting the Explorer tree
  for non-terminal nodes
- 'activating' an item in the Explorer tree, showing
  the Folder information or loading the Tracklist
  for album and playlists terminal nodes.
- selecting item(s) from the Explorer tree
- 'activating' an item in the Tracklist, showing
  the Track information
- selecting Track(s) from the Tracklist

With the general idea of a ContextMenu to act upon
selections, and the possibility of 'shortcuts'
(i.e. double click) for the most common actions.

One fundamental requirement is that of Multiple Selection,
that there are easy ways to select more than one Track,
or node in the Explorer tree.

Another requirement is that the application behaves well
on all three of: my laptop, my iPad, and my Android phone.
This is initially complicated by the fact that the iPad does
not support the standard HTML ContextMenu event.


## Initial Idea for IOS Context Menu

A bit of testing has shown me that I can detect
multi-touch gestures, which are otherwise not used
by the jquery stuff.   I *think* I can create a
'Context Event' when the user touches an already
selected item and then adds another finger to the
touch.



## Multiple Selection

There is a (slightly buggy) implementation of Multiple Selection
buillt into fancytree.   It works "ok-ish" on the laptop, but
of course, does not work at all on the iPad (or Android devices).

On the desktop the typical convention for multi-selection is
the idea of CTRL to add individual items, and SHIFT to add a
range.

I am thinking that this should be extended on the laptop to
include mouse drags, and that on the other devices, touch drags
should implement multiple selection.

There is no concept of CTRL or SHIFT on touch devices.

So, instead of CTRL, perhaps a subsquent touch on item TOGGLES the
selection of an item.  This means that, on touch devices, you must
explicitly UNSELECT an item, whereas on the laptop you use CTRL to
explicitly SELECT additional items.

Likewise, DOUBLE_CLICK on the laptop *could* have the semantic of
(a) clearing the selection, (b) selecting the double clicked item,
and (c) acting upon the double click item.  That could *perhaps*
be implemented on touch devices, differentiating between SINGLE
CLICKS which toggle the selection and DOUBLE CLICK which deselects
everything, selects and acts upon the item.

This also goes to the idea of 'activating' verus 'expanding'
the Explorer tree.

Eventually it comes down to what gestures can be supported
on each device:

On the Laptop it seems that many gestures are possible. The most
common combinations being:

- single left click
- double left click
- single right click
- CTRL left click

But other combinations are certainly possible

- long left or right clicks
- SHIFT modifier on any click
- CTRL modifier on any click
- drag movement with and without modifiers, on either button

On the other hand, the gestures available on the touch devices
are somewhat more limited,

- single touch
- double touch
- long touch (not on iPad)
- touch drag (note use for scrolling)
- multi-touch with or without movement

With the caveat that IOS will mess with any long presses.
Initial testing indicates that IOS DOES NOT pop
up it's own context menu on a long press IF ANOTHER FINGER
IS DOWN.  Its a bit of a learned skill, and works best
with no movement (otherwise it's a 'pinch' and the browser
tries to zoom based on it), but that seems to allow the
following 'reliable' gestures.

- single touch
- double touch
- multi touch

GRRR this is going to be complicated if and when we have to
take things like scrolling on a touch screen into account.



## DESIGN - GENERAL

Selection is Pane specific. Clicking in the Explorer Tree
removes any selection from the Tracklist and vice-versa.


## Laptop Multi Select Problems

I don't like the way fancytree does Multiselect.

Particularly it does not move the anchor when you
CTRL click a new item, so you cannot actually select
multiple distinct ranges (even in a flat list), like
you can typically do in other programs (i.e. windows
explorer).  Actually in Windows Explorer there are
three distinct possibilites.

- click and then SHIFT click to select a range
- CTRL click on a separate item, this establishes
  a new anchor.
- a SHIFT click from there DESELECTS the previous
  and selects the new range.
- a CTRL-SHIFT click from there ADDS the new range.


Heirarchial selection is another problem.
Fancytree selects all items that are expanded
at the point of selection, which is counter-intuitive.
I will have to think about this a bit.

On the desktop, in the Explorer Tree, there is enough precision
that the use of the Expander, separate from the 'activate' (clicking
on the title) is possible to distinguish between the two.



## Desired Behavior - Laptop

### TrackLists on Laptop

I think the SHIFT-CLICK only ADDS items to the selection


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


### Explorer Tree on Laptop

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





## Implementation Steps

- remove visual HTML Audio Player
- add context menu button to Folder Info and Renderer panes
- implement selection within current JS code / html
- re-factor code better
  - derived objects for Tree, Tracklist and new Queue






---- end of gestures.md ----
s