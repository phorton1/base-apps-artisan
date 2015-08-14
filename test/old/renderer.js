//--------------------------------------------------
// renderer.js
//--------------------------------------------------
// Javascript particular to the renderer_pane, generic to
// all versions of the artisan webUI (desktop and car-stereo)
//
// Expects a renderer.html layout with the Now Playing elements,
// and a renderer_list which will be populated automatically on
// loading.

var in_slider = false;
var current_renderer = false;
var renderer_list = false;


$('#renderer_pane').ready(function()
{
	$('#renderer_song_slider').slider({
		onComplete : on_slider_complete,
		onSlideStart : function(value) {
			// alert('onSlideStart');
			in_slider=true;
		},
		onSlideEnd : function(value) { in_slider=false },
		tipFormatter: get_slider_tip,
	});

	// first time initialization
	// get selected renderer, if any, from the server
	// we ignore errors and are only interested in
	// a valid renderer if one is returned
	
	$.get('/webui/renderer/get_selected_renderer', function(result)
	{
		if (result.error)
		{
			// rerror('Error in on_select_renderer(): ' + result.error);
		}
		else
		{
			current_renderer = result;
		}
		update_renderer_ui();
	});

	// start the monitor loop	
	
	monitor_loop();

});




//----------------------------------------------
// monitor loop
//----------------------------------------------
// pause and unpause_monitor functions are
// preambles to methods that call the webui,
// to prevent re-entrancy collisions with monitor_loop


function monitor_loop()
{
	if (current_renderer && !in_slider)
	{
		update_renderer();
	}
	
	monitor_timer = window.setTimeout("monitor_loop()", 1000);
	
}	// monitor_loop



//--------------------------------------------
// event handlers
//--------------------------------------------

function unused_refresh_renderers(clear)
	// called by onclick in buttons, this
	// updates the list of renderers, which *may*
	// result in the current renderer disappearing,
	// which will be handled in on_load_renderers().
{
	var param = clear ? 2 : 1;
	$('#renderer_list').treegrid({
		queryParams: {
			refresh:param
		}
	});	
}



function on_select_renderer(row,data)
	// called by easy-ui event registration on the renderer_list
	// when the user changes the current selection.
	// Set the current renderer name and enable the buttons.
	// We have to be careful about re-entrancy, so that we don't
	// confuse the server.
{
	hide_artisan_menu();
	$.get('/webui/renderer/select_renderer(' + data.id + ')', function(result)
	{
		if (result.error)
		{
			rerror('Error in on_select_renderer(): ' + result.error);
			current_renderer = false;
		}
		else
		{
			current_renderer = result;
		}
		update_renderer_ui();
	});
}



function transport_command(what)
{
	if (!current_renderer)
	{
		rerror("No current_renderer in transport_command: " + what);
		return;
	}

	jQuery.ajaxSetup({async:true});	
	
	$.get('/webui/renderer/transport_' + what + '(' + current_renderer.id + ')',
		function(result)
		{
			if (result.error)
			{
				rerror('Error in transport_command(' + what + '): ' + result.error);
				current_renderer = false;
			}
			else
			{
				current_renderer = result;
			}
			update_renderer_ui();
		}
	);

	jQuery.ajaxSetup({async:false});	
}



function on_slider_complete(value)
{
	if (!current_renderer)
	{
		rerror("No current_renderer in on_slider_complete(" + value + ')');
		return true;
	}
	
	$.get('/webui/renderer/set_position_' + value + '(' + current_renderer.id + ')',
		function(result)
		{
			if (result.error)
			{
				rerror('Error in on_slider_complete(' + value + '): ' + result.error);
				current_renderer = false;
			}
			else
			{
				current_renderer = result;
			}
			
			in_slider=false; 
				// this *might* be needed in async mode
				// if I ever get it working
				
			update_renderer_ui();
			return true;
		}
	);
	
	return true;
}



function get_slider_tip(value)
{
	if (!current_renderer || !current_renderer.duration || !in_slider)
	{
		return '';
	}
	
	var dur = time_to_secs(current_renderer.duration);
	var reltime = parseInt((value/100) * dur);
	return secs_to_time(reltime);
}





function update_renderer()
{
	$.get('/webui/renderer/update_renderer(' + current_renderer.id + ')',
		function(result)
		{
			if (result.error)
			{
				rerror('Error in update_renderer(): ' + result.error);
				current_renderer = false;
			}
			else
			{
				current_renderer = result;
			}
			update_renderer_ui();
		}
	);
}





