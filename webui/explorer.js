//----------------------------------------------------
// explorer.js
//----------------------------------------------------

var dbg_explorer = 1;

var explorer_tree;
var explorer_tracklist;
var explorer_details;



layout_defs['explorer'] = {
	layout_id: '#explorer_page',
	swipe_element: '#explorer_center_div',

	default_params: {
		applyDemoStyles: true,
		resizable: false,
	},

	north: {
		size:40,
		limit:400,
		element_id:'#explorer_page_header_right',
	},
	west: {
		size:280,
		limit:600,
		resizable: true,
		element_id:'#explorer_page_header_left',
	},
	east: {
		size:320,
		limit:800,
		resizable: true,
	},

};



function update_explorer()
	// called when library changes,
	// we need to update urls and re-load the page
{
	display(dbg_explorer,0,"update_explorer()");
	explorer_tree.options.source.url = "/webui/library/" + current_library['uuid'] + "/dir";
	update_explorer_ui('',{})
	init_page_explorer();
}


function init_page_explorer()
{
	// Generally speaking, in fancyTree event data has the node object
	// The node object has a data member  which is any fields we returned via json.
	// fancytree didn't know.  We have to be careful with name collisions,
	// for example, fancyTree treats 'title' specially, so we raise it to
	// TITLE in certain cases.  Another potential conflict is 'key'.

	display(dbg_explorer,0,"init_page_explorer()");

	// CENTER DIV LAYOUT
	// Note that the explorer_center_div has a nested layout!
	// Here we set the 'north' (explorer_album_div) within it
	// to 160 in height, leaving the resst for the 'center'
	// (explorer_tracklist_div) which contains the 'explorer_tracklist'
	// div

	var center_layout = $('#explorer_center_div').layout({
		applyDemoStyles: true,
		north__size:160,
	});


	// EXPLORER TREE

	display(dbg_explorer,1,"initializizing explorer tree");

	$("#explorer_tree").fancytree({

		// checkbox: true,
		// selectMode:3,
		clickFolderMode:3,

		scrollParent: $('#explorer_tree_div'),

		source:
		{
			url: "/webui/library/" + current_library['uuid'] + "/dir",
			data: {mode:explorer_mode, source:'main'},
			cache: false,
		},

		lazyLoad: function(event, data)
		{
			var node = data.node;
			var use_id = node.key;
			// if (use_id == undefined) use_id = 0
			data.result =
			{
				url: "/webui/library/" + current_library['uuid'] + "/dir",
				data: {id: use_id, mode:explorer_mode, source:'lazyLoad'},
				cache: true
			};
		},


		extensions: ["table"],
		renderColumns: function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			var $tdList = $(node.tr).find(">td");

			$tdList.eq(1).text(rec.NUM_ELEMENTS).addClass("explorer_tree_num");
				// add the "number of tracks/children folders"

			// some other examples
			// $tdList.eq(1).text(node.key).addClass("explorer_tree_num_column");
			// $tdList.eq(2).text(node.getIndexHier()).addClass("alignRight");
			// $tdList.eq(4).html("<input type='checkbox' name='like' value='" + node.key + "'>");
		},

		activate: function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			display(dbg_explorer,0,"calling update_explore_album_info() " + node.title);
			update_explorer_ui(node.title,rec);
			display(dbg_explorer,0,"back from update_explore_album_info()");
			// hide_layout_panes();

		}
	});		// explorer_tree

	explorer_tree = $("#explorer_tree").fancytree("getTree");
		// cache the explorer tree


	// EXPLORER TRACKLIST
	// TRACKLIST(S) TO BE REWORKED

	display(dbg_explorer,1,"initializizing explorer tracklist");

	$("#explorer_tracklist").fancytree({

		scrollParent: $('#explorer_tracklist_div'),

		extensions: ["table"],
		table:{
			// nodeColumnIdx:null,		// we'll explicitly write the main node
		},

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
				url:'/webui/library/'+current_library['uuid'] + '/track_metadata?id=' + rec.id,
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

		expand: function(event, data)  { saveExpanded(true,data.node); },
		collapse: function(event, data) { saveExpanded(false,data.node); },
			// save the expanded state when done by hand

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



function saveExpanded(expanded,node)
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

	// load the track list

	if (explorer_tracklist)
	{
		display(dbg_explorer,1,"loading tracks for  " + rec.TITLE);
		if (rec.id != undefined)
		{
			explorer_tracklist.reload({
				url:'/webui/library/' + current_library['uuid'] + '/tracklist?id=' + rec.id,
				cache: true});
		}
		else
		{
			explorer_tracklist.getRootNode().removeChildren();
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
			url:'/webui/library/'+current_library['uuid'] + '/folder_metadata?id=' + rec.id,
			cache: true});
	}

}	// update_explorer_ui()




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
