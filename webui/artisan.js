// artisan.js

var dbg_load 	 = 0;
var dbg_layout 	 = 0;
var dbg_popup 	 = 1;
var dbg_loop     = 1;
var dbg_swipe    = 1;


var WITH_SWIPE = false;
	// If it is true, then a swipe event handler will be added to
	// the element specified in the layout_def that will close or
	// open the relevant pane(s).
var REFRESH_TIME = 600;

var default_page = 'home';
var current_page = ''
var layout_defs = {};
var explorer_mode = 0;
var idle_timer = null;
var idle_count = 0;
var update_id = 1;


display(dbg_load,0,"artisan.js loaded");


function debug_environment()
{
	debug_remote(0,0,
		"orientation(" + screen.orientation.type + ")" +
		"screen(" + screen.width + "," + screen.height + ") " +
		"iwindow(" + window.innerWidth + "," + window.innerHeight + ") " +
		"owindow(" + window.outerWidth + "," + window.outerHeight + ") " +
		"body(" + $('body').width() + "," + $('body').height() + ")");

	debug_remote(0,0,"ratio(" + window.devicePixelRatio + ")");

	debug_remote(0,0,"navigator " +
		"cookies(" + navigator.cookieEnabled + ") " +
		"platform(" + navigator.platform + ") " +
		"appVersion(" + navigator.appVersion + ") " +
		"ua(" + navigator.userAgent + ") ");

	var touchPoints = navigator.maxTouchPoints;
	if (touchPoints == undefined)
		touchPoints = 'undefined';

	debug_remote(0,0,"touchPoints = " + touchPoints);
}



//========================================================
// Main
//========================================================

$(function()
{
	display(dbg_load,0,"START LOADING ARTISAN");

	WITH_SWIPE =
		( 'ontouchstart' in window ) ||
	    ( navigator.maxTouchPoints > 0 ) ||
	    ( navigator.msMaxTouchPoints > 0 );

	debug_environment();

	init_utils();
	init_device_id()
	init_audio();

	WITH_SWIPE = true;
		// turn WITH_SWIPE on for testing on laptop

	// explorer_mode = getCookie('explorer_mode') || 0;



	// STATIC LAYOUT

	$('.artisan_menu_item').button();

	create_layout('home');
	create_layout('explorer');

	// NESTED LAYOUTS
	// The explorer and home 'center' divs are themselves laid out here

	$('#explorer_center_div').layout({
		applyDemoStyles: true,
		north__size:140, });

	$('#renderer_pane_div').layout({
		applyDemoStyles: true,
		north__size:255, });

	// Dynamic Initialization

	init_page_home();
	init_page_explorer();

	// Startup

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

	if (!in_slider) // &&
		// !in_playlist_slider &&
		// !in_playlist_spinner)
	{
		var data = { update_id: update_id };
		if (current_renderer.uuid == html_renderer.uuid)
		{
			audio_command('update');
			update_renderer_ui();
		}
		else
		{
			data.renderer_uuid = current_renderer.uuid;
		}

		$.ajax({
			async: true,
			url: '/webui/update',
			data: data,

			success: function (result)
			{
				if (result.update_id)
					update_id = result.update_id;
				if (result.libraries)
					updateLibraries(result.libraries);
				if (result.renderer)
				{
					current_renderer = result.renderer;
					update_renderer_ui();
				}
			},

			error: function() {
				error("UPDATE ERROR: There was an error calling /webui/update");
			},

			timeout: 3000,
		});
	}

	setTimeout("idle_loop();", REFRESH_TIME);
}



function updateLibraries(libraries)
	// called if 'update' returns libraries, which is
	// in turn predicated on Perl's update_id changing,
	// gets a new new list of active Libraries and adds
	// or removes Library buttons as needed.
{
	var set_current = false;
	var any_changed = false;
	for (var library of libraries)
	{
		display(0,0,"library=" + library.name + "(" + library.uuid + ")");
		var use_id = 'library_' + library.uuid;
		var exists = document.getElementById(use_id);
		if (!exists && library.online != '')
		{
			any_changed = true;
			appendMenuButton('library', library.name, library.uuid, 'selectDevice', 'library', library.uuid);
		}
		else if (exists && library.online == '')
		{
			any_changed = true;
			if (library.uuid == current_library.uuid)
				set_current = true;
			// had to add a wrapper _div to get delete to work as an atomic function
			$('#' + use_id + '_div').remove();
		}
	}

	// if the current library goes offline,
	// select another one (the 0th one)

	if (any_changed)
	{
		$('#library_menu').buttonset('refresh');
		if (set_current)
			selectDefaultDevice('library');
	}
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
	// reset_timeouts();

	resize_layout(current_page);

	// If the default page *were* 'explorer', then you
	// switch to 'home', the accordian was not resized.
	// We have to call resizeAll() twice, once in resize_layout(),
	// once here to force resizeAll() to call the method
	// $.layout.callbacks.resizePaneAccordions,
	// even though it is set as the default west__onresize hook.

	var layout = $('#' + page_id + '_page').layout();
	layout.resizeAll();

	display(dbg_load,0,"set_page(" + page_id + ") returning");
}



//========================================================
// Layout
//========================================================

function create_layout(page_id)
{
	display(dbg_layout,0,'create_layout(' + page_id + ')');

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
			// these options gotten directly from reading jquery.touchSwipe.js,
			// which is apparently an old version and does not match google 'jquery swipe options'

			allowPageScroll:"vertical",
			swipe:onswipe,
			maxTimeThreshold:1500});
		// $(layout_def.swipe_element).on('click',hide_layout_panes);
	}
}


