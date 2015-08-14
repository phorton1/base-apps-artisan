

$('#artisan_menu').ready(function(){
	
	$('#artisan_menu').resize(function(e){artisan_menu_resize(e)});
	
});


function artisan_menu_resize(e)
{
	alert('artisan_menu_resize');
}




function on_artisan_menu_mouseover(id)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		ele.oldClass = ele.className;
		ele.className = 'artisan_menu_hover';
	}
}
function on_artisan_menu_mouseout(id)
{
	var ele = document.getElementById(id);
	if (ele)
	{
		if (ele.className == 'artisan_menu_hover')
		{
			ele.className = ele.oldClass;
		}
	}
}



function select_renderer(id)
{
	hide_artisan_menu();
	
	if (false)
	{
		var name = 'No Renderer Selected';
		if (id)
		{
			var ele = document.getElementById('renderer_' + id);
			if (ele)
			{
				name = ele.innerHTML;
			}
		}
		
		ele_set_inner_html('renderer_header_right',name);
	
		highlight_selected_item('artisan_menu_renderer_div','renderer_' + id);
	}
	
	$.get('/webui/renderer/select_renderer(' + id + ')', function(result)
	{
		if (result.error)
		{
			rerror('Error in on_select_renderer(): ' + result.error);
			current_renderer = false;
		}
		else
		{
			current_renderer = result;
		}
		update_renderer_ui();
	});
}




function select_station(station_num)
{
	hide_artisan_menu();
	var station_id = 'station_' + station_num;
	// highlight_selected_item('artisan_menu_stations',station_id);
	return transport_command(station_id);
}




function clear_selected_menu_items(parent_id)
{
	var ele = document.getElementById(parent_id);
	if (ele)
	{
		var eles = ele.getElementsByClassName('artisan_menu_selected');
		if (eles)
		{
			for (var i=0; i<eles.length; i++)
			{
				eles[i].className = 'artisan_menu_item';
			}
		}
	}
}


function highlight_selected_item(parent_id,id)
{
	var ele = document.getElementById(id);
	
	if (!id || ele.className != 'artisan_menu_selected')
	{
		clear_selected_menu_items(parent_id);
	}
	if (ele)
	{
		ele.className = 'artisan_menu_selected';
	}
}





function new_highlight_current_renderer()
{
	var id;
	var station;
	return;
	if (current_renderer)
	{
		id = 'renderer_' + current_renderer.id;
		if (current_renderer.station > 0)
		{
			station = 'station_' + current_renderer.station;
		}
	}

	highlight_selected_item('artisan_menu_renderer_div',id);
	highlight_selected_item('artisan_menu_stations',station);
}

