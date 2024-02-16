# Browser Caching

Caching could make a huge difference in the perceived speed
of Artisan, paticularly when accessing the rPi from other
machines, where local LAN and implementation limitations
seem to take 8-10 seconds to load the page.

I want the browser to cache as much as possible in a production
system, yet still allow for development, particularly JS/CSS changes,
and/or the ability to update images, etc.

## Cache Clearing Techniques

There is no way to clear the cache for regular HTTP.

	Clear-Site-Data: "cache"

is only available for HTTPS requests.

Likewise it is possible to clear the cache for a
particular HTTPS request from Javascript, although
it is complicated.

This might be interesting for other servers which
typically DO use HTTPS, like the myIOTServer.



## Things that could be cached

- stuff served statically from HTTP::ServerBase
  - the main HTML file
  - the JS and CSS
  - any other static images, icons, etc

- library requests for
  - folder.jpg
  - tracks and folder contents


## Things that should never be cached

- /get_devices - the list of devices is presumed to
  never be cached.

- /webui/update requests - which contains at least the
  system_update_id which drives get_devices calls to
  update the buttons, and which also contains a copy
  of the playlist and/or queue that is dynamically
  changing.

- /webui/queue requests - contains the current queue
  which may change at any time.



## HTTP_USE_STANDARD_CACHE_SCHEME starting with JS/CSS

Defaults to 0 to prevent issues with existing projects.

If HTTP_USE_STANDARD_CACHE_SCHEME is set to 1, JS and CSS
files that are served staticially by ServerBase will send
"cache_control: "max-age:forever" headers instead of the
standard default "cache-control: no-cache". Once they are
sent that way, they will be cached by the browser.

To make it work as expected, it is required to use the processBody
calls to ServerBase::includeJS() and includeCSS() methods to
add  ?datetime to the filenames

	<&$this->includeCSS('/themes/artisan.css')>
	<&$this->includeJS('artisan.js')>

resulting in:

	<link rel="stylesheet" type="text/css" href="/themes/artisan.css?1705696466" />
	<script type="text/javascript" src="artisan.js?1705699845"></script>

Otherwise, the files would be retained forever, and
you'd have to manually clear the browser cache to get
changes to take effect.

With these changes, the normal process of editing a
JS or CSS file and then reloading in the browser will
cause it to get the correct version of the file, just
as if HTTP_USE_STANDARD_CACHE_SCHEME was set to zero,
and the file was served with "cache-control: no-cache".






---- end of md ----
