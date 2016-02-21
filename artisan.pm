#!/usr/bin/perl
#---------------------------------------
# artisan.pm
#---------------------------------------
# A pure perl implementation of an Artisan server.
# This file is the app.  All other perl files in this
# folder are also used in the windows App, which is a
# superset of this application.
#
# As a mimimum, this pure-perl app is a faceless Artisan
# Playback device associated with a static (read-only)
# Local Library.
#
# It has no Local Renderer.
#
# As a faceless Playback device, it must be associated
# with a DLNA Renderer in order to play music, and is
# only really useful if there is a UI to it.
#
# There are preferences that allow automatically
# connecting to a previous (given) DLNA render, and starting
# a previous (given) Station or Saved Songlist, so technically
# speaking, a UI is not really required, but nonetheless,
# by default it presents a webUI Surface (currently this
# surface is implemented at a low level separate from the
# proposed Surface Server. Hopefully the webUI surface can
# be implemented in terms of the Surface Server).
#
# If there is no database found, a scan will be performed.
# But otherwise, by default, no scan is performed on startup.
# There is a preference to SCAN_LIBRARY_ON_STARTUP.
#
# There is also an preference to start a DLNA Server.
# The DLNA Server is really an SSDP Server with support
# in the HTTP Server,.


package artisan;
use strict;
use warnings;
use threads;
use threads::shared;
use Utils;
use artisanPrefs;
use Database;
use HTTPServer;
use HTTPStream;
use SSDP;
use Library;
use WebUI;
use Station;
use artisanInit;

# use Daemon;
# some work needed to make this a real service

our $ssdp;


#-------------------------------------------------------------------------------
# Start Servers, etc
#-------------------------------------------------------------------------------

start_artisan();
	# encapsulates program startup with ini file
	# in artisanInit.pm


#-------------------------------------------------------------------------------
# FALL THRU TO main()
#-------------------------------------------------------------------------------

use sigtrap 'handler', \&onSignal, 'normal-signals';
    # $SIG{INT} = \&onSignal; only catches ^c

sub onSignal
{
    my ($sig) = @_;
    LOG(0,"artisan.pm terminating on SIG$sig");
	end_app();
}

display(0,0,"$program_name Started!!");
dbg_mem(0,"entering endless loop");


if (0)
{
	# the program is aborted if any key is pressed
	# if any key is pressed ...
	
	display(0,0,"Hit any key to Quit the Server ...");
	getc();
	LOG(0,"Aborted via keystroke");
}
else
{
	# or process an endless loop and allow
	# webui to terminate the program
	
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


#-----------------------------------
# ENDING (Fall thru or onSignal)
#-----------------------------------

end_app();

sub end_app
{
	$quitting = 1;
	if ($ssdp)
	{
		$ssdp->send_byebye(1);
	}
	kill 6,$$;
}



1;
