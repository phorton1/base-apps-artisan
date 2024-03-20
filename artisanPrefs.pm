#!/usr/bin/perl
#---------------------------------------
# artisanPrefs.pm
#
# Adds support for separate renderer_defaults.txt
# to standard Pubs::Prefs API.

package artisanPrefs;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Prefs;
use artisanUtils;

my $dbg_defaults = 0;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		$PREF_RENDERER_MUTE
		$PREF_RENDERER_VOLUME

		getDefaultMute
		getDefaultVolume
		setDefaultMute
		setDefaultVolume

		setUserPref
    );
	push @EXPORT,@Pub::Prefs::EXPORT;
}


my $default_mute:shared = 0;
my $default_volume:shared = 80;
my $renderer_defaults_file = "$temp_dir/renderer_defaults.txt";




sub static_init_prefs
{
	Pub::Prefs::initPrefs("$data_dir/artisan.prefs");

	my @lines = getTextLines($renderer_defaults_file);
	my $line = shift @lines;
	if ($line)
	{
		($default_volume,$default_mute) = split(/,/,$line);
		$default_volume ||= 0;
		$default_mute ||= 0;
		display($dbg_defaults,0,"read renderer_defaults($default_volume,$default_mute)");
	}
}



sub write_renderer_defults
{
	my $text = "$default_volume,$default_mute\n";
	display($dbg_defaults+1,0,"write renderer_defaults($default_volume,$default_mute)");
	printVarToFile(1,$renderer_defaults_file,$text);
}


sub getDefaultMute { return $default_mute; }
sub getDefaultVolume { return $default_volume; }
sub setDefaultMute { $default_mute = shift; write_renderer_defults(); }
sub setDefaultVolume { $default_volume = shift; write_renderer_defults(); }



1;
