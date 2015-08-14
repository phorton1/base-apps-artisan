//--------------------------------------------------
// renderer.js
//--------------------------------------------------

var in_slider = false;
var current_renderer = false;
var renderer_list = false;

var default_renderer_id = '';
var default_renderer_name = '';
var last_song = -1;


page_layouts['renderer'] = {
	layout_id: '#renderer_page',
	swipe_element: '#renderer_pane_div',
	
	north: {
		limit:400,
		size:40,
		size_touch:60,
		element_id:'#renderer_page_header_right',
		},
	west: {
		limit:600,
		size:245,
		element_id:'#renderer_page_header_left', 
		},
	east: {
		limit:900,
		size:200,
		element_id:'#renderer_button_shuffle',
		element_is_button:true,
		},
	south: {
		limit:600,
		size:135,
		size_touch:160,
		element_id:'#renderer_button_station_assign', 
		element_is_button:true,
		},
		
	defaults: {
		west__onresize:  $.layout.callbacks.resizePaneAccordions,
	},
};



//------------------------------------------------
// ONLOAD handlers
//------------------------------------------------

function init_page_renderer()
{
	display(dbg_renderer,0,"init_page_renderer()");
	
	// prh - something is kicking me out of init_renderer_pane
	// so if these are in the opposite order, the menu
	// and station_info panes are not inited ...

	init_pane_station_info();
	init_renderer_menu_pane();
	init_renderer_pane();
	
	last_song = -1;
	
}


function init_renderer_pane()
{
	display(dbg_renderer,0,"init_renderer_pane()");

	$( "#renderer_slider" ).slider({
		disabled:true,
		stop: function( event, ui ) {
			on_slider_complete(event,ui);
		},
		start: function( event, ui ) {
			in_slider = true;
		},
	});
	
	$( "input[type=button]" ).button();
	
	// get default renderer cookie
	
	default_renderer_id = getCookie('default_renderer_id')
	default_renderer_name = getCookie('default_renderer_name')
	display(dbg_renderer,0,"default_renderer=" + default_renderer_id + ":'" + default_renderer_name + "'");
	update_renderer_pref_default_renderer_ui();

	// get selected renderer, if any, from the server
	// we ignore errors and are only interested in
	// a valid renderer if one is returned
	
	$.get('/webui/renderer/get_selected_renderer', function(result)
	{
		if (result.error)
		{
			// no selected renderer, try to select the default

			if (default_renderer_id != '')
			{
				display(dbg_renderer,0,"setting default_renderer='" + default_renderer_id + "'");
				select_renderer(default_renderer_id);
			}
		}
		else
		{
			// if the renderer already has a station,
			// make it the edit station
			
			current_renderer = result;
			if (current_renderer.station)
			{
				set_edit_station(current_renderer.station);
			}
		}

		update_renderer_ui();

	});

};



function init_renderer_menu_pane()
{
	display(dbg_renderer,0,"init_renderer_menu_pane()");

	$("#renderer_menu").accordion({ heightStyle: "fill" });
	$('#renderer_prefs_div').buttonset();

	create_numeric_pref(0,10,60,
		'explorer_mode',
		'#pref_explorer_mode');

	create_numeric_pref(0,10,60,
		'autoclose_timeout',
		'#pref_autoclose_timeout');

	create_numeric_pref(0,15,300,
		'autofull_timeout',
		'#pref_autofull_timeout');
	
	$('#device_info').html(
		"<span style='font-size:8px;'>" + navigator.userAgent + '</span><br><br>' +
		'doc=' + document.body.clientWidth + '<br>' +
		'w=' + window.innerWidth + '<br>' +
		'h=' +	window.innerHeight + '<br>' +
		'sw=' + screen.width + '<br>' +
		'sh=' + screen.height);
}




function onload_renderer_list()
{
	display(dbg_renderer,0,"onload_renderer_list()");
    $( "#renderer_list" ).buttonset();
	$( "#renderer_refresh_button" ).button();
	$( "#renderer_clear_button" ).button();
}


