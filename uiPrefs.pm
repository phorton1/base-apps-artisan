#!/usr/bin/perl
#---------------------------------------
# uiPrefs.pm
#
# The server preferences for the webUI.
#
# This module provides configuation settings for the rest of
# the UI. as well as providing the UI to the preferences.
#
# These preferences are common to all instances
# of the webUI for a given Artisan server. 
# In other words, these are global preferences
# for the current instance of the server.

package uiPrefs;
use strict;
use warnings;
use threads;
use threads::shared;
use Utils;
use uiUtils;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		getPreference
		setPreference

		$PREF_MULTIPLE_RENDERERS

    );
}


#-----------------------------
# variables
#-----------------------------

our $PREF_MULTIPLE_RENDERERS = 'MULTIPLE_RENDERERS';


# default preferences

my @default_prefs =  (
#	$PREF_THEME => 'default',
#	$PREF_THEME_MOBILE => 'black',
#	$PREF_START_PANE => 'renderer',
	$PREF_MULTIPLE_RENDERERS => 0,
#	$PREF_SHOW_NUM_TRACKS_IN_LIBRARY_TREE => 1,
);

my %g_prefs:shared = @default_prefs;

my $pref_filename = "$cache_dir/artisan_prefs.txt";


#---------------------------------------
# accessors
#---------------------------------------

sub getPreference
{
	my ($name) = @_;
	return $g_prefs{$name};
}

sub setPreference
	# preferenes must be shared scalars
{
	my ($name,$value) = @_;
	$g_prefs{$name} = $value;
}


#-----------------------------------------
# read and write text file
#-----------------------------------------

sub static_init_prefs
{
	if (-f $pref_filename)
	{
	    my $lines = getTextLines($pref_filename);
        for my $line (@$lines)
        {
            chomp($line);
			my $pos = index($line,'=');
			if ($pos > 1)
			{
				my $left = substr($line,0,$pos);
				my $right = substr($line,$pos+1);
				display(0,0,"pref($left)='$right'");
				$g_prefs{$left} = $right;
		    }
		}
    }
	else
	{
		write_prefs();
	}
}


sub write_prefs
{
    my $text = '';
    for my $k (sort(keys(%g_prefs)))
    {
        $text .= "$k=$g_prefs{$k}\n";
    }
	
	# text files to export to android must be written
	# in binary mode with just \n's
	
    if (!printVarToFile(1,$pref_filename,$text,1))
    {
        error("Could not write prefs to $pref_filename");
        return;
    }
    return 1;
}



#----------------------------------------------
# handle pref requests
#----------------------------------------------

sub prefs_request
{
	my ($param,$post_xml) = @_;

	if ($param eq 'get')
	{
		my $response = json_header();
		$response .= json(\%g_prefs);
		return $response;
	}
	
	if ($param eq 'set')
	{
		use Data::Dumper;
		display($dbg_webui-1,0,"prefs_request(set) post_xml=".Dumper($post_xml));
		
		# prh - set the prefs from the post_xml
		
		my $response = json_header();
		$response .= json(\%g_prefs);
		return $response;
	}

	if ($param eq 'defaults')
	{
		%g_prefs = @default_prefs;
		write_prefs();
		my $response = json_header();
		$response .= json(\%g_prefs);
		return $response;
	}
	
	# user interface request
	
	return xml_error("unknown uiPrefs command: $param");
}



static_init_prefs();


1;
