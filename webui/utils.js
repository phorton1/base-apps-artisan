// utils.js


var DEBUG_REMOTE = true;
	// This variable turns on certain output from mobile devices
	// as I am trying to figure out scaling, rotation, etc.

var DISPLAY_REMOTE = true;
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




var device_id = '';

var IS_IOS = false;
var IS_TOUCH = false;
var IS_DESKTOP = false;



jQuery.ajaxSetup({async:false});


window.onerror = function(message, source, lineNumber, colno, err)
	// this will report 'unhandled exceptions' via my error() method
{
	error(source + ":" + lineNumber + ": " + message,1);
};


const DEVICE_TYPE_RENDERER = 'renderer';
const DEVICE_TYPE_LIBRARY = 'library';


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


//---------------------------------------------
// device_id
//---------------------------------------------

function init_device_id()
	// random 8 hex digit string device id
	// stored to localStorage. returns ''
	// if localStorage not enabled.
{
	try
	{
		device_id = localStorage.getItem('device_id');
		if (device_id == undefined || !device_id)
		{
			device_id = random32Hex();
			display(0,0,"create new device_id=" + device_id);
			localStorage.setItem('device_id', device_id);
		}
		else
		{
			display(0,0,"got existing device_id=" + device_id);
		}
	}
	catch (SecurityError)
	{
		error(SecurityError);
		device_id = '';
	}

	return device_id;
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


function commaJoin(array) { return array.join(','); }
	// to display parameter list in display() headers

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



//----------------------------------------
// cookie utilities
//----------------------------------------

function setCookie(cname, cvalue, exdays)
{
    var d = new Date();
    d.setTime(d.getTime() + (exdays*24*60*60*1000));
    var expires = "expires="+d.toUTCString() + ";";
    document.cookie = cname + "=" + cvalue + ";" + expires + "path=/; SameSite=Strict;";
}

function getCookie(cname)
{
    var name = cname + "=";
    var ca = document.cookie.split(';');
    for(var i=0; i<ca.length; i++) {
        var c = ca[i];
        while (c.charAt(0)==' ') c = c.substring(1);
        if (c.indexOf(name) != -1) return c.substring(name.length, c.length);
    }
    return "";
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



function appendMenuButton(type, name, id, fxn, param1, param2)
{
	display(dbg_menu,1,"appendMenuButton(" + commaJoin([type, name, id, fxn, param1, param2]) + ")" );

	var use_id = type + '_' + id;
	var hash_id = '#' + use_id;

    var input = document.createElement('input');
    input.type = 'radio';
    input.id = use_id;
	input.name = type + '_button';
    input.value = use_id;

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
		appendMenuButton(type, rec.name, rec.uuid, 'selectDevice', type, rec.uuid);
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
