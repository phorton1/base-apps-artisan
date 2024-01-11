//----------------------------------------------------
// explorer.js
//----------------------------------------------------

var dbg_explorer = 1;
var dbg_folder_load = 0;
var dbg_track_load = 0;
var dbg_select = -1;
var dbg_multi = 0;


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
	},
	west: {
		size:280,
		limit:600,
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
	cur_tree = explorer_tree;
	explorer_tree.clear();
	explorer_tracklist.clear();
	update_explorer_ui()
	start_explorer_library();
	// init_page_explorer();
}



function deselectTree(id)
	// unselect all items and remove the 'anchor'
{
	$('#' + id).fancytree("getTree").selectAll(false);
	$('#' + id).fancytree("getTree").activeNode = undefined;
}


function disableSelectPlayAdd(disabled)
{
	disable_button('#select_button_play',disabled);
	disable_button('#select_button_add',disabled);
}

function disableSearchPlayAddAny()
{
	var any =
		explorer_tree.getSelectedNodes().length +
		explorer_tracklist.getSelectedNodes().length;
	disableSelectPlayAdd(!any);
}



function loadDetails(id)
{
	explorer_details.reload({
		url: current_library_url() + '/track_metadata?id=' + id,
		cache: true});
}



//--------------------------------------
// init_page_explorer()
//--------------------------------------

function init_page_explorer()
{
	display(dbg_explorer,0,"init_page_explorer(" + explorer_inited + ")");

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
			cur_tree = explorer_tree;
			var node = data.node;
			var rec = node.data;
			var selected = node.isSelected();
			explorer_tree.onTreeSelect();

			// use the icon as an expander
			// otherwise, do normal activation

			if (data.targetType == 'icon' &&
				rec.dirtype != 'album' &&
				rec.dirtype != 'playlist' )
			{
				node.setExpanded(!node.isExpanded());
				return false;
			}
			else
			{
				update_explorer_ui(node);
				if (IS_TOUCH)
				{
					node.setSelected(!selected);
					return false;
				}
				return true;
			}
		},
		lazyLoad: function(event, data)
		{
			var node = data.node;
			addLoadFolder(node);
			data.result =  [];
		},
		select: function (event,data)
		{
			disableSearchPlayAddAny();
		}
	});

	explorer_tree = $("#explorer_tree").fancytree("getTree");
	explorer_tree.onTreeSelect = function()
		// deselect the other tree, and if ctrl button not pressed,
		// deslect this one as well ..
	{
		deselectTree('explorer_tracklist');
		if (IS_TOUCH &&
			!$('#select_button_ctrl').hasClass('ui-state-active'))
			deselectTree('explorer_tree');
	};
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
		source: 		function() { return []; },
		click:  		function(event,data)
		{
			cur_tree = explorer_tracklist;
			var node = data.node;
			var rec = node.data;
			var selected = node.isSelected();
			explorer_tracklist.onTreeSelect();

			// the time taken by this seems to stop dbl_click from working reliably
			// so I defer it to a timer 500 ms later

			setTimeout( loadDetails, 500, rec.id);

			if (IS_TOUCH)
			{
				node.setSelected(!selected);
				return false;
			}
			return true;
		},
		dblclick:		function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			explorer_tracklist.onTreeSelect();
			explorer_tracklist.selectAll(false);
			node.setSelected(true);
			disableSelectPlayAdd(false);
			renderer_command('play_song',{
				library_uuid: current_library.uuid,
				track_id: rec.id});
		},
		renderColumns: 	function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			var $tdList = $(node.tr).find(">td");
			var artist = rec.artist == '' ? rec.album_artist : rec.artist;

			$tdList.eq(0)						.addClass('tracklist_icon');
			$tdList.eq(1).text(rec.tracknum)	.addClass('tracklist_tracknum');
			$tdList.eq(2).html(rec.TITLE)		.addClass('tracklist_title');
			$tdList.eq(3).text(artist)			.addClass('tracklist_artist');
			$tdList.eq(4).text(rec.genre)		.addClass('tracklist_genre');
			$tdList.eq(5).text(rec.year_str)	.addClass('tracklist_year');
		},
		select: function (event,data)
		{
			disableSearchPlayAddAny();
		}
	});

	explorer_tracklist = $("#explorer_tracklist").fancytree("getTree");
	explorer_tracklist.my_load_counter = 0;
	explorer_tracklist.onTreeSelect = function()
	{
		deselectTree('explorer_tree');
		if (IS_TOUCH &&
			!$('#select_button_ctrl').hasClass('ui-state-active'))
			deselectTree('explorer_tracklist');
	};

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

	// finish up

	$(".select_button").button();
	if (!IS_TOUCH)
		$('#select_button_ctrl').css('display','none');
	disableSelectPlayAdd('true');


	cur_tree = explorer_tree;
	update_explorer_ui()
	start_explorer_library();

	explorer_inited = true;	// unused
	display(dbg_explorer,1,"init_page_explorer() finished");
}


