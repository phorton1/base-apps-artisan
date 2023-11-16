#-----------------------------------------------
# uiRenderer.pm
#-----------------------------------------------

package uiRenderer;
use strict;
use warnings;
use artisanUtils;
use httpUtils;
use Device;
use DeviceManager;
use Renderer;


my $dbg_uir = 1;
	# 0 == show requests
	# 1 == show simple reponses
	# 2 == show complex responses
my $dbg_loops = 1;
	# 0 == show things that happen in a loop (i.e. updating a renderer?!?)
my $dbg_pls = 1;
	# 0 == show shuffling of playlists


sub renderer_request
{
	my ($path,$params) = @_;

	# Artisan Perl has no notion of a selected renderer
	# The ui makes request to a path that starts with the UUID
	# of the renderer selected in the ui ...

	return json_error("could not find renderer uuid in '$path'")
		if $path !~ s/^(.*?)\///;
	my $uuid = $1;

	# Get the renderer, do the command, return error if it fails,
	# or return the render as json if it succeeds.

	my $renderer = findDevice($DEVICE_TYPE_RENDERER,$uuid);
	return json_error("could not find renderer '$uuid'") if !$renderer;
	my $error = $renderer->doCommand($path,$params);
	return json_error("renderer_request($path) error: $error")
		if $error;
	return json_header().json($renderer);

	if ($path eq 'stop')
	{
		if ($renderer->{playlist} && !$renderer->setPlaylist(undef))
		{
		}
		if (!$renderer->stop())
		{
			return json_error("could not issue stop() command");
		}
	}
	elsif ($command eq 'play_pause')
	{
		if ($renderer->{state}  =~ /^PLAYING/)
		{
			if (!$renderer->command('pause'))
			{
				return json_error("Could not call renderer->command(pause)");
			}
		}
		elsif (!$renderer->play())
		{
			return json_error("Could not issue play() command");
		}
    }
	elsif ($command eq 'set_position')
	{
		my $position = $params->{position};
		if (!defined($position) ||
			$position !~ /^\d+$/)
		{
			return json_error("illegal value in set_position("._def($position).")");
		}
		if (!$renderer->set_position($position))
		{
			return json_error("could not call renderer->set_position($position)");
		}
	}

	# transport commands that work on the playlist

	elsif ($command eq 'next')
	{
		if ($renderer->{playlist})
		{
			#if (!$renderer->play_next_song())
			if (!$renderer->async_play_song(1))
			{
				return json_error("could not call renderer->play_next_song()");
			}
		}
		else
		{
			# can't get bubbleUp to do Next or Prev
			return json_error("transport_next not supported for raw renderers");
		}
	}
	elsif ($command eq 'prev')
	{
		if ($renderer->{playlist})
		{
			# if (!$renderer->play_prev_song())
			if (!$renderer->async_play_song(-1))
			{
				return json_error("could not call renderer->play_prev_song()");
			}
		}
		else
		{
			# can't get bubbleUp to do Next or Prev
			return json_error("transport_prev not supported for raw renderers");
		}
	}























	# deprecating use of $params

	# not implemented yet
	if ($path =~ /^play_song\/(.*)\/(.*?)$/)		# should include library uuid
	{
		display($dbg_uir,0,"play_song($params->{song_id})");
		my ($library_uuid,$track_id) = ($1,$2);
		if (!$renderer->play_single_song($library_uuid,$track_id))
		{
			return json_error("uiRenderer - could not play_song($params->{song_id})");
		}
		my $response = json_header();
		$response .= json($renderer);
		display($dbg_uir+2,1,"play_song returning response=$response");
		return $response;
	}

	if ($path eq 'update_renderer')
	{
		return update($renderer);
	}

	if ($path =~ /^set_playlist\/(.*)\/(.*?)$/)
	{
		my ($pls_uuid,$playlist_name) = ($1,$2);
		display($dbg_uir,0,"set_playlist($pls_uuid,$playlist_name)");
		if (!$renderer->doCommand('set_playlist',$pls_uuid,$playlist_name))
		{
			return json_error("uiRenderer - could not set_playlist($pls_uuid,$playlist_name)");
		}
		my $response = json_header();
		$response .= json($renderer);
		display($dbg_uir+2,1,"set_playlist returning response=$response");
		return $response;
	}
	if ($path eq 'transport')
	{
		return transport($renderer,$params);
	}

	return json_error("uiRenderer unknown request): $path");
}















sub update
{
	my ($renderer) = @_;
	display($dbg_loops,0,"update($renderer) called");

	# if the renderer is playing a playlist, we don't call update
	# and just return the renderer ... otherwise we call update()

	$renderer->{error} = '';
	if (!$renderer->{playlist})
	{
		if (!$renderer->update())
		{
			return json_error("call to renderer->update() failed");
		}
	}

	my $response = json_header();
	$response .= json($renderer);
	display($dbg_loops+1,1,"returning response=$response");
	return $response;
}






sub playlist_request
{
	my ($path,$params) = @_;
	display($dbg_pls,0,"playlist_request($path)");

	if ($path eq 'get_playlist')
	{
		my $name = $params->{name};
		my $playlist = getPlaylist($name);
		if (!$playlist)
		{
			return json_error("Unknown playlist name($name) in get_playlist");
		}
		return json($playlist);
	}
	elsif ($path eq 'get_playlists')
	{
		my $playlists = getPlaylists();
		my $xml = json_header();
		for my $playlist (@$playlists)
		{
			$xml .= getPlaylistButtonHTML($playlist);
		}
		return $xml
	}

	# STATION INFO COMMANDS

	elsif ($path eq 'set_playlist_info')
	{
		# 'shuffle' or 'track_index'

		my $name = $params->{name};
		my $field = $params->{field};
		my $value = $params->{value};
		my $playlist = getPlaylist($name);
		if (!$playlist)
		{
			return json_error("Unknown playlist name($name) in set_playlist_info");
		}

		display($dbg_pls,1,"set_playlist_info($playlist->{name},$field,$value)");
		$playlist->{$field} = $value;

		# regenerate the songlist
		# except on track changes

		if ($field eq 'track_index')
		{
			$playlist->save();
		}
		elsif ($field eq 'shuffle')
		{
			display($dbg_pls,1,"REBUILDING STATION LIST");
			$playlist->sortPlaylist();
		}

		# resart the renderer if it's the current station

		my $renderer = Renderer::getSelectedRenderer();

		if ($renderer &&
			$renderer->{playlist} &&
			$renderer->{playlist}->{name} eq $name)
		{
			# if ($field eq 'track_index')
			# {
				$renderer->async_play_song(0);
			# }
			# else
			# {
			# 	$renderer->stop();
			# }
		}
	}

	# UNKNOWN COMMAND

	else
	{
		return json_error("unknown renderer playlist command: $path");
	}

	# SUCCESS RETURN

	return json_header() . '[' . json({result=>'OK'}) . ']';

}


sub getPlaylistButtonHTML
{
	my ($playlist) = @_;
	my $text = '';
	$text .= "<input type=\"radio\" ";
	$text .= "id=\"playlist_button_$playlist->{name}\" ";
	$text .= "class=\"playlist_button\" ";
	$text .= "onclick=\"javascript:select_playlist('$playlist->{name}');\" ";
	$text .= "name=\"playlist_button_set\">";
	$text .= "<label for=\"playlist_button_$playlist->{name}\">";
	$text .= "$playlist->{name}</label>";
	$text .= "<br>";
	$text .= "\n";
	return $text;

}



1;
