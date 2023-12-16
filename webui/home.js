//--------------------------------------------------
// home.js
//--------------------------------------------------

var dbg_home = 0;
var dbg_slider = 0;


var in_slider = false;
var last_song = '';
var renderer_slider;


layout_defs['home'] = {
	layout_id: '#home_page',
	swipe_element: '#renderer_pane_div',

	default_params: {
		applyDemoStyles: true,
		west__onresize:  $.layout.callbacks.resizePaneAccordions,
	},

	north: {
		size:40,
		limit:400,
		resizable: false,
		element_id:'#renderer_page_header_right',
	},
	west: {
		size:245,
		limit:600,
		element_id:'#renderer_page_header_left',
	},
	//	east: {
	//		size:200,
	//		limit:900,
	//		element_id:'#renderer_button_shuffle',
	//		element_is_button:true,
	//	},

};



function init_page_home()
{
	last_song = '';
	display(dbg_home,0,"init_page_home()");

	load_device_list(DEVICE_TYPE_RENDERER);
	load_device_list(DEVICE_TYPE_LIBRARY);

	// init_playlist_info();
	init_renderer_pane();

	$("#home_menu").accordion({
		icons: false,
		heightStyle: "fill",
		classes: {
		  "ui-accordion": "home_accordian"
		}

		});
	$('#prefs_div').buttonset();

	create_numeric_pref(0,10,60,
		'pref_error_mode',
		'#pref_explorer_mode');

	display(dbg_home,0,"init_page_home() done");
}




//-----------------------------------
// Device Lists
//-----------------------------------

function load_device_list(type)
{
	$.get('/webui/getDevices/' + type,
		function(result)
	{
		// add the local html_renderer
		if (type == DEVICE_TYPE_RENDERER)
			result.unshift({
				name: html_renderer.name,
				uuid: html_renderer.uuid,
				type: DEVICE_TYPE_RENDERER });

		buildDeviceMenu(result,type);
		selectDefaultDevice(type);
	});
}



function selectDefaultDevice(type)
{
	var last_cookie = 'last_' + type;
	var last_uuid = getCookie(last_cookie);
	var found = document.getElementById(type + '_' + last_uuid );
	if (!found)
	{
		var buttons = document.getElementsByName(type + '_button');
		found = buttons[0];
	}

	// this should never fail as there should ALWAYS be at least
	// the Perl localLibrary and localRenderer (and HTML Renderer).
	// We have to get the uuid back from the element's id

	var found_uuid = found.id.replace(type + '_','');
	selectDevice(type,found_uuid);
}


function selectDevice(type,uuid)	// handler
{
	if (type == DEVICE_TYPE_RENDERER && uuid == 'html_renderer')
	{
		onSelectDevice(type,uuid,html_renderer);
		return;
	}
	$.get('/webui/getDevice/' + type + "-" + uuid,
		function(result)
	{
		if (result.error)
			rerror('Error in getDevice(' + type + ',' + uuid + '): ' + result.error);
		else
			onSelectDevice(type,uuid,result);
	});
}


function onSelectDevice(type,uuid,result)
{
	var cur_name = 'current_' + type;
	var cur = window[cur_name];
	if (cur && cur.uuid != uuid)
	{
		$( "#" + type + '_' + cur.uuid).prop('checked', false).button('refresh');
	}

	window[cur_name] = result;
	$('#' + type +  '_' + uuid).prop('checked', true).button('refresh');
	setCookie('last_'+type,uuid,180);

	if (type == DEVICE_TYPE_LIBRARY)
	{
		$('.artisan_menu_library_name').html(result.name);
		// init_playlists();
	}

	// current_page indicates the app has really started

	if (current_page)
	{
		if (type == DEVICE_TYPE_RENDERER)
			update_renderer_ui();
		if (type == DEVICE_TYPE_LIBRARY)
			update_explorer();
	}
}



//----------------------------------
// Playlists
//----------------------------------