//--------------------------------------------
// UI
//--------------------------------------------


function update_renderer_ui()
{
	var disable = true;
	var disable_station = true;
	var stop_disabled = true;

	var shuffle_on = 'renderer_control_off';
	var repeat_on = 'renderer_control_off';
	var station_off = 'renderer_control_off';
	var station = [
		'renderer_control_off',
		'renderer_control_off',
		'renderer_control_off',
		'renderer_control_off',
		'renderer_control_off',
		'renderer_control_off' ];

	var state = '';
	var stationName = 'Now Playing';
	var friendlyName = 'No Renderer Selected';
	
	var art_uri = '/webui/icons/artisan.png';
	var song_title = '&nbsp;';
	var album_artist = '&nbsp;';
	var album_title = '&nbsp;';
	var album_track = '&nbsp;';
	var song_genre = '&nbsp;';
	
	var play_pct = 0;
	var reltime = '0:00';
	var duration = '0:00';
	var play_type_size = '';
	
	var pause_button_label = ' > ';
	var pause_button_on = 'renderer_control_off';
	
	//-----------------------------------------------
	// set the values from current renderer if any
	//-----------------------------------------------
	// start with the friendlyName
	// stationName, and overall disable booleans
	
	if (current_renderer)
	{
		disable = false;
		state = current_renderer.state;
		friendlyName = current_renderer.friendlyName;
		if (current_renderer.station > 0)
		{
			station_off = 'renderer_control_on';
			disable_station = false;
			station[current_renderer.station] = 'renderer_control_on';
			stationName = current_renderer.stationName;
			if (!stationName)
			{
				stationName = 'station' + current_renderer.station;
			}
			stationName += '(' +
				current_renderer.track_num + ',' +
				current_renderer.song_num + ')';
		}

		// Song Image and Metadata
		
		var metadata = current_renderer.metadata;
		
		if (metadata)
		{
			if (metadata.albumArtURI)
			{
				art_uri = metadata.albumArtURI;
			}
			else
			{
				art_uri = '/webui/icons/no_image.png';
			}
			song_title = metadata.title ? decode_ampersands(metadata.title) : '&nbsp;';
			album_artist = metadata.artist ? decode_ampersands(metadata.artist) : '&nbsp;'
			album_title = metadata.album ? decode_ampersands(metadata.album) : '&nbsp;'
			
			if (metadata.track_num && metadata.track_num > 0)
			{
				album_track = 'track: ' + metadata.track_num;
			}
			
			song_genre = '';
			if (metadata.genre)
			{
				song_genre = decode_ampersands(metadata.genre);
			}
			if (metadata.date)
			{
				if (song_genre)
				{
					song_genre += ' | ';
				}
				song_genre += metadata.date;
			}
			
			if (!song_genre)
			{
				song_genre = '&nbsp;';
			}
		}
		
		// Transport times and slider

		if (state == 'PLAYING' ||
			state == 'PLAYING_STATION')
		{
			stop_disabled = false;
			pause_button_label = ' || ';
		}
		
		if (state == 'PLAYING' ||
			state == 'PLAYING_STATION' ||
			state == 'PAUSED_PLAYBACK')
		{		
			duration = remove_leading_zeros(current_renderer.duration);
			reltime = current_renderer.reltime;
			if (duration.length < reltime.length)
			{
				reltime = reltime.substr(reltime.length-duration.length);
			}
			play_pct = current_renderer.play_pct;
			play_type_size = current_renderer.type +
				' &nbsp;&nbsp; ' +
				metadata.pretty_size;		
		}
		
		// Shuffle and Repeat buttons
		
		pause_button_on = (state == 'PAUSED_PLAYBACK' ? 'renderer_control_on' : 'renderer_control_off');
		shuffle_on = (current_renderer.shuffle>0) ? 'renderer_control_on' : 'renderer_control_off';
		repeat_on = (current_renderer.repeat>0) ? 'renderer_control_on' : 'renderer_control_off';
	}
	
	
	//----------------------------------------
	// Move the variables into the UI
	//----------------------------------------
	// Note code to change title in a easyUI header
	// var ele = $('#artisan_body');
	// var header_panel = ele.panel('header');
	// var title_panel = header_panel.find('.panel-title');
	// title_panel.html('Now Playing &nbsp;&nbsp; ' + renderer.state);
	
	if (state == 'PLAYING_STATION')
	{
		state = 'STATION';
	}
	else if (state == 'PAUSED_PLAYBACK')
	{
		state = 'PAUSED';
	}
	
	highlight_current_renderer();
	ele_set_inner_html('renderer_header_left',stationName + ' &nbsp;&nbsp; ' + state);
	ele_set_inner_html('renderer_header_right',friendlyName);
		
	// What's Playing info and image
	
	ele_set_inner_html('renderer_song_title',song_title);
	ele_set_inner_html('renderer_album_artist',album_artist);
	ele_set_inner_html('renderer_album_title',album_title); 
	ele_set_inner_html('renderer_album_track',album_track); 
	ele_set_inner_html('renderer_song_genre',song_genre);

	if (ele_get_src('renderer_album_image') != art_uri)
	{
		ele_set_src('renderer_album_image',art_uri);
	}
	
	// Playback Controls

	if (!in_slider)
	{
		$('#renderer_song_slider').slider('setValue',play_pct);
	}
	
	ele_set_inner_html('renderer_reltime',reltime);
	ele_set_inner_html('renderer_duration',duration);
	ele_set_inner_html('renderer_play_type',play_type_size);
		
	ele_set_value('renderer_button_play_pause',pause_button_label );
	ele_set_class('renderer_button_play_pause',pause_button_on);
		
	ele_set_class('renderer_button_shuffle',shuffle_on);
	ele_set_class('renderer_button_repeat',repeat_on);
	ele_set_class('renderer_station_off',station_off);

	for (var i=1; i<6; i++)
	{
		ele_set_class('renderer_station_'+i,station[i]);
	}
	
	// Enable/disable the buttons
	
	ele_set_disabled('renderer_button_shuffle',disable_station);
	ele_set_disabled('renderer_button_prev',disable_station);
	ele_set_disabled('renderer_button_play_pause',disable);
	ele_set_disabled('renderer_button_stop',stop_disabled);
	ele_set_disabled('renderer_button_next',disable_station);
	ele_set_disabled('renderer_button_repeat',disable_station);
	
	ele_set_disabled('renderer_station_off',disable_station);
	ele_set_disabled('renderer_station_1',disable);
	ele_set_disabled('renderer_station_2',disable);
	ele_set_disabled('renderer_station_3',disable);
	ele_set_disabled('renderer_station_4',disable);
	ele_set_disabled('renderer_station_5',disable);
	ele_set_disabled('renderer_station_6',disable);
	ele_set_disabled('renderer_station_remove',disable);

}	// update_renderer_ui()





