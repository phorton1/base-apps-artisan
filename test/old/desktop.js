//----------------------------------------------------
// desktop.js
//----------------------------------------------------
// Contains code specific to the desktop that is
// not in any pane specific files (i.e. renderer.js).
//
// The page identifiers give an html page to be loaded according
// to the expression '/webui/desktop_' + page_id + '.html'. Thus
// 'page1' will load /webui/desktop_page1.html

var default_page = 'page1';
	// the default page loaded at startup 
var current_page = ''
	// the currently loaded page (without the /webui/desktop_ prefix)
	
	
//-----------------------------------------------
// initialization
//-----------------------------------------------
// the jquery syntax of $(function() {...}) is the equivilant
// of $(document.body).ready(function() {...}) and is used
// in place of an explicit body_onload() function that could
// be set with <body onload='javascript:body_onload()'>

$(function(){
	desktop_onload();
});

    
function desktop_onload()
{
	// alert('desktop_onload(1)');
	load_page(default_page);
	// alert('desktop_onload(2)');
}



//-----------------------------------------------
// load_page
//-----------------------------------------------

function load_page(page_id)
	// load the page into the artisan_body div, and call
	// the resize method on the document_body div to lay it out
{
	// $('#artisan_body').panel('refresh','/webui/test2.html');
	$('#artisan_body').panel('refresh','/webui/desktop_' + page_id + '.html');
	$('#document_body').layout('resize', {width:'100%', height:'100%' });
	current_page = page_id;
}
