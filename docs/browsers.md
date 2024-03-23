# Browsers - Screen Devices Orientations and Resolutions

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


Chromium on rPi with 12V HDMI monitor

- platform(Linux x86_64)
- appVersion(5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36)
- ua(Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36)

The platform/ua/appVersion all appear to overlap.  I'm not sure how much useful information
can be derived from these.





## Device Scaling / Orientation Issues

I notice that the screen width and height swap per orientation on android,
but fixed on the ipad.

I notice that a 'pixel' is signifcantly smaller on my Android phone,
and a somewhat smaller on the iPad.

Laptop (fixed with var sized window)

-ratio(1)
-orientation(landscape-primary)	screen(1920,1080) iwindow(936,476) owindow(948,554) body(936,0)

Note the body height of zero?!?


Chrome on Android

-ratio(2.8125)
-orientation(landscape-primary)		screen(854,384) iwindow(779,304) owindow(779,304) body(779,304)
-orientation(portrait-primary)		screen(384,854) iwindow(384,723) owindow(384,723) body(384,723)

definitely had an anomolous orientation(portrait-primary) screen(384,854) iwindow(384,1350) owindow(384,1350) body(384,1350)
on the Android-Chrome


Chrome on iPad (all are actually Safari)

-ratio(2)
-orientation(landscape-primary)		screen(834,1112) iwindow(1112,707) owindow(1112,706) body(1112,707)
-orientation(portrait-primary)		screen(834,1112) iwindow(834,985)  owindow(834,984) body(834,985)

Firefox on iPad

-ratio(2)
-orientation(landscape-primary)		screen(834,1112) iwindow(1112,695) owindow(1112,695) body(1112,695)
-orientation(portrait-secondary)	screen(834,1112) iwindow(834,973)  owindow(834,973) body(834,973)

Safari on iPad:

-ratio(2)
-orientation(landscape-primary)		screen(834,1112) iwindow(1112,753) owindow(1112,834) body(1112,753)
-orientation(portrait-primary)		screen(834,1112) iwindow(834,1031) owindow(834,1112) body(834,1031)

Chromium on rPi with 12V HDMI monitor

- ratio(1)
- orientation(landscape-primary)	screen(800,600) iwindow(735,456) owindow(735,533) body(735,456)


Chromium on rPi with 7" HDMI touchscreen, set to 832x624 resolution

- ratio(1)
- orientation(landscape-primary)	screen(832,624) iwindow(832,xxx=433) owindow(832,xxx=535) body(832,0)
- IS_TOUCH(FALSE) !!



### Summary of Device Scaling / Orientation

- Android swaps screen width/height based on orientation.  iPad doesn't.
- the innerWidth and innerHeight seem to reliably reflect the orientation sizes.
- my buttons are generally accessible on all devices
- explorer tree, tracklist, details are too small to work with on phone and barely usable on iPad

Other Issues:

- Infinite combinations. Lots of other phones could be tried.
- I can only imagine how this is going to get back on the Car Stereo in the Android version.


## Stupid iPad

Safari sucks.  Apple sucks.  IOS sucks.

At least swipes seem to work.

The contextmenu event is not supported.
I looked into fixing it for 1/2 day.  It's a bad idea.

Double clicking zooms on element with no dbl click handler,
which is realy awkward to get out of once it happens.

The only really reliable gestures are single click and swipes.

So, on IOS (Platform == MacIntel && ua contains 'Safari'),
to the best of my ability to determine it, I'll have to
have a completley different interaction.

I'm thinking that double click on Playlist Buttons and
Explorer Tree will bring up the context menu.

There's already a different in the explorer tree between
clicking on an expander and clicking on a album.


For explorer folders, maybe buttons in the 'album pane?'
that work on selected tracks if any

Now I need to rethink the interactions, sheesh.
As if the actual implementtion is not difficult.



---- end of browsers.md ----
