//--------------------------------------------------
// home.js
//--------------------------------------------------

var dbg_home = 0;


layout_defs['home'] = {
	layout_id: '#home_page',
	swipe_element: '#renderer_pane_div',

	default_params: {
		applyDemoStyles: true,
		west__onresize:  $.layout.callbacks.resizePaneAccordions,
	},

	north: {
		size:40,
		limit:400,
		resizable: false,
		element_id:'#renderer_page_header_right',
	},
	west: {
		size:245,
		limit:600,
		element_id:'#renderer_page_header_left',
	},
};



function init_page_home()
{
	display(dbg_home,0,"init_page_home()");

	load_device_list(DEVICE_TYPE_RENDERER);
	load_device_list(DEVICE_TYPE_LIBRARY);

	init_renderer_pane();

	$("#home_menu").accordion({
		icons: false,
		heightStyle: "fill",
		classes: {  "ui-accordion": "home_accordian" }});

	$('#prefs_div').buttonset();

	create_numeric_pref(0,10,60,
		'pref_error_mode',
		'#pref_explorer_mode');

	init_home_tracklists();

	display(dbg_home,0,"init_page_home() done");
}



//-----------------------------------
// Device Lists
//-----------------------------------

function load_device_list(type)
{
	$.get('/webui/getDevices/' + type,
		function(result)
	{
		// add the local html_renderer

		if (type == DEVICE_TYPE_RENDERER)
			result.unshift({
				name: html_renderer.name,
				uuid: html_renderer.uuid,
				type: DEVICE_TYPE_RENDERER });

		buildDeviceMenu(result,type);
		selectDefaultDevice(type);
	});
}


function selectDefaultDevice(type)
{
	var last_cookie = 'last_' + type;
	var last_uuid = getCookie(last_cookie);
	var found = document.getElementById(type + '_' + last_uuid );
	if (!found)
	{
		var buttons = document.getElementsByName(type + '_button');
		found = buttons[0];
	}

	// this should never fail as there should ALWAYS be at least
	// the Perl localLibrary and localRenderer (and HTML Renderer).
	// We have to get the uuid back from the element's id

	var found_uuid = found.id.replace(type + '_','');
	selectDevice(type,found_uuid);
}


function selectDevice(type,uuid)
{
	if (type == DEVICE_TYPE_RENDERER && uuid.startsWith('html_renderer'))
	{
		onSelectDevice(type,uuid,html_renderer);
		return;
	}
	$.get('/webui/getDevice/' + type + "-" + uuid,
		function(result)
	{
		if (result.error)
			rerror('Error in getDevice(' + type + ',' + uuid + '): ' + result.error);
		else
			onSelectDevice(type,uuid,result);
	});
}


function onSelectDevice(type,uuid,result)
{
	var cur_name = 'current_' + type;
	var cur = window[cur_name];
	if (cur && cur.uuid != uuid)
	{
		$( "#" + type + '_' + cur.uuid).prop('checked', false).button('refresh');
	}

	window[cur_name] = result;
	$('#' + type +  '_' + uuid).prop('checked', true).button('refresh');
	setCookie('last_'+type,uuid,180);

	if (type == DEVICE_TYPE_LIBRARY)
	{
		$('.artisan_menu_library_name').html(result.name);
		init_playlists();
	}

	// current_page indicates the app has really started

	if (current_page)
	{
		if (type == DEVICE_TYPE_RENDERER)
			update_renderer_ui();
		if (type == DEVICE_TYPE_LIBRARY)
			update_explorer();
	}
}



//----------------------------------
// Playlists
//----------------------------------

function init_playlists()
	// only works if both current_library and current_renderer are set
{
	if (!current_library || !current_renderer)
		return;
	$.get(library_url() + '/get_playlists',function(result) {
		if (result.error)
		{
			rerror('Error in init_playlists(' + library_uuid + '): ' + result.error);
		}
		else
		{
			buildPlaylistMenu(result);
		}
	});
}


function setPlaylist(uuid,id)
{
	display(dbg_home,0,"setPlaylist("+name+")");
	renderer_command('set_playlist',{
		library_uuid:uuid,
		id: id});
}



//*********************************************************
// Home Tracklists
//*********************************************************
// For each tracklist we need to keep track of what it
// contains, versus what it should contain.
// Queues are specific to Renderers.
// Playlists are also specific by library_uuid and id.
// Both are updated when their version chages.

