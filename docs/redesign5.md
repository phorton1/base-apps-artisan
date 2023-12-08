# redesign5 - Updating, Devices, and Events




    Windows Media Player Network Sharing Service – Automatic (Delayed Start)

    Computer Browser – Manual (Trigger Start)

    UPNP Device Host – Manual

    Workstation – Automatic

    SSDP discovery Sevices – Manual



Henceforth the webUI will call back to the server in a loop regardless of
if it 'playing' or not.

We will make the following assumptions and changes to the program

- Libraries WILL NOT CHANGE while the Server is running!
- remoteLibraries WILL NEVER CHANGE and can be cached by the Server

Later, we can implement UPNP EVENTING against remoteLibraries to KNOW
when their content changes and needs to be refreshed, perhaps even on
a container basis, but initially, for simplicity, I will merely assume
that their content never changes, though their ONLINE status may change.

- The system will have a UPDATE_ID that it passes to the UI
- The UI will pass it's UPDATE_ID back to the Server on every UPDATE call
  in addition the the RENDERER_UUID it currently passes.
- Device changes will register the UPDATE_ID version they occurred at, so that
- We will notify the UI when the status of Devices changes.

And then:



- The UI will ONLY present valid online devices.
- The UI will STOP everything if a Library it has chosen goes offline.
- The UI will switch to an ONLINE library if a Library it has chosen goes offline
- The assumption is that there is always AT LEAST the Servers local 'Artisan Perl' library
- The UI *may* even register if the SERVICE goes offline (i.e. there is a failure to
  call update)

And:

RemoteLibraries will have a 'state' variable that indicates if they are properly initialized
(Playlists have been built).   They will be considered 'offline' until their Playlists are
properly built.

- Devices will no longer be cached.  The Server will build the list of available devices
  via SSDP upon invocation.
- remoteDevices (remoteLibraries) can change their IP:PORT values while the system is running


## Weirdness Once Again

After reworking the UI and device manager to handle devices
coming and going, in experiments with WMP Server, I found that
one cannot simply stop and start the

*Windows Media Player Network Service*

There is some kind of internal state kept somewhere.
It *appears* to work, but then if you bring up the WMP UI,
you will see that after a restart, WMP has 'turned off'
media streaming.

So, I then thought that the correct approach was to turn
'Streaming' off and on via the WMP UI.  However, after
doing so, trying to start a cached playlists from WMP
fails.  No errors, it just doesn't play (and the lame
'image' for John Denver doesn't show up).

Then, weirdness upon weirdness, if in just the right state,
IF I then 'hit' the WMP Server to 'get' something from it,
not sure exactly what, it effing starts working.

Meanwhile I can only find it with M_SEARCH on 127.0.0.1,
but then get 'alive' messages from it on 10.237.50.101,
so it is always changing it's IP everytime I do a search
and it sends an alive message.  Sheesh Fuck.


THEN THIS ....

BUT ...

If I delete my cachefiles for 'search playlists', delete
the playlists.db and playlists folder, stop the WMP Server,
stop my Server, start my Server, and then start the WMP Server,
IT FUCKING WORKS.

This, mind you, in spite of the fact that if I now bring up the WMP UI,
it will show that 'media streaming' is turned off.

It's as if IF I HIT THE SEARCH FOR PLAYLISTS whenever I 'start'
my internal 'device', WMP is ok with it.  But if I don't do that,
or something, to get those tracks, the SERVER does not work
correctly.  Fuck shit.
