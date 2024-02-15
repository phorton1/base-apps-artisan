#-----------------------------------------
# WebUI.pm
#-----------------------------------------
# The webUI is a javascript application based
# on the EasyUI and JQuery libraries.
#
# There is a single persistent page loaded intos
# the browser, artisan.html, that drives all other
# requests.
#
# The application is Pane based, and typically requests
# are of two kinds - a request to return the html associated
# with a pane, and JSON requests to provide data for the
# pane in XML format.
#
# The UI dispataches it's calls to modules that are
# associated with the Panes (i.e. uiRenderer.pm).
# Sometimes these modules have an associated lower
# level 'real' object (i.e. Renderer.pm) that provides
# more complicated functionality.

package WebUI;
use strict;
use warnings;
use threads;
use threads::shared;
use Date::Format;
use Pub::HTTP::Response;
use artisanUtils;
use Device;
use DeviceManager;
use uiLibrary;
use Queue;
use Update;
use if !is_win, 'linuxAudio';


my $dbg_webui = 1;
	# 0 = show basic calls
	# -1 = show building of html files with js and css
	# -2 = show fancytree scaling pct
my $dbg_post_params = 0;
	# specific to get_queue_tracks call


my $SEND_MINIFIED_JS_AND_CSS = 0;
	# I spent over an hour trying to figure out how JS was getting minified
	# when I am loading the unminified versions ins artisan.html, only to discover
	# that I myself am loading the min files if they exist, sheesh.


# old reminder of the user agents from various devices
#
# my $ua1 = 'Mozilla/5.0 (Windows NT 6.3; WOW64; rv:24.0) Gecko/20100101 Firefox/24.0';
	# firefox on laptop  1600x900
# my $ua2 = 'Mozilla/5.0 (iPad; CPU OS 5_1 like Mac OS X) AppleWebKit/534.46 (KHTML, like Gecko ) Version/5.1 Mobile/9B176 Safari/7534.48.3';
	# android dongle.  I think it's 1280x768
# my $ua3a = 'Mozilla/5.0 (Linux; U; Android 4.2.2; en-us; rk30sdk Build/JDQ39) AppleWebKit/534.30 (KHTML, like Gecko) Version/4.0 Mobile Safari/534.30';
# my $ua3b = 'Mozilla/5.0 (Linux' Android 4.4.2; GA10H BuildKVT49L) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39  Mobile Safari...';
	# car stereo;  534x320
# my $ua4 = 'Mozilla/5.0 (Linux' Android 4.4.2; GA10H BuildKVT49L) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/3 ?? ?? ';
	# new 16G tablet. 900x1600


#--------------------------------------
# webUI request dispatcher
#--------------------------------------
# NEW syntax of update is
#	/webui/update?update_id=$update_id&renderer_uuid=$renderer_uuid


