// utils.js


var DEBUG_REMOTE = true;
	// This variable turns on certain output from mobile devices
	// as I am trying to figure out scaling, rotation, etc.

var DISPLAY_REMOTE = false;
	// if this is set to true, all display() and error() calls
	// will additionally GET /webui/debug_output/msg to display
	// on the Perl Console.   It is very slow, and adds a lot
	// of clutter, so should only be used when trying to find
	// bugs on mobile devices.


var debug_level = 0;
var dbg_menu = 0;
var dbg_prefs = 0;
var dbg_ios = 0;

const RENDERER_STATE_INIT		= 'INIT';
const RENDERER_STATE_STOPPED	= 'STOPPED';
const RENDERER_STATE_TRANSIT	= 'TRANSIT';
const RENDERER_STATE_PLAYING	= 'PLAYING';
const RENDERER_STATE_PAUSED		= 'PAUSED';
const RENDERER_STATE_ERROR		= 'ERROR';

const RENDERER_PLAY_QUEUE = 0;
const RENDERER_PLAY_PLAYLIST = 1;

const PLAYLIST_ABSOLUTE = 0;
const PLAYLIST_RELATIVE = 1;
const PLAYLIST_ALBUM_RELATIVE = 2;

const SHUFFLE_NONE	 = 0;
const SHUFFLE_TRACKS = 1;
const SHUFFLE_ALBUMS = 2;

const DEVICE_TYPE_RENDERER = 'renderer';
const DEVICE_TYPE_LIBRARY = 'library';



jQuery.ajaxSetup({async:false});
	// global async jquery Ajax setup


//-------------------------------------------
// important global variables and methods
//-------------------------------------------

var DEVICE_ID = '';

var IS_IOS = false;
var IS_TOUCH = false;
var IS_DESKTOP = false;

var current_renderer = false;
var current_library = false;

// function library_url()
// {
// 	var host = current_library.remote_artisan ?
// 		'http://' + current_library.ip + ':' + current_library.port : '';
// 	var url =  host + "/webui/library/" + current_library['uuid'];
// 	// display(0,0,"library url=" + url);
// 	return url;
// }



function current_library_url()
	// called from explorer.js and home.js, by anybody who wants
	// to do a /webui/library request to the current_library.
	//
	// Will NEVER return '' because it is only called for the
	// current_library which is ALWAYS online and in the list
{
	return library_url(current_library.uuid);
}

function library_url(library_uuid)
	// Called for every access to /webui/library/***
	//
	// May return '' if library is not online (in the device
	// list) so every caller MUST check for that and report
	// an error appropriately.
	//
	// Notices remote_artisan libraries and prepends the
	// server_ip:server_port host to the address.
{
	var button = document.getElementById('library_' + library_uuid);
	if (!button)
	{
		rerror("library " + library_uuid + " is not online!");
		return '';
	}
	var rec = button.rec;		// should always be there
	var host = '';
	if (rec.remote_artisan)
		host = 'http://' + rec.ip + ":" + rec.port;

	var url =  host + "/webui/library/" + library_uuid;
	return url;
}


function getLibraryName(library_uuid)
{
	var button = document.getElementById('library_' + library_uuid);
	if (!button)
	{
		rerror("library " + library_uuid + " is not online!");
		return '';
	}
	var rec = button.rec;		// should always be there
	return rec.name;
}


//---------------------------------------------
// initialization
//---------------------------------------------

function init_utils()
	// this method is currently supplied soley to set
	// IS_IOS, IS_TOUCH, and IS_DESKTOP
	// which are currently not used.
{
	if (navigator.maxTouchPoints &&
		navigator.maxTouchPoints > 1)
	{
		IS_TOUCH = 1;
	}
	var platform = navigator.platform;
	if (navigator.userAgent.includes('iPad') ||
		navigator.userAgent.includes('iPhone') || (
		IS_TOUCH && navigator.platform == 'MacIntel'))
	{
		IS_IOS = true;
	}

	IS_DESKTOP = !IS_TOUCH;
	debug_remote(dbg_ios,0,"IS_IOS(" + IS_IOS + ") IS_TOUCH(" + IS_TOUCH + ") IS_DESKTOP(" + IS_DESKTOP + ")");
}


