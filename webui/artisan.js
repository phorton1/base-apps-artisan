// artisan.js
//
// media queries height=window.innerHeight, and mq device-height==screen.height
// document.body.clientWidth == window.innerWidth == screen.width on tablets
// same is not true on desktop clientWidth<innerWidth<=screen.width
// window.innerHeight < or = screen.height in general
//
// tablet 600 x 1024
// desktop 1600 x 900
// car_stereo 534 x 320
//
// navigator.userAgent containing 'Mobile' or 'Android' is a good clue

jQuery.ajaxSetup({async:false});


var debug_level = 0;

var dbg_load 	 = 0;
var dbg_layout 	 = 0;
var dbg_popup 	 = 1;
var dbg_loop     = 1;

var current_renderer = false;
var current_library = false;

var WITH_SWIPE = true;
var REFRESH_TIME = 600;

var default_page = 'home';
var current_page = ''
var page_layouts = {};


var explorer_mode = 0;
var autoclose_timeout = 0;
var autofull_timeout = 0;
var autoclose_count = 0;
var autofull_count = 0;
var autofull = false;
var idle_timer = null;
var idle_count = 0;

display(dbg_load,0,"artisan.js loaded");



//========================================================
// Main
//========================================================

$(function()
{
	display(dbg_load,0,"START LOADING ARTISAN");

	explorer_mode = getCookie('explorer_mode') || 0;
	autoclose_timeout = parseInt(getCookie('autoclose_timeout') || 0);
	autofull_timeout = parseInt(getCookie('autofull_timeout') || 0);
	default_renderer_name = getCookie('default_renderer_name')

	$('.artisan_menu_table').buttonset();
	$('#context_menu_div').buttonset();

	load_page("home");
	load_page("explorer");

	setTimeout(idle_loop, REFRESH_TIME);
	set_page(default_page);

	display(dbg_load,0,"FINISHED LOADING ARTISAN");
});



$( window ).resize(function()
{
	display(dbg_layout,0,"$(window) resize(" + current_page + ") called");
	resize_layout(current_page);
});


function idle_loop()
{
	display(dbg_loop,0,"idle_loop(" + current_page + ")");
	idle_count++;

	if (current_page == 'home')
	{
		display(dbg_loop,1,"idle_loop() calling renderer_pane_onidle()");
		update_renderer_onidle();
		display(dbg_loop,1,"idle_loop() back from renderer_pane_onidle()");
	}

	if (false)	// crashes
	{
		check_timeouts();
	}


	display(dbg_loop,1,"idle_loop() settingTimeout");
	setTimeout("idle_loop();", REFRESH_TIME);

}	// idle_loop


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

	hide_layout_panes();
}


//------------------------------------------------
// setCurrentPage
//------------------------------------------------

function set_page(page_id)	// ,context)
{
	display(dbg_load,0,"set_page(" + page_id + ")");	//  context=" + context);
	if (current_page != '')
	{
		$('#' + current_page + '_page').css('display','none');
	}

	current_page = page_id;
	$('#' + current_page + '_page').css('display','block');

	// var context_fxn = 'set_context_' + page_id;
	// if (context && context != '' && window[context_fxn])
	// {
	// 	display(0,0,'calling ' + context_fxn + '(' + context + ')');
	// 	window[context_fxn](context);
	// }

	reset_timeouts();
	resize_layout(current_page);
	display(dbg_load,0,"set_page(" + page_id + ") returning");
}



//========================================================
// Page Loading and Resizing
//========================================================
// loadRecursive() is called on each page loaded
// into the artisan_body element by loadPage().
//
// data-load="url" attribute
//
//    Within a page, any element may specify a
//    data=load attribute, in which case it's innerHTML
//    will be automagically loaded from the url.
//
// data-onload='javascript:function' attribute
//
//    If an element specifies an url, then it may also
//    specify a javascript function that will be executed
//    when that innerHTML has been loaded

function load_page(page_id)
{
	display(dbg_load,0,"load_page(" + page_id + ")");

	loadRecursive($('#' + page_id + '_page'));
	create_layout(page_id);

	var init_fxn = 'init_page_' + page_id;
	display(dbg_load,0,"init_fxn=" + init_fxn);

	if (window[init_fxn])
	{
		window[init_fxn]();
		display(dbg_load,0,"back from " + init_fxn + "()");
	}
	else
	{
		display(dbg_load,0,"INIT FXN NOT FOUND: " + init_fxn);
	}

	display(dbg_load,0,"load_page(" + page_id + ") returning");

}


function loadRecursive(context,level)
{
	if (!level) level = 0;
	display(dbg_load,level,'loadRecursive(' + context.attr('id') + ')');

    context.find('[data-load]').each(function() {
		var url = $(this).attr('data-load');
		var onload_fxn = $(this).attr('data-onload');

		display(dbg_load,level,'--> onload url='+url);
		display(dbg_load,level,'    onload fxn='+onload_fxn);

		$(this).load( url, function()
		{
			loadRecursive($(this),level+1);
			if (onload_fxn && onload_fxn != '' && window[onload_fxn])
			{
			    display(dbg_load,level,'    calling onload fxn='+onload_fxn);
				window[onload_fxn]();
			}
		});
    });
}



