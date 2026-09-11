// sync.js
//
// The server-owned mode and the Sync command (docs/notes/sync.md).
// Plain javascript, no jquery: this file outlives the rest of the
// old webUI.  It is coupled to artisan.js in exactly two places:
// idle_loop() hands every /webUI/update result to sync_poll(), and
// onSubMenuItem() hands the 'sync' command to sync_command().
//
// The poll carries
//
//    server_start   the time the service started; when it changes
//                   the server has restarted and we reload
//    busy           '', 'sync' or 'update'; while set every browser
//                   shows the cover screen and stops its own renderer
//    sync           the sync block: sync_step, sync_files_done/total,
//                   sync_bytes_done/total, sync_current(_size/_done),
//                   sync_error

var dbg_sync = 0;

var sync_server_start = 0;
var sync_busy_shown = false;
var sync_page_open = false;
var sync_running = false;
var sync_plan = null;
	// the plan shown before start, used for the summary at the end
var sync_last_step = '';
var sync_log = [];
	// one line per step seen, kept on the page until it closes
var sync_started = 0;
	// millis when start was pressed, for the elapsed time
var sync_samples = [];
	// recent [millis, bytes_done] pairs for the rate and the estimate

var SYNC_LIST_MAX = 40;
	// items shown per list in the plan
var SYNC_SAMPLES = 10;


//------------------------------------------------
// the poll
//------------------------------------------------

function sync_poll(result)
	// called with every /webUI/update result.
	// returns true if the page is reloading.
{
	if (result.server_start)
	{
		if (!sync_server_start)
		{
			sync_server_start = result.server_start;
		}
		else if (result.server_start != sync_server_start)
		{
			display(dbg_sync,0,"server restarted - reloading");
			location.reload();
			return true;
		}
	}

	var busy = result.busy || '';
	if (busy && !sync_busy_shown)
	{
		sync_busy_shown = true;
		sync_show_busy(busy);
	}
	else if (!busy && sync_busy_shown)
	{
		sync_busy_shown = false;
		sync_hide_busy();
	}
	if (busy)
		sync_update_busy(busy,result.sync);
	if (sync_page_open)
		sync_update_page(busy,result.sync);
	return false;
}


function sync_show_busy(busy)
{
	display(dbg_sync,0,"busy(" + busy + ")");
	document.querySelector('.cover_screen').style.display = 'block';
	document.getElementById('busy_message').style.display = 'block';

	// stop our own renderer if we are the renderer

	if (typeof current_renderer != 'undefined' &&
		typeof html_renderer != 'undefined' &&
		current_renderer.uuid == html_renderer.uuid)
	{
		audio_command('stop');
	}
}


function sync_hide_busy()
{
	display(dbg_sync,0,"busy cleared");
	document.getElementById('busy_message').style.display = 'none';
	if (!sync_page_open)
		document.querySelector('.cover_screen').style.display = 'none';
}


function sync_update_busy(busy,sync)
{
	var msg = busy + ' in progress';
	if (busy == 'sync' && sync)
	{
		if (sync.sync_step == 'pull')
			msg += ': ' + sync.sync_files_done + ' of ' + sync.sync_files_total + ' files';
		else if (sync.sync_step)
			msg += ': ' + sync.sync_step;
	}
	document.getElementById('busy_message').innerHTML = msg;
}


//------------------------------------------------
// the Sync command
//------------------------------------------------

function sync_command()
	// the Sync item of the System submenu
{
	sync_open_page();
	sync_set_html('sync_body',"planning ...");
	sync_set_buttons(false,false);
	fetch('/sync/plan')
		.then(function(response) { return response.json(); })
		.then(function(plan)
		{
			if (plan.error)
			{
				sync_set_html('sync_body',
					"<div class='sync_error'>" + plan.error + "</div>");
				sync_set_buttons(false,true);
				return;
			}
			sync_show_plan(plan);
		})
		.catch(function(err)
		{
			sync_set_html('sync_body',
				"<div class='sync_error'>plan request failed: " + err + "</div>");
			sync_set_buttons(false,true);
		});
}


function sync_open_page()
{
	sync_page_open = true;
	sync_running = false;
	sync_samples = [];
	document.querySelector('.cover_screen').style.display = 'block';
	document.getElementById('sync_page').style.display = 'block';
}


function sync_close_page()
{
	sync_page_open = false;
	document.getElementById('sync_page').style.display = 'none';
	if (!sync_busy_shown)
		document.querySelector('.cover_screen').style.display = 'none';
}


function sync_set_html(id,html)
{
	document.getElementById(id).innerHTML = html;
}


