// touch.js
//
// handle double touches and ctrl selection on fancy-trees.



var dbg_touch = 1;

var WITH_TOUCH = true;
	// init_touch() will be called if IS_TOUCH and this
var PREVENT_DEFAULT = false;

display(dbg_touch,0,"touch.js loaded");



const cur_touches = [];
var touch_target1 = false;
	// first two-touch touch-end target


//-----------------------------------
// init
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
	if (dbg_touch > 0)
		return;

	display(dbg_touch+1,1,"start " +
		"page(" + start.pageX + "," + start.pageY + ") " +
		"client(" + start.clientX + "," + start.clientY + ")" +
		"target(" + start.target + ")");
	display(dbg_touch+1,1,"end   " +
		"page(" + end.pageX + "," + end.pageY + ") " +
		"client(" + end.clientX + "," + end.clientY + ")" +
		"target(" + end.target + ")");

	var target = end.target;
	var tables = $(target).closest('table');
	display(dbg_touch+1,0,"tables = " + tables);
	var id = tables[0].id;
	display(dbg_touch+1,0,"id = " + id);

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
					handleDoubleTouch(touch_target1,touch_target2);
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




//--------------------------------------------------
// handleDoubletouch
//--------------------------------------------------
// Called on touchEnd of double touch.
// It is considered a double touch if in the same tree.
// Assumes the fancytrees are tables.

function fancyTreeId(target)
{
	var tables = $(target).closest('table');
	var id = tables[0].id;
	return id;
}



function handleDoubleTouch(touch_target1,touch_target2)
	// if the two targets are in the same tree, do the multi-select
	// explorer_tree targets are <spans>, tracklist are td's
{
	var tree_id1 = fancyTreeId(touch_target1);
	var tree_id2 = fancyTreeId(touch_target2);
	display(dbg_touch+1,0,"handleDoubleTouch(" + tree_id1 + "," + tree_id2 + ")");

	if (tree_id1 == tree_id2)
	{
		// put them in top down order

		display(dbg_touch+1,0,"tagName(" + tree_id1 + ") one(" +
			touch_target1.offsetTop + ") two(" +
			touch_target2.offsetTop + ")");
		if (touch_target2.offsetTop < touch_target1.offsetTop)
		{
			var temp = touch_target1;
			touch_target1 = touch_target2;
			touch_target2 = temp;
		}

		multiTouchSelect(
			tree_id1,
			touch_target1.offsetTop,
			touch_target2.offsetTop);
	}
	else
	{
		display(dbg_touch+1,0,"ignoring double touch to different target types");
	}
}




function multiTouchSelect(tree_id,top1,top2)
{
	display(dbg_touch+1,0,"multiTouchSelect(" + tree_id + ") top1(" + top1 + ") top2(" + top2 + ")");

	var tree = $('#' + tree_id).fancytree("getTree");
	if (tree.onTreeSelect)
		tree.onTreeSelect();

	// still have to make an assumption about LI's in 'trees'
	// and TR's in 'tables'

	tree.visit(function (node) {
		var top = tree_id == 'explorer_tree'  ?
			node.li.offsetTop :
			node.tr.offsetTop;
		if (top >= top1 && top <= top2)
		{
			node.setSelected(true);
		}

	});
}





