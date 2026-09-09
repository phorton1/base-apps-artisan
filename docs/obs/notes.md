# Notes and Random Stuff

This file contains various 'notes' that I want to keep.



## RUN REGEDIT AS SYSTEM 'user' (a 'gem' of information)

Struggling to DLNA Browser to run,  I learned how to RUN REGEDIT AS SYSTEM

	psexec -i -s c:\windows\regedit.exe

I added PsExec.exe to /base/bat after going to the website

	https://learn.microsoft.com/en-us/sysinternals/downloads/psexec

and then finding a link to

	https://download.sysinternals.com/files/PSTools.zip

which I downloaded and saved as

	/zip/apps/PSTools-whereIgotPSExec.exe.zip


This factoid might be useful for like when I was trying to remove
the teensyExpression USB devices and regedit would not let me.



## DLNA Browser (and other unused DLNA apps)

I wanted another app besides WMP to test my DLNA MediaServer.
The best candidate turned out to be a thing called "DLNA Browser",
which is a "universal" windows app.  I installed it from
a google search

	windows app store "DLNA Browser"

which gave the url

	https://apps.microsoft.com/detail/9NBLGGH4VB98?hl=en-US&gl=US

at that time.

Too make DLNA Browser work, it turns out, from an obscure toast that
came up when I first ran it, that I had to open a admin dosbox and run

	CheckNetIsolation.exe LoopbackExempt -a -n=55993czmade.dlnabrowser_876j7evpvqm5g

You can also run toCheckNetIsolation with -d to delete options,
-s to list them, or to get help

	CheckNetIsolation.exe LoopbackExempt -d -n=55993czmade.dlnabrowser_876j7evpvqm5g
		// deletes the above added exception
	CheckNetIsolation.exe LoopbackExempt -s
		// lists LoopBackExempt exceptions
	CheckNetIsolation.exe LoopbackExempt
		// to get help on this obscure exe that is not documented anywhere

CheckNetIsolation is necessary because Win10 home does not have a
"Group Policy Management Editor"
You have to quit and restart DLNA browser for the change to take effect.


Some (UWP) Programs that I installed that did
not work, maybe due to the same loopback issue.
that I subsequently uninstalled:

- VLC - could stream my files but has no browser interface
- All My Media
- Delight Media Player
- Melosik





## Old IP Addresses / Configurations

Removed from artisanUtils, I might want this info someday.

	if (0)
	{
		my $ANDROID = !$HOME_MACHINE;
		my $temp_storage = $ENV{EXTERNAL_STORAGE} || '';
		my $HOST_ID = $HOME_MACHINE ? "win" :
		$temp_storage =~ /^\/mnt\/sdcard$/ ? "arm" :
		"x86";

		if ($HOST_ID eq "arm")   # Ubuntu on Car Stero
		{
			# car stereo MAC address =
			$program_name = 'Artisan Android 1.1v';
			$uuid = '56657273-696f-6e34-4d41-afacadefeed3';
			$artisan_perl_dir = "/external_sd2/artisan";
			$mp3_dir = "/usb_storage2/mp3s";
			$mp3_dir_RE = '\/usb_storage2\/mp3s';
			$server_ip = '192.168.0.103';
		}
		else	# Ubuntu Virtual Box (x86)
		{
			$program_name = 'Artisan x86 1.1v';
			$uuid = '56657273-696f-6e34-4d41-afacadefeed4';
			$artisan_perl_dir = "/media/sf_base/apps/artisan";
			$mp3_dir = "/media/sf_ccc/mp3s";
			$mp3_dir_RE = '\/media\/sf_ccc\/mp3s';
			# $server_ip = '192.168.100.103';
		}
	}



## Local WMP Server Weidrnesses

The local WMP Server does NOT reply to SSDP M-SEARCH
messages on 10.237.50.101.  It DOES reply on 127.0.0.1.

So, I finally determined that I needed to send out
M-SEARCH messages on BOTH $server_ip (10.237.50.101)
and localhost (127.0.0.1).  See SSDP.pm.

The biggest Weirdness, though, with WMP Media Servers
is that, although I can cache Playlists Tracks and their
URLS, they do not work if I stop and restart the WMP Server.

I finally resolved this by a complicated scheme wherein
I rebuild the Playlists.db file for remoteLibraries anytime
the remoteLibrary transits from 'offline' to 'online'.

There are notes in SSDP.md on this issue, as well as in
DeviceManager.pm (around "Windows Media Player Network Sharing Service")
and remotePlaylist.pm around $WMP_PLAYLIST_KLUDGE.



## OLD DLNA Renderer Snippets

For posterities sake, here are some other snippets removed
from the current version of Artisan Perl:


	return $this->private_doAction(0,'Stop') ? 1 : 0;
	$data = $this->private_doAction(1,'GetVolume');
	$data = $this->private_doAction(1,'GetMute');
	return $this->private_doAction(0,'SetAVTransportURI',{
		CurrentURI => "http://$server_ip:$server_port/media/$arg.mp3",
		CurrentURIMetaData => $track->getDidl() });
	return $this->private_doAction(0,'Play',{ Speed => 1}) ? 1 : 0;
	return $this->private_doAction(0,'Seek',{
		Unit => 'REL_TIME',
		Target => $time_str})  ? 1 : 0;
	return $this->private_doAction(0,'Pause') ? 1 : 0;

	my $data = $this->private_doAction(0,'GetTransportInfo');
		my $status = $data =~ /<CurrentTransportStatus>(.*?)<\/CurrentTransportStatus>/s ? $1 : '';
		my $state = $data =~ /<CurrentTransportState>(.*?)<\/CurrentTransportState>/s ? $1 : '';
		$state = 'ERROR' if ($status ne 'OK');

	my $data = $this->private_doAction(0,'GetPositionInfo');
		my $dur_str = $data =~ /<TrackDuration>(.*?)<\/TrackDuration>/s ? $1 : '';
		my $pos_str = $data =~ /<RelTime>(.*?)<\/RelTime>/s ? $1 : '';
		$retval{duration} = duration_to_millis($dur_str);
		$retval{position} = duration_to_millis($pos_str);
		$retval{uri} = $data =~ /<TrackURI>(.*?)<\/TrackURI>/s ? $1 : '';
		$retval{type} = $retval{uri} =~ /.*\.(.*?)$/ ? uc($1) : '';



## JPEG Sizes

The sizes of the the standard DLNA images are, ahem, as follows

	PNG/JPEG_TN,	160x160
	PNG/JPEG_SM,	640x480
	PNG/JPEG_MED    ??
	PNG/JPEG_LRG	??


---- end of notes.md ----
