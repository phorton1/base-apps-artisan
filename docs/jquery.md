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

*afterward* - NOW I notice, after all that work that the "multi"
extension intercepts the "activation" event, that multi-selection
doesn't work well, and that I will probably want to implement it
myself.


## Old Versions

I was using old versions of everything, dating back 8 or more years:

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


That leaves me with the following files in /zip/artisan_js/_artisan_js_new/sources

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


## THEMES

It's so flexible you can't use it.

So, now I'm trying to understand how my legacy CSS files work,
where I got them, what a 'theme' is, and how to incorporate the
correct minimal set of CSS files into my application, and basically,
once again, I am hopeless.

Apparently, at some point in the far distant past, I denormalized
a 'theme' called 'dark hive' and incorporated it directly into
my /webui/themes directory.

Not only is there an issue over identifying the 'correct'
'standard' CSS files to load, but then there are ordering
issues, kludges like '!important' and so on.

All I want to do is get my program to work.

The buttons are grey.  They should be blue.

If I take all my /webui/theme files out of artisan.html,
I get a nothing page ...

Who knows what countless mods I made to various
denormalized files.  I have to start COMPLETELY OVER.


### SEE WHAT I CAN DO WITH WHAT EXISTS

It seems that I would want to load the 'standard' jquery-ui stuff
first.

- /webui/jquery/jquery-ui1.13.2/jquery-ui-structure.css
- /webui/jquery/jquery-ui1.13.2/jquery-ui-theme.css
- /webui/jquery/layout-1.4.3/layout-default.css
- /webui/jquery/fancytree-2.38.3/skin-win8/ui.fancytree.css


These webUI's (like jquery-ui ThemeRoller) that 'let you' define your
own 'themes' are total garbage and totally counter to good software
design principles.  You end up with a glom of unreproducable
CSS that you will NEVER be able to figure out or rebuild again.
And once you do that, as I did, apparently many years ago,
and you need to update something, you are totally hosed.

/webui/jquery/fancytree-2.38.3 contains a bunch of 'skins'
whatever the heck those are.  There is ostensibly documentation
on 'theming' fancytree, but like so many bad documentation efforts,
it starts off by jumping right into details about some particular
weird side issue ... like how to make a particular widget have
a particular icon, and does nothing to give you a reasonable
approach to building a stable long lasting application.

Then they recommend you use 'Less' - a CSS precompiler as
that will *somehow* make it easier to maintain things in
future.  Sheesh.  Who comes up with this stuff?

Likewise, jquery-ui's approach to 'explaining' theming is
to start off by giving you a list of EVERY CLASS that
ANY OBJECT might ever have, and never presenting any
kind of overview.

According to jquery-ui's recommendations, one should start
by downloading a 'theme' from ThemeRoller and stick it in
their project.  I saw a note that I previously started with 'Dark Hive',
so I went to the current ThemeRoller and downloaded that.
It gave me a jquery-ui-1.13.2.custom.zip file that not only RE-GIVES me jquery,
and jquery-ui.js JAVASCRIPT files, but does not even include the name of
the theme I downloaded.  Sheesh.

With the following hugely complicated url embeded in it

	http://jqueryui.com/themeroller/?bgShadowXPos=&bgOverlayXPos=&bgErrorXPos=&bgHighlightXPos=&bgContentXPos=&bgHeaderXPos=&bgActiveXPos=&bgHoverXPos=&bgDefaultXPos=&bgShadowYPos=&bgOverlayYPos=&bgErrorYPos=&bgHighlightYPos=&bgContentYPos=&bgHeaderYPos=&bgActiveYPos=&bgHoverYPos=&bgDefaultYPos=&bgShadowRepeat=&bgOverlayRepeat=&bgErrorRepeat=&bgHighlightRepeat=&bgContentRepeat=&bgHeaderRepeat=&bgActiveRepeat=&bgHoverRepeat=&bgDefaultRepeat=&iconsHover=url(%22images%2Fui-icons_555555_256x240.png%22)&iconsHighlight=url(%22images%2Fui-icons_777620_256x240.png%22)&iconsHeader=url(%22images%2Fui-icons_444444_256x240.png%22)&iconsError=url(%22images%2Fui-icons_cc0000_256x240.png%22)&iconsDefault=url(%22images%2Fui-icons_777777_256x240.png%22)&iconsContent=url(%22images%2Fui-icons_444444_256x240.png%22)&iconsActive=url(%22images%2Fui-icons_ffffff_256x240.png%22)&bgImgUrlShadow=&bgImgUrlOverlay=&bgImgUrlHover=&bgImgUrlHighlight=&bgImgUrlHeader=&bgImgUrlError=&bgImgUrlDefault=&bgImgUrlContent=&bgImgUrlActive=&opacityFilterShadow=Alpha(Opacity%3D30)&opacityFilterOverlay=Alpha(Opacity%3D30)&opacityShadowPerc=30&opacityOverlayPerc=30&iconColorHover=%23555555&iconColorHighlight=%23777620&iconColorHeader=%23444444&iconColorError=%23cc0000&iconColorDefault=%23777777&iconColorContent=%23444444&iconColorActive=%23ffffff&bgImgOpacityShadow=0&bgImgOpacityOverlay=0&bgImgOpacityError=95&bgImgOpacityHighlight=55&bgImgOpacityContent=75&bgImgOpacityHeader=75&bgImgOpacityActive=65&bgImgOpacityHover=75&bgImgOpacityDefault=75&bgTextureShadow=flat&bgTextureOverlay=flat&bgTextureError=flat&bgTextureHighlight=flat&bgTextureContent=flat&bgTextureHeader=flat&bgTextureActive=flat&bgTextureHover=flat&bgTextureDefault=flat&cornerRadius=3px&fwDefault=normal&ffDefault=Arial%2CHelvetica%2Csans-serif&fsDefault=1em&cornerRadiusShadow=8px&thicknessShadow=5px&offsetLeftShadow=0px&offsetTopShadow=0px&opacityShadow=.3&bgColorShadow=%23666666&opacityOverlay=.3&bgColorOverlay=%23aaaaaa&fcError=%235f3f3f&borderColorError=%23f1a899&bgColorError=%23fddfdf&fcHighlight=%23777620&borderColorHighlight=%23dad55e&bgColorHighlight=%23fffa90&fcContent=%23333333&borderColorContent=%23dddddd&bgColorContent=%23ffffff&fcHeader=%23333333&borderColorHeader=%23dddddd&bgColorHeader=%23e9e9e9&fcActive=%23ffffff&borderColorActive=%23003eff&bgColorActive=%23007fff&fcHover=%232b2b2b&borderColorHover=%23cccccc&bgColorHover=%23ededed&fcDefault=%23454545&borderColorDefault=%23c5c5c5&bgColorDefault=%23f6f6f6

When I look back at what I created 8 years ago, all I
see is a reference to 'dark hive'.

TOTAL MESS.  WHAT WILL IT BE LIKE EIGHT YEARS FROM NOW?!?!

So, leesse, at this point, how many copies of the following files
exist in my directory tree

- jquery.js - three, the base copy 3.7.1, and one in each jqeury_ui folder
- jquery-ui.js - two
- jquery-structure.css - two
- et-cetera

Are they the same?  Probably.  Do I have to prove it?
Well, on my first attempt to compare jquery.js I got a lot
of changes that appear to be superflous ... maybe they're
different versions. Who knows.


And if I ever desire to 'boil it down', then I am creating the same
problem in the future.  Rebuilding ALL of this when some little
bug pops up on some module in the future.






---- end of jquery.md ----
