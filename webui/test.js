// test.js

var dbg_test = 0;
var PREVENT_DEFAULT = false;

display(dbg_test,0,"test.js loaded");


function copyTouch({ identifier, pageX, pageY })
{
  return { identifier, pageX, pageY };
}



function debug_environment()
{
	debug_remote(0,0,
		"orientation(" + screen.orientation.type + ")" +
		"screen(" + screen.width + "," + screen.height + ") " +
		"iwindow(" + window.innerWidth + "," + window.innerHeight + ") " +
		"owindow(" + window.outerWidth + "," + window.outerHeight + ") " +
		"body(" + $('body').width() + "," + $('body').height() + ")");

	debug_remote(0,0,"ratio(" + window.devicePixelRatio + ")");

	debug_remote(0,0,"navigator " +
		"cookies(" + navigator.cookieEnabled + ") " +
		"platform(" + navigator.platform + ") " +
		"appVersion(" + navigator.appVersion + ") " +
		"ua(" + navigator.userAgent + ") ");

	var touchPoints = navigator.maxTouchPoints;
	if (touchPoints == undefined)
		touchPoints = 'undefined';

	debug_remote(0,0,"touchPoints = " + touchPoints);
}



//========================================================
// Main
//========================================================


$(function() { init_touch_test() });


function init_touch_test()
{
	display(dbg_test,0,"START init_touch_test()");

	var body = document.body;
	body.addEventListener("touchstart", handleStart);
	body.addEventListener("touchend", handleEnd);
	body.addEventListener("touchcancel", handleCancel);
	body.addEventListener("touchmove", handleMove);

	display(dbg_test,0,"FINISHED init_touch_test()");
}


const ongoingTouches = [];


function handleStart(evt)
{
	if (PREVENT_DEFAULT)
		evt.preventDefault();
	const touches = evt.changedTouches;
	for (let i = 0; i < touches.length; i++)
	{
		var len = ongoingTouches.length;
		var touch = touches[i];
		display(dbg_test,0,"-->(" + len + ") touchstart(" + i + ":" + touch.identifier + ") = " + touch.clientX + "," + touch.clientY);
		ongoingTouches.push(copyTouch(touch));
	}
}


function handleMove(evt)
{
	if (PREVENT_DEFAULT)
		evt.preventDefault();
	const touches = evt.changedTouches;
	for (let i = 0; i < touches.length; i++)
	{
		var touch = touches[i];
		const idx = ongoingTouchIndexById(touch.identifier);
		if (idx >= 0)
		{
			display(dbg_test,0,"handleMove(" + i + "=" + idx + ":" + touch.identifier + ") = " + touch.clientX + "," + touch.clientY);
			ongoingTouches.splice(idx, 1, copyTouch(touches[i])); // swap in the new touch record
		}
		else
		{
			display(dbg_test,"can't figure out which touch to continue");
		}
	}
}


function handleEnd(evt)
{
	if (PREVENT_DEFAULT)
		evt.preventDefault();
	const touches = evt.changedTouches;

	for (let i = 0; i < touches.length; i++)
	{
		var touch = touches[i];
		let idx = ongoingTouchIndexById(touch.identifier);
		if (idx >= 0)
		{
			display(dbg_test,0,"handleEnd(" + i + "=" + idx + ":" + touch.identifier + ") = " + touch.clientX + "," + touch.clientY);

			ongoingTouches.splice(idx, 1); // remove it; we're done
		}
		else
		{
			display(dbg_test,0,"can't figure out which touch to end");
		}
	}
}


function handleCancel(evt)
{
	if (PREVENT_DEFAULT)
		evt.preventDefault();
	display(dbg_test,0,"touchcancel.");
	const touches = evt.changedTouches;

	for (let i = 0; i < touches.length; i++)
	{
		var touch = touches[i];
		let idx = ongoingTouchIndexById(touch.identifier);
		display(dbg_test,0,"handleCancel(" + i + "=" + idx + ":" + touch.identifier + ") = " + touch.clientX + "," + touch.clientY);

		ongoingTouches.splice(idx, 1); // remove it; we're done
	}
}




function ongoingTouchIndexById(idToFind)
{
	for (let i = 0; i < ongoingTouches.length; i++)
	{
		const id = ongoingTouches[i].identifier;
		if (id === idToFind)
		{
			return i;
		}
	}
	return -1; // not found
}
