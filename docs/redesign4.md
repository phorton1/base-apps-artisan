# redesign4 - Devices

Devices come and go.

This goes to ideas of incrementally updating the UI on a single event.

I am currently caching the devices that the Server knows about.
This is probably not the correct approach.
The Server is intended to run long term.
It should not need a disk based cache.
Furthermore it, and the UI, should adapt to changes in the network environment.

Apart from the HTML Renderer, and the (serving) Artisan Library and Renderer,
the system cannot assume the persistence of a device.

Ala WMP and DLNA Browser, devices are only visible when they are online,
and they 'disapear' when they go offline.

At this time that only applies to Libraries as I do not currently actually
support remoteRenderers.


The current loop to call Renderer update would need to change its semantic
to get the state of the system on each call.

I still need to figure out how to manage fancy tree via explicit data.

I see how to rebuild the tree entirely in the Home Menu.



## Explorerer FancyTree Revisited

My initial implementation took advantage of a limited quick-and-dirty
understanding of FancyTree using a few examples that I could find.

I am now experimenting with a complete rewrite of how I build the
Explorer tree, especially regarding nodes that have 1000+ children.

The understanding starts by realizing that if the 'source:' or 'lazyLoad:' options
of the tree return Hashes, those hashes are used to form Ajax requests
to get the data, which is then loaded into the tree from the 'success'
of the Ajax call.  BUT, if source: or lazyLoad: return Arrays, those
arrays ARE the data.


However, the tree itself can be build completely external to the
object once a reference to the fancyTree object is obtained, when
one realizes that the tree itself is a NODE, and that it is possible
to Add Nodes and build the tree given only that initial reference.

				// what they fail to explain succinctly in the documentation is that
				// if source: or lazyLoad: return arrays, that IS the data, but if they
				// return hashes, those hashes DESCRIBE how to get the data with an
				// Ajax call where 'success' will contain the data.
				//
				// Now I need a way to add items to a node, without re-creating it
				// entirely, asynchrounously.
