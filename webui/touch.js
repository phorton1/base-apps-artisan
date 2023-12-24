// unused_touch.js
//
// Contains routines I WAS going to use to implement multi-touch
// gestures on touch devies, and my implementation of fancytree
// 'double click' that does not first call 'click'.
//
// Kept for posterities sake, I did not like the complexity,
// and particularly delving into jquery/fancytree internals.


var dbg_touch = 1;

var WITH_TOUCH = true;
	// init_touch() will be called if IS_TOUCH and this
var PREVENT_DEFAULT = false;

display(dbg_touch,0,"touch.js loaded");



const cur_touches = [];
var touch_target1 = false;
	// first two-touch touch-end target

//-----------------------------------
// main
//-----------------------------------

function init_touch(id)
{
	if (!WITH_TOUCH)
		return;
	display(dbg_touch,0,"init_touch(" + id + ")");

	var ele = document.getElementById(id);
	if (ele)
	{
		ele.addEventListener("touchstart", touchStart);
		ele.addEventListener("touchend", touchEnd);
		ele.addEventListener("touchcancel", touchCancel);
		display(dbg_touch,0,"init_touch(" + id + ") finished");
	}
	else
	{
		error("Could not init_touch(" + id + ")");
	}
}



function debugTouch(start,end)
{
	display(dbg_touch+1,1,"start " +
		"page(" + start.pageX + "," + start.pageY + ") " +
		"client(" + start.clientX + "," + start.clientY + ")" +
		"target(" + start.target + ")");
	display(dbg_touch+1,1,"end   " +
		"page(" + end.pageX + "," + end.pageY + ") " +
		"client(" + end.clientX + "," + end.clientY + ")" +
		"target(" + end.target + ")");
}


function handleDoubleTouich(touch_target1,touch_target2)
	// if the two targets are in the same tree, do the multi-select
	// explorer_tree targets are <spans>, tracklist are td's
{
	if (touch_target1.tagName == touch_target2.tagName)
	{
		// put them in top down order

		display(dbg_touch+1,0,"tagName(" + touch_target1.tagName + ") one(" +
			touch_target1.offsetTop + ") two(" +
			touch_target2.offsetTop + ")");
		if (touch_target2.offsetTop < touch_target1.offsetTop)
		{
			var temp = touch_target1;
			touch_target1 = touch_target2;
			touch_target2 = temp;
		}

		// call explorer.js multiSelect()

		multiTouchSelect(
			touch_target1.tagName == 'SPAN',
			touch_target1.offsetTop,
			touch_target2.offsetTop);
	}
	else
	{
		display(dbg_touch+1,0,"ignoring double touch to different target types");
	}
}



//-----------------------------------
// event handlers
//-----------------------------------

function touchStart(evt)
{
	if (PREVENT_DEFAULT)
		evt.preventDefault();
	const touches = evt.changedTouches;
	for (let i = 0; i < touches.length; i++)
	{
		var len = cur_touches.length;
		const touch = touches[i];
		display(dbg_touch+1,0,"-->(" + len + ") touchStart(" + i + ":" + touch.identifier + ")");
		cur_touches.push(copyTouch(touch));
	}
}


function touchMove(evt)
{
	if (PREVENT_DEFAULT)
		evt.preventDefault();
	const touches = evt.changedTouches;
	for (let i = 0; i < touches.length; i++)
	{
		const touch = touches[i];
		const idx = touchById(touch.identifier);
		if (idx >= 0)
		{
			display(dbg_touch+1,0,"touchMove(" + i + "=" + idx + ":" + touch.identifier + ") = " + touch.clientX + "," + touch.clientY);
			cur_touches.splice(idx, 1, copyTouch(touches[i])); // swap in the new touch record
		}
		else
		{
			error("No idx in touchMove");
		}
	}
}


function touchEnd(evt)
{
	if (PREVENT_DEFAULT)
		evt.preventDefault();
	const touches = evt.changedTouches;
	for (let i = 0; i < touches.length; i++)
	{
		const touch = touches[i];
		let idx = touchById(touch.identifier);
		if (idx >= 0)
		{
			const prev_touch = cur_touches[idx];
			display(dbg_touch+1,0,"<--(" + idx + ") touchEnd(" + i + ":" + touch.identifier + ")");
			debugTouch(prev_touch,touch);

			// if ending touch with two points, we consider it a multi-selection.
			// I notice that prev_touch always has target=undefined, presumably
			// because the initial touch is not resolved to a node. The current
			// touch DOES have a target, but even so, that means that we must wait
			// for both touches to end before considering for multi-selection.

			if (cur_touches.length == 2)
			{
				touch_target1 = touch.target;
				display(dbg_touch,0,"touch_target1(" + touch_target1 + ") html=" + touch_target1.innerHTML);
			}
			else
			{
				if (touch_target1)
				{
					var touch_target2 = touch.target;
					display(dbg_touch,0,"touch_target2(" + touch_target2 + ") html=" + touch_target2.innerHTML);
					handleDoubleTouich(touch_target1,touch_target2);
				}
				touch_target1 = false;
			}

			cur_touches.splice(idx, 1); // remove it; we're done
		}
		else
		{
			error("No idx in touchEnd");
		}
	}
}


