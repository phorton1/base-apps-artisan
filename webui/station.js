//--------------------------------------------------
// station.js
//--------------------------------------------------

var edit_station;
var in_station_info_slider = false;
var in_station_info_spinner = false;


page_layouts['stations'] = {
	layout_id: '#stations_page',
	swipe_element: '#station_tree',
	
	north: {
		limit:400,
		size:40,
		size_touch:60,
		element_id:'#stations_page_header_right',
		},
	west: {
		limit:600,
		size:235,
		element_id:'#stations_page_header_left', 
		},
	east: {
		limit:800,
		size:200,
		size_touch:235,
		},
		
	defaults: {
	},
};



//--------------------------------------
// ONLOAD handlers
//--------------------------------------

function init_page_stations()
{
	display(dbg_stations,0,"init_page_stations()");

	init_station_tree();
	set_stations_title();
	init_pane_station_info();
	
}




//---------------------------------------
// station_list handling
//---------------------------------------

function set_edit_station(station)
{
	edit_station = station;
	set_stations_title();
	update_station_info_ui();
}


function set_stations_title()
{
	display(dbg_stations,0,"set_stations_title()");
	var text = 'No Edit Station Selected';
	if (edit_station)
	{
		text = 'Edit Station ' + edit_station.station_num + ' - ' + edit_station.name;
		if (current_renderer &&
			current_renderer.station &&
			current_renderer.station.station_num == edit_station.station_num)
		{
			text += " (now playing)";
		}
	}
	$('#stations_header_left').text(text);
}


function onload_edit_station_list()
{
	display(dbg_stations,0,"onload_edit_station_list()");
	
    $('#edit_station_list').buttonset();
	$('.edit_station_list_button').each( function()
	{
		var id = $(this).attr('id');
		var checked = false;
		var check_id = edit_station ? 'edit_station_list_button_' + edit_station.station_num : '';
		display(dbg_stations,0,'checking id=' + id);
		if (id == check_id)
		{
			checked = true;
		}
		$(this).blur();
		$(this).prop('checked', checked ).button('refresh');
	});
}


function select_edit_station(id)
{
	hide_layout_panes();
	
	$.get('/webui/station/get_station?station=' + id,
		  
		function(result)
		{
			var station = false;
			if (result.error)
			{
				rerror('Error in select_edit_station((' + id + '): ' + result.error);
			}
			else
			{
				station = result;
			}
			set_edit_station(station);
			onload_edit_station_list();
			update_station_tree_bits(id);
		}
	);
}


//-----------------------------------------
// station_tree (fancytree) handlers
//-----------------------------------------

function init_station_tree()
{
	display(dbg_stations,0,"init_station_tree()");

	// call the kludge to fix the first time
	// incorrect wrapper_div size
	
	resizeStationTree();	


	$("#station_tree").fancytree({
		
		checkbox: true,
		clickFolderMode:3,
		selectMode:3,
 		
		scrollParent: $('#station_tree_wrapper'),
		
		// extensions: ["table"],
			
		click: onClickEditStationTree,

		source:
		{
			url: "/webui/explorer/dir",
			data: { station: function() { return edit_station?edit_station.station_num:0 }},
			cache: false,
		},

		lazyLoad: function(event, data)
		{
			var node = data.node;
			data.result =
			{
				url: "/webui/explorer/dir",
				data: {id: node.key,  station: function() { return edit_station?edit_station.station_num:0 } },
				cache: false,
			};
		},
		
		activate: function(event, data)
			// The event data has the node object
			// The node object has a data member
			// which is to any fields we returned by
			// json that fancytree didn't know (i.e.
			// key and title). We use uppercase to
			// distinguish and hopefully prevent
			// namespace collisions.
		{	
			var node = data.node;
			var rec = node.data;
			$("#stations_header_right").text(node.title);
		},

	});
	
}


// ok, here is the kludge for the station tree scrollbars.
// The wrapper_div is incorrectly sized by the layout ...
// The first time, apparently it is 68 + the titlebar height + a few pixels too high.
// Thereafter (on window resize) it is too high by the titlebar and a few pixels;

// $(window).resize(resizeStationTree);
	// resize the wrapper_div on any window resizes


var FIRST_TIME_OFFSET = 68;
var A_FEW_EXTRA_PIXELS = 3;
var first_resize_station_tree = true;

