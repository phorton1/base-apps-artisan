#!/usr/bin/perl
#---------------------------------------
# artisan.pl
#---------------------------------------
# A simplified media server focused on audio content.
# Will deliever non-transcoded audio.

package artisan;
use strict;
use warnings;
use threads;
use threads::shared;
use Utils;
use Database;
use HTTPServer;
use HTTPStream;
use SSDP;
use Library;
use WebUI;
use Station;

#use Daemon;

#--------------------------------------
# initialization
#--------------------------------------

LOG(0,"-------------------------------------------------------");
LOG(0,"Starting $program_name");
dbg_mem(0,'at program startup');

db_initialize();
Station::static_init_stations();


our $ssdp = SSDP->new();
# Daemon::daemonize(\%SIG, \$ssdp);
# Daemon::write_pidfile($CONFIG{'PIDFILE'}, $$);



# start the database scanner thread
# prh - don't like the way this is going, see "createDefaultStations"
# Struggling - cannot reliably call fpcalc.exe from a thread
# so we don't use the thread approach ..

if (0)
{
    display($dbg_library,0,"Starting database scanner thread");
    my $thread1 = threads->create('Library::scanner_thread');
    $thread1->detach();
}

# and on the android we don't even do a scan.
# the android gets whatever database already exists

elsif (!$ANDROID)
{
    display(0,0,"Scanning library ...");
    Library::scanner_thread(1);
    display(0,0,"Finished scanning library ...");
}



# start the webserver

display($dbg_http,0,"Starting webserver thread");
my $thread2 = threads->create('HTTPServer::start_webserver');
$thread2->detach();

# setup SSDP
# start the listening thread and then start
# sending alive messages

$ssdp->send_byebye(1);
$ssdp->start_listening_thread();
if (1)
{
    $ssdp->start_alive_messages_thread();
}


# start the Renderer monitor thread

if (1)
{
	display(0,1,"creating Renderer auto_update thread ...");
	my $monitor_thread = threads->create('Renderer::auto_update_thread');
	if (!$monitor_thread)
	{
		error("Could not create Renderer auto_update thread");
	}
	else
	{
		$monitor_thread->detach();
		display(0,1,"done creating auto_update thread ...");
	}
}



#-------------------------------------
# main
#-------------------------------------

use sigtrap 'handler', \&onSignal, 'normal-signals';
    # $SIG{INT} = \&onSignal; only catches ^c

sub onSignal
{
    my ($sig) = @_;
    LOG(0,"artisan.pm terminating on SIG$sig");
	$quitting = 1;
    if ($ssdp)
    {
        $ssdp->send_byebye(1);
    }
    kill 6,$$;
}

# the program is aborted if any key is pressed
# if any key is pressed ...

if (0)
{
	getc();
	LOG(0,"Aborted via keystroke");
}
else
{
	# or process an endless loop and allow
	# webui to terminate the program
	
	display(9,0,"waiting for requests ....");
	dbg_mem(0,"entering endless loop");
	my $webui_aborted = 0;	# vestigal
	while (!$webui_aborted)
	{
		sleep(3);
	}
	if ($webui_aborted)
	{
		LOG(0,"Aborted via web_ui");
	}
}

$quitting = 1;
if ($ssdp)
{
	$ssdp->send_byebye(1);
}
kill 6,$$;

1;
