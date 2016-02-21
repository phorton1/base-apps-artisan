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


var debug_level = 1;

var dbg_load 	 = 1;
var dbg_layout 	 = 1;
var dbg_popup 	 = 1;

var dbg_renderer = 1;
var dbg_explorer = 1;
var dbg_stations = 1;



var default_page = 'renderer';
	// the default page loaded at startup 
var current_page = ''
	// the currently loaded page
	// found in '/webui/page_' + current_page + '.html'
var page_layouts = {};
	// and hash of page layouts

// numbers from preferences
// timeouts have counters and state bit

var explorer_mode = 0; // getCookie('explorer_mode') || 0;

var autoclose_timeout = 0;
var autofull_timeout = 0;

var autoclose_count = 0;
var autofull_count = 0;
var autofull = false;

display(dbg_load,0,"artisan.js loaded");

	
function get_explorer_mode()
{
	return explorer_mode;
}


//-----------------------------------------------
// INITIALIZATION
//-----------------------------------------------
// And main application Page Loading Logic

$(function()
{
	display(dbg_load,0,"$() ready function called");

	// get cookie preferences
	
	explorer_mode = getCookie('explorer_mode') || 0;	
	autoclose_timeout = parseInt(getCookie('autoclose_timeout') || 0);
	autofull_timeout = parseInt(getCookie('autofull_timeout') || 0);
	default_renderer_name = getCookie('default_renderer_name')
	display(dbg_load,0,"default_renderer=" + default_renderer_id + ":'" + default_renderer_name + "'");
	
	// one time static initialization
	
	$('.artisan_menu_table').buttonset();
	$('#context_menu_div').buttonset();
	init_popup_editors();
	
	// loadRecursive($(this));
	// deferred to load_page()

	// load the default page and
	// start the application idle loop

	load_page(default_page);
	idle_loop();	

});


//---------------------------------------------
// idle loop and window timeouts
//---------------------------------------------


function idle_loop()
{
	if (current_page == 'renderer')
	{
		renderer_pane_onidle();
	}
	
	check_timeouts()
	
	idle_timer = window.setTimeout("idle_loop()", 1000);
	
}	// monitor_loop



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



//-------------------------------------------------------
// page loading and sizing
//-------------------------------------------------------



function load_page(page_id,context)
{
	display(dbg_load,0,"load_page(" + page_id + ") context=" + context);
	if (current_page != '')
	{
		$('#' + current_page + '_page').css('display','none');
	}
	
	current_page = page_id;
	$('#' + current_page + '_page').css('display','block');

	if (!page_layouts[current_page].loaded)
	{
		loadRecursive($('#' + current_page + '_page'));

		// set_popup_editors();

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
		
		create_layout();
		page_layouts[current_page].loaded = true;

	}


	var context_fxn = 'set_context_' + page_id;
	if (context && context != '' && window[context_fxn])
	{
		display(0,0,'calling ' + context_fxn + '(' + context + ')');
		window[context_fxn](context);
	}
	
	reset_timeouts();
	resize_layout();

}


// first time == create
	
function create_layout()
{
	var width = window.innerWidth;
	var height = window.innerHeight;
	var page_layout = page_layouts[current_page];
	var params = $.extend({
		applyDemoStyles: true,
		}, page_layout.defaults);

	var width = window.innerWidth;
	var height = window.innerHeight;
	page_layout.width = width;
	page_layout.height = height;
	page_layout.touch_enabled = width<600 || screen.width != 1600 ? true : false;
	
	display(dbg_layout,0,'create_layout(' + current_page + ',' + width + ',' + height + ')');
	
	create_layout_pane(page_layout,params,height,'north');
	create_layout_pane(page_layout,params,width,'west');
	create_layout_pane(page_layout,params,width,'east');
	create_layout_pane(page_layout,params,height,'south');
	
	var layout = $(page_layout.layout_id).layout(params);
	
	$(page_layout.swipe_element).swipe({
		allowPageScroll:"vertical",
		swipe:onswipe_page,
		maxTimeThreshold:1500});
	$(page_layout.swipe_element).on('click',hide_layout_panes);

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
			params[pane + '__spacing_closed'] = pane_hidden?0:6;
			params[pane + '__initClosed'] = pane_hidden;
			params[pane + '__onclick'] = pane_hidden ? reset_timeouts : false;
		}
	}
}


