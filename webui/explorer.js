//----------------------------------------------------
// explorer.js
//----------------------------------------------------

var dbg_explorer = 1;
var dbg_folder_load = 0;
var dbg_track_load = 0;


const LOAD_PER_REQUEST = 100;


var explorer_inited = false;


var cur_tree;
var explorer_tree;
var explorer_tracklist;
var explorer_details;
var loading_tracklist = 0;
	// an incrementing unique id to stop previous loads

var load_folders = [];
var load_folder_timer;
	// a queue of folders to be loaded


layout_defs['explorer'] = {
	layout_id: '#explorer_page',
	swipe_element: '#explorer_center_div',

	default_params: {
		applyDemoStyles: true,
	},

	north: {
		size:40,
		limit:400,
		resizable: false,
		element_id:'#explorer_page_header_right',
	},
	west: {
		size:280,
		limit:600,
		element_id:'#explorer_page_header_left',
	},
	east: {
		size:320,
		limit:800,
	},

};



function update_explorer()
	// called when library changes,
	// we need to update urls and re-load the page
{
	display(dbg_explorer,0,"update_explorer()");
	explorer_tree.reload();
	init_page_explorer();
}



function deselectTree(id)
	// unselect all items and remove the 'anchor'
{
	$('#' + id).find('.fancytree-selected')
		.removeClass('fancytree-selected');
	$('#' + id).fancytree("getTree").activeNode = undefined;

}


function nodeTitle(node)
{
	return node.data.TITLE;
}

function nodeType(node)
{
	var type = node.data.dirtype;
	if (type == undefined)
		type = 'track';
	return type;
}



//--------------------------------------
// init_page_explorer()
//--------------------------------------

function init_page_explorer()
{
	display(dbg_explorer,0,"init_page_explorer()");

	// EXPLORER TREE
	// nodata: 				false = don't add a dummy 'No Data' node
	// clickFolderMode:		1:activate, 2:expand, 3:activate and expand, 4:activate/dblclick expands (default: 4)
	// source: 				has to at least return an empty array or my addNodes don't render.

	display(dbg_explorer,1,"initializizing explorer tree");

	$("#explorer_tree").fancytree({
		nodata:				false,
		clickFolderMode:  	1,
		scrollParent: 		$('#explorer_tree_div'),
		extensions: 		["multi"],
		multi: 				{ mode: "sameParent" },
		source: 			function() { return []; },
		click:				function(event,data)
		{
			// return myOnClick('tree', event, data)
			var node = data.node;
			update_explorer_ui(node);
			deselectTree('explorer_tracklist');
			cur_tree = explorer_tree;
		},
		lazyLoad: function(event, data)
		{
			var node = data.node;
			var test_bool = false; // node.title == 'Beatles';
			addLoadFolder(0,node,test_bool);
			data.result =  [];
		},
	});

	explorer_tree = $("#explorer_tree").fancytree("getTree");
	$.get(library_url() + "/dir" + '?id=0&mode=0&source=main',
		function (result) { onLoadFolder(0,result) } );
	if (IS_TOUCH)
		init_touch('explorer_tree');


	// EXPLORER TRACKLIST

	display(dbg_explorer,1,"initializizing explorer tracklist");

	$("#explorer_tracklist").fancytree({
		nodata:			false,
		scrollParent: 	$('#explorer_tracklist_div'),
		selectMode:		2,
		extensions: 	["table","multi"],
		table: 			{},
		source: 		function() {  return []; },
		click:  		function(event,data)
		{
			// return myOnClick('tracklist', event, data)
			var node = data.node;
			var rec = node.data;
			explorer_details.reload({
				url: library_url() + '/track_metadata?id=' + rec.id,
				cache: true});
			deselectTree('explorer_tree');
			cur_tree = explorer_tracklist;
			return true;
		},
		renderColumns: 	function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			var $tdList = $(node.tr).find(">td");

			$tdList.eq(0)						.addClass('tracklist_icon');
			$tdList.eq(1).text(rec.tracknum)	.addClass('tracklist_tracknum');
			$tdList.eq(2).html(rec.TITLE)		.addClass('tracklist_title');
			$tdList.eq(3).text(rec.album_title)	.addClass('tracklist_album');
			$tdList.eq(4).text(rec.genre)		.addClass('tracklist_genre');
			$tdList.eq(5).text(rec.year_str)	.addClass('tracklist_year');
		},
	});

	explorer_tracklist = $("#explorer_tracklist").fancytree("getTree");
	if (IS_TOUCH)
		init_touch('explorer_tracklist');


	// EXPLORER DETAILS

	display(dbg_explorer,1,"initializizing explorer details");

	$("#explorer_details").fancytree({
		nodata:				false,
		clickFolderMode:	3,
		extensions: 		["table"],
		source: 			function() { return []; },
		expand: 			function(event, data) { saveDetailsExpanded(true,data.node); },
		collapse: 			function(event, data) { saveDetailsExpanded(false,data.node); },
		click: function(event, data)
		{
			var node = data.node;
			if (node.children)
				node.setExpanded(!node.isExpanded());
			return false;	// no default event
		},
		renderColumns: function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			var $tdList = $(node.tr).find(">td");

			$tdList.eq(0)					.addClass('explorer_details_icon');
			$tdList.eq(1).html(rec.TITLE)	.addClass('explorer_details_lvalue');
			$tdList.eq(2).html(rec.VALUE)	.addClass('explorer_details_rvalue');

			if (!node.children)
			{
				var expander = $tdList.eq(0).find('.fancytree-expander');
				expander.css('display','none');
			}
			else
			{
				if (explorer_details)	// use saved expanded state if available
				{
					var exp = explorer_details['expanded_' + rec.TITLE];
					if (exp != undefined)
						node.setExpanded(exp);
				}

				$tdList.eq(2).prop("colspan", 2);
				$tdList.eq(1).addClass('explorer_details_section_label');
			}
 		},
	});		// explorer_details

	explorer_details = $("#explorer_details").fancytree("getTree");

	update_explorer_ui()
	cur_tree = explorer_tree;

	if (!explorer_inited)
	{
		$(".select_button").button();
	}
	explorer_inited = true;

	display(dbg_explorer,1,"init_page_explorer() finished");
}


