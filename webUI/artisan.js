// artisan.js

var dbg_load 	 = 0;
var dbg_layout 	 = 0;
var dbg_popup 	 = 1;
var dbg_loop     = 1;
var dbg_swipe    = 1;

// var restarting = 0;
	// -1 = transient restarting
	//  0 = running normally
	//  1 = check for restart

var WITH_SWIPE = false;
	// If it is true, then a swipe event handler will be added to
	// the element specified in the layout_def that will close or
	// open the relevant pane(s).
var REFRESH_TIME = 1000;

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

	debug_environment();
	// clearStorage();
	// explorer_mode = getCookie('explorer_mode') || 0;

	init_utils();
	init_device_id()
	init_audio();

	WITH_SWIPE = IS_TOUCH;
	// WITH_SWIPE = true;
	// can turn WITH_SWIPE on for testing on laptop

	// STATIC LAYOUT

	if (!is_win)
		$('.linux_only').show();
	if (as_service)
		$('.as_service').show();


	$('.artisan_menu_item').button();

	// LAYOUT TRICKS for IS_TOUCH and more.
	// Set use_small_renderer for everything except
	// the laptop.

	var use_small_renderer = screen.width != 1024 && screen.width != 1920;
		// this must match the @media (max-device-width: 1900px) in fancy.css

	if (IS_TOUCH)
	{
		// we turn off the explorer details pane on both iPad and phone
		// by setting limit to a high number (2000) and use a smaller
		// default size when it is open.

		// THERE IS A CURRENT BUG THAT THE HOME MENU GOES BLANK ON
		// THE PHONE AFTER SELECTING A LARGE (xmas) PLAYLIST

		var explorer_east = layout_defs['explorer']['east'];
		explorer_east['size'] = 160;
		explorer_east['limit'] = 2000;
	}

	// When we use the small renderer, or on the 7" rpi,
	// we also shrink
	// the home menu and explorer tree size too. This
	// code can generally be changed independently of
	// fancy.css, so I *may* want slightly bigger settings
	// on the iPad at some point.

	if (use_small_renderer || screen.width == 1024)
	{
		var home_west = layout_defs['home']['west'];
		home_west['size'] = 140;
		var explorer_west = layout_defs['explorer']['west'];
		explorer_west['size'] = 200;
	}

	create_layout('home');
	create_layout('explorer');
	create_layout('search');

	// NESTED LAYOUTS
	// The explorer and home 'center' divs are themselves laid out here
	// We make the explorer album info pane smaller for IS_TOUCH
	// and the renderer_pane is specifically resized for is_phone_landscape

	$('#explorer_center_div').layout({		// height of album info pane
		applyDemoStyles: true,
		north__resizable : false,
		north__size: IS_TOUCH ? 115 : 100, });

	$('#renderer_pane_div').layout({		// height of renderer pane
		applyDemoStyles: true,
		north__resizable : false,
		north__size : use_small_renderer ? 164 : 255, });

	$('#search_page_div').layout({
		applyDemoStyles: true,
		north__size :  122,
		north__resizable : false,
		north__closable : false });


	// Dynamic Initialization

	init_page_home();
	init_page_explorer();
	init_page_search();

	// Startup

    init_standard_system_commands({
        show_command : '.artisan_menu_library_name',
        countdown_timer : '.artisan_menu_library_name',
        restart_time : 30,
        reboot_time : 60 });

	setTimeout(idle_loop, REFRESH_TIME);
	set_page(default_page);

	display(dbg_load,0,"FINISHED LOADING ARTISAN");
});



$( window ).resize(function()
{
	if (current_page != '')
	{
		display(dbg_layout,0,"$(window) resize(" + current_page + ") called");
		resize_layout(current_page);
	}
});



function idle_loop()
{
	if (!reload_seconds &&
		!in_slider && !in_volume_slider)
	{
		display(dbg_loop,0,"idle_loop(" + current_page + ")");
		idle_count++;

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
			url: '/webUI/update',
			data: data,

			success: function (result)
			{
				// if (restarting)
				// 	clearRestart();

				if (result.update_id)
					update_id = result.update_id;
				if (result.libraries)
					updateLibraries(result.libraries);
				if (result.renderer)
				{
					current_renderer = result.renderer;
					update_renderer_ui();
				}
				setTimeout("idle_loop();", REFRESH_TIME);
			},

			error: function() {
				error("UPDATE ERROR: There was an error calling /webUI/update");
				setTimeout("idle_loop();", REFRESH_TIME);
			},

			timeout: 3000,
		});
	}
	else
	{
		setTimeout("idle_loop();", REFRESH_TIME);
	}
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
			appendMenuButton('library', library.name, library.uuid, 'selectDevice', 'library', library.uuid, library);
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


//---------------------------------------
// system_command (reboot is linux only)
//---------------------------------------
// THIS CODE IS IDENTICAL in all standard services
//
//	var needs_stash = false;
//
//	function system_command(command)
//		// restarting != 0 stops any subsequent gets to the server
//		// which is, as far as I know, only the on_idle() update loop
//	{
//		if (command == 'update_system' && needs_stash)
//		{
//			command = 'update_system_stash';
//		}
//
//		if (confirm(command + '?'))
//		{
//			$('.cover_screen').show();
//			restarting = -1;
//			audio_command('stop');
//			update_renderer_ui();
//			$('.artisan_menu_library_name').html(command);
//
//			setTimeout(function() {
//				$.get(command,function(result) {
//
//					if (result.startsWith("GIT_") &&
//						!result.startsWith("GIT_UPDATE_DONE"))
//					{
//						myAlert(command,result);
//						restarting = 0;
//						$('.artisan_menu_library_name').html(current_library.name);
//						$('.cover_screen').hide();
//
//						if (result.startsWith('GIT_NEEDS_STASH'))
//						{
//							needs_stash = true;
//							$('.update_allowed').html('stash_update');
//						}
//						else
//						{
//							needs_stash = false;
//							$('.update_allowed').html('update');
//						}
//					}
//					else
//					{
//						if (needs_stash)
//						{
//							needs_stash = false;
//							$('.update_allowed').html('update');
//						}
//
//						// show html resullt in a dialog
//						myAlert(command,result);
//						var delay = command == 'reboot' || command == 'update_system' ?
//							30000 :
//							8000;
//						setTimeout(function() { restarting = 1; }, delay);
//					}
//				});
//			},10);
//		}
//	}
//
//
//
//	function clearRestart()
//	{
//		$('.artisan_menu_library_name').html(current_library.name);
//		restarting = 0;
//		location.reload();
//	}






// end of artisan.js