function create_layout(page_id)
{
	var width = window.innerWidth;
	var height = window.innerHeight;
	var page_layout = page_layouts[page_id];
	var params = $.extend({
		applyDemoStyles: true,
		}, page_layout.defaults);

	var width = window.innerWidth;
	var height = window.innerHeight;
	page_layout.width = width;
	page_layout.height = height;
	page_layout.touch_enabled = width<600 || screen.width != 1600 ? true : false;

	display(dbg_layout,0,'create_layout(' + page_id + ',' + width + ',' + height + ')');

	create_layout_pane(page_layout,params,height,'north');
	create_layout_pane(page_layout,params,width,'west');
	create_layout_pane(page_layout,params,width,'east');
	create_layout_pane(page_layout,params,height,'south');

	var layout = $(page_layout.layout_id).layout(params);

	if (WITH_SWIPE)
	{
		$(page_layout.swipe_element).swipe({
			allowPageScroll:"vertical",
			swipe:onswipe_page,
			maxTimeThreshold:1500});
		$(page_layout.swipe_element).on('click',hide_layout_panes);
	}

	// page_layout.loaded = true;

}


function create_layout_pane(page_layout,params,value,pane)
{
	var pane_layout = page_layout[pane];
	if (pane_layout)
	{
		var size =  pane_layout.size;
		if (page_layout.touch_enabled && pane_layout.size_touch > 0)
		{
			size = pane_layout.size_touch;
		}
		display(dbg_layout,1,'create_layout_pane(' + pane + ') size=' + size);
		params[pane + '__size'] = size;

		// not needed if we call resize() anyways

		if (false)
		{
			var pane_hidden = value < pane_layout.limit ? true : false;
			params[pane + '__slide'] = pane_hidden;
			params[pane + '__slidable'] = pane_hidden;
			params[pane + '__spacing_closed'] = pane_hidden?(WITH_SWIPE?0:6):6;
			params[pane + '__initClosed'] = pane_hidden;
			params[pane + '__onclick'] = pane_hidden ? reset_timeouts : false;
		}
	}
}



function resize_layout(page_id)
{
	var width = window.innerWidth;
	var height = window.innerHeight;
	display(dbg_layout,0,"resize_layout(" + width + ',' + height + ')');

	var page_layout = page_layouts[page_id];

	// page_layout.loaded *might* be needed if the browser is resized
	// before it the pages have loaded ...

	if (page_layout) // && page_layout.loaded)
	{
		page_layout.width = width;
		page_layout.height = height;
		page_layout.touch_enabled = width<600 || screen.width != 1600 ? true : false;
		var layout = $('#' + page_id + '_page').layout();

		display(dbg_layout,0,"resizing layout(" + width + ',' + height + ')');

		resize_layout_pane(layout,page_layout,height,'north');
		resize_layout_pane(layout,page_layout,width,'west');
		resize_layout_pane(layout,page_layout,width,'east');
		resize_layout_pane(layout,page_layout,height,'south');

		display(dbg_layout+1,0,"calling layout.resizeAll()");

		layout.resizeAll();
	}
	display(dbg_load,0,"resizing layout(" + width + ',' + height + ') returning');
}



function resize_layout_pane(layout,page_layout,value,pane)
{
	var pane_layout = page_layout[pane];
	if (pane_layout)
	{
		var size =  pane_layout.size;
		if (page_layout.touch_enabled && pane_layout.size_touch > 0)
		{
			size = pane_layout.size_touch;
		}
		display(dbg_layout,1,'resize_layout_pane(' + pane + ') size=' + size);
		layout.sizePane(pane,size);
		display(dbg_layout,2,'back from initial sizePane()');

		element_id = pane_layout.element_id;
		if (value <= pane_layout.limit)
		{
			display(dbg_layout,2,'sizing pane as closed');

			// don't see the button to re-open it if Swiping

			layout.options[pane].slide = true;
			layout.options[pane].spacing_closed = (WITH_SWIPE ? 0 : 6);
			layout.close(pane);
			if (element_id)
			{
				$(element_id).css( 'cursor', 'pointer' );
				$(element_id).on('click',function(event)
				{
					open_pane(pane);
				});
				if (pane_layout.element_is_button)
				{
					$(element_id).button('enable');
				}
			}
		}
		else
		{
			display(dbg_layout,2,'sizing pane as open');
			layout.options[pane].slide = false;
			layout.options[pane].spacing_closed = 6;
			layout.open(pane);
			layout.panes[pane].off('click');
			if (element_id)
			{
				$(element_id).css( 'cursor', 'auto' );
				$(element_id).off('click');
				if (pane_layout.element_is_button)
				{
					$(element_id).button('disable');
				}
			}
		}
		display(dbg_layout,2,'resize_layout_pane(' + pane + ') returning');

	}	// if pane_layout
}




