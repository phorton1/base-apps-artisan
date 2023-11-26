// artisan.js
//
// We will need to modify the layout based on the device.
// That can be inferred from screen.width and height and
// window.innerHeight and innerWidth.  Another clue is
// navigator.userAgent (containing 'Mobile' or 'Android'
// is a good clue)

jQuery.ajaxSetup({async:false});
	// to be used from utils.js

var dbg_load 	 = 0;
var dbg_layout 	 = 0;
var dbg_popup 	 = 1;
var dbg_loop     = 1;

var current_renderer = false;
var current_library = false;

var WITH_SWIPE = false;
	// this is currently set to false.
	// If it is true, then no handles will show for closed windows,
	// and a swipe event handler will be added to the element specified
	// in the layout_def that will close or open the relevant pane.
var REFRESH_TIME = 600;

var default_page = 'home';
var current_page = ''
var layout_defs = {};


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

	// explorer_mode = getCookie('explorer_mode') || 0;
	// autoclose_timeout = parseInt(getCookie('autoclose_timeout') || 0);
	// autofull_timeout = parseInt(getCookie('autofull_timeout') || 0);

	init_audio();

	create_layout('home');
	create_layout('explorer');

	init_page_home();
	init_page_explorer();

	$('.artisan_menu_table').buttonset();
	$('#context_menu_div').buttonset();

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
// Layout
//========================================================


function create_layout(page_id)
{
	var width = window.innerWidth;
	var height = window.innerHeight;
	display(dbg_layout,0,'create_layout(' + page_id + ',' + width + ',' + height + ')');

	var layout_def = layout_defs[page_id];
	var params = layout_def.default_params;

	add_pane_params(layout_def,params,'north');
	add_pane_params(layout_def,params,'west');
	add_pane_params(layout_def,params,'east');
	add_pane_params(layout_def,params,'south');

	var layout = $(layout_def.layout_id).layout(params);

	if (WITH_SWIPE)
	{
		$(layout_def.swipe_element).swipe({
			allowPageScroll:"vertical",
			swipe:onswipe_page,
			maxTimeThreshold:1500});
		$(layout_def.swipe_element).on('click',hide_layout_panes);
	}
}


function add_pane_params(layout_def,params,pane)
{
	var pane_def = layout_def[pane];
	if (pane_def)
	{
		var size =  pane_def.size;
		var resizable = pane_def.resizable || false;
		display(dbg_layout,1,'add_pane_params(' + pane + ') size=' + size + " resizable=" + resizable);
		params[pane + '__size'] = size;
		params[pane + '__resizable'] = resizable;

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

	var layout_def = layout_defs[page_id];

	var layout = $('#' + page_id + '_page').layout();

	resize_layout_pane(layout,layout_def,height,'north');
	resize_layout_pane(layout,layout_def,width,'west');
	resize_layout_pane(layout,layout_def,width,'east');
	resize_layout_pane(layout,layout_def,height,'south');
	layout.resizeAll();
}


function resize_layout_pane(layout,layout_def,value,pane)
{
	var pane_def = layout_def[pane];
	if (pane_def)
	{
		// var size =  pane_def.size;
		// layout.sizePane(pane,size);

		var state = layout.state;
		if (pane_def.limit && state && state[pane])
		{
			var is_closed = state[pane].isClosed ? true : false;
			display(dbg_layout,2,'pane(' + pane + ') is_closed=' + is_closed + ' value=' + value + ' limit=' + pane_def.limit);

			if (!is_closed && value <= pane_def.limit)
			{
				display(dbg_layout,2,'sizing pane ' + pane + ' as closed');

				layout.options[pane].slide = true;
				layout.options[pane].spacing_closed = 6;	// (WITH_SWIPE ? 0 : 6);
				layout.close(pane);

				// element_id = pane_def.element_id;
				// if (element_id)
				// {
				// 	$(element_id).css( 'cursor', 'pointer' );
				// 	$(element_id).on('click',function(event)
				// 	{
				// 		open_pane(pane);
				// 	});
				// 	if (pane_def.element_is_button)
				// 	{
				// 		$(element_id).button('enable');
				// 	}
				// }
			}
			else if (is_closed && value > pane_def.limit)
			{
				display(dbg_layout,2,'sizing pane ' + pane + ' as open');
				layout.options[pane].slide = false;
				layout.options[pane].spacing_closed = 6;
				layout.open(pane);
				// layout.panes[pane].off('click');
				// if (element_id)
				// {
				// 	$(element_id).css( 'cursor', 'auto' );
				// 	$(element_id).off('click');
				// 	if (pane_def.element_is_button)
				// 	{
				// 		$(element_id).button('disable');
				// 	}
				// }
			}
		}
	}
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



//---------------------------------------------
// unused utilities
//---------------------------------------------


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
