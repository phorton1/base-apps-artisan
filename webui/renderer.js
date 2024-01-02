//--------------------------------------------------
// renderer.js
//--------------------------------------------------

var dbg_slider = 0;

var in_slider = false;
var in_volume_slider = false;

var last_song = '';
var last_playing = -1;



function toggle_volume_control()
{
	$('#volume_control').toggle();
}


function init_renderer_pane()
{
	display(dbg_home,0,"init_renderer_pane()");

	$('#volume_slider').slider({
		// disabled:true,
		orientation:'vertical',
		stop: function( event, ui ) {
			renderer_command('set_volume',{
				volume:ui.value });
		},
		start: function( event, ui ) {
			in_volume_slider = true;
		},
		slide: function( event, ui ) {
		},
	});


	$('#renderer_slider').slider({
		disabled:true,
		stop: function( event, ui ) {
			on_slider_complete(event,ui);
		},
		start: function( event, ui ) {
			in_slider = true;
		},
		slide: function( event, ui ) {
			if (in_slider)
			{
				var pct = ui.value / 100;
				$('#renderer_position').html(
					millis_to_duration(pct * current_renderer.duration,false));
			}
		},

	});

	$(".transport_button").button();
	$('.header_button').button();

	// use 'select' event to shuffle when they press a
	// drop-down shuffle button, even if it's the same one

	$('#transport_shuffle').selectmenu({
		select: function( event, ui ) { onShuffleChanged(event,ui); }
	});

	// have to implement world-wide standard behavior for
	// brain-dead jquery ... if you click outside of selectmenu
	// it should just effing close ... another hour wasted.

    $(document).on("click", function(event) {
		if (!event.target.classList.contains("ui-selectmenu-text"))
		{
           $('#transport_shuffle').selectmenu('close');
		}
		if (!event.target.classList.contains('vc_dont_close') &&
			$('#volume_control').is(':visible'))
			$('#volume_control').hide();
	});
}



//------------------------------------
// renderer_command()
//------------------------------------

function renderer_command(command,args)
{
	if (!current_renderer)
	{
		rerror("No current_renderer in renderer_command: " + what);
		return;
	}
	if (current_renderer['uuid'].startsWith('html_renderer'))
	{
		audio_command(command,args);
		in_slider = false;
		in_volume_slider = false;
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
			in_volume_slider = false;
			update_renderer_ui();
		}
	);
}



//------------------------------------
// event handlers
//------------------------------------

function on_slider_complete(event,ui)
	// sliders are in pct
	// command is in millieseconds
{
	var millis = parseInt(ui.value * current_renderer.duration/100);
	display(dbg_slider,0,"on_slider_complete(" + millis + ")");
	renderer_command('seek',{position:millis});
	return true;
}


var ignore_shuffle_change = false;

function onShuffleChanged(event,ui)
{
	var how = ui.item.value;
	if (!ignore_shuffle_change)
	{
		display(0,0,"onShuffleChanged(" + how + ")");
		renderer_command('shuffle',{how:how});
	}
	else
	{
		display(0,0,"ignoring onShuffleChanged(" + how + ")");
	}
}



//------------------------------------
// update_renderer_ui()
//------------------------------------