sub webui_request
{
	my ($request,$path) = @_;
	my $params = $request->{params};
	my $use_dbg = $dbg_webui + $request->{extra_debug};

	display_hash($use_dbg,0,"webui_request($path)",$params);

	my $response;
	if ($path =~ s/^debug_output\///)
	{
		my $color = $path =~ /^ERROR/ ?
			$DISPLAY_COLOR_ERROR :
			$UTILS_COLOR_LIGHT_GREEN;

		Pub::Utils::_setColor($color);
		print "REMOTE: ".url_decode($path)."\n";
		Pub::Utils::_setColor($DISPLAY_COLOR_NONE);
		$response = html_ok($request,"OK");
	}

	# device requests

	elsif ($path =~ /^getDevices\/(renderer|library)$/)
	{
		my $what = $1;
		$response = getDevicesJson($request,$what);
	}
	elsif ($path =~ /^getDevice\/(renderer|library)-(.*)$/)
	{
		my ($singular,$uuid) = ($1,$2);
		$response = getDeviceJson($request,$singular,$uuid);
	}


	# NEW UPDATE SYNTAX

	elsif ($path eq 'update')
	{
		my $update_id = $params->{update_id} || 0;
		return json_error($request,"No update_id in UPDATE call")
			if !$update_id;

		# The HTML Renderer can call without a UUID at this time

		my $renderer_uuid = $params->{renderer_uuid} || '';
		warning($use_dbg,0,"No renderer_uuid in UPDATE call!")
			if !$renderer_uuid;

		my $data = {
			update_id => $system_update_id };

		$data->{libraries} = getDevicesData($DEVICE_TYPE_LIBRARY)
			if $update_id != $system_update_id;

		if ($renderer_uuid)
		{
			my $renderer = findDevice($DEVICE_TYPE_RENDERER,$renderer_uuid);
			return json_error($request,"could not find renderer '$renderer_uuid'")
				if !$renderer;

			my $error = $renderer->doCommand('update',$params);

			return json_error($request,"renderer_request($path) error: $error")
				if $error;
			$data->{renderer} = $renderer;
		}

		$response = json_response($request,$data);
	}

	# dispatch renderer request directly to object
	# note that actual playlist commands take place
	# on the renderer ...
	#
	# renderer/update is no longer called.

	elsif ($path =~ s/^renderer\///)
	{
		return json_error($request,"could not find renderer uuid in '$path'")
			if $path !~ s/^(.*?)\///;
		my $uuid = $1;

		# Get the renderer, do the command, return error if it fails,
		# or return the render as json if it succeeds.

		my $renderer = findDevice($DEVICE_TYPE_RENDERER,$uuid);
		return json_error($request,"could not find renderer '$uuid'")
			if !$renderer;
		my $error = $renderer->doCommand($path,$params);
		return json_error($request,"renderer_request($path) error: $error")
			if $error;
		$response = json_response($request,$renderer);
	}

	# pass library requests to PM sub module

	elsif ($path =~ s/^library\///)
	{
		# my $post_params = $path =~'get_queue_tracks' ? my_decode_json($post_data) : '';
		# display_hash($dbg_post_params,0,"decoded post_params",$post_params) if $path =~ 'get_queue_tracks';
		$response = uiLibrary::library_request($request,$path);	#,$params,$post_params);
	}

	# queue request

	elsif ($path =~ /^queue\/(.*)$/)
	{
		my $command = $1;
		my $request_json = $request->get_decoded_content();
			# my_decode_json($post_data);
		my $json = Queue::queueCommand($command,$request_json);
		$response = json_response($request,$json);
	}

	# get/set linux audio device
	# This stuff *might* go directly in the HTTP Server

	elsif (!is_win() && $path =~ /^get_audio_devices/)
	{
		my $devices = linuxAudio::getDevices();
		$response = json_header().my_encode_json({devices=>$devices});
	}
	elsif (!is_win() && $path =~ /^set_audio_device\/(.*)$/)
	{
		my $device = $1;
		my $error = linuxAudio::setDevice($device);
		$response = $error ?
			json_error($error) :
			json_response($request,{result => "OK"});
	}

	# unknown request

	else
	{
		$response = http_error($request,"web_ui(unknown request): $path");
	}

	# display($use_dbg + 1,0,"webui_request($path) returning "._def($response));
	return $response;
}



sub getDeviceJson
{
	my ($request,$type,$uuid) = @_;

	display($dbg_webui + $request->{extra_debug},0,"getDeviceJson($type,$uuid)");
	my $device  = findDevice($type,$uuid);
	return http_error("Could not get getDeviceJson($type,$uuid)")
		if !$device;
	my $response = json_response($request,$device);
	return $response;
}


sub getDevicesData
{
	my ($type) = @_;

	my $devices = getDevicesByType($type);
	my $result = [];
	for my $device (@$devices)
	{
		next if	$type eq $DEVICE_TYPE_RENDERER &&
			!$device->{local};
			# remote renderers not yet supported

		my $use_device = {
			type => $device->{type},
			uuid => $device->{uuid},
			name => $device->{name},
			ip   => $device->{ip},
			port => $device->{port},
			online => $device->{online} };

		$use_device->{local} = 'true'
			if $device->{local};
		$use_device->{remote_artisan} = 'true'
			if $device->{remote_artisan};

		# temporary kludge to handle remoteLibrary initialization

		$use_device->{online} = '' if
			$type eq $DEVICE_TYPE_LIBRARY &&
			$device->{state} != $DEVICE_STATE_READY;

		push @$result,$use_device;
	}

	return $result;
}


sub getDevicesJson
{
	my ($request,$type) = @_;
	my $result = getDevicesData($type);
	my $response = json_response($request,$result);
	return $response;
}





1;