// thereafter == resize


$( window ).resize(function()
	// We hook the global window onresize function and
	// call page specific versions in each page specific js file,
	// which then setup the panes by calling set_pane_slider() as needed.
{
	display(dbg_layout,0,"$(window) resize(" + current_page + ") called");
	resize_layout();
});


	
function resize_layout()
{
	var width = window.innerWidth;
	var height = window.innerHeight;
	display(dbg_layout,0,"resize_layout(" + width + ',' + height + ')');

	var page_layout = page_layouts[current_page];
	if (page_layout &&
		page_layout.loaded
		//&&
		//(page_layout.width != width ||
		// page_layout.height != height)
		)
	{
		page_layout.width = width;
		page_layout.height = height;
		page_layout.touch_enabled = width<600 || screen.width != 1600 ? true : false;
		var layout = $('#' + current_page + '_page').layout();

		display(dbg_layout,0,"resizing layout(" + width + ',' + height + ')');
		
		resize_layout_pane(layout,page_layout,height,'north');
		resize_layout_pane(layout,page_layout,width,'west');
		resize_layout_pane(layout,page_layout,width,'east');
		resize_layout_pane(layout,page_layout,height,'south');
		
		layout.resizeAll();

		if (current_page == 'stations')
		{
			resizeStationTree();
		}
		
		set_popup_editors();
	}
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

		element_id = pane_layout.element_id;
		if (value <= pane_layout.limit)
		{
			layout.options[pane].slide = true;
			layout.options[pane].spacing_closed = 0;
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
	}	// if pane_layout
}


// pane utilities

function hide_layout_panes()
	// close it if it is showing and has slide option set
{
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




//-------------------------------------------
// loadRecursive
//-------------------------------------------
// Recursive loading of html and javascript.
//
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
//    An element may also specify a javascript function that
//    will be executed when that innerHTML has been loaded
//    by specifying a data-onloadattribute.
//
// The recursive load then continues gathering
// all the items with data-load attributes on
// subsequently loaded html chunks and recurses to
// load the entire tree.
//
// Although the onload() functions *could* be presented
// as inline-javascript, or as <script src=> calls
// in the loaded html, for debugging with firebug,
// it is better if all javascript is statically loaded
// with the inital actual html page.
//
// So we take this approach, and in this UI, ALL
// JAVASCRIPT IS STATICALLY INCLUDED IN THE MAIN PAGE
// and dynamic data-onload() functions are used to
// provide "just in time" initialization of freshly
// loaded html pages.
//
// $(function() { loadRecursive($(this)); });
//
//    loadRecursive()*could* be called on the main
//    page of a website (the html file that includes
//    this javascript), in which case it would look
//    at all the elements on the page and recursively
//    load them.  But for artisan, the main page does
//    not contain any data-load attributes ... those
//    are on the pages that are atually loaded into
//    the artisan body.


function loadRecursive(context,level)
{
	if (!level)
	{
		level = 0;
	}
	
	display(dbg_load,level,'loadRecursive(' + context.attr('id') + ')');
	
    context.find('[data-load]').each(function() {
		var url = $(this).attr('data-load');
		var onload_fxn = $(this).attr('data-onload');
		
		$(this).load( url, function(){
			loadRecursive($(this),level+1);
			if (onload_fxn && onload_fxn != '' && window[onload_fxn])
			{
				window[onload_fxn]();
			}
		});
    });
}



//--------------------------------------
// fullscreen mode
//--------------------------------------

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


//--------------------------------------
// DOM utilities
//--------------------------------------

function ele_set_display(id,value)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.style.display = value;
	}
}


function ele_set_inner_html(id,html)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.innerHTML = html;
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