function onload_renderer_station_list()
{
	display(dbg_renderer,0,"onload_renderer_station_list()");
    $('#renderer_station_list').buttonset();        
}


function onload_pane_song_stations()
{
	display(dbg_renderer,0,"onload_pane_song_stations()");
    $('#renderer_song_stations_div').buttonset();        
}




function on_renderer_autofull_changed()
{
	if (autofull)
	{
		$('#renderer_pane').css('display','none');
		$('#renderer_autofull_div').css('display','block');
	}
	else
	{
		$('#renderer_pane').css('display','block');
		$('#renderer_autofull_div').css('display','none');
	}
}



//----------------------------------------------
// monitor loop
//----------------------------------------------
// pause and unpause_monitor functions are
// preambles to methods that call the webui,
// to prevent re-entrancy collisions with monitor_loop

function stop_monitor()
{
	current_renderer = false;
	update_renderer_ui();
}

function renderer_pane_onidle()
{
	if (current_renderer && !in_slider)
	{
		update_renderer();
	}
}



//--------------------------------------------
// event handlers
//--------------------------------------------

function refresh_renderers(refresh)
	// called by onclick in buttons, this
	// updates the list of renderers, which *may*
	// result in the current renderer disappearing,
	// which will be handled in on_load_renderers().
{
	$('#renderer_list').load('/webui/renderer/get_renderers?refresh='+refresh,
		function()
		{
			current_renderer = false;
			onload_renderer_list();
		}	
	);
}



function select_renderer(id)
	// called by easy-ui event registration on the renderer_list
	// when the user changes the current selection.
	// Set the current renderer name and enable the buttons.
	// We have to be careful about re-entrancy, so that we don't
	// confuse the server.
{
	hide_layout_panes();

	$.get('/webui/renderer/select_renderer?id='+id, function(result)
	{
		if (result.error)
		{
			rerror('Error in select_renderer('+id+'): ' + result.error);
			current_renderer = false;
			if (id == default_renderer_id)
			{
				// dunno ... this clear the default renderer
				// it it cannot be connected to.
				
				clear_default_renderer();
			}
		}
		else
		{
			current_renderer = result;
		}
		update_renderer_ui();
	});
}



function select_renderer_station(id)
	// called by easy-ui event registration on the renderer_list
	// when the user changes the current selection.
	// Set the current renderer name and enable the buttons.
	// We have to be careful about re-entrancy, so that we don't
	// confuse the server.
{
	hide_layout_panes();
	
	if (!current_renderer)
	{
		rerror("No current_renderer in select_renderer_station(" + id + ")");
		return;
	}

	$.get('/webui/renderer/set_station' +
		  '?id='+current_renderer.id +
		  '&station=' + id,

		function(result)
		{
			if (result.error)
			{
				rerror('Error in select_renderer_station(' + id + '): ' + result.error);
				current_renderer = false;
			}
			else
			{
				current_renderer = result;
			}
			update_renderer_ui();

			// if they explicitly select a station,
			// change the edit station to that
			
			var station = false;
			if (current_renderer && current_renderer.station)
			{
				station = current_renderer.station;
			}
			set_edit_station(current_renderer.station);
		}
	);
	
}