function resizeStationTree(event,data)
{
    var div_height = parseInt($('#station_tree_div').css('height'));
    var hdr_height = parseInt($('#stations_header_bar').css('height'));
	var use_height = div_height-hdr_height-A_FEW_EXTRA_PIXELS;
	
	if (first_resize_station_tree)
	{
		first_resize_station_tree = false;
		use_height -= FIRST_TIME_OFFSET;
	}
	
	display(dbg_stations,1,'resizeStationTree() div=' + div_height + ' header=' + hdr_height + ' use_height=' + use_height);
	$('#station_tree_wrapper').css('height',use_height+'px');
}



function update_station_tree_bits(id)
	// Called when the edit_station changes.
	// Get a list of all the folders and tracks in the station
	// given by 'id' and then loop through the tree's loaded elements
	// and reset the checkboxes. data is hash of all folders/tracks
	// within the station. Note that the id's for tracks are
	// track_NNN whereas the ids for folders are just NNN
{
	$.get('/webui/explorer/get_station_items?station=' + id,
		function (data)
		{
			var tree = $("#station_tree").fancytree("getTree");
			tree.visit(function(node)
			{
				var extraClass = '';
				var selected = false;
				var value = data[node.key];
				if (value == 1)
				{
					selected = true;
				}
				else if (value == 2)
				{
					extraClass = 'fancytree-partsel';
				}
				node.extraClasses = extraClass;
				node.setSelected(selected);
				node.render(true,true);
			});
		});
}



function onClickEditStationTree(data,node)
{
	if (edit_station && node.targetType == 'checkbox')
	{
		var real_node = node.node;
		var isOn = real_node.selected;
		var set = isOn ? 0 : 1;
		var url ='/webui/station/set_station_bit' +
			 '?station=' + edit_station.station_num +
			 '&item_id=' + real_node.key +
			 '&checked=' + set;
		
		$.get(url,function(result)
		{
			if (result.error)
			{
				rerror("result from server: " + result.error);
				return false;
			}
			return true;
		});
		
	}
	return true;
}



//----------------------------------------------------------
// set_context_stations()
//----------------------------------------------------------

function set_context_stations(context)
{
	display(0,0,'set_context_stations(' + context + ') called');

	if (current_renderer &&
		current_renderer.station)
	{
		edit_station = current_renderer.station;
	}

	$.get('/webui/explorer/get_id_path' +
		  '?track_id='+context,

		function(result)
		{
			if (result.error)
			{
				rerror('Error in set_context_stations(): ' + result.error);
			}
			else
			{
				display(0,1,"id_path='" + result.id_path + "'");
				var tree = $('#station_tree').fancytree('getTree');
				var last_node;
				
				tree.loadKeyPath(result.id_path, function(node, status)
				{
					display(0,2,"Node ["+node.title+"] status ["+status+"]");
					if (status == "loading")
					{
						node.data.shouldPromptForFilter=false;
					}
					else if (status == "loaded")
					{
						display(0,2,"intermediate node " + node);
					}
					else if (status == "ok")
					{
						// node.setExpanded(true);
						// node.setActive(true);
						last_node = node;
					}
				});
				

				last_node.makeVisible({scrollIntoView: true});
				last_node.setActive(true);
			}
		});
}



//------------------------------------------------------
// pane_station_info handling
//------------------------------------------------------

function get_station_for_info()
	// in the renderer page, we show and act upon the
	// current_renderer.station. in the station page we
	// act up on the edit_station
{
	var station = false;
	if (current_page == 'renderer')
	{
		if (current_renderer &&
			current_renderer.station)
		{
			station = current_renderer.station;
		}
	}
	else
	{
		station = edit_station;
	}
	return station;
}
	


function init_pane_station_info()
{
	display(dbg_stations,0,"onload_pane_station_info(" + current_page + ")");
	var use_id = '#' + current_page + '_station_info_';
	
	$( use_id + 'div' ).buttonset({
		disabled:true,
	});
	
	$( use_id + 'slider' ).slider({
		disabled:true,
		
		stop: function( event, ui ) {
			station_set_info('track_index', ui.value);
		},
		start: function( event, ui ) {
			in_station_info_slider = true;
		},
		slide: function( event, ui ) {
			$( use_id + 'track_num').spinner('value',ui.value);
		},
	});

	
	$( use_id + 'track_num' ).spinner({
		// disabled:true,
		width:20,
		min:0,
		max:0,
		
		spin: function(event, ui) {
			$( use_id + 'slider').slider('value',ui.value);
		},
		start: function( event, ui ) {
			in_station_info_spinner = true;
		},
		stop: function( event, ui ) {
			if (!in_station_info_slider)
			{
				in_station_info_spinner	= false;
				var value = $( use_id + 'track_num').spinner('value');
				station_set_info('track_index', value);
			}
		},
	});
	
	update_station_info_ui();

}



