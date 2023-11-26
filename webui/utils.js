// utils.js





var debug_level = 0;

var device_id = '';


jQuery.ajaxSetup({async:false});


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
		// if (WITH_SWIPE)
			$('#temp_console_output').append(out_msg + "<br>");

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


// end of utils.js
