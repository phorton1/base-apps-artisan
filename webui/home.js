//--------------------------------------------------
// renderer.js
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
		resizable: false,
		west__onresize:  $.layout.callbacks.resizePaneAccordions,
	},

	north: {
		size:40,
		limit:400,
		element_id:'#renderer_page_header_right',
	},
	west: {
		size:245,
		limit:600,
		element_id:'#renderer_page_header_left',
	},
	east: {
		size:200,
		limit:900,
		element_id:'#renderer_button_shuffle',
		element_is_button:true,
	},

};



//========================================================
// Home Page initialization
//========================================================

function init_page_home()
{
	last_song = '';
	display(dbg_home,0,"init_page_home()");

	load_device_list('renderers');
	load_device_list('libraries');

	init_playlist_info();
	init_renderer_pane();

	$("#home_menu").accordion({ heightStyle: "fill" });
	$('#prefs_div').buttonset();

	create_numeric_pref(0,10,60,
		'pref_error_mode',
		'#pref_explorer_mode');
}



//------------- Device Lists

function makeSingular(plural)
{
	if (plural == 'renderers') return 'renderer';
	if (plural == 'libraries') return 'library';
	return '';
}
function makePlural(singular)
{
	if (singular == 'renderer') return 'renderers';
	if (singular == 'library')  return 'libraries';
	return '';
}

function load_device_list(plural)
	// if singular, it's being called from init_page_home()
	// and we check the last_singular cookie,
{
	var singular = makeSingular(plural);
	display(dbg_home,0,"onload_renderer_list(" + plural + ")");

	$.get('/webui/getDevicesHTML/' + plural,

		function(result)
		{
			$( "#" + plural ).html(result);
			$( "#" + plural ).buttonset();

			var last_cookie = 'last_' + singular;
			var last_uuid = singular ? getCookie("last_" + singular) : '';
			var found = $( "#" + plural ).buttonset().length;
			if (found)
			{
				found = false;
				var ele = last_uuid ? $("#" + singular + "-" + last_uuid) : false;
				if (ele && ele.length)
				{
					found = true;
					selectDevice(singular,last_uuid);
				}
				if (!found)
				{
					found = true;
					var first = $("#" + plural + " input").first();
					var first_uuid = first.attr('id');
					first_uuid = first_uuid.replace(singular + "-","");
					selectDevice(singular,first_uuid);
				}
			}
			if (!found)
				setCookie(last_cookie,'',-1);
		}
	);
}


function selectDevice(singular,uuid)	// handler
{
	if (singular == 'renderer' && uuid == 'html_renderer')
	{
		onSelectDevice(singular,uuid,html_renderer);
		return;
	}

	$.get('/webui/getDevice/' + singular + "-" + uuid, function(result)
	{
		if (result.error)
		{
			rerror('Error in getDevice(' + kind + ',' + uuid + '): ' + result.error);
		}
		else
		{
			onSelectDevice(singular,uuid,result);

			var cur_name = 'current_' + singular;
			var cur = window[cur_name];
			if (cur && cur.uuid != uuid)
			{
				$( "#" + singular + '-' + cur.uuid).prop('checked', false).button('refresh');
			}

			window[cur_name] = result;
			$('#' + singular +  '-' + uuid).prop('checked', true).button('refresh');
			setCookie('last_'+singular,uuid,180);

			// current_page indicates the app has really started

			if (singular == 'library')
				$('.artisan_menu_library_name').html(result.name);
			init_playlists();
				// will only do something if both are set.

			if (current_page)
			{
				if (singular == 'renderer')
					update_renderer_ui();
				if (singular == 'library')
					update_explorer();
			}
		}
	});
}



