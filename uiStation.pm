#-----------------------------------------
# uiStation.pm
#-----------------------------------------
# Handle webUI requests starting with /station

package uiStation;
use strict;
use warnings;
use Utils;
use uiUtils;
use Station;
use Renderer;


sub station_request
{
	my ($path,$params) = @_;
	display($dbg_webui,0,"station_request($path)");

	#------------------------------------------------
	# commands
	#------------------------------------------------
	# that return
	
	if ($path eq 'get_station')
	{
		my $station_num = $params->{station};
		my $station = getStation($station_num);
		if (!$station)
		{
			return json_error("illegal station number($station_num) in get_station");
		}
		return json_header().json($station);
	}

	# HTML - get_stations and get_edit stations return - HTML
	# prh - this should be converted to json
	
	elsif ($path =~ /^get_(renderer|edit|song)_stations$/)
	{
		my $what = $1;
		my $stations = getStations();
		my $cur_renderer = getSelectedRenderer();
		
		my $text = '';
		$text .= start_station_song_table() if ($what eq 'song');
		for my $id (sort{$a <=> $b}(keys(%$stations)))
		{
			my $station = $stations->{$id};
			$text .= station_list_button($what,$station);
		}
		$text .= end_station_song_table() if ($what eq 'song');

		my $response = http_header();
		$response .= $text."\r\n";
		display($dbg_webui+2,0,"returning response=$response");
		return $response;
	}
	
	# from here down, the commands return json_errors
	# and fall thru to json {OK} on success
	
	elsif ($path eq 'set_station_bit')
	{
		my $station_num = $params->{station};
		my $item_id = $params->{item_id};
		my $on = $params->{checked} || 0;
		my $station = getStation($station_num);
		if (!$station)
		{
			return json_error("Could not get station($station_num} in set_station_bit");
		}
		if (!$item_id)
		{
			return json_error("No item_id("._def($item_id).") in set_station_bit");
		}
		
		if ($item_id =~ s/^track_//)
		{
			if (!$station->setTrackStationBit($item_id,$on))
			{
				return json_error("setTrackStationBit($params) failed");
			}
		}
		elsif (!$station->setFolderStationBit($item_id,$on))
		{
			return json_error("setFolderStationBit($params) failed");
		}
	}
	
	# not used yet (may not be correctly implemented)
	
	elsif ($path eq 'clear_all_stations')
	{
		if (!clearStations())
		{
			return json_error("clearAllStations() failed");
		}
	}
	elsif ($path eq 'clear_current_station')
	{
		if (!clearStations(getStationNum()))
		{
			return json_error("clearAllStations() failed");
		}
	}
	
	# STATION INFO COMMANDS
	
	elsif ($path eq 'set_station_info')
	{
		my $station_num = $params->{station};
		my $field = $params->{field};
		my $value = $params->{value};
		my $station = getStation($station_num);
		if (!$station)
		{
			return json_error("Could not get station($station_num} in set_station_bit");
		}
		display($dbg_webui-1,0,"set_station_info($station->{name},$field,$value)");
		$station->{$field} = $value;
	
		Station::write_stations();
		
		# regenerate the songlist
		# except on track changes
		
		if ($field ne 'track_index')
		{
			display($dbg_webui-1,1,"REBUILDING STATION LIST");
			$station->setStationList($station);
		}
		
		# resart the renderer if it's the current station
		
		my $selected = getSelectedRenderer();

		display($dbg_webui-1,0,"set_station_info() selected="._def($selected));
		
		display($dbg_webui-1,1,"station="._def($selected->{station})) if ($selected);
		
		display($dbg_webui-1,1,"name="._def($selected->{station}->{name})."  ".
			"station_num="._def($selected->{station}->{station_num}))
			if ($selected && $selected->{station});

		if ($selected &&
			$selected->{station} &&
			$selected->{station}->{station_num} == $station->{station_num})
		{
			if ($field eq 'track_index')
			{
				$selected->async_play_song(0);
			}
			else
			{
				$selected->stop();
			}
		}
	}
	
	# UNKNOWN COMMAND
	
	else
	{
		return json_error("unknown uiStation command: $path");
	}

	# SUCCESS RETURN
	
	return json_header() . '[' . json({result=>'OK'}) . ']';
		
}



sub start_station_song_table
{
	return
		"<table id='renderer_song_stations_table'>".
		"<tr>\n";
}

sub end_station_song_table
{
	return "</td></tr></table>";
}



sub station_list_button
{
	my ($what,$station) = @_;
	my $station_num = $station->{station_num};
	my $type = $what eq 'song' ? 'checkbox' : 'radio';
	
	my $text = '';
	if ($what eq 'song')
	{
		if ($station_num =~ /^(9|17|25)$/)
		{
			$text .= "</tr><tr>\n";
		}
		if ($station_num != 32)
		{
			$text .= "</td>\n";
		}
		$text .= "<td class='renderer_song_stations_td'>\n";
	}
	
	$text .= "<input type=\"$type\" ";
	$text .= "id=\"" . $what . "_station_list_button_$station_num\" ";
	$text .= "class=\"". $what ."_station_list_button\" ";
	$text .= "onclick=\"javascript:select_".$what."_station($station_num);\" ";
	$text .= "name=\"". $what ."_station_list_set\">";
	$text .= "<label for=\"". $what . "_station_list_button_$station_num\">";
	$text .= "$station->{name}</label>";
	
	$text .= "<br>" if ($what ne 'song');
	$text .= "\n";
	
	return $text;

}

1;