function saveDetailsExpanded(expanded,node)
{
	var rec = node.data;
	var title = rec.TITLE;
	// alert((expanded ? "expand " : "collapse") + title);
	explorer_details['expanded_' + title] = expanded;
}



//---------------------------------------
// incremental directory loading
//---------------------------------------

function addLoadFolder(level,node,load_children)
{
	var rec = node.data;
	var title = node.title;
	display(dbg_folder_load,level,"addLoadFolder(" + load_children + ") " + rec.TITLE);

	rec.load_level = level;
	load_folders.push(node);

	// push any existing children for recursive loading

	if (load_children)
	{
		rec.load_children = true;
		var children = node.getChildren();
		if (children != undefined)
		{
			for (let i=0; i<children.length; i++)
			{
				var child = children[i];
				var child_rec = child.data;
				if (child_rec.dirtype != 'album' &&
					child_rec.dirtype != 'playlist')
				{
					addLoadFolder(level+1,child,true);
				}
			}
		}
	}

	if (load_folder_timer == undefined)
		load_folder_timer = setTimeout(loadFolders,1);
}


function loadFolders()
{
	load_folder_timer = undefined;
	if (load_folders.length == 0)
	{
		display(0,0,"loadFolders() finished");
		return;
	}
	var node = load_folders.shift();
	loadFolder(node);
}



function addFolderNode(level,rec,load_children)
{
	display(dbg_folder_load+1,level,"addFolderNode(" + load_children + ") " + rec.TITLE);
	rec.cache = true;
	var parent = explorer_tree.getNodeByKey(rec.parent_id);
	if (!parent)
		parent = explorer_tree.getRootNode();
	var node = parent.addNode(rec);

	// push any newly loaded folders for recursive loading

	if (load_children &&
		rec.dirtype != 'album' &&
		rec.dirtype != 'playlist' )
	{
		addLoadFolder(1,node,true);
	}
}


function onLoadFolder(level,result,load_children)
{
	if (load_children == undefined)
		load_children = false;
	display(dbg_folder_load,level,"onLoadFolder(" + load_children + ") length=" + result.length);
	for (var i=0; i<result.length; i++)
	{
		addFolderNode(level+1,result[i],load_children);
	}
}


function loadFolder(node)
{
	var rec = node.data;
	var level = rec.load_level;
	if (rec.loaded == undefined)
		rec.loaded = 0;
	display(dbg_folder_load,level,"loadFolder(" + rec.TITLE + ") loaded=" + rec.loaded + " num=" + rec.num_elements);

	if (rec.loaded >= rec.num_elements)
	{
		load_folder_timer = setTimeout(loadFolders,1);
		return;
	}

	$.ajax({
		async: true,
		url: library_url() + "/dir",
		data: {
			id: rec.id,
			mode: 0,
			source: 'incremental',
			start: rec.loaded,
			count: LOAD_PER_REQUEST },
		success: function (result)
		{
			onLoadFolder(level,result,rec.load_children);
			rec.loaded += result.length;
			loadFolder(node);
		},
	});
}



//--------------------------------------
// incremental tracklist loading
//--------------------------------------

function loadTracklist(rec)
	// incrementally, and asyncrhounously load the tracklist
{
	if (rec.loading != loading_tracklist)
		return;
	if (rec.loaded >= rec.num_elements)
		return;

	$.ajax({
		async: true,
		url: library_url() + "/tracklist",
		data: {
			id: rec.id,
			source: 'loadTracklist',
			start: rec.loaded,
			count: LOAD_PER_REQUEST },
		success: function (result)
		{
			// it *may not* be an actual 'album' or 'playlist', so
			// if the result returns 0 length, we bail.

			if (!result.length)
				return;
			onLoadTracks(result,rec.loading);
			rec.loaded += result.length;
			loadTracklist(rec);
		},
	});
}


