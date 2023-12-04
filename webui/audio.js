// https://css-tricks.com/lets-create-a-custom-audio-player/
// https://developer.mozilla.org/en-US/docs/Web/HTML/Element/audio

// TODO:  WMA Files don't work on HTML renderer.  Need a good way to skip em (esp in playlists)


var dbg_audio = 0;

var audio;


const PLAYLIST_ABSOLUTE = 0;
const PLAYLIST_RELATIVE = 1;


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
		type		: DEVICE_TYPE_RENDERER,
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
	audio = document.createElement('audio');
	audio.setAttribute('autoplay', true);

	if (true)
	{
		// <! audio id='audio_player'
		// 	style='padding-top:10px;'
		// 	autoplay controls height='30px'/ >
		audio.setAttribute('controls', true);
		var div = document.getElementById('explorer_album_info_td');
		div.appendChild(audio);
	}

	init_html_renderer(RENDERER_STATE_NONE);
	audio.addEventListener("ended", (event) =>
		{ onMediaEnded(event); } );
}


function audio_command(command,args)
{
	var use_dbg = dbg_audio;
	if (command == 'update') use_dbg += 1;
	display(use_dbg,0,"audio_command(" + command + ")");

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
			html_renderer.position = position;
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
		playlist_song(PLAYLIST_RELATIVE,1);
	}
	else if (command == 'prev')
	{
		playlist_song(PLAYLIST_RELATIVE,-1);
	}
	else if (command == 'playlist_song')
	{
		var index = args['index'];
		playlist_song(PLAYLIST_ABSOLUTE,index);
	}
	else if (command == 'shuffle_playlist')
	{
		var shuffle = args.shuffle;
		playlist_shuffe(shuffle);
	}
}




function play_song_local(library_uuid,track_id)
{
	init_html_renderer(RENDERER_STATE_TRANSIT);
	$.get(library_url() + '/get_track?id=' + track_id,
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
		pretty_size : prettyBytes(track['size']) };

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
	$.get(library_url()  + '/get_playlist' +
		  '?id=' + playlist_id,

	function(result)
	{
		if (result.error)
		{
			rerror('Error in set_local_playlist(' + library_uuid + ',' + playlist_id + '): ' + result.error);
		}
		else
		{
			html_renderer.playlist = result;
			var track_id = result.track_id;
			if (track_id == undefined || !track_id)
			{
				rerror("No track_id(" + track_id + ") in set_local_playlist(" + library_uuid + ',' + playlist_id + ")");
			}
			else
			{
				play_song_local(library_uuid,track_id);
			}
		}
	});
}


function playlist_song(mode,inc)
{
	var playlist = html_renderer.playlist;
	if (!playlist)
		return;

	library_uuid = playlist.uuid;
	playlist_id = playlist.id;

	$.get(library_url()  + '/get_playlist_track' +
	  '?version=' + playlist.version +
	  '&id=' + playlist_id +
	  '&mode=' + mode +
	  '&index=' + inc,

	function(result)
	{
		if (result.error)
		{
			rerror('Error in playlist_song(' + mode + ',' + inc + '): ' + result.error);
		}
		else
		{
			html_renderer.playlist = result;
			var track_id = result.track_id;
			if (track_id == undefined ||
				!track_id)
			{
				rerror("No track_id(" + track_id + ") in playlist_song local(" + mode + "," + inc + ")");
			}
			else
			{
				play_song_local(library_uuid,track_id);
			}
		}
	});
}



function playlist_shuffe(shuffle)
{
	var playlist = html_renderer.playlist;
	if (!playlist)
		return;

	library_uuid = playlist.uuid;
	playlist_id = playlist.id;

	$.get(library_url() + '/shuffle_playlist' +
	  '?id=' + playlist_id +
	  '&shuffle=' + shuffle,

	function(result)
	{
		if (result.error)
		{
			rerror('Error in playlist_shuffe(' + shuffle + '): ' + result.error);
		}
		else
		{
			html_renderer.playlist = result;
			var track_id = result.track_id;
			if (track_id == undefined || !track_id)
			{
				rerror("No track_id(" + track_id + ") in playlist_shuffe(" + shuffle + ")");
			}
			else
			{
				play_song_local(library_uuid,track_id);
			}
		}
	});
}






function onMediaEnded(event)
{
	if (html_renderer.playlist &&
		html_renderer.state == RENDERER_STATE_PLAYING)
	{
		playlist_song(PLAYLIST_RELATIVE,1);
	}
}


// It is interesting that the audio appears to cache the audio data.
// Playing the same song twice does not get it twice from me.
//
//  Trying ---> SET HTTPServer::$SINGLE_THREAD to 0!!
//
//      If the HTTP Server is single threaded.
//		the audio player can wait to read the bytes of a long song
//      so any ui that involves a web hit stop working
//
// However, there are several problems.
//
//	Partial buffering ...
//
//      The slider fails miserably if you move it past the amount
//      that is buffered ... jumps to the next song.
//
//		Bad Starting Position
//
//			I have seen cases where the audio
//			on a re-play starts in the middle of the song, and
//      	the audio.currentTime starts at 0 ... hmmm ...
//
//  Solutions:
//
//  	I think I need a way to really clear the audio cache
//		and reget it on every replay.






// end of audio.js