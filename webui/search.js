//----------------------------------------------------
// search.js
//----------------------------------------------------
// The search window does not currently support a
// touch CTRL button ...


var dbg_search =  0;
var search_tracklist;


layout_defs['search'] = {
	layout_id: '#search_page',
	swipe_element: '#search_conditions_div',

	default_params: {
		applyDemoStyles: true,
	},

	north: {
		size:40,
		limit:400,
		resizable: false,
	},

};


function disableSearchPlayAdd(disabled)
{
	disable_button('#search_button_play',disabled);
	disable_button('#search_button_add',disabled);
}


function init_page_search()
{
	$(".search_button").button();
	$(".search_label").on("click",onClickSearchLabel);
	// $(".search_value").prop('value','');
		// initialize all values to blank on reload
	disableSearchPlayAdd(true);


	$("#search_tracklist").fancytree({
		nodata:			false,
		scrollParent: 	$('#search_result_div'),
		selectMode:		2,
		extensions: 	["table","multi"],
		table: 			{},
		source: 		function() { return []; },
		click:  		function(event,data)
		{
			var node = data.node;
			if (IS_TOUCH)
			{
				var selected = node.isSelected();
				search_tracklist.onTreeSelect();
				node.setSelected(!selected);
				return false;
			}
			return true;
		},
		dblclick:		function(event, data)
		{
			var node = data.node;
			var rec = node.data;
			deselectTree('search_tracklist');
			node.setSelected(true);
			disableSearchPlayAdd(false);
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

			$tdList.eq(0)						.addClass('home_rownum');
			$tdList.eq(1).html(rec.TITLE)		.addClass('home_title');
			$tdList.eq(2).html(artist)			.addClass('home_artist');
			$tdList.eq(3).text(rec.tracknum)	.addClass('home_tracknum');
			$tdList.eq(4).text(rec.album_title)	.addClass('home_album');
			$tdList.eq(5).text(rec.genre)		.addClass('home_genre');
			$tdList.eq(6).text(rec.year_str)	.addClass('home_year');
		},
		select: function (event,data)
		{
			disableSearchPlayAdd(
				!search_tracklist.getSelectedNodes().length);
		}
	});

	search_tracklist = $("#search_tracklist").fancytree("getTree");
	search_tracklist.onTreeSelect = function()
		// with no CTRL button, we always deleect our tree,
	{
		if (IS_TOUCH)
			deselectTree('search_tracklist');
	};
	if (IS_TOUCH)
		init_touch('search_tracklist');
}


function onClickSearchLabel(event)
	// clicking on any label clears all search terms
{
	$(".search_value").prop('value','');
}



function onSearchButton(command)
{
	if (command == 'find')
	{
		var any = $("#search_any").prop('value');
		var album = $("#search_album").prop('value');
		var title = $("#search_title").prop('value');
		var artist = $("#search_artist").prop('value');

		var data = {  };	// count: LOAD_PER_REQUEST
		if (any    != '') data.any    = any   ;
		if (album  != '') data.album  = album ;
		if (title  != '') data.title  = title ;
		if (artist != '') data.artist = artist;

		search_tracklist.clear();
		disableSearchPlayAdd(true);

		$.ajax({
			async: false,
			url: current_library_url() + "/find",
			data: data,
			success: function (result)
			{
				if (result.error)
				{
					rerror(result.error);
				}
				else
				{
					onLoadSearchTracks(result.tracks);
				}
			},
		});
	}
	else
	{
		doSearchSelectCommand(command);
	}
}




//-----------------------------------------------
// load tracks
//-----------------------------------------------

function addSearchTrackNode(rec)
{
	rec.cache = true;
	rec.TITLE = rec.title;
	rec.title = '';
	var	parent = search_tracklist.getRootNode();
	parent.addNode(rec);
}


function onLoadSearchTracks(tracks)
{
	display(dbg_search,0,"onLoadSearchTracks()");
	for (var i=0; i<tracks.length; i++)
	{
		addSearchTrackNode(tracks[i]);
	}
}



//---------------------------------------------
// play/add tracks
//---------------------------------------------

function doSearchSelectCommand(command)
{
	display(dbg_search,0,'doSearchSelectCommand(' + command + ')');

	var tracks = [];
	var selected = search_tracklist.getSelectedNodes();
	for (let i=0; i<selected.length; i++)
	{
		var node = selected[i];
		tracks.push(node.data.id);
	}

	var data_rec = {
		// VERSION update_id: update_id,
		renderer_uuid: current_renderer.uuid,
		library_uuid: current_library.uuid,
		tracks: tracks.join(',') };

	display(dbg_search+1,1,'sending ' + url + "data=\n" + data);

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

			display(dbg_search+1,1,'doSelectCommand() success result=' + result)
		});
	}

	search_tracklist.selectAll(false);
	search_tracklist.activeNode = undefined;
}


// end of search.js