function start_explorer_library()
{
	$.get(current_library_url() + "/dir" + '?id=0&mode=0&source=main',
		function (result) { onLoadFolder(result) } );
}


function saveDetailsExpanded(expanded,node)
{
	var rec = node.data;
	var title = rec.TITLE;
	// alert((expanded ? "expand " : "collapse") + title);
	explorer_details['expanded_' + title] = expanded;
}



function onSelectButton(command)
{
	display(dbg_select,0,'onSelectButton(' + command + ')');
	if (command == 'play')
		doSelectCommand('play');
	else if (command == 'add')
		doSelectCommand('add');
	else if (command == 'ctrl')
	{
		$('#select_button_ctrl').toggleClass('ui-state-active');
	}
}





//---------------------------------------
// incremental directory loading
//---------------------------------------

function addLoadFolder(node)
{
	var rec = node.data;
	var title = node.title;
	display(dbg_folder_load,0,"addLoadFolder(" + rec.TITLE + ")");

	load_folders.push(node);

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


function addFolderNode(rec)
{
	display(dbg_folder_load+1,3,"addFolderNode(" + rec.TITLE + ")");
	rec.cache = true;
	var parent = explorer_tree.getNodeByKey(rec.parent_id);
	if (!parent)
		parent = explorer_tree.getRootNode();
	var node = parent.addNode(rec);

}


function onLoadFolder(result)
{
	display(dbg_folder_load,2,"onLoadFolder() length=" + result.length);
	for (var i=0; i<result.length; i++)
	{
		addFolderNode(result[i]);
	}
}


function loadFolder(node)
{
	var rec = node.data;
	if (rec.loaded == undefined)
		rec.loaded = 0;
	display(dbg_folder_load,1,"loadFolder(" + rec.TITLE + ") loaded=" + rec.loaded + " num=" + rec.num_elements);

	if (rec.loaded >= rec.num_elements)
	{
		load_folder_timer = setTimeout(loadFolders,1);
		return;
	}

	$.ajax({
		async: true,
		url: current_library_url() + "/dir",
		data: {
			id: rec.id,
			mode: 0,
			source: 'incremental',
			start: rec.loaded,
			count: LOAD_PER_REQUEST },
		success: function (result)
		{
			onLoadFolder(result);
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
		url: current_library_url() + "/tracklist",
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



function doSelectCommand(command)
{
	var tree_id = (cur_tree == explorer_tracklist) ?
		'explorer_tracklist' : 'explorer_tree';

	var tracks;
	var folders;

	display(dbg_select,0,'doSelectCommand(' + tree_id + ',' + command + ')');
	var tree = cur_tree;
	var selected = tree.getSelectedNodes();
	for (let i=0; i<selected.length; i++)
	{
		var node = selected[i];
		if (node.data.dirtype == undefined)
		{
			display(dbg_select+1,1,'track ' + node.data.TITLE);
			if (tracks == undefined)
				tracks = [];
			tracks.push(node.data.id);
		}
		else
		{
			display(dbg_select+1,1,'folder ' + node.data.TITLE);
			if (folders == undefined)
				folders = [];
			folders.push(node.data.id);
		}
	}

	var data_rec = {
		// VERSION update_id: update_id,
		renderer_uuid: current_renderer.uuid,
		library_uuid: current_library.uuid };
	if (tracks != undefined)
		data_rec.tracks = tracks.join(',');
	if (folders != undefined)
		data_rec.folders = folders.join(',');

	display(dbg_select+1,1,'sending ' + url + "data=\n" + data);

	// must be passed to html_renderer for needs_start
	// it's synchronous in either case ...

	if (current_renderer.uuid.startsWith('html_renderer'))
	{
		audio_command(command,data_rec);
	}
	else
	{
		var url = '/webui/queue/' + command;
		var data = JSON.stringify(data_rec);
		$.post(url,data,function(result)
		{
			if (result.error)
			{
				rerror(result.error);
			}
			else if (result.queue &&
					 current_renderer.uuid.startsWith('html_renderer'))
			{
				current_renderer.queue = result.queue;
			}

			display(dbg_select+1,1,'doSelectCommand() success result=' + result)
		});
	}

	deselectTree(tree_id);
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
		explorer_tracklist.clear();		// getRootNode().removeChildren();
	}

	if (node == undefined)
	{
		$('#explorer_folder_image').attr('src','/webui/icons/artisan.png');
		$('#explorer_folder_title') .html('');
		$('#explorer_folder_artist').html('');
		$('#explorer_folder_genre') .html('');
		$('#explorer_folder_year')  .html('');
		$('#explorer_folder_path')  .html('');

		disable_button('select_button_add',true);
		disable_button('select_button_play',true);
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

		disable_button('select_button_add',false);
		disable_button('select_button_play',false);

		explorer_details.reload({
			url: current_library_url() + '/folder_metadata?id=' + rec.id,
			cache: true});

		display(dbg_explorer,1,"loading tracks for  " + rec.TITLE);
		rec.loaded = 0;
		rec.loading = loading_tracklist;
		loadTracklist(rec);
	}

}	// update_explorer_ui()


// end of explorer.js