function init_device_id()
	// random 8 hex digit string device id
	// stored to localStorage. returns ''
	// if localStorage not enabled.
{
	DEVICE_ID = getStorage('device_id');
	if (!DEVICE_ID)
	{
		DEVICE_ID = random32Hex();
		debug_remote(0,0,"create new device_id=" + DEVICE_ID);
		putStorage('device_id', DEVICE_ID);
	}
	else
	{
		debug_remote(0,0,"got existing device_id=" + DEVICE_ID);
	}
}


function random32Hex()
{
  return random16Hex() + random16Hex();
}

function random16Hex()
{
	return (0x10000 | Math.random() * 0x10000).toString(16).substr(1);
}



//---------------------------------------------
// display utilities
//---------------------------------------------

window.onerror = function(message, source, lineNumber, colno, err)
	// this will report 'unhandled exceptions' via my error() method
{
	error(source + ":" + lineNumber + ": " + message,1);
};


function my_alert(title,msg)
{
	var d = new dialog(title, msg);
	d.show();
}

function error(msg,call_level)
{
	if (call_level == undefined)
		call_level = 1;
	var call_part = caller(call_level);
	console.error(call_part + " " + msg);
	if (DISPLAY_REMOTE)
		output_remote("ERROR: " + call_part + " " + msg);
}

function rerror(msg,call_level)
{
	if (call_level == undefined)
		call_level = 1;
	error(msg,call_level + 1);
	my_alert("Error at " + caller(call_level),msg);
}


function display(level,indent,msg,call_level)
{
	if (level > debug_level)
		return;
	if (call_level == undefined)
		call_level = 1;

	var indent_txt = '';
	while (indent--) { indent_txt += '    '; }
	var out_msg = caller(call_level) + ' ' + indent_txt + msg;

	console.debug(out_msg);
	if (DISPLAY_REMOTE)	// && !IS_DESKTOP)
		output_remote(out_msg);
}


function output_remote(msg)
	// To help work with Browsers on mobile devices, where
	// there is no javascript debugger, and it can be very
	// difficult to tell whats wrong when all you get is a
	// blank page, I added this routine which will make a
	// call back to the server to display output.
{
	$.get('/webui/debug_output/' + msg);
}


function debug_remote(level,indent,msg,call_level)
	// this is a bit of the opposite.
	// if DEBUG_REMOTE is set, this will do a display()
	// and output_remote().  It is used to ferret out
	// specific issues on specific devices.
{
	if (level > debug_level)
		return;
	if (call_level == undefined)
		call_level = 1;
	display(level,indent,msg,call_level+1);
	if (!DEBUG_REMOTE)
		return;

	var indent_txt = '';
	while (indent--) { indent_txt += '    '; }
	var out_msg = caller(call_level) + ' ' + indent_txt + msg;
	output_remote(out_msg);
}


function caller(call_level)
{
	var stack = (new Error).stack.split("\n");
	var index = 1 + call_level;
	if (index > stack.length-1)
		index = stack_length-1;
	var caller = '';
	var caller_full = stack[index];
	if (caller_full != undefined)
	{
		var caller_parts = caller_full.split("\/");
		if (caller_parts.length > 0)
		{
			caller = caller_parts[caller_parts.length-1];
		}
		else
		{
			caller = caller_full;
		}
	}
	while (caller.length<20) {caller += ' '; }
	return caller;
}


//--------------------------------------
// generic jquery dialog
//--------------------------------------

function dialog(title, message)
{
	this.elem = $('<div></div>')
		.html(message)
		.dialog({
			// 	// width:  237,
			// 	// autoOpen: false,
			// 	// modal: true,
			// 	// closeOnEscape: true,
			autoOpen: false,
			title: title,
			close: function() {
				$(this).remove();
			}
	});
}

dialog.prototype =
{
	show: function() {  this.elem.dialog('open'); }
};




//--------------------------------------
// misc utilities
//--------------------------------------

function commaJoin(array)
	// to display parameter list in display() headers
{
	return array.join(',');
}


function prettyBytes(bytes)
{
    if (!bytes)  bytes = 0;

	var ctr = 0;
	var size = ['', 'K', 'M', 'G', 'T'];
	for (ctr = 0; bytes > 1000; ctr++)
	{
		bytes = bytes / 1000;
	}

	var rslt = bytes;
	if (ctr > 0)
		rslt = bytes.toFixed(1) + size[ctr];
    return rslt;
}


