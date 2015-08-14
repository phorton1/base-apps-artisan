//----------------------------------------------------
// artisan.js
//----------------------------------------------------

var menu_showing = false;
	// will only be closed if it was shown by show_menu

jQuery.ajaxSetup({async:false});	
	// Syncrhonous mode is arguably safer as it prevents
	// the stacking up of webUI calls, but responsiveness
	// suffers as the buttons stick until the webUI call
	// completes. Async mode seems to work better for
	// most things, in terms of responsiveness, but
	// for some reason the slider stops working .. it
	// completely stops sending events, and I suspect
	// the base easyUI draggable class also fails in
	// general in synchronous mode. Sheesh.


function rerror(msg)
{
	alert(msg);
}


function show_artisan_menu()
{
	// alert('show artisan menu');
    $('#artisan_menu').window('open');
	menu_showing = true;
}

function hide_artisan_menu()
{
	if (menu_showing)
	{
	    $('#artisan_menu').window('close');
		menu_showing = false;
	}
}



	

//--------------------------------------
// DOM utilities used throughout
//--------------------------------------

function ele_set_inner_html(id,html)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.innerHTML = html;
	}
}

function ele_set_disabled(id,disabled)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.disabled = disabled;
	}
}

function ele_set_value(id,value)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.value = value;
	}
}

function ele_set_src(id,src)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.src = src;
	}
}

function ele_get_src(id)
{
	var src = '';
	var ele = document.getElementById(id);
	if (ele)
	{
		src = ele.src;
	}
	return src;
}


function ele_set_class(id,className)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.className = className;
	}
}




//----------------------------------------
// unused cookies
//----------------------------------------

function setCookie(cname, cvalue, exdays)
{
    var d = new Date();
    d.setTime(d.getTime() + (exdays*24*60*60*1000));
    var expires = "expires="+d.toUTCString();
    document.cookie = cname + "=" + cvalue + "; " + expires;
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


//-------------------------------------------------------
// various other utilities
//-------------------------------------------------------

function toggleFullScreen()
{
	var doc = window.document;
	var docEl = doc.documentElement;
	var requestFullScreen =
		docEl.requestFullscreen ||
		docEl.mozRequestFullScreen ||
		docEl.webkitRequestFullScreen ||
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



function decode_ampersands(encoded)
	// convert strings with double escaped ampersands
	// into the actual display string. This *should*
	// be safe to call multiple times ... 
{
	var div = document.createElement('div');
	div.innerHTML = encoded;
	return div.firstChild.nodeValue;
}