var dbg_tl = 0;


var queue_tracklist;
var playlist_tracklist;

var tracklist_renderer_uuid = '';
	// both tracklists are invalidated when the renderer changes
var tracklist_queue_version = -1;
var tracklist_playlist_uuid = '';
var tracklist_playlist_id = '';
var tracklist_playlist_version = -1;


function init_home_tracklists()
{
	// QUEUE TRACKLIST

	display(dbg_explorer,1,"initializizing queue tracklist");

	$("#queue_tracklist").fancytree({
		nodata:			false,
		scrollParent: 	$('#home_tracklist_div'),
		selectMode:		2,
		extensions: 	["table","multi"],
		table: 			{},
		source: 		function() { return []; },
		renderColumns: 	function(event, data)  { renderTracklistNode(event,data,1); },
		dblclick:		function(event, data)		// move to the given track
		{
			var node = data.node;
			var rec = node.data;
			queue_tracklist.selectAll(false);

			// we must let the html renderer do this command
			// so that it gets the track from the result

			if (current_renderer.uuid.startsWith('html_renderer'))
			{
				audio_command('play_track',{pl_idx:rec.pl_idx});
			}
			else
			{
				var params = JSON.stringify({
					pl_idx: rec.pl_idx,
					renderer_uuid: current_renderer.uuid });
				$.post('/webui/queue/play_track',params,function(result)
				{
					if (result.error)
					{
						rerror(result.error);
					}
				});
			}
		},
	});

	queue_tracklist = $("#queue_tracklist").fancytree("getTree");
	queue_tracklist.my_load_counter = 0;


	// PLAYLIST_TRACKLIZT

	display(dbg_explorer,1,"initializizing playlist tracklist");

	$("#playlist_tracklist").fancytree({
		nodata:			false,
		scrollParent: 	$('#home_tracklist_div'),
		selectMode:		2,
		extensions: 	["table","multi"],
		table: 			{},
		source: 		function() { return []; },
		renderColumns: 	function(event, data)  { renderTracklistNode(event,data,0); },
		dblclick:		function(event, data)		// move to the given track
		{
			var node = data.node;
			var rec = node.data;
			playlist_tracklist.selectAll(false);
			renderer_command('playlist_song',{index: rec.pl_idx});
		},
	});

	playlist_tracklist = $("#playlist_tracklist").fancytree("getTree");
	playlist_tracklist.my_load_counter = 0;
}


function renderTracklistNode(event,data,pl_offset)
	// pl_offset is zero for playlists, which use 1 based indexes,
	// and is one for the queue which uses 0 based indexes, so
	// that we show the tracks starting at '1'
{
	var node = data.node;
	var rec = node.data;
	var $tdList = $(node.tr).find(">td");
	var show_idx = rec.pl_idx + pl_offset;

	// For the life of me, I could not figure out WHY
	// this tracklist has problems with scrolling because
	// the node.span.offsetHeight and Width are 0 ...
	// One would think that just adding the node would
	// be sufficient.
	//
	//It's not a visibility issue ... it's visible.
	//
	// 		$tdList.eq(0).css('height', '100px');
	// 		$tdList.eq(0).css('width', '100px');
	//
	// or any variations of trying to set the height
	// in CSS did not work.
	//
	// But adding an icon makes it have a small
	// width and height and so it works ...


	// Ad-hoc (bogus) solution - set the 'title' to pl_idx
	// and deal with fancyTree's compulsion to take over td0.
	// We add a style .. but that's not good enough cuz
	// the inner things are in spans

	$tdList.eq(0)						.addClass('home_rownum');

	// $tdList.eq(0).html(show_idx)		.addClass('home_rownum');
	$tdList.eq(1).html(rec.TITLE)		.addClass('tracklist_title');
	$tdList.eq(2).text(rec.tracknum)	.addClass('home_tracknum');
	$tdList.eq(3).text(rec.album_title)	.addClass('tracklist_album');
	$tdList.eq(4).text(rec.genre)		.addClass('tracklist_genre');
	$tdList.eq(5).text(rec.year_str)	.addClass('tracklist_year');
}



//-------------------------------------------------
// update_home_tracklists()
//-------------------------------------------------

function invalidate_tracklists()
	// when tracklist_renderer_uuid changes
{
	tracklist_queue_version = -1;
	tracklist_playlist_uuid = '';
	tracklist_playlist_id = '';
	tracklist_playlist_version = -1;
	if (queue_tracklist)
		queue_tracklist.clear();
	if (playlist_tracklist)
		playlist_tracklist.clear();

}

