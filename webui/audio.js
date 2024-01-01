// https://css-tricks.com/lets-create-a-custom-audio-player/
// https://developer.mozilla.org/en-US/docs/Web/HTML/Element/audio


var dbg_audio = 0;
var dbg_queue = 0;

var audio;


var html_renderer = {
		name		: 'HTML Audio',
		type		: DEVICE_TYPE_RENDERER,
		playing     : RENDERER_PLAY_QUEUE,

		position 	: 0,
		duration 	: 0,
		needs_start : 0,
		muted	    : 0,

		maxVol 		: 100,
		canMute		: true,
		canLoud		: false,
		maxBal 		: 100,
		maxFade		: 0,
		maxBass		: 0,
		maxMid 		: 0,
		maxHigh		: 0,
		volume      : 80,
		balance     : 0,
		fade        : 0,
		bassLevel   : 0,
		midLevel    : 0,
		highLevel   : 0,
};


function init_html_renderer(state)
{
	html_renderer.state = state;
	html_renderer.path = '';
	html_renderer.position = 0;
	html_renderer.duration = 0;
	delete html_renderer.metadata;
}


function init_audio()
{
	audio = document.createElement('audio');
	audio.setAttribute('autoplay', true);

	if (false)
	{
		// The HTML Renderer no longer has a visual set of controls
		audio.setAttribute('controls', true);
		var div = document.getElementById('explorer_album_info_td');
		div.appendChild(audio);
	}

	// Set a unique semi-persistent uuid and get a Queue from Perl

	html_renderer.uuid = 'html_renderer_' + DEVICE_ID;
	queue_command('get_queue');

	// if inited with a queue, set state STOPPED instead of init

	init_html_renderer( html_renderer.queue.num_tracks > 0 ?
		RENDERER_STATE_STOPPED :
		RENDERER_STATE_INIT);


	audio.addEventListener("ended", (event) =>
		{ onMediaEnded(event); } );
}


function queue_command(command,params)
	// remember that these POSTS are synchronous
	// which means we don't have to worry about update (get_queue)
	// happening in the middle of one.  However, the html renderer
	// responsiveness will suffer with bad WiFi or big commands.
{
	if (params == undefined) params = {};
	params.renderer_uuid = html_renderer.uuid;

	var data = JSON.stringify(params);
	var url = '/webui/queue/' + command;

	if (command != 'get_queue')
	{
		display(dbg_queue,1,'queue_command ' + url + "data=\n" + data);
	}
	$.post(url,data,function(result)
	{
		if (result.error)
		{
			rerror(result.error);
		}
		else
		{
			if (result.queue)
			{
				var queue = result.queue;
				html_renderer.queue = queue;
				if (html_renderer.needs_start != queue.needs_start)
				{
					html_renderer.needs_start = queue.needs_start;
					html_renderer.playing = RENDERER_PLAY_QUEUE;
					track = result.track;
					if (track)
					{
						play_song_local(track.library_uuid,track.id);
					}
					else
					{
						audio_command('stop');
					}
				}
			}
		}
	});
}



//-------------------------------------------
// audio_command()
//-------------------------------------------

