#!/usr/bin/perl
#---------------------------------------
# artisan.pm
#---------------------------------------
# LINUX SERVICE
#
#	to test this on the rPi with $AS_SERVICE
#   you must execute "sudo /base/apps/artisan/artisan.pm"
#   because ServerUtils changes to the / root directory
#   in start_unix_service(). You kill it by finding the
#   PID with "ps -ax", and then "sudo kill -9 PID"
#
#   For completeness, there were a number of other issues
#   for using sudo, and in general with artisan
#
#	- /etc/environment is "./:/base:/base/apps/artisan"
#		because I don't fully qualify Perl artisan packages
#   - had to add "Defaults env_keep += PERLLIB" to
#		/etc/sudoers
#
#   With the kludge in the amixer (alsa) volume control below,
#   I *think* it is now ready to be installed as a service.
#	See artisan.service for more info.
#
#
# WINDOWS SERVICE
#
# 	Quite simply installed as a Windows service by running
#
#		  nssm install _artisan
#
# 	And then edit the service in Services
#
#		 (a) set the 'path' to point to c:\Perl\bin\perl.exe
# 	   (b) set the 'starting directory' to c:\base\apps\artisan
# 	   (c) setting the 'arguments' to '/base/apps/artisan/artisan.pm'
#
# 	Can be modified and retarted with no build process
# 	Can be stopped and run with 'perl artisan.pm NO_SERVICE' from dos box
# 	Can be removed with 'nssm remove _artisan'
#
# 	SERVICE NOTES (and wTaskBar.pm) at Initial Check-in
#
#		In truth Artisan only wants to run when there is a network,
# 	  and even then only on a specific network (for my bookmarks).
#
#		There is a chicken-and-egg situation with starting the service
# 	  automatically.  I don't know how to build dependencies in, but
# 	  from a fresh boot it currently doesn't work, probably due to network.
#		Yet I can hit it the webUI from the wTaskBar?
# 	  Something else is going on, but I'm doing a sanity checkin


package artisan;
use strict;
use warnings;
use threads;
use threads::shared;
use Error qw(:try);
use Pub::Utils;
use if is_win, 'Win32::Console';
use Time::HiRes qw(sleep time);
use artisanUtils;
use artisanPrefs;
use SSDP;
use HTTPServer;
use Database;
use DatabaseMain;
use DeviceManager;
use localRenderer;
use localLibrary;
use localPlaylist;
use remoteLibrary;
use remoteRenderer;
use remoteArtisanLibrary;

use sigtrap 'handler', \&onSignal, 'normal-signals';


my $dbg_main = 0;


display($dbg_main,0,"----------------------------------------------");
display($dbg_main,0,"Artisan.pm starting");
display($dbg_main,0,"----------------------------------------------");
display($dbg_main,0,"perl_dir=$artisan_perl_dir");
display($dbg_main,0,"server_ip($server_ip) server_port($server_port)");


sub onSignal
{
    my ($sig) = @_;
    if ($sig eq 'PIPE')
    {
		warning(0,0,"got SIG$sig");
		return;
	}
    LOG(-1,"main terminating on SIG$sig");
	$quitting = 1;
	sleep(3);
    kill 6,$$;
}


my $CONSOLE_IN;

if (!$AS_SERVICE && is_win())
{
	$CONSOLE_IN = Win32::Console->new(
		Win32::Console::STD_INPUT_HANDLE());
	$CONSOLE_IN->Mode(
		Win32::Console::ENABLE_MOUSE_INPUT() |
		Win32::Console::ENABLE_WINDOW_INPUT() );
}


#----------------------------------
# setup linux sound 
#----------------------------------
# use `aplay -l' to get a listing of devices.
# you will see something like this:
#
#	card 3: Device [USB PnP Sound Device], device 0: USB Audio [USB Audio]
#
# Set the USB sound card as the default by editing
# /etc/asound.conf with the card and devoce number from above
# 
# 	defaults.pcm.card 3
#	defaults.pcm.device 0

# can do it at runtime because
# pactl does not work from root because it needs XDG_RUNTIME_DIR

if (0 && !is_win())  
{
	my $sinks = `pactl list sinks short`;
	LOG(0,"pactl sinks=$sinks");
	my $cards = `aplay -l`;
	LOG(0,"aplay cards=$cards");
	my $controls = `amixer scontrols`;
	LOG(0,"amixer controls= $controls");
	# exit(0);   # if you just want to see debugging
}

# use pactl to set default audio device
# comment out && $AS_SERVICE for debugging

if (0 && !is_win() && $AS_SERVICE)
{
	my $usb_dev = '';
	my $sinks = `pactl list sinks short`;
	for my $line (split(/\n/,$sinks))
	{
		if ($line =~ /usb/)
		{
			my @parts = split(/\s+/,$line);
			$usb_dev = $parts[1];
		}
	}
	
	if ($usb_dev)
	{
		LOG(-1,"setting USB AUDIO DEVICE to $usb_dev");
		my $rslt = `pactl set-default-sink $usb_dev`;
		error($rslt) if $rslt;
	}
}

