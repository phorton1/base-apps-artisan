// EXPERIMENTAL
//
// This is an <audio> element that conforms to the API of mpXXX.pm
// for plugging into the localRenderer on linux.
//
// As such, as with audio.js, please see
//
// https://developer.mozilla.org/en-US/docs/Web/HTML/Element/audio


var html_audio;
var html_audio_state = RENDERER_STATE_INIT;
var html_audio_version = 0;


function init_html_audio()
{
	if (!html_audio)
	{
		display(0,0,"INIT_HTML_AUDIO()");
		html_audio = document.createElement('audio');
		html_audio.setAttribute('autoplay', true);
		html_audio.addEventListener("ended", (event) =>
			{ onHTMLMediaEnded(event); } );
	}
}


function addHTMLAudioData(data)
{

	var position = 0;
	var duration = 0;

	if (html_audio_state == RENDERER_STATE_PAUSED ||
		html_audio_state == RENDERER_STATE_PLAYING)
	{
		var tm = html_audio.currentTime;
		var dur = html_audio.duration;
		if (tm != undefined)
			position = tm * 1000;
		if (dur != undefined)
			duration = dur * 1000;
	}

	data.html_audio_state = html_audio_state;
	data.html_audio_version = html_audio_version;
	data.html_audio_position = position;
	data.html_audio_duration = duration;
}


function handle_html_audio(data)
{
	init_html_audio();
	var command = data.command;
	// display(0,0,"html_audio dv(" + data.version + ") hv(" + html_audio_state.version + ") command=" + command);
	if (command != '')
	{
		display(0,0,"GOT COMMAND " + command);
		var parts = command.split(',');
		html_audio_command(parts[0],parts[1] || '');
	}
	html_audio_version = data.version;
}



function html_audio_command(command,arg)
{

	display(0,0,"html_audio_command(" + command + ") arg='" + arg + "'");

	if (command == 'stop')
	{
		if (html_audio_state == RENDERER_STATE_PLAYING ||
			html_audio_state == RENDERER_STATE_PAUSED)
		{
			html_audio.pause();
			html_audio_state = RENDERER_STATE_STOPPED;
		}
	}
	else if (command == 'pause')
	{
		if (html_audio_state == RENDERER_STATE_PLAYING)
		{
			html_audio.pause();
			html_audio_state = RENDERER_STATE_PAUSED;
		}
	}
	else if (command == 'set_position')
	{
		if (html_audio_state == RENDERER_STATE_PLAYING ||
			html_audio_state == RENDERER_STATE_PAUSED)
		{
			html_audio.currentTime = arg / 1000;
		}
	}
	else if (command == 'play' && arg == '')
	{
		if (html_audio_state == RENDERER_STATE_PAUSED)
		{
			html_audio.play();
			html_audio_state = RENDERER_STATE_PLAYING;
		}
	}
	else if (command == 'play')
	{
		html_audio.src = arg;
		html_audio_state = RENDERER_STATE_PLAYING;
	}
}


function onHTMLMediaEnded(event)
{
	html_audio_state = RENDERER_STATE_STOPPED;
}




// end of html_audio.js