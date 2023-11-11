#-----------------------------------------------
# uiPLSource.pm
#-----------------------------------------------

package uiPLSource;
use strict;
use warnings;
use artisanUtils;
use Device;
use DeviceManager;
use uiUtils;


my $dbg_uipls = 0;
	# 0 == show requests
	# 1 == show simple reponses
	# 2 == show complex responses
my $dbg_loops = 1;
	# 0 == show things that happen in a loop (i.e. updating a renderer?!?)
my $dbg_pls = 1;
	# 0 == show shuffling of playlists


sub plsource_request
{
	my ($path,$params) = @_;

	return json_error("could not find plsource uuid in '$path'")
		if $path !~ s/^(.*?)\///;
	my $uuid = $1;

	# Get the renderer

	my $plsource = findDevice($DEVICE_TYPE_PLSOURCE,$uuid);
	return json_error("could not find plsource '$uuid'") if !$plsource;

	if ($path eq 'get_playlist_json')
	{
		my $name = $params->{name};
		display($dbg_uipls,0,"plsource_request($path,$name)");
		my $playlist = $plsource->getPlaylist($name);
		return json_error("Could not find playlist($name}")
			if !$playlist;
		return json_header().json($playlist);
	}
	elsif ($path eq 'get_playlists')
	{
		display($dbg_uipls,0,"plsource_request($path)");

		my $playlist_names = $plsource->getPlaylistNames();
		my $html = html_header();
		for my $name (@$playlist_names)
		{
			$html .= getPlaylistMenuHTML($name);
		}
		# display(0,0,"get_playlists returning $html");
		return $html;
	}

	# STATION INFO COMMANDS

	elsif ($path eq 'set_playlist_info')
	{
		# 'shuffle' or 'track_index'
		# it is the responsibility of the UI to re-call
		# Renderer::setPlaylist() if they modify it!

		my $name = $params->{name};
		my $field = $params->{field};
		my $value = $params->{value};
		display($dbg_uipls,0,"plsource_request($path,$name,$field,$value)");
		my $json = $plsource->setPlaylistInfo($name,$field,$value);
			# returns the json for the playlist, or json containing
			# error=>msg
		return json_header().$json;
	}

	# UNKNOWN COMMAND

	return json_error("plsource_ui(unknown request): $path");
}


sub getPlaylistMenuHTML
{
	my ($name) = @_;
	my $text = '';
	$text .= "<input type=\"radio\" ";
	$text .= "id=\"playlist_button_$name\" ";
	$text .= "class=\"playlist_button\" ";
	$text .= "onclick=\"javascript:set_playlist('$name');\" ";
	$text .= "name=\"playlist_button_set\">";
	$text .= "<label for=\"playlist_button_$name\">";
	$text .= "$name</label>";
	$text .= "<br>";
	$text .= "\n";
	return $text;

}



1;