function highlight_current_renderer()
{
	if (renderer_list)
	{
		var index = -1;
		if (current_renderer)
		{
			var rows =  $('#renderer_list').datagrid('getRows');
			for (var i=0; i<rows.length; i++)
			{
				if (rows[i].id == current_renderer.id)
				{
					index = i;
					break;
				}
			}
			name = current_renderer.friendlyName;
		}
		
		if (index != -1)
		{
			 $('#renderer_list').datagrid('selectRow',index);
		}
		else
		{
			 $('#renderer_list').datagrid('clearSelections');
		}
	}
}	



function remove_leading_zeros(st)
{
	var pos = 0;
	var len = st.length;
	while (pos<4 && pos<len)
	{
		var c = st.substr(pos,1);
		if (c != '0' && c != ':')
		{
			break;
		}
		pos++;
	}
	if (pos)
	{
		st = st.substr(pos);
	}
	return st;
}



function secs_to_time(secs)
{
    var retval = '';
    while (secs)
    {
        var part = secs % 60;
		if (part < 10)
		{
			part = '0' + part;
		}
		if (retval)
		{
			retval = ':' + retval;
		}
        retval = part + retval;
        secs = parseInt(secs / 60);
    }
	if (!retval)
	{
		retval = '0:00';
	}
	
	if (retval.length < 3)
	{
		retval = '0:' + retval;
	}
    return retval;
}
	

function time_to_secs(st)
{
	var secs = 0;
	var parts = st.split(":");
	for (var i=0; i<parts.length; i++)
	{
		secs *= 60;
		secs += parseInt(parts[i]);
	}
	return secs;
}


// END OF renderer.js

