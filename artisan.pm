#!/usr/bin/perl
#---------------------------------------
# artisan.pm
#---------------------------------------

package artisan;
use strict;
use warnings;
use threads;
use threads::shared;
use Error qw(:try);
use Win32::Console;
use Time::HiRes;
use artisanUtils;
use artisanPrefs;
use SSDP;
use HTTPServer;
use Database;
use DatabaseMain;
use DeviceManager;
use localRenderer;
use localLibrary;
use localPLSource;
use remoteLibrary;
use remoteRenderer;
use Pub::Utils;
use sigtrap 'handler', \&onSignal, 'normal-signals';


my $dbg_main = 0;


$HTTPServer::SINGLE_THREAD=1;


sub onSignal
{
    my ($sig) = @_;
    LOG(-1,"main terminating on SIG$sig");
    kill 6,$$;
}

my $CONSOLE_IN = Win32::Console->new(STD_INPUT_HANDLE);
$CONSOLE_IN->Mode(ENABLE_MOUSE_INPUT | ENABLE_WINDOW_INPUT );


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

db_initialize();
display($dbg_main,0,"Scanning Library ...");
DatabaseMain::scanTree();
display($dbg_main,0,"Finished Scanning Library");

# (2) Create Local and Cached Devices

addDevice(new localLibrary());
addDevice(new localRenderer());
addDevice(new localPLSource());
$local_plsource->initPlaylists();

# (3) HTTP SERVER - establishes $server_ip

display($dbg_main,0,"Starting HTTP Server ....)");
my $thread2 = threads->create('HTTPServer::start_webserver');
$thread2->detach();
display($dbg_main,0,"HTTP Server Started");

# (4) SSDP SERVER

display($dbg_main,0,"Starting SSDP Server");
my $ssdp = SSDP->new();
display($dbg_main,0,"SSDP Server Started");


# if (0)   # start the Renderer monitor thread
# {
# 	display(0,0,"Starting Renderer Monitor ...");
# 	my $monitor_thread = threads->create('Renderer::auto_update_thread');
# 	if (!$monitor_thread)
# 	{
# 		error("Could not create Renderer auto_update thread");
# 	}
# 	else
# 	{
# 		$monitor_thread->detach();
# 		display(0,0,"Renderer Monitor Started");
# 	}
# }
#
# if (artisanPrefs::getPreference($PREF_USE_PREVIOUS_RENDERER) &&
# 	(my $id = artisanPrefs::getPreference($PREF_PREVIOUS_RENDERER)))
# {
# 	display(0,0,"Selecting Startup Renderer: $id");
# 	Renderer::selectRenderer($id);
# }



while (1)
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
					exit(0);
				}
				elsif ($event[1] == 1)       # key down
				{
					if ($CONSOLE && $char == 4)            # CTRL-D
					{
						$CONSOLE->Cls();    # clear the screen
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

display(0,0,"never gets here to end $program_name");


1;