//	function init_playlists()
//		// only works if both current_library and current_renderer are set
//	{
//		if (!current_library || !current_renderer)
//			return;
//		$.get(library_url() + '/get_playlists',function(result) {
//			if (result.error)
//			{
//				rerror('Error in init_playlists(' + library_uuid + '): ' + result.error);
//			}
//			else
//			{
//				buildHomeMenu(result,'playlist','id','setPlaylist','uuid','id');
//			}
//		});
//	}
//
//
//	function setPlaylist(uuid,id)
//		// called by easy-ui event registration on the renderer_list
//		// when the user changes the current selection.
//		// Set the current renderer name and enable the buttons.
//		// We have to be careful about re-entrancy, so that we don't
//		// confuse the server.
//	{
//		display(dbg_home,0,"setPlaylist("+name+")");
//		// the button is a radio button and I don't want it to be,
//		// so I have to explicitly uncheck it ... fix later
//		$('#playlist_' + id).prop('checked', false).button('refresh');
//
//
//		// hide_layout_panes();
//		renderer_command('set_playlist',{
//			library_uuid:uuid,
//			id: id});
//	}



//========================================================
// API - renderer_command() and update_renderer_onidle()
//========================================================

function renderer_command(command,args)
{
	if (!current_renderer)
	{
		rerror("No current_renderer in renderer_command: " + what);
		return;
	}

	if (current_renderer['uuid'] == 'html_renderer')
	{
		audio_command(command,args);
		in_slider = false;
		// in_playlist_slider = false;
		// in_playlist_spinner = false;
		update_renderer_ui();
		return;
	}

	var cmd_args = '';
	if (args != undefined)
	{
		for (key in args)
		{
			cmd_args += (cmd_args ? '&' : '?');
			cmd_args += key + '=' + args[key];
		}
	}

	$.get('/webui/renderer/' + current_renderer['uuid'] + '/' + command + cmd_args,

		function(result)
		{
			if (result.error)
			{
				rerror('Error in renderer_command(' + command + '): ' + result.error);
				current_renderer = false;
			}
			else
			{
				current_renderer = result;
			}
			in_slider = false;
			// in_playlist_slider = false;
			// in_playlist_spinner = false;
			update_renderer_ui();
		}
	);
}





//========================================================
// RENDERER PANE (init and update)
//========================================================

function init_renderer_pane()
{
	display(dbg_home,0,"init_renderer_pane()");

	$( "#renderer_slider" ).slider({
		disabled:true,
		stop: function( event, ui ) {
			on_slider_complete(event,ui);
		},
		start: function( event, ui ) {
			in_slider = true;
		},
	});

	renderer_slider = $('#renderer_slider');

	$( "input[type=button]" ).button();

}


function on_slider_complete(event,ui)
	// sliders are in pct
	// command is in millieseconds
{
	var millis = parseInt(ui.value * current_renderer.duration/100);
	display(dbg_slider,0,"on_slider_complete(" + millis + ")");
	renderer_command('seek',{position:millis});
	return true;
}