function addTrackNode(rec,loading)
{
	rec.cache = true;
	var	parent = explorer_tracklist.getRootNode();
	if (loading == loading_tracklist)
	{
		display(dbg_track_load+1,1,"addTrackNode(" + rec.TITLE + ")");
		parent.addNode(rec);
	}
}


function onLoadTracks(result,loading)
{
	display(dbg_track_load,0,"onLoadTracks()");
	for (var i=0; loading==loading_tracklist && i<result.length; i++)
	{
		addTrackNode(result[i],loading);
	}
}




//--------------------------------------------------------------
// selection handling
//--------------------------------------------------------------
// WIP

var selection_sessions = [];
var loaded_tracks = [];
var selected_folders = [];
var album_queue = [];


function pushTrack(node,level)
{
	display(0,level+1,"pushTrack(" + node.data.TITLE + ")");
	loaded_tracks.push(node);
}

function pushFolder(node,level)
{
	display(0,level+1,"pushFolder(" + nodeType(node) + ") " + nodeTitle(node));
	folder_queue.push(node);
}

function pushAlbum(node,level)
{
	display(0,level+1,"pushAlbum(" + nodeType(node) + ") " + nodeTitle(node));
	album_queue.push(node);
}


function enqueuAll(main_node)
{
	display(0,0,"enqueueAll(" + main_node + ")");
	var tree = main_node.tree;
	var selected = tree.getSelectedNodes();
	for (let i=0; i<selected.length; i++)
	{
		var node = selected[i];
		if (node.data.dirtype == undefined)
		{
			pushTrack(node,0);
		}
		else
		{
			enqueueFolder(node,0);
		}
	}
}


function enqueueFolder(node,level)
	// the rubber meets the road.
	// This ties into the 'regular' directory loading process which is
	// 		aynchrounous and can be happening simultaneously and now
	// 		becomes aware that it must continue for other directories
	//		and is not solely predicated on fancytree lazyload logic.
{
	var rec = node.data;
	var type = rec.dirtype;
	display(0,1+level,"enqueueFolder(" + type + ") " + node.title);
	if (type == 'album')
	{
		enqueuAlbum(node);
	}
	else
	{
	}
}


function enqueueAlbum(node)
	// except for the current selected Album, all
	// would have to be loaded, and even then, the
	// current tracklist could be in the process of
	// asynchrounously loading, so we just go ahead
	// and synchronously load the entire tracklist
	// for the album in a single call.
{
}







//---------------------------------------------------------------
// update_explorer_ui
//---------------------------------------------------------------

function update_explorer_ui(node)
	// Update the album pane of the explorer which in turn clears
	// the old details and loads the tracks if any
{
	if (explorer_tracklist)
	{
		loading_tracklist++;
		explorer_tracklist.getRootNode().removeChildren();
	}

	if (node == undefined)
	{
		$('#explorer_folder_image').attr('src','/webui/icons/artisan.png');
		$('#explorer_folder_title') .html('');
		$('#explorer_folder_artist').html('');
		$('#explorer_folder_genre') .html('');
		$('#explorer_folder_year')  .html('');
		$('#explorer_folder_path')  .html('');
		explorer_details.getRootNode().removeChildren();
	}
	else
	{
		rec = node.data;

		var title = rec.TITLE;
		if (rec.genre && (
			rec.genre.startsWith('Dead') ||
			rec.genre.startsWith('Beatles')))
		{
			title = rec.artist + ' - ' + title;
		}
		else if (rec.dirtype != 'album')
		{
			title = rec.dirtype + ' - ' + title;
		}

		$('#explorer_folder_image').attr('src',
			rec.art_uri == '' ? '/webui/icons/no_image.png' :
			rec.art_uri);
		$('#explorer_folder_title') .html(title);
		$('#explorer_folder_artist').html(rec.artist == ''   ? '' : 'Artist: ' + rec.artist);
		$('#explorer_folder_genre') .html(rec.genre  == ''   ? '' : 'Genre: ' + rec.genre);
		$('#explorer_folder_year')  .html(rec.year_str == '' ? '' : 'Year: ' + rec.year_str);
		$('#explorer_folder_path')  .html(rec.path == ''     ? '' : 'Path: ' + rec.path);

		explorer_details.reload({
			url: library_url() + '/folder_metadata?id=' + rec.id,
			cache: true});

		display(dbg_explorer,1,"loading tracks for  " + rec.TITLE);
		rec.loaded = 0;
		rec.loading = loading_tracklist;
		loadTracklist(rec);
	}

}	// update_explorer_ui()