function audio_command(command,args)
{
	var use_dbg = dbg_audio;
	if (command == 'update') use_dbg += 1;
	display(use_dbg,0,"audio_command(" + command + ")");

	//-------------------------------------------------------------
	// Generic commands that work directly on the HTML Renderer
	//-------------------------------------------------------------

	if (command == 'seek')
	{
		if (html_renderer.state == RENDERER_STATE_PLAYING ||
			html_renderer.state == RENDERER_STATE_PAUSED)
		{
			var position = args['position'];
			html_renderer.position = position;
			audio.currentTime = position / 1000;
		}
	}
	else if (command == 'play_song')
	{
		var library_uuid = args['library_uuid'];
		var track_id = args['track_id'];
		play_song_local(library_uuid,track_id);
	}
	else if (command == 'toggle_mute')
	{
		html_renderer.muted = html_renderer.muted ? 0 : 1;
		audio.muted = html_renderer.muted;
	}


	//-----------------------------------------------------------
	// Generic Commands with extra behavior if Queue
	//-----------------------------------------------------------

	else if (command == 'stop')
	{
		if (html_renderer.state == RENDERER_STATE_PLAYING ||
			html_renderer.state == RENDERER_STATE_PAUSED)
		{
			audio.pause();
			init_html_renderer(RENDERER_STATE_STOPPED);
		}
		else if (html_renderer.state == RENDERER_STATE_STOPPED)
		{
			delete html_renderer.playlist;
			queue_command('clear');
			init_html_renderer(RENDERER_STATE_INIT);
		}
	}

	if (command == 'play_pause')
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
		else if (html_renderer.playing == RENDERER_PLAY_PLAYLIST)
		{
			playlist_song(PLAYLIST_RELATIVE,0);
		}
		else if (html_renderer.state == RENDERER_STATE_STOPPED)
		{
			if (html_renderer.queue.num_tracks > 0)
				queue_command('restart');
		}
	}
	else if (command == 'update')
	{
		if (html_renderer.playing == RENDERER_PLAY_QUEUE)
			queue_command('get_queue');

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

	//-------------------------------------
	// Playlist specific commands
	//-------------------------------------

	else if (command == 'set_playlist')
	{
		html_renderer.playing = RENDERER_PLAY_PLAYLIST;
		var library_uuid = args['library_uuid'];
		var playlist_id = args['id'];
		set_local_playlist(library_uuid,playlist_id);
	}
	else if (command == 'playlist_song')
	{
		playlist_song(PLAYLIST_ABSOLUTE,args.index);
	}


	//-------------------------------------
	// Orthogonally implemented commands
	//-------------------------------------

	else if (command == 'set_playing')
	{
		// only called on changes
		var playing = args.playing
		html_renderer.playing = playing;
		if (playing == RENDERER_PLAY_PLAYLIST)
		{
			playlist_song(PLAYLIST_RELATIVE,0);
		}
		else
		{
			var queue = html_renderer.queue;
			if (queue.track_index < queue.num_tracks)
				queue_command('restart');
		}
	}


	else if (command == 'next')
	{
		if (html_renderer.playing == RENDERER_PLAY_PLAYLIST)
		{
			playlist_song(PLAYLIST_RELATIVE,1);
		}
		else
		{
			queue_command('next');
		}
	}
	else if (command == 'prev')
	{
		if (html_renderer.playing == RENDERER_PLAY_PLAYLIST)
		{
			playlist_song(PLAYLIST_RELATIVE,-1);
		}
		else
		{
			queue_command('prev');
		}
	}
	else if (command == 'next_album')
	{
		if (html_renderer.playing == RENDERER_PLAY_PLAYLIST)
		{
			playlist_song(PLAYLIST_ALBUM_RELATIVE,1);
		}
		else
		{
			queue_command('next_album');
		}
	}
	else if (command == 'prev_album')
	{
		if (html_renderer.playing == RENDERER_PLAY_PLAYLIST)
		{
			playlist_song(PLAYLIST_ALBUM_RELATIVE,-1);
		}
		else
		{
			queue_command('prev_album');
		}
	}

	else if (command == 'shuffle')
	{
		var how = args.how;
		if (html_renderer.playing == RENDERER_PLAY_PLAYLIST)
		{
			playlist_shuffe(how);
		}
		else
		{
			queue_command('shuffle',{how:how});
		}
	}

	//------------------------------------------------
	// Queue Specific Commands
	//------------------------------------------------

	else if (command == 'play_track')
	{
		queue_command('play_track',args);
	}

	// enqueing is done here so html_renderer can get
	// queue.needs_start

	else if (command == 'add' ||
			 command == 'play')
	{
		queue_command(command,args);
	}

}


//-----------------------------------------------
// methods
//-----------------------------------------------

function track_to_html_renderer(library_uuid,track)
{
	var button = document.getElementById('library_' + library_uuid);
	if (!button)
	{
		rerror("library " + library_uuid + " is not online!");
		return false;
	}
	var rec = button.rec;

	html_renderer['position'] = 0;
	html_renderer['duration'] = track['duration'];

	html_renderer['metadata'] = {
		artist      : track['artist'],
		album_title : track['album_title'],
		genre       : track['genre'],
		title       : track['title'],
		tracknum   : track['tracknum'],
		type        : track['type'],
		year_str    : track['year_str'],
		art_uri     : track['art_uri'],
		pretty_size : prettyBytes(track['size']),
		library_uuid : library_uuid };

	// tracks from playlists will not include the library_uuid?

	// create the media path for our localLibrary

	var path = track['path'];
	if (rec.local || rec.remote_artisan)
	{
		var ip = rec.ip;
		var port = rec.port;
		var host = rec.remote_artisan ? 'http://' + ip + ':' + port : '';
		path = host + "/media/" + track['id'] + '.' + track['type'];
		html_renderer.metadata.art_uri = host + '/get_art/' + track['parent_id'] + '/folder.jpg';
	}

	html_renderer.path = path;
	return true;
}


function play_song_local(library_uuid,track_id)
{
	init_html_renderer(RENDERER_STATE_TRANSIT);
	var url = library_url(library_uuid);
	if (!url) return;

	$.get(url + '/get_track?id=' + track_id,
	function(result)
	{
		if (result.error)
		{
			rerror('Error in play_song_local(): ' + result.error);
		}
		else
		{
			if (track_to_html_renderer(library_uuid,result))
			{
				audio.src = html_renderer.path;
				$('#audio_player_title').html(html_renderer.metadata.title);
				$('#explorer_folder_image').attr('src',html_renderer.metadata.art_uri);
				html_renderer.state = RENDERER_STATE_PLAYING;
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

	var url = library_url(library_uuid);
	if (!url) return;

	$.get(url + '/get_playlist_track' +
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


function playlist_shuffe(how)
{
	var playlist = html_renderer.playlist;
	if (!playlist)
		return;

	library_uuid = playlist.uuid;
	playlist_id = playlist.id;

	var url = library_url(library_uuid);
	if (!url) return;

	$.get(url + '/shuffle_playlist' +
	  '?id=' + playlist_id +
	  '&shuffle=' + how,
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


function set_local_playlist(library_uuid,playlist_id)
{
	init_html_renderer(RENDERER_STATE_TRANSIT);
	var url = library_url(library_uuid);
	if (!url) return;

	$.get(url + '/get_playlist' +
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


function onMediaEnded(event)
{
	if (html_renderer.state == RENDERER_STATE_PLAYING)
	{
		if (html_renderer.playing == RENDERER_PLAY_PLAYLIST)
		{
			// html_renderer.playlist will be set
			playlist_song(PLAYLIST_RELATIVE,1);
		}
		else
		{
			queue_command('next');
		}
	}
}


// end of audio.js