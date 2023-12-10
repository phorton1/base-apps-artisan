//----------------------------------------------------
// explorer.js
//----------------------------------------------------

var dbg_explorer = 1;

var explorer_tree;
var explorer_tracklist;
var explorer_details;
var loading_tracklist = 0;
	// an incrementing unique id to stop previous loads

const LOAD_PER_REQUEST = 100;



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
	explorer_tree.reload();	// options.source.url = "/webui/library/" + current_library['uuid'] + "/dir";
	update_explorer_ui('',{})
	init_page_explorer();
}




//---------------------------------------
// incremental directory loading
//---------------------------------------

function addDirNode(data)
{
	data.cache = true;
	var parent = explorer_tree.getNodeByKey(data.parent_id);
	if (!parent)
		parent = explorer_tree.getRootNode();
	parent.addNode(data);
}


function onLoadDir(result)
{
	display(0,0,"onLoadDir()");
	for (var i=0; i<result.length; i++)
	{
		addDirNode(result[i]);
	}
}


function loadDirRemaining(rec)
	// called the first time after an asynchrounous lazyLoad completes,
	// loop through more synchronous calls to $.get{)->onLoadDir() until
	// the whole thing is loaded.
{
	if (rec.loaded >= rec.num_elements)
		return;

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
			onLoadDir(result);
			rec.loaded += result.length;
			loadDirRemaining(rec);
		},
	});
}



//--------------------------------------
// init_page_explorer()
//--------------------------------------

