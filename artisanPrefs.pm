#!/usr/bin/perl
#---------------------------------------
# artisanPrefs.pm
#
# The preferences for the Pure-Perl Artisan Server,
# loaded at the top of artisan.pm, with safe defaults
# for the artisanWin application.

# In other words, these are global preferences
# for the current instance of the server.

package artisanPrefs;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;

my $dbg_prefs = 1;
	# 0 = show static_init_prefs() header msg
	# -1 = show individual prefs
my $dbg_web_prefs = 1;
	# 0 = show setting of prefs


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (

		getPreference
		setPreference

		$PREF_RENDERER_MUTE
		$PREF_RENDERER_VOLUME
    );
}


#-----------------------------
# variables
#-----------------------------

our	$PREF_RENDERER_MUTE = "RENDERER_MUTE";
our $PREF_RENDERER_VOLUME = "RENDERER_VOLUME";


# default preferences

my @default_prefs =  (
	$PREF_RENDERER_MUTE => 0,
	$PREF_RENDERER_VOLUME => 80,
);

my %g_prefs:shared = @default_prefs;



#---------------------------------------
# accessors
#---------------------------------------

sub prefFilename()
{
	return "$temp_dir/artisan.prefs";
}


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
	write_prefs();
}


#-----------------------------------------
# read and write text file
#-----------------------------------------

sub static_init_prefs
{
	my $filename = prefFilename();
	display($dbg_prefs,0,"Reading prefs from $filename");
	if (-f $filename)
	{
	    my @lines = getTextLines($filename);
        for my $line (@lines)
        {
			my $pos = index($line,'=');
			if ($pos > 1)
			{
				my $left = substr($line,0,$pos);
				my $right = substr($line,$pos+1);
				display($dbg_prefs,0,"pref($left)='$right'");
				$g_prefs{$left} = $right;
		    }
		}
    }
	elsif (0)	# create an empty prefs file
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

	my $filename = prefFilename();
    if (!printVarToFile(1,$filename,$text,1))
    {
        error("Could not write prefs to $filename");
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
		$response .= my_encode_json(\%g_prefs);
		return $response;
	}

	if ($param eq 'set')
	{
		use Data::Dumper;
		$Data::Dumper::Indent = 1;
		$Data::Dumper::Sortkeys = 1;
		display($dbg_web_prefs,0,"prefs_request(set) post_xml=".Dumper($post_xml));

		# set the prefs from the post_xml

		my $response = json_header();
		$response .= my_encode_json(\%g_prefs);
		return $response;
	}

	if ($param eq 'defaults')
	{
		%g_prefs = @default_prefs;
		write_prefs();
		my $response = json_header();
		$response .= my_encode_json(\%g_prefs);
		return $response;
	}

	# user interface request

	return xml_error("unknown uiPrefs command: $param");
}



# static_init_prefs();


1;