function onSelectDevice(singular,uuid,result)
{
	var cur_name = 'current_' + singular;
	var cur = window[cur_name];
	if (cur && cur.uuid != uuid)
	{
		$( "#" + singular + '-' + cur.uuid).prop('checked', false).button('refresh');
	}

	window[cur_name] = result;
	$('#' + singular +  '-' + uuid).prop('checked', true).button('refresh');
	setCookie('last_'+singular,uuid,180);

	// current_page indicates the app has really started

	if (singular == 'library')
	{
		$('.artisan_menu_library_name').html(result.name);
	}

	init_playlists();

	if (current_page)
	{
		if (singular == 'renderer')
			update_renderer_ui();
		if (singular == 'library')
			update_explorer();
	}
}



//------------- Init Playlists

function init_playlists()
	// only works if both current_library and current_renderer are set
{
	if (!current_library || !current_renderer)
		return;

	var library_uuid = current_library.uuid;
	var renderer_uuid = current_renderer.uuid;

	$.get('/webui/library/' + library_uuid + '/get_playlists',
	function(result)
	{
		if (result.error)
		{
			rerror('Error in init_playlists(' + library_uuid + ',' + renderer_uuid + '): ' + result.error);
		}
		else
		{
			$('#playlists').html(result);
			onload_playlists();
		}
	});
}


function onload_playlists()
{
	display(dbg_pl,0,"onload_playlists()");
    $('#playlists').buttonset();

}


//------------- Init Renderer

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

//------------- Init Preferences

function create_numeric_pref(min,med,max,var_name,spinner_id)
{
	display(dbg_layout,0,"create_numeric_pref(" + min + ',' + med + ',' + max + ',' + var_name + ',' + spinner_id + ")");

	$(spinner_id).spinner({
		width:20,
		min:min,
		max:max,
		change: function(event, ui)
		{
			var value = parseInt($(this).spinner('value'));
			window[var_name] = value;
			setCookie(var_name,value,180);
			if (false && var_name == 'explorer_mode')
			{
				var tree = $('#explorer_tree').fancytree('getTree');
				tree.reload({
					url: "/webui/library/" + current_library['uuid'] + "/dir",
					data: {mode:explorer_mode, source:'numeric_pref'},
					cache: false,
				});
			}
		},
	});

	var value = window[var_name];
	$(spinner_id).spinner('value',value);
}



//========================================================
// Handlers
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
		in_slider=false;
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
			in_slider=false;
			update_renderer_ui();
		}
	);
}


function on_slider_complete(event,ui)
	// sliders are in pct
	// command is in millieseconds
{
	in_slider=false;
	var millis = parseInt(ui.value * current_renderer.duration/100);
	display(dbg_slider,0,"on_slider_complete(" + millis + ")");
	renderer_command('seek',{position:millis});
	return true;
}


function set_playlist(uuid,id)
	// called by easy-ui event registration on the renderer_list
	// when the user changes the current selection.
	// Set the current renderer name and enable the buttons.
	// We have to be careful about re-entrancy, so that we don't
	// confuse the server.
{
	display(dbg_home,0,"set_playlist("+name+")");
	// hide_layout_panes();
	renderer_command('set_playlist',{
		library_uuid:uuid,
		id: id});
}


function update_renderer_onidle()
{
	display(dbg_loop,0,"update_renderer_onidle");
	if (current_renderer && !in_slider)
	{
		renderer_command('update');
	}
}




//========================================================
// UI REFRESH
//========================================================

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
		disable = false;
		state = current_renderer.state;

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
		set_button_on('renderer_button_shuffle',shuffle_on);

		// Enable/disable the buttons

		display(dbg_loop,0,"renderer.update_renderer_ui(1)");

		disable_button('renderer_button_prev',disable_prevnext);
		disable_button('renderer_button_play_pause',disable);
		disable_button('renderer_button_stop',stop_disabled);
		disable_button('renderer_button_next',disable_prevnext);

		display(dbg_loop,0,"renderer.update_renderer_ui(2)");

		update_playlist_ui();
			// in playlist.js

	}	// !autofull

	display(dbg_loop,0,"renderer.update_renderer_ui() returning");

}	// update_renderer_ui()



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


//-------------------------------------
// autofull stuff
//-------------------------------------

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


// END OF renderer.js