function update_home_tracklists()
	// this method responible for reloading the tracklist(s)
	// 		when versions or other info changes.
	// it is also the logical place to update the
	//      highlight for the currently playing track
	//      for which will initially use 'selected' status
	// later, selection versus current playing will be
	//      different and we will need to allow the user
	//      to scroll to different positions, perhaps
	//      with an activity timer.
	// it is still complicated due to incremental loading ..
	//      the current playing track may not yet be in
	//      the tree.  Therefore there are yet more
	//      variables added to the tree,
	// my_show_index  = -1 if nothing to show
	// my_index_shown = -1 when needs showing
{
	// redo everything if renderer changes

	if (tracklist_renderer_uuid != current_renderer.uuid)
	{
		display(dbg_tl,0,"tracklist_renderer_uuid changed from " +
			tracklist_renderer_uuid + " to " + current_renderer.uuid);
		tracklist_renderer_uuid = current_renderer.uuid;
		invalidate_tracklists();
	}

	// UPDATE QUEUE TRACKLIST

	var queue = current_renderer.queue;
	if (!queue) return;		// not ready yet
	var queue_version = queue.version;
	if (tracklist_queue_version != queue_version)
	{
		display(dbg_tl,0,"queue_version changed from " + tracklist_queue_version + " to " + queue_version);
		tracklist_queue_version = queue_version;
		queue_tracklist.clear();

		if (queue.num_tracks > 0)
		{
			var ajax_params = {
				async: true,
				method: 'POST',
				url: "/webui/queue/get_tracks", };
			var params = {
				field:'tracks',
				renderer_uuid:current_renderer.uuid, };

			loadHomeTracklist(
				queue_tracklist,
				queue.num_tracks,
				ajax_params,
				params);
		}
	}


	// UPDATE PLAYLIST TRACKLIST

	var playlist_uuid = '';
	var playlist_id = '';
	var playlist_version = -1;
	var playlist = current_renderer.playlist;
	if (playlist)
	{
		playlist_uiud = playlist.uuid;
		playlist_id = playlist.id;
		playlist_version = playlist.data_version;
	}


	if (tracklist_playlist_uuid != playlist_uuid ||
		tracklist_playlist_id != playlist_id ||
		tracklist_playlist_version != playlist_version)
	{
		display(dbg_tl,0,"playlist changed from " +
			tracklist_playlist_uuid + ":" + tracklist_playlist_id + ":" + tracklist_playlist_version + " to " +
			playlist_uuid+":"+playlist_id+":"+playlist_version);

		tracklist_playlist_uuid = playlist_uuid;
		tracklist_playlist_id = playlist_id;
		tracklist_playlist_version = playlist_version;
		playlist_tracklist.clear();

		if (playlist && playlist.num_tracks > 0)
		{
			var ajax_params = {
				async: true,
				method: 'GET',
				url: "/webui/library/" + playlist.uuid + "/get_playlist_tracks_sorted", };
			var params = {
				id:playlist_id, };

			loadHomeTracklist(
				playlist_tracklist,
				playlist.num_tracks,
				ajax_params,
				params);
		}
	}

	// HIGHLIGHT CURRENT TRACK
	// update my_show_index for both trees as needed
	// try to show it in the tree that is visible

	if (queue.num_tracks)
		queue_tracklist.my_show_index = queue.track_index;
	if (playlist && playlist.num_tracks)
		playlist_tracklist.my_show_index = playlist.track_index - 1;

	var show_tree = current_renderer.playing == RENDERER_PLAY_PLAYLIST ?
		playlist_tracklist : queue_tracklist;

	var show = show_tree.my_show_index;
	var shown = show_tree.my_index_shown;
	if (shown != show && show < show_tree.count())
	{
		var children = show_tree.rootNode.children;
		if (shown != -1)
			children[shown].removeClass('current_track');	// setSelected(false)
		var show_node = children[show];
		show_node.addClass('current_track');	// setSelected(true);

		// fancytree scrollIntoView() functions did not work ext-table.
		// this was actually the 'addNode not giving any width or height' bug
		// I'm keeping the (false) case JIC I want different alignment, etc

		if (true)
		{
			show_node.scrollIntoView(false);
		}
		else
		{
			var container = show_tree.$container;
			var table = container[0];
			scrollIntoView(show_node.tr,table.parentElement);
		}
		show_tree.my_index_shown = show;
	}
}



