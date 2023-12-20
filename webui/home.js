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
	if (type == DEVICE_TYPE_RENDERER && uuid == 'html_renderer')
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


function invalidate_tracklists()
	// when tracklist_renderer_uuid changes
{
	tracklist_queue_version = -1;
	tracklist_playlist_uuid = '';
	tracklist_playlist_id = '';
	tracklist_playlist_version = -1;
}



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
		dblclick:		function(event, data)		// move to the given track
		{
			var node = data.node;
			var rec = node.data;
			node.setSelected(true);
		},
		renderColumns: 	function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			var $tdList = $(node.tr).find(">td");

			$tdList.eq(0).text(rec.tracknum)	.addClass('tracklist_tracknum');
			$tdList.eq(1).html(rec.TITLE)		.addClass('tracklist_title');
			$tdList.eq(2).text(rec.album_title)	.addClass('tracklist_album');
			$tdList.eq(3).text(rec.genre)		.addClass('tracklist_genre');
			$tdList.eq(4).text(rec.year_str)	.addClass('tracklist_year');
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
		dblclick:		function(event, data)		// move to the given track
		{
			var node = data.node;
			var rec = node.data;
			node.setSelected(true);
		},
		renderColumns: 	function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			var $tdList = $(node.tr).find(">td");

			$tdList.eq(0).text(rec.tracknum)	.addClass('tracklist_tracknum');
			$tdList.eq(1).html(rec.TITLE)		.addClass('tracklist_title');
			$tdList.eq(2).text(rec.album_title)	.addClass('tracklist_album');
			$tdList.eq(3).text(rec.genre)		.addClass('tracklist_genre');
			$tdList.eq(4).text(rec.year_str)	.addClass('tracklist_year');
		},
	});

	playlist_tracklist = $("#playlist_tracklist").fancytree("getTree");
	playlist_tracklist.my_load_counter = 0;
}




function update_home_tracklists()
{
	var queue = current_renderer.queue;
	if (!queue) return;		// not ready yet

	// redo everything if renderer changes

	if (tracklist_renderer_uuid != current_renderer.uuid)
	{
		display(dbg_tl,0,"tracklist_renderer_uuid changed");
		tracklist_renderer_uuid = current_renderer.uuid;
		invalidate_tracklists();
	}

	// get the state from current_renderer

	var queue_version = queue.version;

	var playlist_uuid = '';
	var playlist_id = '';
	var playlist_version = -1;
	var playlist = current_renderer.playlist;

	if (playlist)
	{
		playlist_uiud = playlist.uuid;
		playlist_id = playlist.id;
		playlist_version = playlist.version;
	}

	// QUEUE TRACKLIST

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
				renderer_uuid:current_renderer.uuid, };

			loadHomeTracklist(
				queue_tracklist,
				queue.num_tracks,
				ajax_params,
				params);
		}
	}

	// PLAYLIST TRACKLIST

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
				url: "/webui/library/" + playlist_uuid + "/get_playlist_tracks_sorted", };
			var params = {
				id:playlist_id, };

			loadHomeTracklist(
				playlist_tracklist,
				playlist.num_tracks,
				ajax_params,
				params);
		}
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
	display(dbg_tl,0,"loadHomeTracklist(" + params.method + ") num(" + num_elements + ") " + params.url);
	tree.my_load_counter++;		// stop any other loads on this tree
	tree.my_num_loaded = 0;		// initialize for new load
	tree.my_num_elements = num_elements;

	params.source = 'loadTracks';

	loadHomeTracks(tree,tree.my_load_counter,ajax_params,params);
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
		onHomeLoadTracks(tree,counter,result);
		tree.my_num_loaded += result.length;
		loadHomeTracks(tree,counter,ajax_params,params);
	};


	$.ajax(ajax_params);
}



function addHomeTrackNode(tree,counter,rec)
{
	if (counter == tree.my_load_counter)
	{
		rec.TITLE = rec.title;
		delete rec.title;

		display(dbg_tl,2,"addHomeTrackNode(" + rec.TITLE + ")");
		var	parent = tree.getRootNode();
		parent.addNode(rec);
	}
}


function onHomeLoadTracks(tree,counter,result)
{
	display(dbg_tl,1,"onHomeLoadTracks(" + result.length + ")");
	for (var i=0; counter==tree.my_load_counter && i<result.length; i++)
	{
		addHomeTrackNode(tree,counter,result[i]);
	}
}




function unused_queue_command(command)
{
	var data_rec = {
		// VERSION update_id: update_id,
		renderer_uuid: current_renderer.uuid };
	var data = JSON.stringify(data_rec);
	var url = '/webui/queue/' + command;

	display(dbg_select+1,1,'sending ' + url + "data=\n" + data);

	$.post(url,data,function(result)
	{
		display(dbg_select+1,1,'queue_command() success result=' + result)
	});
}




// END OF home.js
