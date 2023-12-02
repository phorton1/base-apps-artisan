#!/usr/bin/perl
#---------------------------------------
# artisan.pm
#---------------------------------------
# Quite simply installed as a service by running
#
#	  nssm install _artisan
#
# And then edit the service in Services
#
#	 (a) set the 'path' to point to c:\Perl\bin\perl.exe
#    (b) set the 'starting directory' to c:\base\apps\artisan
#    (c) setting the 'arguments' to '/base/apps/artisan/artisan.pm'
#
# Can be modified and retarted with no build process
# Can be stopped and run with 'perl artisan.pm NO_SERVICE' from dos box
# Can be removed with 'nssm remove _artisan'
#
# SERVICE NOTES (and wTaskBar.pm) at Initial Check-in
#
#	In truth Artisan only wants to run when there is a network,
#   and even then only on a specific network (for my bookmarks).
#
#	There is a chicken-and-egg situation with starting the service
#   automatically.  I don't know how to build dependencies in, but
#   from a fresh boot it currently doesn't work, probably due to network.
#	Yet I can hit it the webUI from the wTaskBar?
#   Something else is going on, but I'm doing a sanity checkin


package artisan;
use strict;
use warnings;
use threads;
use threads::shared;
use Error qw(:try);
use Win32::Console;
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
use Pub::Utils;
use sigtrap 'handler', \&onSignal, 'normal-signals';


Pub::Utils::initUtils(1);

my $dbg_main = 0;


sub onSignal
{
    my ($sig) = @_;
    LOG(-1,"main terminating on SIG$sig");
	$quitting = 1;
	sleep(3);
    kill 6,$$;
}


my $CONSOLE_IN;

if (!$AS_SERVICE)
{
	$CONSOLE_IN = Win32::Console->new(STD_INPUT_HANDLE);
	$CONSOLE_IN->Mode(ENABLE_MOUSE_INPUT | ENABLE_WINDOW_INPUT );
}



#----------------------------------------
# main
#----------------------------------------

display($dbg_main,0,"starting $program_name");


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
DeviceManager::read_device_cache();


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
						if ($CONSOLE && $char == 4)            # CTRL-D
						{
							$CONSOLE->Cls();    # clear the screen
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
