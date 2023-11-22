// https://css-tricks.com/lets-create-a-custom-audio-player/
// https://developer.mozilla.org/en-US/docs/Web/HTML/Element/audio

var audio;



const RENDERER_STATE_NONE 		= 'NONE';
const RENDERER_STATE_INIT		= 'INIT';
const RENDERER_STATE_STOPPED	= 'STOPPED';
const RENDERER_STATE_TRANSIT	= 'TRANSIT';
const RENDERER_STATE_PLAYING	= 'PLAYING';
const RENDERER_STATE_PAUSED		= 'PAUSED';
const RENDERER_STATE_ERROR		= 'ERROR';


var html_renderer = {
		name		: 'HTML Audio',
		uuid		: 'html_renderer',
		maxVol 		: 100,
		canMute		: true,
		canLoud		: false,
		maxBal 		: 100,
		maxFade		: 0,
		maxBass		: 0,
		maxMid 		: 0,
		maxHigh		: 0,
		// state 		: RENDERER_STATE_NONE,
		muted       : 0,
		volume      : 80,
		balance     : 0,
		fade        : 0,
		bassLevel   : 0,
		midLevel    : 0,
		highLevel   : 0,
		// position 	: 0,
		// duration 	: 0,
		playlist	: '',
		//metadata    : {
		//	artist      : '',
		//	album_title : '',
		//	genre       : '',
		//	title       : '',
		//	track_num   : '',
		//	type        : '',
		//	year_str    : '',
		//	art_uri     : '',
		//	pretty_size : '', },
	};


function init_html_renderer(state)
{
	html_renderer.state = state;
	html_renderer.path = '';
	html_renderer.position = 0,
	html_renderer.duration = 0,
	html_renderer.metadata = {
		artist      : '',
		album_title : '',
		genre       : '',
		title       : '',
		track_num   : '',
		type        : '',
		year_str    : '',
		art_uri     : '',
		pretty_size : '' };

}

function init_audio()
{
	audio = document.getElementById('audio_player');
	init_html_renderer(RENDERER_STATE_NONE);
}


function audio_command(command,args)
{
	if (command == 'stop')
	{
		// method does not exist
		// audio.stop();

		if (html_renderer.state == RENDERER_STATE_PLAYING)
			audio.pause();
		init_html_renderer(RENDERER_STATE_STOPPED);
		$('#audio_player_title').html(html_renderer.metadata.title);
		$('#explorer_album_image').attr('src',html_renderer.metadata.art_uri);
	}
	else if (command == 'play_pause')
	{
		if (html_renderer.state == RENDERER_STATE_PLAYING)
		{
			audio.pause();
			html_renderer.state = RENDERER_STATE_PAUSED;
		}
		else if (html_renderer.state == RENDERER_STATE_PAUSED)
		{
			audio.play();
			html_renderer.state = RENDERER_STATE_PLAYING;
		}
	}
	else if (command == 'seek')
	{
		if (html_renderer.state == RENDERER_STATE_PLAYING ||
			html_renderer.state == RENDERER_STATE_PAUSED)
		{
			var position = args['position'];
			audio.currentTime = position / 1000;
		}
	}


	else if (command == 'update')
	{
		if (html_renderer.state == RENDERER_STATE_PLAYING ||
			html_renderer.state == RENDERER_STATE_PAUSED)
		{
			html_renderer.position = audio.currentTime * 1000;
		}
		else
		{
			html_renderer.position = 0;
		}
	}

	else if (command == 'play_song')
	{
		var library_uuid = args['library_uuid'];
		var track_id = args['track_id'];
		// audio_command('stop');
		play_song_local(library_uuid,track_id);
	}

	else if (command == 'set_playlist')
	{
		var library_uuid = args['library_uuid'];
		var playlist_id = args['id'];
		set_local_playlist(library_uuid,playlist_id);
	}
	else if (command == 'next')
	{
	}
	else if (command == 'prev')
	{
	}
	else if (command == 'playlist_song')
	{
		var index = args['index'];

	}
}




function play_song_local(library_uuid,track_id)
{
	init_html_renderer(RENDERER_STATE_TRANSIT);
	$.get('/webui/library/'+library_uuid +
		  '/get_track?id=' + track_id,
	function(result)
	{
		if (result.error)
		{
			rerror('Error in play_song_local(): ' + result.error);
		}
		else
		{
			track_to_html_renderer(result);
			audio.src = html_renderer.path;
			$('#audio_player_title').html(html_renderer.metadata.title);
			$('#explorer_album_image').attr('src',html_renderer.metadata.art_uri);
			html_renderer.state = RENDERER_STATE_PLAYING;
		}
	});
}



function track_to_html_renderer(track)
{
	html_renderer['position'] = 0;
	html_renderer['duration'] = track['duration'];

	html_renderer['metadata'] = {
		artist      : track['artist'],
		album_title : track['album_title'],
		genre       : track['genre'],
		title       : track['title'],
		track_num   : track['track_num'],
		type        : track['type'],
		year_str    : track['year_str'],
		art_uri     : track['art_uri'],
		pretty_size : track['size'] };

	// create the media path for our localLibrary

	var path = track['path'];
	if (!path.startsWith('http'))
	{
		path = "/media/" + track['id'] + '.' + track['type'];
		html_renderer.metadata.art_uri = '/get_art/' + track['parent_id'] + '/folder.jpg';
	}

	html_renderer.path = path;

}


function set_local_playlist(library_uuid,playlist_id)
{
	init_html_renderer(RENDERER_STATE_TRANSIT);
	$.get('/webui/library/'+ library_uuid + '/get_playlist' +
		  '?renderer_uuid=' + html_renderer.uuid +
		  '&id=' + playlist_id,

	function(result)
	{
		if (result.error)
		{
			rerror('Error in set_local_playlist(' + library_uuid + ',' + playlist_id + '): ' + result.error);
		}
		else
		{
			html_renderer.playlist = result;
			playlist_local(0);
		}
	});
}


function playlist_local(inc)
{

}