function transport_command(command)
{
	if (!current_renderer)
	{
		rerror("No current_renderer in transport_command: " + what);
		return;
	}

	$.get('/webui/renderer/transport' +
		  '?id='+current_renderer.id +
		  '&command=' + command,
	
		function(result)
		{
			if (result.error)
			{
				rerror('Error in transport_command(' + command + '): ' + result.error);
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



function on_slider_complete(event,ui)
{
	if (!current_renderer)
	{
		rerror("No current_renderer in on_slider_complete(" + value + ')');
		return true;
	}
	
	if (!ui || !ui.value)
	{
		rerror("no value");
		return false;
	}
	
	$.get('/webui/renderer/transport' +
		  '?id='+current_renderer.id +
		  '&command=set_position' +
		  '&position=' + ui.value,
		  
		function(result)
		{
			if (result.error)
			{
				rerror('Error in on_slider_complete(' + ui.value + '): ' + result.error);
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



function update_renderer()
{
	$.get('/webui/renderer/update_renderer' +
		  '?id='+current_renderer.id,

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
	var disable_slider = true;

	var shuffle_on = false;
	var station = [ false,false,false,false,false,false ];

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
	var song_num = 0;
	
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
		song_num = parseInt(current_renderer.song_num);
		
		friendlyName = current_renderer.friendlyName;
		if (current_renderer.station)
		{
			disable_station = false;
			station[current_renderer.station.station_num] = true;
			stationName =
				// current_renderer.station.station_num + '. ' +
				current_renderer.station.name;
			stationName += '(' +
				current_renderer.station.track_index + ',' +
				current_renderer.station.num_tracks + ')';
			shuffle_on = (current_renderer.station.shuffle>0) ? true : false;
		}

		// Song Image and Metadata
		
		var metadata = current_renderer.metadata;
		
		if (metadata)
		{
			disable_slider = false;
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
		
		pause_button_on = (state == 'PAUSED_PLAYBACK') ? true : false;
	}

	if (autofull)
	{
		ele_set_inner_html('renderer_full_song_title',song_title);
		ele_set_inner_html('renderer_full_album_artist',album_artist);
		ele_set_inner_html('renderer_full_album_title',album_title); 
		ele_set_inner_html('renderer_full_album_track',album_track); 
		ele_set_inner_html('renderer_full_song_genre',song_genre);
		if (ele_get_src('renderer_full_album_image') != art_uri)
		{
			ele_set_src('renderer_full_album_image',art_uri);
		}
	}
	else
	{
		
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
			$('#renderer_slider').slider( disable_slider?'disable':'enable');
			$('#renderer_slider').slider('value',play_pct);
		}
		
		ele_set_inner_html('renderer_reltime',reltime);
		ele_set_inner_html('renderer_duration',duration);
		ele_set_inner_html('renderer_play_type',play_type_size);
	
		ele_set_value('renderer_button_play_pause',pause_button_label );
		set_button_on('renderer_button_play_pause',pause_button_on);
	
		for (var i=1; i<6; i++)
		{
			set_button_on('renderer_button_station_'+i,station[i]);
		}
	
		set_button_on('renderer_button_shuffle',shuffle_on);
		
		// Enable/disable the buttons
		
		disable_button('renderer_button_prev',disable_station);
		disable_button('renderer_button_play_pause',disable);
		disable_button('renderer_button_stop',stop_disabled);
		disable_button('renderer_button_next',disable_station);
		// disable_button('renderer_button_shuffle',disable_station);
	
		disable_button('renderer_button_station_1',disable);
		disable_button('renderer_button_station_2',disable);
		disable_button('renderer_button_station_3',disable);
		disable_button('renderer_button_station_4',disable);
		disable_button('renderer_button_station_5',disable);
		disable_button('renderer_button_station_6',disable);
		disable_button('renderer_button_station_assign',
			window.innerWidth>700 || song_num == 0);
		
		update_station_info_ui();
		update_song_stations_ui(song_num);
		
		
	}	// !autofull
}	// update_renderer_ui()




function highlight_current_renderer()
{
	if (current_renderer)
	{
		var id = '#' + current_renderer.id;
		$(id).prop('checked', true ).button('refresh');
		if (current_renderer.station)
		{
			var station_id = '#' + 'renderer_station_list_button_' + current_renderer.station.station_num;
			$(station_id).prop('checked', true).button('refresh');
		}
		else 
		{
			$('.renderer_station_list_button').prop('checked',false).button('refresh');
		}
	}
	else
	{
		$('.renderer_list_button').prop('checked',false).button('refresh');
		$('.renderer_station_list_button').prop('checked',false).button('refresh');
	}
}	



//--------------------------------------------
// song stations
//--------------------------------------------



function update_song_stations_ui(song_num)
{
	// actually the whole darned updateRendererUI() loop should be turned off
	
	if (!document.getElementById('song_station_list_button_1'))
	{
		return;
	}

	if (song_num == 0)
	{
		$('.song_station_list_button')
			.prop('checked',false)
			.button('disable')
			.button('refresh');
	}
	else if (last_song != song_num)
	{
		last_song = song_num;
		$.get('/webui/explorer/get_track?id=' + song_num,
			function(result) {

			if (result.error)
			{
				rerror('update_song_stations_ui(' + song_num + '): ' + result.error);
			}
			else
			{
				var match_station = current_renderer && current_renderer.station ?
					parseInt(current_renderer.station.station_num) : 0;
				
				var stations = result.STATIONS;
				for (var id=1; id<=32; id++)
				{
					var bit = 1 << (id - 1);
					var checked = stations & bit ? true : false;
					var use_id = '#song_station_list_button_' + id;
					var match = match_station == id ? true : false;

					// toggle the style class on the button label
					
					$('[for="' + 'song_station_list_button_' + id + '"]')
						.toggleClass('song_station_list_button_on',match)
					
					$(use_id)
						.prop('checked',checked)
						.button('enable')
						.button('refresh');
						
				}						
			}
		});
	}		
}



function select_song_station(station_num)
	// they pressed a song station button for station_num
	// it will act upon the showing song number ..
{
	var song_num = current_renderer ?
		parseInt(current_renderer.song_num) : false;
	if (song_num)
	{
		var id = '#song_station_list_button_' + station_num;
		var checked = $(id).prop('checked')?1:0;
		
		$.get(
			'/webui/station/set_station_bit' +
			'?station='+station_num+
			'&item_id=track_' + song_num +
			'&checked='+checked,
			
			function(result)
			{
				if (result.error)
				{
					rerror('select_song_station(' + station_num + ',' + song_num + '):' + result.error)
				}
			}
		);
	}
	
	return true;
}



//--------------------------------------------
// ui utilities
//--------------------------------------------


function set_button_on(id,on)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		$('#'+id).toggleClass('renderer_control_on',on);
	}
}


function disable_button(id,disabled)
{
	var use_id = '#' + id;
	if ($(use_id))
	{
		$(use_id).button(disabled?'disable':'enable');
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


// This snippet of code overrides the buttonset refresh() method
// to NOT do rounded-corners-on-first-and-last-buttons-only.
// The body of the method is everything from buttonset::refresh()
// in jquery-ui.js, EXCEPT the loop that does the corners.

$.ui.buttonset.prototype.refresh = function()
{
	// code copied verbatim from jquery-ui.js
	
	var rtl = this.element.css( "direction" ) === "rtl",
		allButtons = this.element.find( this.options.items ),
		existingButtons = allButtons.filter( ":ui-button" );

	// Initialize new buttons
	allButtons.not( ":ui-button" ).button();

	// Refresh existing buttons
	existingButtons.button( "refresh" );
	
};



//-----------------------------------------------
// renderer preferences
//-----------------------------------------------

function update_renderer_pref_default_renderer_ui()
{
	var use_renderer_name = default_renderer_name;
	if (use_renderer_name == '')
	{
		use_renderer_name = 'none';
	}
	$('#pref_default_renderer').text(use_renderer_name);
}



function clear_default_renderer()
{
	default_renderer_id = '';
	default_renderer_name = '';
	set_renderer_pref_default_renderer_cookie();
}


function set_default_renderer()
{
	default_renderer_id = '';
	default_renderer_name = '';
	if (current_renderer)
	{
		default_renderer_id = current_renderer.id;
		default_renderer_name = current_renderer.friendlyName;
	}
		
	set_renderer_pref_default_renderer_cookie();
}


function set_renderer_pref_default_renderer_cookie()
{
	setCookie('default_renderer_id',default_renderer_id,180);
	setCookie('default_renderer_name',default_renderer_name,180);
	update_renderer_pref_default_renderer_ui();
}
	





// END OF renderer.js


