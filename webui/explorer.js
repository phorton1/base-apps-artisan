//----------------------------------------------------
// explorer.js
//----------------------------------------------------


page_layouts['explorer'] = {
	layout_id: '#explorer_page',
	swipe_element: '#explorer_center_div',
	
	north: {
		limit:400,
		size:40,
		size_touch:60,
		element_id:'#explorer_page_header_right',
		},
	west: {
		limit:600,
		size:280,
		size_touch:380,
		element_id:'#explorer_page_header_left', 
		},
	east: {
		limit:800,
		size:320,
		},
		
	defaults: {
	},
};



function init_page_explorer()
{
	display(dbg_explorer,0,"init_page_explorer()");

	// CENTER DIV LAYOUT
	
	var center_layout = $('#explorer_center_div').layout({
		applyDemoStyles: true,
		north__size:160,
	});

	
	// EXPLORER TREE
	
	$("#explorer_tree").fancytree({
		
		// checkbox: true,
		// selectMode:3,
		clickFolderMode:3,
		
		scrollParent: $('#explorer_tree_div'),

		source:
		{
			url: "/webui/explorer/dir",
			data: {mode:explorer_mode},
			cache: false,
		},

		lazyLoad: function(event, data)
		{
			var node = data.node;
			data.result =
			{
				url: "/webui/explorer/dir",
				data: {id: node.key, mode:explorer_mode},
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
			// The event data has the node object
			// The node object has a data member
			// which is any fields we returned by
			// json that fancytree didn't know (i.e.
			// key and title). We use uppercase to
			// distinguish and hopefully prevent
			// namespace collisions.
			
			var node = data.node;
			var rec = node.data;
			
			// note that we use .html() for the title,
			// which is required to work with Utils::escape_tag()
			// which changes non-printable characters into their
			// &#NNN; html equivilants.
		
			$("#explorer_header_left").html(node.title);
			$('#explorer_album_image').attr('src',rec.ART_URI);
			update_explorer_album_info(rec);
			hide_layout_panes();
		},
		
	});
	
	
	
	// EXPLORER TRACKLIST
	
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

			// note that we use .html() for the title,
			// which is required to work with Utils::escape_tag()
			// which changes non-printable characters into their
			// &#NNN; html equivilants.

			$tdList.eq(0).addClass('explorer_tracklist_td0');
			$tdList.eq(1).text(rec.TRACKNUM).addClass('explorer_tracklist_td1');
			$tdList.eq(2).html(rec.TITLE)	.addClass('explorer_tracklist_td2');
			$tdList.eq(3).text(rec.FILEEXT)	.addClass('explorer_tracklist_td3');
			
			// Should note differences in GENRE and only display non-standard GENRES
			// that don't agree with the Album Info
			
			$tdList.eq(4).text(rec.GENRE)	.addClass('explorer_tracklist_td4 explorer_tracklist_variable_td');
			
			// Should note difference in ARTIST / ALBUM / ALBUM_ARTIST and
			// only show those that don't agree with the Album Info
			// Other candidate fields include ID, STREAM_MD5, FILE_MD5, etc
			
			$tdList.eq(5).text(rec.YEAR)	.addClass('explorer_tracklist_td5 explorer_tracklist_variable_td');
		},
		
		activate: function(event, data)
		{
			// The event data has the node object
			// The node object has a data member
			// which is to any fields we returned by
			// json that fancytree didn't know (i.e.
			// key and title). We use uppercase to
			// distinguish and hopefully prevent
			// namespace collisions.
			
			// prh - clicking on a track in the car stereo should
			// open up the details pane
			
			var node = data.node;
			var rec = node.data;
			var details = $("#explorer_details").fancytree("getTree");
			details.reload({
				url:'/webui/explorer/item_tags?id=' + rec.ID,
				cache: true});
		},

	});


	// CONTEXT MENU
	// Requires modified prh-jquery.ui-contextmenu.js

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
				if (!current_renderer)
				{
					rerror('No current renderer selected');
				}
							
				$.get('/webui/renderer/play_song' +
					  '?id='+current_renderer.id +
					  '&song_id=' + node.data.ID,
					function(result)
					{
						if (result.error)
						{
							rerror('Error in transport_command(' + command + '): ' + result.error);
						}
					}
				);
			}

			else if (ui.cmd == 'play_local')
			{
				var play_url = "/media/" + node.data.ID + '.' + node.data.FILEEXT;
				$('#audio_player').attr('src',play_url);
				$('#audio_player_title').html(node.data.NAME);
			}

			else if (ui.cmd == 'play_download')
			{
				var play_url = "/media/" + node.data.ID + '.' + node.data.FILEEXT;
				var myWindow = window.open(
					play_url,
					"playerWindow",
					"width=400, height=300");
			}
		}
		
	});
	
	
	// EXPLORER DETAILS
	// should inherit already expanded state of tree
	
	$("#explorer_details").fancytree({
		
		clickFolderMode:3,
		extensions: ["table"],
		renderColumns: function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			var $tdList = $(node.tr).find(">td");

			// note that we use .html() for the value,
			// which is required to work with Utils::escape_tag()
			// which changes non-printable characters into their
			// &#NNN; html equivilants.
			//
			// It is worth noting that non-displayable characters
			// will show up as a white triangle, and we *may* want
			// to consider that chr(13), and chr(0) are special
			// cases in Utils::escape_tag()
			
			$tdList.eq(0)					.addClass('explorer_details_td0');
			$tdList.eq(1).text(rec.TITLE)	.addClass('explorer_details_td1');
			$tdList.eq(2).html(rec.VALUE)	.addClass('explorer_details_td2');
			
			if (!node.children)
			{
				var expander = $tdList.eq(0).find('.fancytree-expander');
				expander.css('display','none');
			}
			else
			{
				$tdList.eq(1).addClass('explorer_details_section_label');
			}
 		},

	});

}	// init_page_explorer()




