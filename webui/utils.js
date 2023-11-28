// utils.js


var debug_level = 0;
var dbg_menu = 0;
var dbg_prefs = 0;

var device_id = '';


jQuery.ajaxSetup({async:false});

const DEVICE_TYPE_RENDERER = 'renderer';
const DEVICE_TYPE_LIBRARY = 'library';


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

function commaJoin(array) { return array.join(','); }
	// to display parameter list in display() headers


function my_alert(title,msg)
{
	var d = new dialog(title, msg);
	d.show();
}

function error(msg,call_level)
{
	if (call_level == undefined)
		call_level = 1;
	console.error(caller(call_level) + " " + msg);
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
	if (call_level == undefined)
		call_level = 1;
	if (level <= debug_level)
	{
		var indent_txt = '';
		while (indent--) { indent_txt += '    '; }
		var out_msg = caller(call_level) + ' ' + indent_txt + msg;

		console.debug(out_msg);

		// $('#temp_console_output').append(out_msg + "<br>");

	}
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
// decode utilities
//--------------------------------------

function decode_ampersands(encoded)
	// convert strings with double escaped ampersands
	// into the actual display string. This *should*
	// be safe to call multiple times ...
{
	var div = document.createElement('div');
	div.innerHTML = encoded;
	return div.firstChild.nodeValue;
}




//--------------------------------------
// DOM utilities
//--------------------------------------

function unused_ele_set_display(id,value)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.style.display = value;
	}
}


function ele_set_inner_html(id,html)	// used a lot
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.innerHTML = html;
	}
}


function ele_set_value(id,value)	// used once
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.value = value;
	}
}

function ele_set_src(id,src)	//  used twice
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.src = src;
	}
}

function ele_get_src(id)	//  used twice
{
	var src = '';
	var ele = document.getElementById(id);
	if (ele)
	{
		src = ele.src;
	}
	return src;
}


function unused_ele_set_class(id,className)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.className = className;
	}
}



//----------------------------------------
// cookie utilities
//----------------------------------------

function setCookie(cname, cvalue, exdays)
{
    var d = new Date();
    d.setTime(d.getTime() + (exdays*24*60*60*1000));
    var expires = "expires="+d.toUTCString() + ";";
    document.cookie = cname + "=" + cvalue + ";" + expires + "SameSite=Strict;";
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


function appendRadioButton(menu_name, name, id, fxn, param1, param2)
	// called from home.js
	// menu_name will be 'playlist', 'renderer', or 'library'
	// caller provides the id to concatenate to the menu_name
	//		 playlist_003
	//       renderer_90830984feed
	// as well as the specific function (i.e. setPlaylist) and
	// parametrers (setPlaylist(library_uuid, playist_id)
{
	display(dbg_menu,1,"appendRadioButton(" + commaJoin([menu_name, name, id, fxn, param1, param2]) + ")" );

	var use_id = menu_name + '_' + id;
	var hash_id = '#' + use_id;

	$('#' + menu_name + '_menu').append(
		$('<input>').prop({
			type: 	'radio',
			name: 	menu_name,		// the name of the radio group
			id: 	use_id,
		})
	).append(
		$('<label>').prop({
			for: use_id,
		}).html(name)
	).append(
		$('<br>'));

	$(hash_id).attr('onClick',fxn + "('" + param1 + "','" + param2 + "')");
}


function buildHomeMenu(array, menu_name, id_field, fxn, param1_field, param2_field)
	// builds the menu_playlist, menu_renderer or menu_library in the page_home_menu.html
{
	display(dbg_menu,0,"buildHomeMenu(" + commaJoin([ menu_name, id_field, fxn, param1_field, param2_field ]) + ")");

	$('#' + menu_name + '_menu').html('');		// clear existing

	$.each(array , function(index, item)  {

		appendRadioButton(
			menu_name,
			item.name,
			item[id_field],
			fxn,
			item[param1_field],
			item[param2_field]);
	});

	$('#' + menu_name + '_menu').buttonset();
}



// end of utils.js