function touchCancel(evt)
{
	if (PREVENT_DEFAULT)
		evt.preventDefault();
	const touches = evt.changedTouches;
	for (let i = 0; i < touches.length; i++)
	{
		const touch = touches[i];
		let idx = touchById(touch.identifier);
		if (idx >= 0)
		{
			const prev_touch = cur_touches[idx];
			display(dbg_touch+1,0,"<--(" + idx + ") touchCancel(" + i + ":" + touch.identifier + ")");
			debugTouch(prev_touch,touch);
			cur_touches.splice(idx, 1); // remove it; we're done
		}
		else
		{
			error("No idx in touchEnd");
		}
	}
}


function copyTouch(touch)
{
  return {
	id: touch.identifier,
	pageX: touch.pageX,
	pageY: touch.pageY,
	clientX: touch.clientX,
	clientY: touch.clientY,	};
}


function touchById(id)
{
	for (let i = 0; i < cur_touches.length; i++)
	{
		if (cur_touches[i].id === id)
		{
			return i;
		}
	}
	return -1; // not found
}



//------------------------------------------------------
// UNUSED OLD CODE: Simgle versus Double click handling
//------------------------------------------------------
// We needed to wait and THEN call the default behavior
// A faincytree Mouse Event looks something like this:
//
// 		originalEvent: click
// 		eventPhase: 0
// 		explicitOriginalTarget: span.fancytree-expander
// 		isTrusted: true
// 		layerX: 9
// 		layerY: 12
// 		metaKey: false
// 		movementX: 0
// 		movementY: 0
// 		offsetX: 0
// 		offsetY: 0
// 		originalTarget: span.fancytree-expander
// 		pageX: 13
// 		pageY: 64
// 		rangeOffset: 0
// 		rangeParent: null
// 		relatedTarget: null
// 		returnValue: false
// 		screenX: 518
// 		screenY: 229
// 		shiftKey: false
// 		srcElement: span.fancytree-expander???
// 		target: span.fancytree-expander
// 		timeStamp: 8948



const DBL_CLICK_TIME = 240;
	// 300 ms on same item is a double click


var click_node;
var click_event;
var click_from;


function myClickNode(node)
	// this is some hard-fought-for code to be able to call
	// the original click event from a deferred timer.
	// The ctx is generally necessary to call tree.nodeClick.
	// The targetType is necessary to differntiate clicking
	// on explorer_tree item (title) and clicking on the
	// expander.
{
	var tree = click_node.tree;
	var ctx = tree._makeHookContext(click_node,click_event.originalEvent);
	ctx.node = click_node;
	var res = $.ui.fancytree.getEventTarget(click_event.originalEvent);
	ctx.targetType = res.type;
	tree.nodeClick(ctx);
}



function clickDone()
{
	var node = click_node;
	var rec = node.data;
	var dbg_title = node.title != undefined ?
		node.title : rec.TITLE;

	if (node.doubleclicked)
	{
		display(0,0,"dblClick(" + dbg_title + ") selected=" + node.isSelected());

		// if the item is NOT selected, we send the original event
		// effectively sublimating dblclick to click.

		if (!node.isSelected())
		{
			myClickNode();
		}

		// Finally, 'enqueue' all selected Track from either tree

		enqueuAll(node);

	}
	else
	{
		display(0,0,"click(" + dbg_title + ")");
		myClickNode();

		// this is 'my stuff' that I do on clicking items

		if (click_from == 'tracklist')
		{
			explorer_details.reload({
				url: library_url() + '/track_metadata?id=' + rec.id,
				cache: true});
			deselectTree('explorer_tree');
		}
		if (click_from == 'tree')
		{
			deselectTree('explorer_tracklist');
			update_explorer_ui(node);
		}
	}

	node.doubleclicked = false;
	click_node = undefined;
	click_event = undefined;
	click_from = undefined;
}




function myOnClick(from, event, data)
	// differentiates single from double clicks
	// by returning false to not call fancytree default behavior
	// and then re-sending the event when the time expires
{
	var node = data.node;
	var rec = node.data;

	display(0,0,"myOnClick(" + from + ") " + rec.TITLE );

	// this if statement allows me to test the 'original'
	// selection behavior, albeit without calling 'my stuff'

	if (true)		// call directly
	{
		if (from == 'tracklist')
		{
			explorer_details.reload({
				url: library_url() + '/track_metadata?id=' + rec.id,
				cache: true});
			deselectTree('explorer_tree');
		}
		if (from == 'tree')
		{
			deselectTree('explorer_tracklist');
			update_explorer_ui(node);
		}

		return true;
	}
	else			// call via timer
	{
		if (click_node == undefined ||
			click_node != node)
		{
			node.doubleclicked = false;
			click_node = node;
			click_event = event;
			click_from = from;
			setTimeout(clickDone,DBL_CLICK_TIME);
		}
		else
		{
			node.doubleclicked = true;
		}
		return false;
	}
}