function init_page_explorer()
{
	// Generally speaking, in fancyTree event data has the node object
	// The node object has a data member  which is any fields we returned via json.
	// fancytree didn't know, chiefly among them 'title', 'key', and 'lazy'

	display(dbg_explorer,0,"init_page_explorer()");

	// EXPLORER TREE

	display(dbg_explorer,1,"initializizing explorer tree");

	$("#explorer_tree").fancytree({

		clickFolderMode:3,
			// 1:activate, 2:expand, 3:activate and expand, 4:activate/dblclick expands (default: 4)
		scrollParent: $('#explorer_tree_div'),

		// Incremental Loading
		// sourc: has to at least return an empty array or my addNodes don't render.

		source: function()
		{
			return [];
		},

		lazyLoad: function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			var id = node.key;

			// use a Deferred result for the 0th lazyLoad

			var dfd = new $.Deferred();
			data.result = dfd.promise();
			rec.loaded = 0;

			$.ajax({
				async: true,
				url: library_url() + "/dir",
				data: {
					id: id,
					mode: 0,
					source: 'lazyLoad',
					start: 0,
					count: LOAD_PER_REQUEST },
				success: function (result)
				{
					dfd.resolve(result);

					// Therafter, load the remaing recs in a self-perpetuating loop.
					// We check result.length JIC it's not really a folder and has
					// no 'folder' children.  Then it is probably an 'album' or a
					// 'playlist' and will load tracks in update_explorer_ui().
					// This will have the added effect of removing the (bogus) expander,
					// as now fancyTree will know there are no children.

					if (result.length)
					{
						rec.loaded = result.length;
						loadDirRemaining(rec);
					}
				},
			});

			display(0,0,"as we can prove from this");

		},

		activate: function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			update_explorer_ui(node.title,rec);
		}
	});		// explorer_tree

	explorer_tree = $("#explorer_tree").fancytree("getTree");
		// cache the explorer tree, then...
	$.get(library_url() + "/dir" + '?id=0&mode=0&source=main',
		function (result) { onLoadDir(result) } );
		// load the data ...


	// EXPLORER TRACKLIST
	// TRACKLIST(S) TO BE REWORKED

	display(dbg_explorer,1,"initializizing explorer tracklist");

	$("#explorer_tracklist").fancytree({

		scrollParent: $('#explorer_tracklist_div'),
		extensions: ["table"],
		table: {},

		renderColumns: function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			var $tdList = $(node.tr).find(">td");

			// TITLE in lowercase conflicts with jquery-ui,
			// so we raise it to TITLE in uiLibrary.pm
			// Note also that we used to use .text() for content,
			// but now we use .html() as the content may contain
			// encoded characters from Perl Utils::escape_tag()

			$tdList.eq(0).addClass('explorer_tracklist_td0');
			$tdList.eq(1).text(rec.tracknum).addClass('explorer_tracklist_td1');
			$tdList.eq(2).html(rec.TITLE)	.addClass('explorer_tracklist_td2');
			$tdList.eq(3).text(rec.type)	.addClass('explorer_tracklist_td3');

			// Should note differences in GENRE and only display non-standard GENRES
			// that don't agree with the Album Info

			$tdList.eq(4).text(rec.genre).addClass('explorer_tracklist_td4 explorer_tracklist_variable_td');

			// Should note difference in ARTIST / ALBUM / ALBUM_ARTIST and
			// only show those that don't agree with the Album Info
			// Other candidate fields include ID, STREAM_MD5, file_md5, etc

			$tdList.eq(5).text(rec.year_str).addClass('explorer_tracklist_td5 explorer_tracklist_variable_td');
		},

		activate: function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			explorer_details.reload({
				url: library_url() + '/track_metadata?id=' + rec.id,
				cache: true});
		},

		dblclick: function(event, data) {
			var node = data.node;
			var rec = node.data;

			renderer_command('play_song',{
				library_uuid: current_library['uuid'],
				track_id: node.data.id });

			return true;
				// we could return false to prevent default handling,
				// i.e. generating subsequent activate, expand, or select events
		},
	});		// explorer_tracklist


	explorer_tracklist = $("#explorer_tracklist").fancytree("getTree");
		// cache the tracklist


	// EXPLORER DETAILS

	display(dbg_explorer,1,"initializizing explorer details");

	$("#explorer_details").fancytree({

		clickFolderMode:3,		// activateAndExpand
		extensions: ["table"],

		expand: function(event, data)  { saveDetailsExpanded(true,data.node); },
		collapse: function(event, data) { saveDetailsExpanded(false,data.node); },
			// save the expanded state when done by hand

		click: function(event, data)
		{
			var node = data.node;
			if (node.children)
			{
				node.setExpanded(!node.isExpanded());
			}
			return false;	// no default event
		},


		renderColumns: function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			var $tdList = $(node.tr).find(">td");

			// note that we use .html() for the error icons,
			// and Utils::escape_tag() which changes non-printable
			// characters into their &#NNN; html equivilants.
			//
			// It is worth noting that non-displayable characters
			// will show up as a white triangle, and we *may* want
			// to consider that chr(13), and chr(0) are special
			// cases in Utils::escape_tag()

			$tdList.eq(0)					.addClass('explorer_details_td0');
			$tdList.eq(1).html(rec.TITLE)	.addClass('explorer_details_td1');
			$tdList.eq(2).html(rec.VALUE)	.addClass('explorer_details_td2');

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
		// cache the explorer_details


	// TRACKLIST CONTEXT MENU
	// Requires modified prh-jquery.ui-contextmenu.js

	display(dbg_explorer,1,"initializizing explorer context menu");

	$("#explorer_tracklist").contextmenu({

		// delegate: "span.fancytree-title",
		// menu: "#options",

		menu:
		[
			{title: "Play (Renderer)", cmd: "play_renderer", uiIcon: "ui-icon-extlink"},
			{title: "Play (Local)", cmd: "play_local", uiIcon: ".ui-icon-newwin"},
			{title: "Play (Download)", cmd: "play_download", uiIcon: ".ui-icon-newwin"},

			{title: "----"},
			{title: "Cut", cmd: "cut", uiIcon: "ui-icon-scissors"},
			{title: "Copy", cmd: "copy", uiIcon: "ui-icon-copy"},
			{title: "Paste", cmd: "paste", uiIcon: "ui-icon-clipboard", disabled: false },
			{title: "----"},
			{title: "Edit", cmd: "edit", uiIcon: "ui-icon-pencil", disabled: true },
			{title: "Delete", cmd: "delete", uiIcon: "ui-icon-trash", disabled: true },
			{title: "More", children: [
				{title: "Sub 1", cmd: "sub1"},
				{title: "Sub 2", cmd: "sub1"}
				]}
		],

		beforeOpen: function(event, ui)
		{
			var node = $.ui.fancytree.getNode(ui.target);
			// node.setFocus();
			node.setActive();
		},

		select: function(event, ui)
		{
			var node = $.ui.fancytree.getNode(ui.target);

			if (ui.cmd == 'play_renderer')
			{
				renderer_command('play_song',{
					library_uuid: current_library['uuid'],
					track_id: +node.data.id });
			}

			else if (ui.cmd == 'play_local')
			{
				var play_url = "/media/" + node.data.id + '.' + node.data.type;
				$('#audio_player').attr('src',play_url);
				$('#audio_player_title').html(node.data.title);
			}

			else if (ui.cmd == 'play_download')
			{
				var play_url = "/media/" + node.data.id + '.' + node.data.type;
				var myWindow = window.open(
					play_url,
					"playerWindow",
					"width=400, height=300");
			}
		}

	});		// tracklist context menu


	display(dbg_explorer,1,"init_page_explorer() returning");

}	// init_page_explorer()



function saveDetailsExpanded(expanded,node)
{
	var rec = node.data;
	var title = rec.TITLE;
	// alert((expanded ? "expand " : "collapse") + title);
	explorer_details['expanded_' + title] = expanded;
}


//---------------------------------------------------------------
// update_explorer_ui
//---------------------------------------------------------------

function update_explorer_ui(title,rec)
	// Update the album pane of the explorer which in turn clears
	// the old details and loads the tracks if any
{
	if (rec.genre && (
		rec.genre.startsWith('Dead') ||
		rec.genre.startsWith('Beatles')))
	{
		title = rec.artist + ' - ' + title;
	}

	display(dbg_explorer,1,"update_explorer_ui() " + title);

	$("#explorer_header_left").html(title);
	$('#explorer_album_image').attr('src',rec.art_uri);

	var error_string = 'no errors';
	if (rec.errors)
	{
		for (var i=0; i<rec.errors.length; i++)
		{
			var level = rec.errors[i].level;
			error_string += "<img src='/webui/icons/error_" + level + ".png' height='16px' width='16px'>";
			error_string += rec.errors[i].msg + "<br>";
		}
	}

	$('#explorer_album_info1').html(
		'type: ' + rec.dirtype + ' &nbsp;&nbsp ' +
		(rec.year_str ? 'year: ' + rec.year_str + ' &nbsp;&nbsp ' : '') +
		(rec.genre ? 'genre: ' + rec.genre + ' &nbsp;&nbsp ' : '') +
		'id:' + rec.id + ' &nbsp;&nbsp; ');

	$('#explorer_album_info2').html(
		(rec.has_art ? 'has_art:'+rec.has_art : '') + ' &nbsp;&nbsp ' +
		'error:' + rec.folder_error + ' &nbsp;&nbsp ' +
		'high_folder_error:' + rec.highest_folder_error +  ' &nbsp;&nbsp ' +
		'high_track_error:' + rec.highest_track_error +  ' &nbsp;&nbsp ' );

	$('#explorer_album_info3').html(
		'parent:' + rec.parent_id + ' &nbsp;&nbsp '
	 );

	$('#explorer_album_info4').html(rec.path);

	$('#explorer_album_info5').html(
		error_string ? error_string : ""
	 );

	// Incrementally load the track list asynchronously
	// The rec keeps track of the number loaded, just like the tree folders,
	// but we also set a unique id 'loading_tracklist' to stop the load if
	// it the activated explorer_tree 'folder' changes.

	if (explorer_tracklist)
	{
		loading_tracklist++;
		explorer_tracklist.getRootNode().removeChildren();
		display(dbg_explorer,1,"loading tracks for  " + rec.TITLE);
		if (rec.id != undefined)
		{
			rec.loaded = 0;
			rec.loading = loading_tracklist;
			loadTracklist(rec);
		}
	}
	else
	{
		display(dbg_explorer,1,"could not find #explorer_tracklist");
	}

	// replace track details if an id exists or clear them

	if (rec.id == undefined)
	{
		explorer_details.getRootNode().removeChildren();
	}
	else
	{
		explorer_details.reload({
			url: library_url() + '/folder_metadata?id=' + rec.id,
			cache: true});
	}

}	// update_explorer_ui()



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


function addTrackNode(data,loading)
{
	data.cache = true;
	var	parent = explorer_tracklist.getRootNode();
	if (loading == loading_tracklist)
		parent.addNode(data);
}


function onLoadTracks(result,loading)
{
	display(0,0,"onLoadTracks()");
	for (var i=0; loading==loading_tracklist && i<result.length; i++)
	{
		addTrackNode(result[i],loading);
	}
}




//----------------------------------------------------------
// set_context_explorer()
//----------------------------------------------------------

function set_context_explorer(context)
{
	display(0,0,'set_context_explorer(' + context + ') called');

	$.get('/webui/explorer/get_id_path' +
		  '?track_id='+context,

		function(result)
		{
			if (result.error)
			{
				rerror('Error in set_context_explorer(): ' + result.error);
			}
			else
			{
				var path = result.id_path;
				display(0,1,"id_path='" + path + "'");

				// strip the last track_id off if it exists

				var track_id = '';
				if (path.replace(/\/track_(.*)$/,''))
				{
					track_id = RegExp.$1;
				}


				var last_node;
				var tree = $('#explorer_tree').fancytree('getTree');
				tree.loadKeyPath(path, function(node, status)
				{
					display(0,2,"Node ["+node.title+"] status ["+status+"]");
					if (status == "loading")
					{
						node.data.shouldPromptForFilter=false;
					}
					else if (status == "loaded")
					{
						display(0,2,"intermediate_node=" + node);
						last_node = node;
					}
					else if (status == "ok")
					{
						// node.setExpanded(true);
						// node.setActive(true);
						display(0,2,"ok_node=" + node);
						last_node = node;
					}
				});


				display(0,1,"last_node=" + last_node);
				if (last_node)
				{
					last_node.makeVisible({scrollIntoView: true});
					last_node.setActive(true);

					// explorer specific code

					if (track_id)
					{
						display(0,1,"set track_id=" + track_id);
						var track_list = $("#explorer_tracklist").fancytree('getTree');
						var node = track_list.getNodeByKey(track_id);
						if (node)
						{
							node.makeVisible({scrollIntoView: true});
							node.setActive(true);
						}
					}
				}
			}
		});
}