function update_renderer_ui()
{
	display(dbg_loop,0,"renderer.update_renderer_ui()");
	var disable_play_pause = true;
	var disable_prevnext = true;
	var stop_disabled = true;
	var disable_slider = true;
	var shuffle_on = false;

	var state = '';
	// var playlistName = 'Now Playing';
	var rendererName = 'No Renderer Selected';

	var art_uri = '/webui/icons/artisan.png';
	var song_title = '';
	var album_artist = '';
	var album_title = '';
	var album_track = '';
	var song_genre = '';

	var play_pct = 0;
	var position_str = '0:00';
	var duration_str = '0:00';
	var play_type_size = '';

	var pause_button_label = ' > ';
	var pause_button_on = 'renderer_control_off';


	//-----------------------------------------------
	// set the values from current renderer if any
	//-----------------------------------------------
	// start with the rendererName
	// playlistName, and overall disable booleans

	if (current_renderer)
	{
		disable_play_pause =
			!current_renderer.duration ||
			current_renderer.duration == '0';
		state = current_renderer.state;

		rendererName = current_renderer.name;
		//	if (current_renderer.playlist)
		//	{
		//		disable_prevnext = false;
		//		playlistName =
		//			// current_renderer.playlist.num + '. ' +
		//			current_renderer.playlist.name;
		//		playlistName += '(' +
		//			current_renderer.playlist.track_index + ',' +
		//			current_renderer.playlist.num_tracks + ')';
		//	}

		// Display information about the Song in fields
		// that just happen to be the same as fields in a Track,
		// but gotten from the input didle.

		var metadata = current_renderer.metadata;
		if (metadata)
		{
			disable_slider = false;

			if (metadata.art_uri)
			{
				art_uri = metadata.art_uri;
			}
			else
			{
				art_uri = '/webui/icons/no_image.png';
			}
			song_title = metadata.title ? decode_ampersands(metadata.title) : '&nbsp;';
			album_artist = metadata.artist ? decode_ampersands(metadata.artist) : '&nbsp;'
			album_title = metadata.album_title ? decode_ampersands(metadata.album_title) : '&nbsp;'
			play_type_size = metadata.type ? metadata.type + ' &nbsp;&nbsp; ' : '';
			play_type_size += metadata.pretty_size ? metadata.pretty_size : '';

			if (metadata.track_num && metadata.track_num != "")
			{
				album_track = 'track: ' + metadata.track_num;
			}

			song_genre = '';
			if (metadata.genre)
			{
				song_genre = decode_ampersands(metadata.genre);
			}
			if (metadata.year_str && metadata.year_str != "")
			{
				if (song_genre)
				{
					song_genre += ' | ';
				}
				song_genre += metadata.year_str;
			}

			if (!song_genre)
			{
				song_genre = '&nbsp;';
			}
		}

		// Transport times and slider

		if (state == 'PLAYING')
		{
			stop_disabled = false;
			pause_button_label = ' || ';
		}

		if (state == 'PLAYING' ||
			state == 'PAUSED')
		{
			duration_str = millis_to_duration(current_renderer.duration,false);
			position_str = millis_to_duration(current_renderer.position,false);
			if (current_renderer.duration>0)
				play_pct = parseInt(current_renderer.position / current_renderer.duration  * 100);
		}

		// Shuffle and Repeat buttons

		pause_button_on = (state == 'PAUSED') ? true : false;
	}

	//----------------------------------------
	// Move the variables into the UI
	//----------------------------------------

	var playlistName = '';
	ele_set_inner_html('renderer_header_left',playlistName + ' &nbsp;&nbsp; ' + state);
	ele_set_inner_html('renderer_header_right',"" +  + idle_count + " " + rendererName);

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
		display(dbg_loop,0,"renderer.update_renderer_ui(a)");

		renderer_slider.slider( disable_slider?'disable':'enable');
		$('#renderer_slider').slider('value',play_pct);
	}

	ele_set_inner_html('renderer_position',position_str);
	ele_set_inner_html('renderer_duration',duration_str);
	ele_set_inner_html('renderer_play_type',play_type_size);

	ele_set_value('renderer_button_play_pause',pause_button_label );
	set_button_on('renderer_button_play_pause',pause_button_on);

	// Enable/disable the buttons

	display(dbg_loop,0,"renderer.update_renderer_ui(1)");

	disable_button('renderer_button_prev',disable_prevnext);
	disable_button('renderer_button_play_pause',disable_play_pause);
	disable_button('renderer_button_stop',stop_disabled);
	disable_button('renderer_button_next',disable_prevnext);

	display(dbg_loop,0,"renderer.update_renderer_ui(2)");

	// update_playlist_ui();
		// in playlist.js

	display(dbg_loop,0,"renderer.update_renderer_ui() returning");

}	// update_renderer_ui()




//--------------------------------------------
// update_renderer_ui() utilities
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
	// in the ongoing litany of issues with jquery ui
	// for some reason most important objects cannot
	// be accessed by id when within firebug, but they
	// seem to work ok outside of it ...
{
	var use_id = '#' + id;
	display(dbg_loop,0,"disable_button(" + id + ")");

	// a bunch of attempts
	// most recently, set the class directly at least doesn't hang firebug

	if ($(use_id))	 // .length)
	{
		$(use_id).button(disabled?'disable':'enable');
	}
	display(dbg_loop,0,"disable_button(" + id + ") finished");
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


function remove_trailing_decimal(st)
{
	var parts = st.split(".");
	return parts[0];
}


function padZero(len,st0)
{
	var st = "" + st0;
	if (st.length < len)
		st = "0" + st;
	return st;
}


function millis_to_duration(millis,precise)
{
	millis = parseInt(millis);
	var secs = parseInt(parseInt(millis)/1000);
	millis = millis - secs * 1000;

	var mins = parseInt(secs/60);
	secs = secs - mins * 60;

	var hours = parseInt(mins/60);
	mins = mins - hours * 60;

    var retval = '';
	if (hours > 0 || precise)
	{
		if (precise)
			hours = padZero(2,hours);
		retval += hours + ":";
	}

	if (precise)
		mins = padZero(2,mins);
	retval += mins + ":";
	retval += padZero(2,secs);

	if (precise)
		retval += "." + padZero(3,millis);

	return retval;
}


// END OF renderer.js