//------------------------------------------------------------------------
// currently untested and unused auto-close, swipe, and autofull
//------------------------------------------------------------------------
// auto-closing windows

function reset_timeouts()
{
	display(dbg_layout,0,"reset_timeouts()");
	update_autofull(false);
	autoclose_count = 0;
	autofull_count = 0;
}

function check_timeouts()
{
	if (autoclose_timeout > 0)
	{
		autoclose_count++;
		if (autoclose_count == autoclose_timeout)
		{
			hide_context_menu();
			hide_layout_panes();
		}
	}
	if (autofull_timeout > 0)
	{
		autofull_count++;
		if (autofull_count == autofull_timeout)
		{
			update_autofull(true);
		}
	}
}


// autofull

function update_autofull(value)
{
	if (autofull != value)
	{
		autofull = value;
		if (current_page == 'renderer')
		{
			on_renderer_autofull_changed();
		}
	}
}


// swiping

function hide_layout_panes()
	// close it if it is showing and has slide option set
{
	return;
		// crashing

	onchange_popup_numeric();

	var layout = $('#' + current_page + '_page').layout();
	hide_layout_pane(layout,'west');
	hide_layout_pane(layout,'north');
	hide_layout_pane(layout,'east');
	hide_layout_pane(layout,'south');
}

function hide_layout_pane(layout,pane)
{
	if (!layout.state[pane].isClosed &&
		layout.options[pane].slide)
	{
		layout.options[pane].closable = true;
		layout.slideClose(pane);
	}
}

function onswipe_page(event,direction)
{
	var layout = $('#' + current_page + '_page').layout();
	onswipe_open_pane(direction,'right',layout,'west');
	onswipe_open_pane(direction,'left',layout,'east');
	onswipe_open_pane(direction,'down',layout,'north');
	onswipe_open_pane(direction,'up',layout,'south');
}

function onswipe_open_pane(direction,cmp_direction,layout,pane)
{
	reset_timeouts();
	if (direction == cmp_direction)
	{
		open_pane(pane);
	}
	else if (layout.options[pane].slide)
	{
		layout.options[pane].closable = true;
		layout.slideClose(pane);
	}
}

function open_pane(pane)
{
	var layout = $('#' + current_page + '_page').layout();
	if (layout.options[pane].slide)
	{
		layout.slideOpen(pane);
		layout.options[pane].closable = false;
	}
	else if (layout.state[pane].isClosed)
	{
		layout.open(pane);
	}
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


//---------------------------------------------
// display utilities
//---------------------------------------------

function rerror(msg)
{
	alert(msg);
}


function display(level,indent,msg)
{
	if (level <= debug_level)
	{
		var stack = (new Error).stack.split("\n");
		var callers = stack[1].split("\/");
		var caller = callers[callers.length-1];
		while (caller.length<20) {caller += ' '; }

		var indent_txt = '';
		while (indent--) { indent_txt += '    '; }
		console.debug(caller + ' ' + indent_txt + msg);
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



function unused_loadCSS(href)
	// Usage:
	// loadCSS("/css/file.css");
{
	var cssLink = $("<link>");
	$("head").append(cssLink); //IE hack: append before setting href

	cssLink.attr({
		rel:  "stylesheet",
		type: "text/css",
		href: href
	});
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



//------------------------------------------------------------------------
// context menu
//------------------------------------------------------------------------

function show_in_explorer(event)
{
	if (current_page == "home" &&
		current_renderer &&
		current_renderer.song_id &&
		current_renderer.song_id != "")
	{
		ele_set_inner_html('renderer_header_left',"Showing current track in explorer...");

		load_page("explorer");
		set_context_explorer(current_renderer.song_id);
	}
}


function unused_show_context_menu(event)
{
	display(0,0,"show_context_menu()");

	var height = window.innerHeight;
	var width = window.innerWidth;
	var w = parseInt($('#context_menu_div').css('width'));
	var h = parseInt($('#context_menu_div').css('height'));

	var x = parseInt((width - w) / 2);
	var y = 100;
	if (event.type=='click')
	{
		x = event.clientX;
		y = event.clientY;
	}

	var fudge = 20;

	if (x + w + fudge > width)
		{ x = width-w-fudge; }
	if (y + h + fudge> height)
		{ y = height-h-fudge; }
	if (x<0)
		{ x=0; }
	if (y<0)
		{ y=0; }

	$('#context_menu_div').css('left',x);
	$('#context_menu_div').css('top',y);

	$('#context_menu_div').css('display','block');

}

function hide_context_menu()
{
	$('#context_menu_div').css('display','none');
}

function do_context_menu(page_id)
{
	display(0,0,"do_context_menu(" + page_id + ")");
	hide_context_menu();

	var context = '';
	if (current_page == 'home')
	{
		if (current_renderer && current_renderer.song_id != '')
		{
			context =  current_renderer.song_id;
		}
	}

	// if (context)
	// {
	// 	load_page(page_id,context);
	// }

}
