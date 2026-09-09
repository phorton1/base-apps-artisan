#!/usr/bin/perl
#---------------------------------------
# artisanPrefs.pm
#---------------------------------------
# Initializes the standard Pub::Prefs API on the
# library's artisan.prefs file.  The device renderer's
# volume and mute, once kept in a file here, are now
# part of the state set; see Playlist.pm.

package artisanPrefs;
use strict;
use warnings;
use Pub::Prefs;
use artisanUtils;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw ( );
	push @EXPORT,@Pub::Prefs::EXPORT;
}


sub static_init_prefs
{
	Pub::Prefs::initPrefs("$data_dir/artisan.prefs");
}



1;