function update_renderer_ui()
{
	display(dbg_loop,0,"renderer.update_renderer_ui()");
	var metadata;
	var state = '';
	var queue = '';
	var playlist = '';

	// BASED ON RENDERER

	if (!current_renderer || !current_renderer.queue)
	{
		last_playing = -1;
		$('#renderer_header_left').html('');
		$('#renderer_header_right').html('no renderer');
		disable_button('#mute_button',true);
		disable_button('#renderer_status',true);
	}
	else
	{
		state = current_renderer.state;
		queue = current_renderer.queue;
		playlist = current_renderer.playlist;
		metadata = current_renderer.metadata;

		disable_button('#mute_button',false);
		$('#mute_button').attr('src',current_renderer.muted?
			'/webui/icons/speaker_mute.png' :
			'/webui/icons/speaker.png' );
		disable_button('#renderer_status',false);
		if (!in_volume_slider)
			$('#volume_slider').slider('value',current_renderer.volume);

		$('#renderer_state').html(state);
		$('#renderer_queue_state').html(
			queue.num_tracks ?
			"Q(" + (queue.track_index+1) + "/" + queue.num_tracks + ")" : '');
		$('#renderer_playlist_state').html(
			playlist ? playlist.name + "(" + playlist.track_index + "/" + playlist.num_tracks + ")" : '');
		$('#renderer_status').html(
			idle_count + " " + current_renderer.name);

		if (last_playing != current_renderer.playing)
		{
			last_playing = current_renderer.playing;

			var shuffle;
			if (current_renderer.playing == RENDERER_PLAY_PLAYLIST)
			{
				$('#renderer_queue_state').removeClass('header_active');
				$('#renderer_queue_state').button('enable');
				$('#renderer_playlist_state').addClass('header_active');
				$('#renderer_playlist_state').button('disable');
				shuffle = playlist.shuffle;
				$('#queue_tracklist').css('display','none');
				$('#playlist_tracklist').css('display','block');
				playlist_tracklist.my_index_shown = -1;
			}
			else
			{
				$('#renderer_playlist_state').removeClass('header_active');
				$('#renderer_playlist_state').button('enable');
				$('#renderer_queue_state').addClass('header_active');
				$('#renderer_queue_state').button('disable');
				shuffle = queue.shuffle;
				$('#playlist_tracklist').css('display','none');
				$('#queue_tracklist').css('display','block');
				queue_tracklist.my_index_shown = -1;
			}

			// we make onShuffleChanged ignore the event if its
			// because we are changing the value

			ignore_shuffle_change = true;
			$('#transport_shuffle').val(shuffle);
			$("#transport_shuffle").selectmenu("refresh");
		}
	}

	// BASED ON QUEUE

	if (!queue)
	{
		$('#transport_play').html('>');

		$('#transport_shuffle').selectmenu('disable');
		disable_button('#transport_prev_album',	true);
		disable_button('#transport_prev',		true);
		disable_button('#transport_play',		true);
		disable_button('#transport_stop',		true);
		disable_button('#transport_next',		true);
		disable_button('#transport_next_album',	true);
	}
	else
	{
		var no_tracks = queue.num_tracks == 0;
		var no_earlier = queue.track_index == 0;
		var no_later = queue.track_index >= queue.num_tracks;

		if (playlist &&		// should always by synonymous
			current_renderer.playing == RENDERER_PLAY_PLAYLIST)
		{
			// playlists wrap so earlier/later is true if there's
			// more than one track
			no_tracks = playlist.num_tracks == 0;
			no_earlier = playlist.num_tracks <= 1;
			no_later = playlist.num_tracks <= 1;
			shuffle = playlist.shuffle;
		}

		$('#transport_play').html(
			state == RENDERER_STATE_PAUSED ||
			state == RENDERER_STATE_INIT ||		// playlist in stopped state
			state == RENDERER_STATE_STOPPED ? '>' : '||');

		$('#transport_stop').html(
			state == RENDERER_STATE_STOPPED ? 'O' : 'X');

		$('#transport_shuffle').selectmenu(no_tracks ? 'disable' : 'enable');
		disable_button('#transport_prev_album',	no_tracks || no_earlier);
		disable_button('#transport_prev',		no_tracks || no_earlier);
		disable_button('#transport_play',		no_tracks);
		disable_button('#transport_stop',		no_tracks);
		disable_button('#transport_next',		no_tracks || no_later);
		disable_button('#transport_next_album',	no_tracks || no_later);
	}

	// BASED ON METADATA
	// which is the current song playing

	if (!metadata)
	{
		$('#renderer_song_title')	.html('');
		$('#renderer_album_artist')	.html('');
		$('#renderer_album_title')	.html('');
		$('#renderer_album_track')	.html('');
		$('#renderer_song_genre')	.html('');
		$('#renderer_album_image').attr('src','/webui/icons/artisan.png');

		$('#renderer_slider').slider('disable')
		$('#renderer_slider').slider('value',0);
		$('#renderer_position')		.html('');
		$('#renderer_duration')		.html('');
		$('#renderer_play_type')	.html('');
	}
	else
	{
		$('#renderer_song_title')	.html(decode_ampersands(metadata.title));
		$('#renderer_album_artist') .html(decode_ampersands(metadata.artist));

		$('#renderer_album_title')	.html(decode_ampersands(metadata.album_title));

		var track_info = 'Library: ' + getLibraryName(metadata.library_uuid);
		if (metadata.tracknum != undefined && metadata.tracknum != '')
			track_info += ' &nbsp; Album Track: ' + metadata.tracknum;
		$('#renderer_album_track')  .html(track_info);

		var genre_year = metadata.genre ?
			decode_ampersands(metadata.genre) : '';
		if (metadata && metadata.year_str && metadata.year_str != "")
		{
			if (genre_year) genre_year += ' | ';
			genre_year += metadata.year_str;
		}
		$('#renderer_song_genre').html(genre_year);

		$('#renderer_album_image').attr('src', metadata.art_uri ?
			metadata.art_uri : '/webui/icons/no_image.png');

		$('#renderer_play_type').html(
			metadata.type + ' &nbsp;&nbsp; ' +  metadata.pretty_size);

		$('#renderer_button_play_pause').val(
			state == RENDERER_STATE_PLAYING ? '||' : '>')
			$('#renderer_duration').html(
				millis_to_duration(current_renderer.duration,false));

		$('#renderer_position').html(
			millis_to_duration(current_renderer.position,false));

		if (current_renderer.duration>0)
		{
			$('#renderer_slider').slider('enable');
			if (!in_slider)
				$('#renderer_slider').slider('value',
				parseInt(100 * (current_renderer.position / current_renderer.duration)));
		}
		else
		{
			$('#renderer_slider').slider('disable');
			$('#renderer_slider').slider('value',0);
		}
	}

	// UPDATE HOME TRACKLISTS

	update_home_tracklists();
	ignore_shuffle_change = false;

	display(dbg_loop,0,"renderer.update_renderer_ui() returning");

}	// update_renderer_ui()




//--------------------------------------------
// update_renderer_ui() utilities
//--------------------------------------------

function disable_button(selector,disabled)
{
	$( selector).button( "option", "disabled", disabled );
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


// end of renderer.js
