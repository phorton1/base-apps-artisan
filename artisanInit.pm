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


package artisan;	# continued, maybe
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

# use Daemon;
# some work needed to make this a real service

our $ssdp;

sub start_artisan
{
	LOG(0,"-------------------------------------------------------");
	LOG(0,"Starting $program_name");
	LOG(0,"-------------------------------------------------------");
	dbg_mem(0,'at program startup');
	
	artisanPrefs::static_init_prefs();
	Station::static_init_stations();
	DLNARenderer::static_init_dlna_renderer_cache();
		# creates empty set of stations
	
	#---------------------------------------
	# (1) LIBRARY	
	#---------------------------------------
	# and create Real Stations after the scan if the file not found
	
	db_initialize();
	
	if (0)
	{
		# Unused code to start the Library scanner as a thread-loop
		# Struggling - cannot reliably call fpcalc.exe from a thread
		# so we don't use the thread approach ..
		display(0,0,"Starting database scanner thread");
		my $thread1 = threads->create('Library::scanner_thread');
		$thread1->detach();
	}
	
	if (artisanPrefs::getPreference($PREF_SCAN_LIBRARY_AT_STARTUP))
	{
		display(0,0,"Scanning Library ...");
		Library::scanner_thread(1);
		display(0,0,"Finished Scanning Library");
	}
	else
	{
		display(0,0,"Library Started");
	}
	
	if (!-f $Station::station_datafile)
	{
		Station::setDefaultStations();
	}
	
	
	#---------------------------------------
	# (2) RENDERER MONITOR
	#---------------------------------------
	# And possibly set the startup state
	# (PreviousRenderer, Playstate)
	
	
	if (1)   # start the Renderer monitor thread
	{
		display(0,0,"Starting Renderer Monitor ...");
		my $monitor_thread = threads->create('Renderer::auto_update_thread');
		if (!$monitor_thread)
		{
			error("Could not create Renderer auto_update thread");
		}
		else
		{
			$monitor_thread->detach();
			display(0,0,"Renderer Monitor Started");
		}
	}
	
	if (artisanPrefs::getPreference($PREF_USE_PREVIOUS_RENDERER) &&
		(my $id = artisanPrefs::getPreference($PREF_PREVIOUS_RENDERER)))
	{
		display(0,0,"Selecting Startup Renderer: $id");
		Renderer::selectRenderer($id);
	}
	
	
	
	#---------------------------------------
	# (3) HTTP SERVER
	#---------------------------------------
	
	display(0,0,"Starting HTTP Server ....)");
	my $thread2 = threads->create('HTTPServer::start_webserver');
	$thread2->detach();
	display(0,0,"HTTP Server Started");
	
	
	
	#---------------------------------------
	# (4) DLNA (SSDP) SERVER
	#---------------------------------------
	
	if (artisanPrefs::getPreference($PREF_START_DLNA_SERVER))
	{
		display(0,0,"Starting DLNA Server");
		
		$ssdp = SSDP->new();
		# Daemon::daemonize(\%SIG, \$ssdp);
		# Daemon::write_pidfile($CONFIG{'PIDFILE'}, $$);
	
		# start the listening thread and then start
		# sending alive messages
	
		if ($ssdp)
		{
			$ssdp->send_byebye(1);
			$ssdp->start_listening_thread();
			if (1)
			{
				$ssdp->start_alive_messages_thread();
			}
		}
		display(0,0,"DLNA Server Started");
	}
	else
	{
		warning(0,0,"Not starting DLNA Server")
	}
	
}	



1;