function sync_set_buttons(can_start,can_close,can_restart)
{
	document.getElementById('sync_start').style.display = can_start ? 'inline-block' : 'none';
	document.getElementById('sync_close').style.display = can_close ? 'inline-block' : 'none';
	document.getElementById('sync_restart').style.display = can_restart ? 'inline-block' : 'none';
	document.getElementById('sync_cancel').style.display = sync_running ? 'inline-block' : 'none';
}


function sync_bytes_str(bytes)
{
	if (bytes >= 1000000000)
		return (bytes / 1000000000).toFixed(2) + ' GB';
	if (bytes >= 1000000)
		return (bytes / 1000000).toFixed(1) + ' MB';
	if (bytes >= 1000)
		return (bytes / 1000).toFixed(0) + ' KB';
	return bytes + ' bytes';
}


function sync_escape(str)
	// the server's json already renders non-ascii characters in
	// paths as html entities, so & is left alone
{
	return String(str)
		.replace(/</g,'&lt;')
		.replace(/>/g,'&gt;');
}


function sync_todo(html,todo)
	// things that make the plan do something are shown in yellow
{
	return todo ? "<span class='sync_todo'>" + html + "</span>" : html;
}


function sync_list_html(title,list,fn)
{
	var html = "<div class='sync_list_title'>" +
		sync_todo(title + " (" + list.length + ")",list.length) + "</div>";
	if (!list.length)
		return html;
	html += "<div class='sync_list'>";
	var n = Math.min(list.length,SYNC_LIST_MAX);
	for (var i = 0; i < n; i++)
		html += sync_escape(fn(list[i])) + "<br>";
	if (list.length > n)
		html += "... and " + (list.length - n) + " more<br>";
	html += "</div>";
	return html;
}


function sync_show_plan(plan)
{
	var html = "<div class='sync_summary'>";
	html += "source " + sync_escape(plan.source) + "<br>";
	html += sync_todo(plan.files + " files to transfer, " + sync_bytes_str(plan.bytes),plan.files) + "<br>";
	html += sync_todo("artisan.db " + (plan.data.db ? "differs" : "same"),plan.data.db) + ", " +
		sync_todo("playlists.txt " + (plan.data.playlists ? "differs" : "same"),plan.data.playlists);
	html += "</div>";

	html += sync_list_html("add",plan.add,function(a) { return a.path; });
	html += sync_list_html("rename",plan.rename,function(r) { return r.from + " -> " + r.to; });
	html += sync_list_html("remove",plan.remove,function(p) { return p; });
	html += sync_list_html("art add",plan.art_add,function(a) { return a.path; });
	html += sync_list_html("art remove",plan.art_remove,function(p) { return p; });

	var nothing =
		!plan.add.length && !plan.rename.length && !plan.remove.length &&
		!plan.art_add.length && !plan.art_remove.length &&
		!plan.data.db && !plan.data.playlists;
	if (nothing)
		html += "<div class='sync_summary'>nothing to do</div>";

	sync_plan = plan;
	sync_set_html('sync_body',html);
	sync_set_buttons(!nothing,true,false);
}


function sync_start()
{
	sync_running = true;
	sync_samples = [];
	sync_log = [];
	sync_last_step = '';
	sync_started = Date.now();
	sync_set_buttons(false,false,false);
	sync_set_html('sync_body',"starting ...");
	fetch('/sync/start')
		.then(function(response) { return response.json(); })
		.then(function(result)
		{
			if (result.error)
			{
				sync_running = false;
				sync_set_html('sync_body',
					"<div class='sync_error'>" + result.error + "</div>");
				sync_set_buttons(false,true,false);
			}
		});
}


function sync_cancel()
{
	fetch('/sync/cancel');
}


function sync_restart()
	// after done: restart the service; the page reloads
	// when the poll sees the new server_start
{
	sync_set_buttons(false,false,false);
	sync_log.push("restarting the service; this page reloads when it is back");
	sync_set_html('sync_body',sync_log_html());
	fetch('/sync/restart');
}


function sync_log_html()
{
	var html = "<div class='sync_log'>";
	for (var i = 0; i < sync_log.length; i++)
		html += sync_log[i] + "<br>";
	html += "</div>";
	return html;
}


function sync_elapsed_str()
{
	var secs = Math.floor((Date.now() - sync_started) / 1000);
	var hours = Math.floor(secs / 3600);
	var mins = Math.floor((secs % 3600) / 60);
	secs = secs % 60;
	var parts = [];
	if (hours) parts.push(hours + (hours == 1 ? " hour" : " hours"));
	if (hours || mins) parts.push(mins + (mins == 1 ? " minute" : " minutes"));
	parts.push(secs + (secs == 1 ? " second" : " seconds"));
	return parts.join(", ");
}


