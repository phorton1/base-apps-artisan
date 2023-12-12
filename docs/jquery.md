# jQuery - old and new

This readme details the process that I went through to
update to the latest versions of jQuery related stuff
on 2023-12-12.

This was necessary to get the "multi" extension to
fancytree to work for multiple-selection in the
Explorer Tracklist.

fancyTree multiple selection did not work as advertised.
Particularly there is no "multi" extension in my (old) version
of fancyTree.  Some testing showed that the current versions
of jquery stuff basically work and support "multi" extension
and multiple selection in the Tracklist, so I am updating
to the latest versions of all jquery related JS.

The underlying collections of jquery related 'sources' files
can now be found in my /zip/js folder

- /zip/artisan_js/_artisan_js_old
- /zip/artisan_js/_artisan_js_new

## Old Versions

I am/was using old versions of everything, dating back 8 or more years:

- jquery 1.11.1
- jquery-ui 1.11.2
- jquery-layout 1.4.3
- jquery.fancytree 2.6.0

and a few other one-of-a-kind files:

- jquery.layout.resizeaneAccordians (from callbacks folder of jquery-layout 1.4.3)
- jquery.touchSwipe - from https://github.com/mattbryson/TouchSwipe-Jquery-Plugin
- jquery.ui-contextmenu - from https://github.com/mar10/jquery-ui-contextmenu
- jquery.touch-punch - unversioned single repo at https://github.com/furf/jquery-ui-touch-punch


### New Versions

Here's what I found as the current, latest available sources on 2023-12-11.
These files are downloaded to _artisan_js_new/sources before unzipping or
re-organizing:

- [jquery](https://jquery.com/) 3.7.1 released 2023-08-28
  - downloaded regular and min versioned JS files via browser from
    first two links on https://jquery.com/download/
  - [github source](https://github.com/jquery/jquery)
- [jquery-ui](https://jqueryui.com/) 1.13.2, released 2023-07-14
  - says it is compatible with jquery upto 3.6
  - downloaded https://jqueryui.com/resources/download/jquery-ui-1.13.2.zip
    which contains unversioned regular, min, and css files
  - [github source](https://github.com/jquery/jquery-ui)
- [jquery layout](https://plugins.jquery.com/layout) 1.4.3, released 2014-09-07
  - same version I was already using
  - download link returns layout_master.zip which contains unversioned
    regular and min js files under the source/stable folder
  - [github source](https://github.com/allpro/layout)
- [jquery.fancytree](https://github.com/mar10/fancytree) 2.38.3, released 2023-02-01
  - downloaded 2.38.3 zip from the 'releases' link on the github site
- [jquery.touch-punch](https://github.com/furf/jquery-ui-touch-punch) - unversioned
  - single repo at https://github.com/furf/jquery-ui-touch-punch
  - downloaded entire repos as jquery-ui-touch-punch-master.zip file
- [jquery.touchSwipe](https://github.com/mattbryson/TouchSwipe-Jquery-Plugin) 1.6, from 2018-09-17
  - version implied from github readme
  - downloaded TouchSwipe-Jquery-Plugin-master.zip
  - small doc appears at http://labs.rampinteractive.co.uk/touchSwipe/demos/index.html
- [jquery.ui-contextmenu](https://github.com/mar10/jquery-ui-contextmenu) 1.18.1, from 2017-08-28
  - downloaded jquery-ui-contextmenu-1.18.1 from releases link on github site


That leaves me with the following files in _artisan_js_new/sources

- jquery-3.7.1.js
- jquery-3.7.1.min.js
- jquery-3.7.1.min.map
- jquery-ui-1.13.2.zip
- layout-master.zip
- fancytree-2.38.3.zip
- jquery-ui-touch-punch-master.zip
- TouchSwipe-Jquery-Plugin-master.zip
- jquery-ui-contextmenu-1.18.1.zip


## New artisan/webui/jquery folder

I then built a 'new' version of the /webui/jquery folder from that stuff.

- jquery-3.7.1.js - copied bare file
- jquery-3.7.1.min.js - copied bare file
- jquery-3.7.1.min.map - copied bare file
- subfolder jquery-ui-1.13.2 - from zip file
- subfolder layout-1.4.3 - copied and versioned from 'stable' folder from zip file
- subfolder fancytree-2.38.3 - copied and versioned from 'dist' folder from zip file
- jquery.ui.touch-punch.js - copied unversioned file from root of zip file
- jquery.ui.touch-punch.min.js - copied unversioned file from root of zip file
- jquery.touchSwipe-1.6.js - copied and versioned from root folder from zip file
- jquery.touchSwipe-1.6.min.js - copied and versioned from root folder from zip file
- jquery.ui-contextmenu-1.18.1.js - copied and versioned from root folder from zip file
- jquery.ui-contextmenu.min-1.18.1.js - copied and versioned from root folder from zip file
- jquery.ui-contextmenu.min-1.18.1.js.map - copied and versioned from root folder from zip file

To get it to work, I did the following steps:

- renamed webui/jquery to webui/jquery_old
- added the new webui/jquery folder
- modified artisan.html to call the new versions


## NEW JQUERY - Problems

After correcting the following two problems, the UI came up,
albeit with pretty major CSS problems.

### (1) TypeError: v.selector is undefined

When I got it all hooked up, I ran into this problem:

	TypeError: v.selector is undefined

A search on the web found a page at

	https://stackoverflow.com/questions/39513448/jquery-layout-throws-error-because-n-selector-is-undefined

that said the following

	For jquery.layout 1.4.4 just comment row 1831: sC.selector = $N.selector.split(".slice")[0];
	and all works normally (tested on jQuery v3.3.1)

So I made that change in jquery.layout.js and jquery.layout.min.js


### (2) Error: ui-contextmenu: Missing required option `delegate`.

I commented out the code that uses the jquery-ui-context menu
from explorer.js.

I will be entirely changing the way I call
context menus, using on('context_menu') rather than the
context_menu.js extension and will probably do away
with this external JS file.


## NEW JQUERY - getting it basically working

I had already added explorer.css styles:

	.fancytree-selected > td,
	.fancytree-partsel > td
	{
		background: green;
		background-color: #74992e !important;
	}

When I added the "multi" extension to the Tracklist,
multiple selection, with highlighting, began to work.


## NEW JQUERY - Noted problems at this time

- The Renderer and Library Buttons are styled incorrectly, with checkboxes, in center
- The top menu Home/Explorer/Full Screen buttons are styled incorrectly, light grey with tiny print
- The Renderer Transport buttons are likewise styled incorrectly
- Explorer tree has a node that says "No Data" at top





---- end of jquery.md ----
