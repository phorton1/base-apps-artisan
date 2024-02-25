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
use IO::Select;
use Pub::Utils;
use Pub::ServiceMain;
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

$SIG{CHLD} = 'DEFAULT' if !is_win();
	# needed to run git in ServiceUpdate.pm from backticks
	# must be called after initServerUtils(), which is called
	# inline in artisanUtils.pm, sets it to IGNORE when spawning
	# the initial unix service

my $dbg_main = 0;
my $last_update_check = 0;

display($dbg_main,0,"----------------------------------------------");
display($dbg_main,0,"Artisan.pm starting");
display($dbg_main,0,"----------------------------------------------");
display($dbg_main,0,"perl_dir=$artisan_perl_dir");
display($dbg_main,0,"mp3_dir=$mp3_dir");
display($dbg_main,0,"server_ip($server_ip) server_port($server_port)");

artisanPrefs::static_init_prefs();

# Wait upto 10 seconds for mp3_dir to exist (for booting rPi)
# and exit (restart service) if not

{
	my $now = time();
	while (!(-d $mp3_dir))
	{
		if (time() - $now > 10)
		{
			error("Timeout waiting for MP3 directory");
			restart();
		}
		display(0,0,"waiting for $mp3_dir");
		sleep(1);
	}
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


# (2) Create Local Devices, early so that local devices come first

addDevice(new localLibrary());
addDevice(new localRenderer());

# (3) HTTP SERVER

display($dbg_main,0,"Starting HTTP Server ....)");
my $http_server = HTTPServer->new();
$http_server->start();
display($dbg_main,0,"HTTP Server Started");

# (4) SSDP SERVER

display($dbg_main,0,"Starting SSDP Server");
my $ssdp = SSDP->new();
display($dbg_main,0,"SSDP Server Started");


#-----------------------------------------------
# main_loop
#-----------------------------------------------



sub on_terminate
{
	my ($sig) = @_;
	display($dbg_main,0,"artisan on_terminate($sig)");
	if (0)
	{
		$http_server->stop() if $http_server;

		$quitting = 1;
		my $ssdp_running = $ssdp ? $ssdp->running() : 0;
		my $lr_running = $local_renderer ? $local_renderer->running() : 0;
		my $start = time();
		while (time()<$start+3 && $http_server->{running} || $ssdp_running || $lr_running )
		{
			display($dbg_main,1,"stopping http($http_server->{running}) ssdp($ssdp_running) lr($lr_running)");
			$ssdp_running = $ssdp ? $ssdp->running() : 0;
			$lr_running = $local_renderer ? $local_renderer->running() : 0;
			sleep(0.2);
		}
		display($dbg_main,1,"Artisan stopped");
	}
	return 0;	# don't ignore; i.e. quit
}


sub on_console_key
{
	my ($key) = @_;
	if (chr($key) eq 'a')
	{
		display($dbg_main,0,"artisan.pm calling SSDP doAlive()");
		SSDP::doAlive();
	}
	elsif (chr($key) eq 's')
	{
		display($dbg_main,0,"artisan.pm calling SSDP doSearch()");
		SSDP::doSearch();
	}
	elsif (chr($key) eq 'u')
	{
		display($dbg_main,0,"artisan.pm calling doUpdates()");
		doUpdates();
	}
}



sub on_loop
{
}


Pub::ServiceMain::main_loop({
	MAIN_LOOP_CONSOLE => 1,
	MAIN_LOOP_SLEEP => 0.2,
	MAIN_LOOP_CB_TIME => 1,
	MAIN_LOOP_CB => \&on_loop,
	MAIN_LOOP_KEY_CB => \&on_console_key,
	MAIN_LOOP_TERMINATE_CB => \&on_terminate,
});


# never gets here


1;
