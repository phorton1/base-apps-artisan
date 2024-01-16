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
#	- /etc/environment needs "./:/base:/base/apps/artisan"
#		because I don't fully qualify Perl artisan packages
#   - had to add "Defaults env_keep += PERLLIB" to
#		/etc/sudoers
#
#   See artisan.service, rpi.md, and /zip/_rpi/_setup/rpi_Setup.docx.
#
# WINDOWS SERVICE
#
# 	Quite simply installed as a Windows service by running
#
#		  nssm install _artisan
#
# 	And then edit the service in Services
#
#	   (a) set the 'path' to point to c:\Perl\bin\perl.exe
# 	   (b) set the 'starting directory' to c:\base\apps\artisan
# 	   (c) setting the 'arguments' to '/base/apps/artisan/artisan.pm'
#
# 	Can be modified and retarted with no build process
# 	Can be stopped and run with 'perl artisan.pm NO_SERVICE' from dos box
# 	Can be removed with 'nssm remove _artisan'


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
use IO::Select;


use sigtrap 'handler', \&onSignal, 'normal-signals';


my $dbg_main = 0;


display($dbg_main,0,"----------------------------------------------");
display($dbg_main,0,"Artisan.pm starting");
display($dbg_main,0,"----------------------------------------------");
display($dbg_main,0,"perl_dir=$artisan_perl_dir");
display($dbg_main,0,"server_ip($server_ip) server_port($server_port)");


sub onSignal
{
    my ($sig) = @_;			# 15 = SIGTERM, 2=SIGINT
    if ($sig eq 'PIPE')		# 13 = SIGPIPE
    {
		warning(0,0,"got SIG$sig");
		return;
	}
    LOG(-1,"main terminating on SIG$sig");

	# I used to try to do an orderly shutdown of the service,
	# particularly sending SSDP byebye messages, but that seemed
	# to hang frequently on linux, so now I just exit immediately.
	#
	# 		$quitting = 1;
	# 		sleep(3);
    # 		kill 6,$$;		# 6 == SIGABRT

	kill 9, $$;		# 9 == SIGKILL
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


# setup linux sound
# was using 20% with PCM for HDMI output
# may have needed to explicitly set 100% for USB card

if (0 && !is_win() && $AS_SERVICE)
{
	my $volume = '100%';
	my $device = $AS_SERVICE ? 'PCM' : 'Master';
	my $rslt = `amixer sset '$device' $volume`;
	LOG(-1,"amixer sset '$device' $volume rslt=$rslt");
}



#----------------------------------
# start artisan
#----------------------------------
# (0) static initialization of prefs


artisanPrefs::static_init_prefs();


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


# (2) Create Local Devices, early so that local devices come first

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


# (5) OLD CODE for taskBarIcon, which is now started
#     with the windows task scheduler

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



#------------------------------------------------------
# main
#------------------------------------------------------
# keyboard input only supported on Windows NO_SERVICE

my $linux_keyboard;
if (is_win() && !$AS_SERVICE)
{
	$linux_keyboard = IO::Select->new();
	$linux_keyboard->add(\*STDIN);
}


while (1)
{
	if ($restart_service && time() > $restart_service + 5)
	{
		$restart_service = 0;
		LOG(0,"RESTARTING SERVICE");
		system("sudo systemctl restart artisan");
	}



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

	elsif ($linux_keyboard)
	{
		if ($linux_keyboard->can_read(2))
		{
			my $line = <STDIN>;
			chomp $line;
			if ($line eq 'd')
			{
				 print "\033[2J\n";
			}
			elsif ($line eq 'a')
			{
				display($dbg_main,0,"artisan.pm calling SSDP doAlive()");
				SSDP::doAlive();
			}
			elsif ($line eq 's')
			{
				display($dbg_main,0,"artisan.pm calling SSDP doSearch()");
				SSDP::doSearch();
			}
		}
	}

}


display(0,0,"never gets here to end $program_name");


1;