function sync_files_str(sync)
	// "30 tracks and 2 art files", from the plan when we have it
{
	var plan = sync_plan;
	if (!plan)
		return sync.sync_files_total + " files";
	var tracks = plan.add.length;
	var art = plan.art_add.length;
	var str = tracks + (tracks == 1 ? " track" : " tracks");
	if (art)
		str += " and " + art + (art == 1 ? " art file" : " art files");
	return str;
}


function sync_step_line(step,sync)
	// the log line for a step as it is first seen
{
	var plan = sync_plan;
	if (step == 'fetch')
		return "fetching the librarian's artisan.db and playlists.txt";
	if (step == 'plan')
		return "planning";
	if (step == 'pull')
		return "pulling " + sync_files_str(sync) + ", " + sync_bytes_str(sync.sync_bytes_total);
	if (step == 'place')
		return "placing " + sync.sync_files_done + " files";
	if (step == 'rename')
		return "renaming " + (plan ? plan.rename.length : '') + " tracks";
	if (step == 'remove')
		return "removing " + (plan ? plan.remove.length + " tracks, " + plan.art_remove.length + " art files" : '');
	if (step == 'data')
	{
		if (!plan) return "replacing data files";
		var what = [];
		if (plan.data.playlists) what.push("playlists.txt");
		if (plan.data.db) what.push("artisan.db");
		return what.length ? "replacing " + what.join(" and ") : "data files unchanged";
	}
	if (step == 'done')
		return "<span class='sync_todo'>done: " + sync_files_str(sync) + ", " +
			sync_bytes_str(sync.sync_bytes_done) + " transferred in " + sync_elapsed_str() +
			"; press restart to finish</span>";
	return step;
}


function sync_bar_html(cls,done,total)
{
	var pct = total ? Math.floor(100 * done / total) : 0;
	if (pct > 100) pct = 100;
	return "<div class='sync_bar " + cls + "'><div class='sync_bar_fill' style='width:" + pct + "%'></div></div>";
}


function sync_update_page(busy,sync)
	// called from the poll while the page is open
{
	if (!sync_running)
		return;
	if (!sync)
		return;

	var step = sync.sync_step || '';

	// the log: one line per step, appended as each is first seen.
	// steps that pass between two polls are filled in from the
	// order they run in, so nothing is skipped.

	if (step && step != sync_last_step)
	{
		var steps = ['fetch','plan','pull','place','rename','remove','data','done'];
		var from = steps.indexOf(sync_last_step) + 1;
		var to = steps.indexOf(step);
		for (var i = from; i <= to; i++)
			sync_log.push(sync_step_line(steps[i],sync));
		sync_last_step = step;
	}

	var html = sync_log_html();

	if (sync.sync_error)
	{
		sync_running = false;
		html += "<div class='sync_error'>stopped in " + step + ": " +
			sync_escape(sync.sync_error) + "</div>";
		html += "<div class='sync_summary'>" + sync.sync_files_done + " of " +
			sync.sync_files_total + " files were transferred; " +
			"run Sync again to continue</div>";
		sync_set_html('sync_body',html);
		sync_set_buttons(false,true,false);
		return;
	}

	if (step == 'pull')
	{
		var done = sync.sync_bytes_done;
		var total = sync.sync_bytes_total;

		// rate and estimate from the recent samples

		sync_samples.push([Date.now(),done]);
		if (sync_samples.length > SYNC_SAMPLES)
			sync_samples.shift();
		var rate = 0;
		if (sync_samples.length > 1)
		{
			var first = sync_samples[0];
			var last = sync_samples[sync_samples.length - 1];
			var secs = (last[0] - first[0]) / 1000;
			if (secs > 0)
				rate = (last[1] - first[1]) / secs;
		}
		var eta = '';
		if (rate > 0)
		{
			var remain = Math.floor((total - done) / rate);
			eta = remain >= 60 ?
				"about " + Math.ceil(remain / 60) + " minutes" :
				"about " + remain + " seconds";
		}

		html += "<div class='sync_progress'>" +
			sync.sync_files_done + " of " + sync.sync_files_total + " files, " +
			sync_elapsed_str() + ", " +
			sync_bytes_str(done) + " of " + sync_bytes_str(total) +
			(rate ? ", " + sync_bytes_str(rate) + "/s, " + eta : "") +
			"</div>";
		html += sync_bar_html('sync_bar_total',done,total);
		if (sync.sync_current)
		{
			html += "<div class='sync_progress'>" + sync_escape(sync.sync_current) + "</div>";
			html += sync_bar_html('sync_bar_file',sync.sync_current_done,sync.sync_current_size);
		}
	}
	sync_set_html('sync_body',html);
	if (step == 'done')
	{
		sync_running = false;
		sync_set_buttons(false,false,true);
	}
	else
		sync_set_buttons(false,false,false);
}
