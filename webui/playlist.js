// playlist.js

var dbg_pl = 0;


var in_playlist_slider = false;
var in_playlist_spinner = false;




function init_playlist_info()
{
	display(dbg_pl,0,"init_playlist_info(" + current_page + ")");
	var use_id = '#playlist_info_';

	$( use_id + 'div' ).buttonset({
		disabled:true,
	});

	$( use_id + 'slider' ).slider({

		disabled:true,

		slide: function( event, ui ) {
			$( use_id + 'track_num').spinner('value',ui.value);
		},
		start: function( event, ui ) {
			in_playlist_slider = true;
		},
		stop: function( event, ui ) {
			playlist_song();
		},
	});

	$( use_id + 'track_num' ).spinner({
		// disabled:true,
		width:20,
		min:0,
		max:0,

		spin: function(event, ui) {
			$( use_id + 'slider').slider('value',ui.value);
		},
		start: function( event, ui ) {
			in_playlist_spinner	= true;
		},
		stop: function( event, ui ) {
			playlist_song();
		},
	});

	update_playlist_ui();

}



function playlist_song()
{
	var index = $('#playlist_info_track_num').spinner('value');
	renderer_command('playlist_song?index='+index);
	return true;		// I'm not sure return value is needed
}



//------------------------------------------------------
// pane_playlist_info handling
//------------------------------------------------------


function update_playlist_ui()
{
	display(dbg_loop,0,"update_playlist_ui(" + current_page + ")");
	var use_id = '#playlist_info_';

	var show_name = 'No playlist selected';
	var shuffle = 0;
	var unplayed_first = false;
	var track_num = 0;
	var num_tracks = 0;
	var min_track = 0;
	var disable = true;

	var playlist = current_renderer ? current_renderer.playlist : null;
	if (playlist)
	{
		show_name = playlist.library_name + "(" + playlist.name + ")";
		shuffle = parseInt(playlist.shuffle);
		unplayed_first = parseInt(playlist.unplayed_first);
		track_num = parseInt(playlist.track_index);
		num_tracks = parseInt(playlist.num_tracks);
		min_track = num_tracks ? 1 : 0;
		disable = false;
	}

	// enable disable all the controls

	$(use_id + 'slider').slider( disable?'disable':'enable');
	$(use_id + 'shuffle_off').button({disabled:disable});
	$(use_id + 'shuffle_tracks').button({disabled:disable});
	$(use_id + 'shuffle_albums').button({disabled:disable});
	$(use_id + 'unplayed_first').button({disabled:disable});

	// set the values

	$(use_id + 'playlist_name').html(show_name);
	$(use_id + 'shuffle_off').prop('checked',(shuffle==0)).button('refresh').blur();
	$(use_id + 'shuffle_tracks').prop('checked',(shuffle==1)).button('refresh').blur();
	$(use_id + 'shuffle_albums').prop('checked',(shuffle==2)).button('refresh').blur();
	$(use_id + 'unplayed_first').prop('checked',unplayed_first).button('refresh').blur();
	$(use_id + 'num_tracks').html(num_tracks);
	$(use_id + 'slider').slider('option','min',min_track);
	$(use_id + 'slider').slider('option','max',num_tracks);

	$(use_id + 'track_num').spinner('option','min',min_track);
	$(use_id + 'track_num').spinner('option','max',num_tracks);

	if (!in_playlist_spinner &&
		!in_playlist_slider)
	{
		$(use_id + 'slider').slider('value',track_num);
		$(use_id + 'track_num').spinner('value',track_num);
	}
	display(dbg_loop,0,"update_playlist_ui(" + current_page + ") returning");
}