function add_pane_params(layout_def,params,pane)
{
	var pane_def = layout_def[pane];
	if (pane_def)
	{
		var size =  pane_def.size;
		var resizable = pane_def.resizable;
		display(dbg_layout,1,'add_pane_params(' + pane + ') size=' + size + " resizable=" + resizable);
		params[pane + '__size'] = size;
		if (resizable != undefined)
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
				layout.options[pane].spacing_closed = 6;
					// was: WITH_SWIPE ? 0 : 6;
					// but I prefer a reminder that there is a pane that can be opened.
					// as it is not always the case
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



//-------------------------------------------
// Swiping
//-------------------------------------------
// Generally speaking, we set the swipe handler on the 'center' pane,
// and allow it to open or close the other four panes.  Where the
// swipe begins, and it's direction determine the possible actions.
// For example, with left-right for horizontal swipes.
//
//      +--------+--------+---------+
//      |        |        |         |
//      |        |        |         |
//      |        |        |         |
//      |        |        |         |
//      |        |        |         |
//      +--------+--------+---------+
//
//   Starting
//   Region       Direction    	Function
//     left         left       	close west pane
//     center       left		close west pane
//     right        left		open east pane
//
//     right        right       close east pane
//     center       right	   	close east pane
//     left         right	   	open west pane

function onswipe(event, direction, distance, duration, fingerCount, fingerData)
{
	var layout = $('#' + current_page + '_page').layout();
	var state = layout.center.state;
	var pane = '';
	var action = '';

	// these vars are just for debugging

	var start_x = fingerData[0].start.x;
	var start_y = fingerData[0].start.y;
	var left = state.offsetLeft;
	var top = state.offsetTop;
	var width = state.innerWidth;
	var height = state.innerHeight;
	display(dbg_swipe,0,
		"onswipe(" + direction + ") " +
		"start(" + start_x + "," + start_y + ") " +
		"center_ltwh(" + left + "," + top + "," + width + "," + height + ")");


	if (direction == 'left' || direction == 'right')
	{
		var start = fingerData[0].start.x;
		var rel_pos = start - state.offsetLeft;
		var third_size = state.innerWidth / 3;
		var region = Math.floor(rel_pos / third_size);

		if (direction == 'left')
		{
			if (region == 2)
			{
				pane = 'east';
				action = 'open';
			}
			else
			{
				pane = 'west';
				action = 'close';
			}
		}

		// direction == 'right'

		else if (region == 0)
		{
			pane = 'west';
			action = 'open';
		}
		else
		{
			pane = 'east';
			action = 'close';
		}
	}

	else if (direction == 'up' || direction == 'down')
	{
		var start = fingerData[0].start.y;
		var rel_pos = start - state.offsetTop;
		var third_size = state.innerHeight / 3;
		var region = Math.floor(rel_pos / third_size);

		if (direction == 'up')
		{
			if (region == 2)
			{
				pane = 'south';
				action = 'open';
			}
			else
			{
				pane = 'north';
				action = 'close';
			}
		}

		// direction == 'down'

		else if (region == 0)
		{
			pane = 'north';
			action = 'open';
		}
		else
		{
			pane = 'south';
			action = 'close';
		}
	}

	display(dbg_swipe,1,"swipe pane(" + pane + ") action(" + action + ")");

	// for now they are pure 'open' or 'closes', but there is
	// also the option of sliding OVER the center pane ...

	if (pane && layout[pane])
	{
		if (action == 'open')
		{
			layout.options[pane].slide = false;
			layout.options[pane].spacing_closed = 6;
			layout.open(pane);
		}
		else // action == 'close'
		{
			layout.options[pane].slide = true;
			layout.options[pane].spacing_closed = 6;
			layout.close(pane);
		}
	}
}


// end of artisan.js
