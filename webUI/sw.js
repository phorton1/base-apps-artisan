// sw.js - Artisan's service worker
//
// Exists only so that Chrome on Android treats the webUI as an
// installable web app (fullscreen from the home screen, per
// artisan_manifest.json).  It caches nothing and changes nothing:
// every request goes to the network exactly as before.

self.addEventListener('install', function(event)
{
	self.skipWaiting();
});

self.addEventListener('activate', function(event)
{
	event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', function(event)
{
	// deliberately empty: the browser fetches as usual
});
