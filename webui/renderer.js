//--------------------------------------------------
// renderer.js
//--------------------------------------------------


var in_slider = false;
var current_renderer = false;
var renderer_list = false;

var default_renderer_id = '';
var default_renderer_name = '';
var last_song = '';

// for some reason I have to cache these objects
// as the program just hangs, no message or anything
// when it apparently cannot find them by id during
// methods called from nowhere ...

var renderer_slider;

var NEW_WAY = false;


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
	// south: {
	// 	limit:600,
	// 	size:135,
	// 	size_touch:160,
	// 	element_id:'#renderer_button_playlist_assign', 
	// 	element_is_button:true,
	// 	},
		
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
	// and playlist_info panes are not inited ...

	init_playlists();
	init_renderer_menu_pane();
	init_renderer_pane();
	
	last_song = '';
	
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
	
	renderer_slider = $('#renderer_slider');
	
	
	
	
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
			current_renderer = result;
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
	display(dbg_loop,0,"renderer_pane_on_idle");
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
	display(dbg_renderer,0,"select_renderer(" + id + ")");
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



function select_playlist(name)
	// called by easy-ui event registration on the renderer_list
	// when the user changes the current selection.
	// Set the current renderer name and enable the buttons.
	// We have to be careful about re-entrancy, so that we don't
	// confuse the server.
{
	display(dbg_renderer,0,"select_playlist("+name+")");
	hide_layout_panes();
	
	if (!current_renderer)
	{
		rerror("No current_renderer in select_renderer_playlist(" + name + ")");
		return;
	}

	$.get('/webui/renderer/set_playlist?playlist=' + name,

		function(result)
		{
			if (result.error)
			{
				rerror('Error in select_playlist(' + id + '): ' + result.error);
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
	
	// sliders are in pct
	// command is in millieseconds
	
	var millis = parseInt(ui.value * current_renderer.duration/100); 
	
	$.get('/webui/renderer/transport' +
		  '?id='+current_renderer.id +
		  '&command=set_position' +
		  '&position=' + millis,
		  
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
	display(dbg_loop,0,"renderer.update_renderer()");
	
	$.get('/webui/renderer/update_renderer' +
		  '?id='+current_renderer.id,

		function(result)
		{
			display(dbg_loop,0,"renderer.update_renderer().result");
			if (result.error)
			{
				rerror('Error in update_renderer(): ' + result.error);
				current_renderer = false;
			}
			else
			{
				current_renderer = result;
			}
			display(dbg_loop,0,"renderer.update_renderer().result calling udpate_rendere_ui");
			update_renderer_ui();
			display(dbg_loop,0,"renderer.update_renderer().result finished");
		}
	);
	display(dbg_loop,0,"renderer.update_renderer() finished");
}




//--------------------------------------------
// UI
//--------------------------------------------


function update_renderer_ui()
{
	display(dbg_loop,0,"renderer.update_renderer_ui()");
	var disable = true;
	var disable_prevnext = true;
	var stop_disabled = true;
	var disable_slider = true;
	var shuffle_on = false;

	var state = '';
	var playlistName = 'Now Playing';
	var rendererName = 'No Renderer Selected';
	
	var art_uri = '/webui/icons/artisan.png';
	var song_title = '&nbsp;';
	var album_artist = '&nbsp;';
	var album_title = '&nbsp;';
	var album_track = '&nbsp;';
	var song_genre = '&nbsp;';
	
	var play_pct = 0;
	var position_str = '0:00';
	var duration_str = '0:00';
	var pretty_size = '';
	var play_type_size = '';
	var song_id = '';
	
	var pause_button_label = ' > ';
	var pause_button_on = 'renderer_control_off';

	
	//-----------------------------------------------
	// set the values from current renderer if any
	//-----------------------------------------------
	// start with the rendererName
	// playlistName, and overall disable booleans
	
	if (current_renderer)
	{
		disable = false;
		state = current_renderer.state;
		song_id = current_renderer.song_id;
		
		rendererName = current_renderer.name;
		if (current_renderer.playlist)
		{
			disable_prevnext = false;
			playlistName =
				// current_renderer.playlist.num + '. ' +
				current_renderer.playlist.name;
			playlistName += '(' +
				current_renderer.playlist.track_index + ',' +
				current_renderer.playlist.num_tracks + ')';
			shuffle_on = (current_renderer.playlist.shuffle>0) ? true : false;
		}

		// Display information about the Song in fields
		// that just happen to be the same as fields in a Track,
		// but gotten from the input didle.

		var metadata = current_renderer.metadata;
		if (metadata)
		{
			disable_slider = false;
			
			if (metadata.pretty_size)
				pretty_size = metadata.pretty_size;
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
				song_genre += metadata.yearstr;
			}
			
			if (!song_genre)
			{
				song_genre = '&nbsp;';
			}
		}

		// Transport times and slider

		if (state == 'PLAYING' ||
			state == 'PLAYING_PLAYLIST')
		{
			stop_disabled = false;
			pause_button_label = ' || ';
		}
		
		if (state == 'PLAYING' ||
			state == 'PLAYING_PLAYLIST' ||
			state == 'PAUSED_PLAYBACK')
		{		
			duration_str = millis_to_duration(current_renderer.duration,false);
			position_str = millis_to_duration(current_renderer.position,false);
			if (current_renderer.duration>0)
				play_pct = parseInt(current_renderer.position / current_renderer.duration  * 100);
			
			play_type_size = current_renderer.type + ' &nbsp;&nbsp; ' +	pretty_size;		
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
		
		if (state == 'PLAYING_PLAYLIST')
		{
			state = 'PLAYLIST';
		}
		else if (state == 'PAUSED_PLAYBACK')
		{
			state = 'PAUSED';
		}
		
		highlight_current_renderer();
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
			if (NEW_WAY)	// new way
			{
				disable_button('renderer_slider',disable_slider);
			}
			else
			{
				display(dbg_loop,0,"renderer.update_renderer_ui(a)");
				renderer_slider.slider( disable_slider?'disable':'enable');
				display(dbg_loop,0,"renderer.update_renderer_ui(b) play_pct=" + play_pct);
				$('#renderer_slider').slider('value',play_pct);
				display(dbg_loop,0,"renderer.update_renderer_ui(c)");
			}
		}

		ele_set_inner_html('renderer_position',position_str);
		ele_set_inner_html('renderer_duration',duration_str);
		ele_set_inner_html('renderer_play_type',play_type_size);
	
		ele_set_value('renderer_button_play_pause',pause_button_label );
		set_button_on('renderer_button_play_pause',pause_button_on);
		set_button_on('renderer_button_shuffle',shuffle_on);
		

		
		// Enable/disable the buttons

		display(dbg_loop,0,"renderer.update_renderer_ui(1)");
		
		disable_button('renderer_button_prev',disable_prevnext);
		disable_button('renderer_button_play_pause',disable);
		disable_button('renderer_button_stop',stop_disabled);
		disable_button('renderer_button_next',disable_prevnext);
	
		display(dbg_loop,0,"renderer.update_renderer_ui(2)");
	
		if (false)	
		{
			// this don't work inside firebugx
			update_playlist_info_ui();
		}

		
	}	// !autofull
	
	display(dbg_loop,0,"renderer.update_renderer_ui() returning");
	
}	// update_renderer_ui()




function highlight_current_renderer()
{
	if (current_renderer)
	{
		var id = '#' + current_renderer.id;
		$(id).prop('checked', true ).button('refresh');
	}
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
		//	display(0,0,"disable_button(" + id + ")");
		//	display(0,1,"class=" + $(use_id).attr('class'));
		//	display(0,1,"disabled=" + $(use_id).prop('disabled'));
		//	var desired = disabled?'disable':'enable';
		//  if ($(use_id).prop('disabled') != desired)
		
		if (NEW_WAY)	// new way
		{
			if (disabled)
				$(use_id).attr('disabled', true).addClass( 'ui-state-disabled' );
			else
				$(use_id).attr('disabled', false).removeClass( 'ui-state-disabled' );
		}
		else	// old way 
		{
			$(use_id).button(disabled?'disable':'enable');
		}
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
	

function duration_to_millis(st)
{
	var secs = 0;
	var parts = st.split(":");
	var dec_parts = parts[parts.length-1].split(".");
	if (dec_parts.length > 1)
	{
		parts[parts.length-1] = dec_parts[0];
		var millistr = dec_parts[1];
		while (millistr.length < 3) { millistr = millistr + "0"; }
		millis = parseInt(millistr);
	}
	for (var i=0; i<parts.length; i++)
	{
		secs *= 60;
		secs += parseInt(parts[i]);
	}
	
	millis = millis + secs * 1000;
	return millis;
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
		default_renderer_name = current_renderer.name;
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


