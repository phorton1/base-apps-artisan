#-----------------------------------------------
# uiRenderer.pm
#-----------------------------------------------
	
package uiRenderer;
use strict;
use warnings;
use Utils;
use uiUtils;
use uiPrefs;
use Renderer;
use Station;


sub renderer_request
{
	my ($path,$params) = @_;

	if ($path eq 'get_renderers')
	{
		# HTML REQUEST 
		return renderer_get_renderers($params->{refresh});
	}
	if ($path eq 'select_renderer')
	{
		return renderer_select_renderer($params->{id});
	}
	if ($path eq 'get_selected_renderer')
	{
		return renderer_get_selected_renderer();
	}
	
	
	# get renderer for following requests
	# use the one passed in if PREF_MULTIPLE_RENDERES
	# otherwise, return the currently selected renderer
	
	my $renderer;
	if (getPreference($PREF_MULTIPLE_RENDERERS))
	{
		$renderer = getRenderer($params->{id});
	}
	else
	{
		$renderer = getSelectedRenderer();
	}
	if (!$renderer)
	{
		return json_error("no renderer in command $path");
	}
	
	# handle requests that require a renderer
	
	if ($path eq 'play_song')
	{
		if (!$renderer->play_single_song($params->{song_id}))
		{
			return json_error("web_ui - could not play_song($params->{song_id})");
		}
		my $response = json_header();
		$response .= json($renderer);
		display($dbg_webui+2,0,"returning response=$response");
		return $response;
	}
	if ($path eq 'update_renderer')
	{
		return renderer_update($renderer);
	}
	if ($path eq 'set_station')
	{
		return renderer_set_station($renderer,$params->{station});
	}
	if ($path eq 'transport')
	{
		return renderer_transport($renderer,$params);
	}

	return json_error("web_ui(unknown renderer request): $path");
}



sub renderer_get_renderers
{
	my ($refresh) = @_;
	$refresh ||= 0;
	display($dbg_webui,0,"renderer_get_renderers($refresh) called");
	
	# output the static refresh/clear buttons

	my $text = '';
	$text .= "<table width='100%' align='center'><tr>";

	$text .= "<td width='33%' align='center'>";
	$text .= "<button ";
	$text .= "id=\"renderer_off_button\" ";
	$text .= "class=\"renderer_top_button\" ";
	$text .= "onclick=\"javascript:stop_monitor();\">";
	$text .= "off</button>";
	$text .= "</td>";
	
	$text .= "<td width='33%' align='center'>";
	$text .= "<button ";
	$text .= "id=\"renderer_refresh_button\" ";
	$text .= "class=\"renderer_top_button\" ";
	$text .= "onclick=\"javascript:refresh_renderers(1);\">";
	$text .= "refresh</button>";
	$text .= "</td>";
	
	$text .= "<td width='33%' align='center'>";
	$text .= "<button ";
	$text .= "id=\"renderer_clear_button\" ";
	$text .= "class=\"renderer_top_button\" ";
	$text .= "onclick=\"javascript:refresh_renderers(2);\">";
	$text .= "clear</button>";
	$text .= "</td>";
	
	$text .= "</tr></table>";
	$text .= "<br>";
	
	# output the list of renderers
	
	my $renderers = getRenderers($refresh);
	my $cur_renderer = getSelectedRenderer();
	for my $id (sort(keys(%$renderers)))
	{
		my $renderer = $renderers->{$id};
		$text .= "<input type=\"radio\" ";
		$text .= "id=\"$id\" ";
		$text .= "class=\"renderer_list_button\" ";
		$text .= "onclick=\"javascript:select_renderer('$id');\" ";
		$text .= "name=\"renderer_list\">";
		$text .= "<label for=\"$id\">$renderer->{friendlyName}</label><br>\n";
	}
	my $response = http_header();
	$response .= $text."\r\n";
	display($dbg_webui+2,0,"returning response=$response");
	return $response;
}


sub renderer_select_renderer
{
	my ($id) = @_;
	display($dbg_webui,0,"renderer_select_renderer($id) called");
	my $renderer = selectRenderer($id);
	if (!$renderer)
	{
		return json_error("no renderer returned in renderer_select_renderer()");
	}
	my $response = json_header();
	$response .= json($renderer);
	display($dbg_webui+2,0,"returning response=$response");
	return $response;
}


sub renderer_get_selected_renderer
{
	my ($id) = @_;
	display($dbg_webui,0,"renderer_get_selected_renderer() called");
	my $renderer = getSelectedRenderer();
	if (!$renderer)
	{
		return json_error("no renderer in renderer_get_selected_renderer()");
	}
	my $response = json_header();
	$response .= json($renderer);
	display($dbg_webui+2,0,"returning response=$response");
	return $response;
}



sub renderer_update
{
	my ($renderer) = @_;
	display($dbg_webui+1,0,"renderer_update($renderer) called");

	# if the renderer is playing a station, we don't call update
	# and just return the renderer ... otherwise we call update()

	$renderer->{error} = '';
	if (!$renderer->{station})
	{
		if (!$renderer->update())
		{
			return json_error("call to renderer->update() failed");
		}
	}

	my $response = json_header();
	$response .= json($renderer);
	display($dbg_webui+2,0,"returning response=$response");
	return $response;
}


sub renderer_set_station
{
	my ($renderer,$station_num) = @_;
	display($dbg_webui,0,"renderer_set_station($renderer->{friendlyName},$station_num) called");
	my $station = getStation($station_num);
	if (!$renderer->setStation($station))
	{
		return json_error("could not issue setStation($station_num) command");
	}
	my $response = json_header();
	$response .= json($renderer);
	display($dbg_webui+2,0,"returning response=$response");
	return $response;
}


sub renderer_transport
	# do raw transport commands and return the
	# return the renderer or an error, but the
	# effect of the command wont be visible to
	# the UI until the next renderer_update() call
{
	my ($renderer,$params) = @_;
	my $command = $params->{command} || '';
	display($dbg_webui,0,"renderer_transport($renderer->{friendlyName},$command) called");
	
	# transport commands that work on raw renderers
	
	if ($command eq 'stop')
	{
		if ($renderer->{station} && !$renderer->setStation(undef))
		{
			return json_error("could not issue setStation(undef) command");
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
			if (!$renderer->doAction(0,'Pause'))
			{
				return json_error("Could not call doAction('Pause')");
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
			$position !~ /^\d+$/ ||
			$position > 100)
		{
			return json_error("illegal value in set_position("._def($position).")");
		}
		if (!$renderer->set_position($position))
		{
			return json_error("could not call renderer->set_position($position)");
		}
	}

	# transport commands that work on the 'radio station'
	
	elsif ($command eq 'next')
	{
		if ($renderer->{station})
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
		if ($renderer->{station})
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
	
	# unknown command
	
	else
	{
		return json_error("unknown command in renderer_transport: $command");
	}
	
	my $response = json_header();
	$response .= json($renderer);
	display($dbg_webui+2,0,"returning response=$response");
	return $response;
	
}




1;