# set volume

if (0 && !is_win() && $AS_SERVICE)	
{
	my $volume = '100%';
	my $device = $AS_SERVICE ? 'PCM' : 'Master';
	
	my $rslt = `amixer sset '$device' $volume`;
	LOG(-1,"amixer sset '$device' $volume rslt=$rslt");
}

# exit 0 if !is_win();
	# short ending for testing above code


#----------------------------------
# start artisan
#----------------------------------

# (0) static initialization of prefs

if (0)
{
	artisanPrefs::static_init_prefs();
}


# (1) LIBRARY
# not done if $DEBUG_SSDP_ALONE

if ($DEBUG_SSDP_ALONE)
{
	display($dbg_main,0,"DEBUG_SSDP_ALONE - no library or local devices!");
}
else
{
	db_initialize();
	display($dbg_main,0,"Scanning Library ...");
	DatabaseMain::scanTree();
	display($dbg_main,0,"Finished Scanning Library");
	localPlaylist::initPlaylists();
}

# (2) Create Local Devices, and THEN read the device Cache
# so that local devices come first

addDevice(new localLibrary());
addDevice(new localRenderer());


# (3) HTTP SERVER - establishes $server_ip

display($dbg_main,0,"Starting HTTP Server ....)");
my $thread2 = threads->create('HTTPServer::start_webserver');
$thread2->detach();
display($dbg_main,0,"HTTP Server Started");

# (4) SSDP SERVER

display($dbg_main,0,"Starting SSDP Server");
my $ssdp = SSDP->new();
display($dbg_main,0,"SSDP Server Started");

if (0)
{
	my $taskbar_pm = "/base/apps/artisan/wxTaskBarIcon.pm";
	$taskbar_pm =~ s/\//\\/g;
	$taskbar_pm = "c:".$taskbar_pm;
	display(0,0,"taskbar_pm=$taskbar_pm");
	my $perl = "\\perl\\bin\\perl.exe";
	Pub::Utils::execNoShell("wxTaskBarIcon.pm","\\base\\apps\\artisan");
}

if (0)
{
	require wxTaskBarIcon;
	taskBarIcon->new();
}

while (1)
{
	if ($CONSOLE_IN)
	{

AFTER_EXCEPTION:

		try
		{
			display($dbg_main+1,0,"main loop");
			# display_hash(0,0,"mp",$mp);

			if ($CONSOLE_IN->GetEvents())
			{
				my @event = $CONSOLE_IN->Input();
				if (@event &&
					$event[0] &&
					$event[0] == 1) # key event
				{
					my $char = $event[5];

					# print "got event down(" . $event[1] . ") char(" . $event[5] . ")\n";

					if ($char == 3)        # char = 0x03
					{
						display($dbg_main,0,"exiting Artisan on CTRL-C");
						if (0)
						{
							$quitting = 1;
							my $http_running = HTTPServer::running();
							my $ssdp_running = $ssdp ? $ssdp->running() : 0;
							my $lr_running = $local_renderer ? $local_renderer->running() : 0;
							my $start = time();
							while (time()<$start+3 && $http_running || $ssdp_running || $lr_running )
							{
								display($dbg_main,1,"stopping http($http_running) ssdp($ssdp_running) lr($lr_running)");
								$http_running = HTTPServer::running();
								$ssdp_running = $ssdp ? $ssdp->running() : 0;
								$lr_running = $local_renderer ? $local_renderer->running() : 0;
								sleep(0.2);
							}
							display($dbg_main,1,"Artisan stopped");
						}
						exit(0);
					}
					elsif ($event[1] == 1)       # key down
					{
						if ($Pub::Utils::CONSOLE && $char == 4)            # CTRL-D
						{
							$Pub::Utils::CONSOLE->Cls();    # clear the screen
						}
						elsif (chr($char) eq 'a')
						{
							display($dbg_main,0,"artisan.pm calling SSDP doAlive()");
							SSDP::doAlive();
						}
						elsif (chr($char) eq 's')
						{
							display($dbg_main,0,"artisan.pm calling SSDP doSearch()");
							SSDP::doSearch();
						}
					}
				}
			}

			sleep(0.2);
		}
		catch Error with
		{
			my $ex = shift;   # the exception object
			display($dbg_main,0,"exception: $ex");
			error($ex);
			my $msg = "!!! main() caught an exception !!!\n\n";
			error($msg);
			goto AFTER_EXCEPTION if (1);
		};
	}

	else	# !$CONSOLE_IN
	{
		sleep(10);
	}
}


display(0,0,"never gets here to end $program_name");


1;