function decode_ampersands(encoded)
	// convert strings with double escaped ampersands
	// into the actual display string. This *should*
	// be safe to call multiple times ...
{
	return encoded;

	var div = document.createElement('div');
	div.innerHTML = encoded;
	return div.firstChild.nodeValue;
}


function toggleFullScreen()
{
	var doc = window.document;
	var docEl = doc.documentElement;
	var requestFullScreen =
		docEl.requestFullscreen ||
		docEl.mozRequestFullScreen ||
		docEl.webkitRequestFullscreen ||
		docEl.msRequestFullscreen;
	var cancelFullScreen =
		doc.exitFullscreen ||
		doc.mozCancelFullScreen ||
		doc.webkitExitFullscreen ||
		doc.msExitFullscreen;
	if(!doc.fullscreenElement &&
	   !doc.mozFullScreenElement &&
	   !doc.webkitFullscreenElement &&
	   !doc.msFullscreenElement)
	{
		requestFullScreen.call(docEl);
	}
	else
	{
		cancelFullScreen.call(doc);
	}
}


//----------------------------------------
// storage utilities
//----------------------------------------


function getStorage(key)
{
	var value = '';
	try
	{
		value = localStorage.getItem(key);
		if (value == undefined)
			value = '';
	}
	catch (SecurityError)
	{
		error(SecurityError);
	}

	return value;
}

function putStorage(key,value)
{
	try
	{
		localStorage.setItem(key,value);
	}
	catch (SecurityError)
	{
		error(SecurityError);
	}
	return value;
}

function clearStorage()
	// clears all local storage
	// use removeITem for individual items
{
	try
	{
		localStorage.clear();
	}
	catch (SecurityError)
	{
		error(SecurityError);
	}
}


//-------------------------------------------------
// home_menu builder utilities
//-------------------------------------------------

function create_numeric_pref(min,med,max,var_name,spinner_id)
{
	display(dbg_prefs,0,"create_numeric_pref(" + min + ',' + med + ',' + max + ',' + var_name + ',' + spinner_id + ")");

	$(spinner_id).spinner({
		width:20,
		min:min,
		max:max,
		change: function(event, ui)
		{
			var value = parseInt($(this).spinner('value'));
			window[var_name] = value;
			setCookie(var_name,value,180);
		},
	});

	var value = window[var_name];
	$(spinner_id).spinner('value',value);
}


function appendMenuButton(type, name, id, fxn, param1, param2, rec)
{
	display(dbg_menu,1,"appendMenuButton(" + commaJoin([type, name, id, fxn, param1, param2]) + ")" );

	var use_id = type + '_' + id;
	var hash_id = '#' + use_id;

    var input = document.createElement('input');
    input.type = 'radio';
    input.id = use_id;
	input.name = type + '_button';
    input.value = use_id;
	if (rec != undefined)
		input.rec = rec;

    var label = document.createElement('label')
    var text = document.createTextNode(name);
    label.htmlFor = use_id;
    label.appendChild(text);

    var br = document.createElement('br');

	var div = document.createElement('div');
	div.id = use_id + '_div';
    div.appendChild(input);
    div.appendChild(label);
    div.appendChild(br);

    var menu = document.getElementById(type + "_menu");
	menu.appendChild(div);

	$(hash_id).attr('onClick', fxn + "('" + param1 + "','" + param2 + "')");
	$(hash_id).button({ icon: false });
}


function buildDeviceMenu(array, type)
	// builds a set of buttons for the a list of devices in array
	// typeis either 'library' or 'renderer'
{
	display(dbg_menu,0,"buildDeviceMenu(" + type + ")");
	$('#' + type + '_menu').html('');	// remove existing buttons
	$.each(array , function(index, rec)
	{
		appendMenuButton(type, rec.name, rec.uuid, 'selectDevice', type, rec.uuid, rec);
	});
	$('#' + type + '_menu').buttonset();
}


function buildPlaylistMenu(array)
	// builds a set of buttons for the a list of devices in array
	// typeis either 'library' or 'renderer'
{
	display(dbg_menu,0,"buildPlaylistMenu()");
	$('#playlist_menu').html('');	// remove existing buttons
	$.each(array , function(index, rec)
	{
		appendMenuButton('playlist', rec.name, rec.id, 'setPlaylist', rec.uuid, rec.id);
	});
	$('#playlist_menu').buttonset();
}


// end of utils.js