//----------------------------------------------------
// popup editor for stupid android keyboard
//----------------------------------------------------
// it's complicated.
//
// client controls call create_numeric_pref
// to both create their own spinner, and to
// hook it up to a pref, AND to hook it up
// to the popup editor.
//
// onclick calls popup_input_numeric() which
// checks if we're in the car stereo version
// (and which would be better based on an
// android-specific useragent), and if so,
// pops up the hidden div, sets the control value,
// and puts the focus on the control.
//
// We then check for a variety of ending
// conditions .. if the control loses focus,
// it's 'change' method is called.  Or we
// might get a chr(13) if they press 'go'
// on the android keyboard. We also call
// onchange_popup_numeric() if somebody
// calls hide_layout_panes() due to a
// click on a body.
//
// onchange_popup_numeric() then moves
// the value from the control back to
// the underlying spinner, hides the
// popup_input_div, and blurs the control
// so-as to lose focus (and get rid of
// the android keyboard).


function create_numeric_pref(min,med,max,var_name,spinner_id)
{
	display(dbg_layout,0,"create_numeric_pref(" + min + ',' + med + ',' + max + ',' + var_name + ',' + spinner_id + ")");

	$(spinner_id).spinner({
		width:20,
		min:min,
		max:max,
		change: function(event, ui)
		{
			var value = parseInt($(this).spinner('value'));
			window[var_name] = value;
			setCookie(var_name,value,180);
			if (var_name == 'explorer_mode')
			{
				var tree = $('#explorer_tree').fancytree('getTree');
				tree.reload({
					url: "/webui/explorer/dir",
					data: {mode:explorer_mode},
					cache: false,
				}); 
			}
		},
	});
	
	var value = window[var_name];
	$(spinner_id).spinner('value',value);
}





//--------------------------
// private
//--------------------------

var popup_input = false;
var initial_value;


function init_popup_editors()
{
	$('#popup_input_div').buttonset();
	$('#popup_input_numeric').spinner({
		change: onchange_popup_numeric, });
	$('#popup_input_numeric').on('keydown',
		onkeydown_popup_numeric);
}


function set_popup_editors()
	// called from window resize
	// hooks up or turns off the click handler
{
	var page_layout = page_layouts[current_page];
	if (page_layout && page_layout.touch_enabled)
	{
		$('.popup_numeric_pref').on('click',function(event, ui) {
			popup_input_numeric($(this)); });
	}
	else
	{
		$('.popup_numeric_pref').off('click');
	}
}
	


function onkeydown_popup_numeric(event)
{
	display(dbg_popup+1,0,"onkeydown(" + event.keyCode + ")");
	if (event.keyCode == 13)
	{
		onchange_popup_numeric();
	}		
}


function onchange_popup_numeric(event,ui)
{
	display(dbg_popup,0,"onchange_popup_numeric(" + popup_input + ")");
	
	if (popup_input)
	{
		var val = $('#popup_input_numeric').spinner('value');
		display(dbg_popup,1,"val=" + val);

		popup_input.spinner('value',val);
		$('#popup_input_div').css('display','none');
		
		popup_input = false;
		$('#popup_input_numeric').on('blur');

	}
}



function popup_input_numeric(input)
{
	var page_layout = page_layouts[current_page];
	if (page_layout && page_layout.touch_enabled)
	{
		autoclose_count = -1;
			// turn off the autoclose counter
			// try to keep the prefs window open
		
		display(dbg_popup,0,"popup_input_numeric(" + input.attr('title') + ")");
	
		$('#popup_input_div').css('display','block');
		$('#popup_input_title').text(input.attr('title'));
		
		var val = input.spinner('value');
		var min = input.spinner('option','min');
		var max = input.spinner('option','max');
		display(dbg_popup,1,"val="+val + " min="+min + " max="+max);
		initial_value = val;
		
		$('#popup_input_numeric').spinner('value',val);
		$('#popup_input_numeric').spinner('option','min',min);
		$('#popup_input_numeric').spinner('option','max',max);
	
		$('#popup_input_numeric').focus();
		popup_input = input;
	}
	
}



function cancel_popup_input()
{
	if (popup_input)
	{
		$('#popup_input_numeric').spinner('value',initial_value);
		onchange_popup_numeric();
	}
}


//-------------------------------------
// context menu
//-------------------------------------

function show_context_menu(event)
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
	if (current_page == 'renderer')
	{
		if (current_renderer && current_renderer.song_id != '')
		{
			context =  current_renderer.song_id;
		}
	}

	if (context)
	{
		load_page(page_id,context);
	}
		
}

                