function scrollIntoView(element, container)
	// found this function at
	// https://stackoverflow.com/questions/1805808/how-do-i-scroll-a-row-of-a-table-into-view-element-scrollintoview-using-jquery
{
	var containerTop = $(container).scrollTop();
	var containerBottom = containerTop + $(container).height();
	var elemTop = element.offsetTop;
	var elemBottom = elemTop + $(element).height();
	if (elemTop < containerTop)
	{
		$(container).scrollTop(elemTop);
	}
	else if (elemBottom > containerBottom)
	{
		$(container).scrollTop(elemBottom - $(container).height());
	}
}



//--------------------------------------
// incremental tracklist loading
//--------------------------------------
// very similar code in explorer.js
// one key factor is to stop any previous loads if a new load starts
// 	   which is managed via tree.my_load_counter changing
//     and passing it via parameter to the async loop.

function loadHomeTracklist(tree,num_elements,ajax_params,params)
{
	display(dbg_tl,0,"loadHomeTracklist(" + ajax_params.method + ") num(" + num_elements + ") " + ajax_params.url);
	tree.my_load_counter++;		// stop any other loads on this tree
	tree.my_num_loaded = 0;		// initialize for new load
	tree.my_num_elements = num_elements;
	tree.my_show_index = -1;
	tree.my_index_shown = -1;
	params.source = 'loadTracks';

	loadHomeTracks(tree,tree.my_load_counter,ajax_params,params);
	display(dbg_tl,0,"returning from loadHomeTracklist");
}


function loadHomeTracks(tree,counter,ajax_params,params)
{
	// if the counter has changed, the old load is now invalid

	if (counter != tree.my_load_counter)
		return;

	// if we have loaded all the elements, we are done

	if (tree.my_num_loaded >= tree.my_num_elements)
		return;

	params.start = tree.my_num_loaded;
	params.count = LOAD_PER_REQUEST;
	display(dbg_tl,1,"loadHomeTracks(" + params.start + "," + params.count + ")");

	if (ajax_params.method == 'POST')
	{
		ajax_params.data = JSON.stringify(params);
	}
	else
	{
		ajax_params.data = params;
	}

	ajax_params.success =  function (result)
	{
		if (result.error)
		{
			rerror(result.error);
		}
		else

		// currently both results are flat lists of tracks
		// which should be changed to tracks => []
		// for more iot-like approach to handling json results

		var pass = params.field ? result[params.field] : result;
		if (onHomeLoadTracks(tree,counter,pass))
		{
			tree.my_num_loaded += pass.length;
			loadHomeTracks(tree,counter,ajax_params,params);
		}
	};

	$.ajax(ajax_params);
	display(dbg_tl,1,"returning from loadHomeTracks(" + params.start + "," + params.count + ")");
}



function addHomeTrackNode(tree,counter,rec)
{
	if (counter == tree.my_load_counter)
	{
		rec.TITLE = rec.title;

		// bogus solution - let fancytree have td0 and the 'title',
		// which we assign to our row number (pl_idx)

		rec.title = rec.pl_idx;
		rec.icon = false;
			// needed for bogus solution

		// otherwise, the following did not help or make any difference
		// to get the node to think it has a height ...
		//
		// 		rec.folder = false;
		// 		delete rec.title;
		// 		delete rec.type;
		// 		rec.key = rec.id;
		// 		rec.icon = '/webui/icons/error_0.png',
		//				 this was the only thing that effing worked

		display(dbg_tl+1,2,"addHomeTrackNode(" + rec.TITLE + ")");
		var	parent = tree.getRootNode();
		var node = parent.addNode(rec);

		// Nor these:
		//
		//		parent.addChildren(rec);
		// 		var $tdList = $(node.tr).find(">td");
		// 		$tdList.eq(0).css('height', '100px');
		// 		$tdList.eq(0).css('width', '100px');
		//
		// I think I might have been better off just using a table ..
	}
}


function onHomeLoadTracks(tree,counter,result)
{
	display(dbg_tl,1,"onHomeLoadTracks(" + result.length + ")");
	if (result.error)
	{
		rerror(result.error);
		return false;
	}

	for (var i=0; counter==tree.my_load_counter && i<result.length; i++)
	{
		addHomeTrackNode(tree,counter,result[i]);
	}

	return true;
}


// end of home.js