//---------------------------------------------------------------
// html version of a FOLDERS database record
//---------------------------------------------------------------

function update_explorer_album_info(rec)
{
	var error_string = '';
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
		'type: ' + rec.DIRTYPE + ' &nbsp;&nbsp ' +
		'class: ' + rec.CLASS + ' &nbsp;&nbsp ' +
		(rec.YEAR ? 'year: ' + rec.YEAR + ' &nbsp;&nbsp ' : '') + 
		(rec.GENRE ? 'genre: ' + rec.GENRE + ' &nbsp;&nbsp ' : ''));

	$('#explorer_album_info2').html(
		'id:' + rec.ID + ' &nbsp;&nbsp; ' +
		'parent:' + rec.PARENT_ID + ' &nbsp;&nbsp ' +
		'error:' + rec.FOLDER_ERROR + ' &nbsp;&nbsp ' +
		'high_folder:' + rec.HIGHEST_FOLDER_ERROR +  ' &nbsp;&nbsp ' +
		'high_track:' + rec.HIGHEST_ERROR +  ' &nbsp;&nbsp ' +
		(rec.HAS_ART ? 'hasart='+rec.HAS_ART : ''));

	$('#explorer_album_info3').html(
		error_string
	 );

	var station_bits = '';
	for (var i=15; i>=0; i--)
	{
		var bit = 1 << i;
		station_bits += (rec.STATIONS & bit) ? '1' : '0';
	}
	
	$('#explorer_album_info4').html(
		'stations: ' + station_bits);

	$('#explorer_album_info5').html(rec.FULLPATH);
	
	
	//-------------- LOAD THE TRACKLIST -------------------- 
	
	var tree = $("#explorer_tracklist").fancytree("getTree");
	tree.reload({
		url:'/webui/explorer/items?id=' + rec.ID,
		cache: true});
	
	var details = $("#explorer_details").fancytree("getTree");
	details.getRootNode().removeChildren();
	
}




//----------------------------------------------------------
// set_context_stations()
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

				// same code in stations.js
				
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



