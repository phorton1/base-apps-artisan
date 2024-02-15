#!/usr/bin/perl
#---------------------------------------
# artisanPrefs.pm
#
# Thin pass thru to Pub::Prefs.
# artisan.prefs are readonly program preferences
#	that use getPref & getPrefEncrypted
# artisan_user_prefs are temp global volume preferences
#	for the localRenderer that use getUserPref
#   and setUserPref

package artisanPrefs;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Prefs;
use artisanUtils;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		$PREF_RENDERER_MUTE
		$PREF_RENDERER_VOLUME
    );
	push @EXPORT,@Pub::Prefs::EXPORT;
}



our	$PREF_RENDERER_MUTE = "RENDERER_MUTE";
our $PREF_RENDERER_VOLUME = "RENDERER_VOLUME";

# default user preferences

my $default_user_prefs =  {
	$PREF_RENDERER_MUTE => 0,
	$PREF_RENDERER_VOLUME => 80,
};



sub static_init_prefs
{
	Pub::Prefs::initPrefs("$data_dir/artisan.prefs");
	Pub::Prefs::initUserPrefs("$temp_dir/artisan_user.prefs",$default_user_prefs);

}





1;