function update_station_info_ui()
{
	display(dbg_stations,0,"update_station_info_ui(" + current_page + ")");
	var use_id = '#' + current_page + '_station_info_';
 
	var show_num = 'No station selected';
	var shuffle = 0;
	var unplayed_first = false;
	var track_num = 0;
	var num_tracks = 0;
	var min_track = 0;
	var disable = true;

	var station = get_station_for_info();
	
	if (station)
	{
		show_num = 'Station ' + station.station_num + ' - ' + station.name;
		shuffle = parseInt(station.shuffle);
		unplayed_first = parseInt(station.unplayed_first);
		track_num = parseInt(station.track_index);
		num_tracks = parseInt(station.num_tracks);
		min_track = num_tracks ? 1 : 0;
		disable = false;
	}

	// enable disable all the controls

	$(use_id + 'slider').slider( disable?'disable':'enable');
	$(use_id + 'shuffle_off').button({disabled:disable});
	$(use_id + 'shuffle_tracks').button({disabled:disable});
	$(use_id + 'shuffle_albums').button({disabled:disable});
	$(use_id + 'unplayed_first').button({disabled:disable});
	
	// set the values
	
	$(use_id + 'station_num').html(show_num);
	$(use_id + 'shuffle_off').prop('checked',(shuffle==0)).button('refresh').blur();
	$(use_id + 'shuffle_tracks').prop('checked',(shuffle==1)).button('refresh').blur();
	$(use_id + 'shuffle_albums').prop('checked',(shuffle==2)).button('refresh').blur();
	$(use_id + 'unplayed_first').prop('checked',unplayed_first).button('refresh').blur();
	$(use_id + 'num_tracks').html(num_tracks);
	$(use_id + 'slider').slider('option','min',min_track);
	$(use_id + 'slider').slider('option','max',num_tracks);

	$(use_id + 'track_num').spinner('option','min',min_track);
	$(use_id + 'track_num').spinner('option','max',num_tracks);
	
	if (!in_station_info_spinner &&
		!in_station_info_slider)
	{
		$(use_id + 'slider').slider('value',track_num);
		$(use_id + 'track_num').spinner('value',track_num);
	}
}



// EDIT STATION ACTIONS
//
// Changing the shuffle, unplayed_first, dropping the slider,
// or the spinner losing focus all constitute 'station changing'
// actions.
//
// There are going to be a lot of issues.
//
// This brings to light changes made via different UI's ..
// we handle the obvious renderer/station_num changes, but
// don't asynchrously update other clients (and are not updated)
// when the songs within a station change, or the characteristics
// of a station change (except in the special case of the current
// playing station).
//
// In any case, these actions call the server to update the station
// descriptor.  At this time it is upto the engine to REGENERATE
// THE STATION SONGLIST.
//
// I envision that, in regenerating the songlist, that the engine
// will try to preserve the currently playing song. That is, by
// default, it will search the newly generated list for the old
// "current" song, and will set it's track_index appropriately if
// found.  The user generally has the choice of using the slider
// to reset the track_number to 1 in these cases.
//
// The currently playing station will then proceed with the next
// song after the current one has stopped playing.


function station_set_info(field,value,obj)
{
	if (obj)
	{
		obj.blur();
	}
	
	var station = get_station_for_info();
	if (!station)
	{
		rerror("attempt to set shuffle('+shuffle+') without a station");
		return false;
	}
	
	if (field == 'unplayed_first')
	{
		// toggle the value
		value = station.unplayed_first ? 0 : 1;
	}
	
	$.get('/webui/station/set_station_info' +
		'?station=' + station.station_num +
		'&field=' + field +
		'&value=' + value,
		
		function(result) {
			
			in_station_info_slider = false;

			if (result.error)
			{
				rerror('station_set_info('+what+','+value+'):' + result.error);
				return false;
			}
			
			station[field] = value;
			hide_layout_panes();
			return true;
		});

	return true;
}




// END OF edit_station.js


