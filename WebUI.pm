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
use Queue;
use Update;
use Device;
use uiLibrary;
use DeviceManager;

use if !is_win, 'linuxAudio';


my $dbg_webui = 1;
	# 0 = show basic calls
	# -1 = show building of html files with js and css
	# -2 = show fancytree scaling pct


#--------------------------------------
# webUI request dispatcher
#--------------------------------------


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

	# pass library requests to uiLibrary sub module

	elsif ($path =~ s/^library\///)
	{
		$response = uiLibrary::library_request($request,$path);	#,$params,$post_params);
	}

	#----------------------------------------------------
	# Call methods that return data to be jsonified
	#----------------------------------------------------
	# The rest of these requests call methods in other objects
	# that return errors or hashes to be returned by json.

	# NEW UPDATE SYNTAX
	# /webui/update?update_id=$update_id&renderer_uuid=$renderer_uuid
	# includes lists of new devices (libraries) if update_id changes

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

	# RENDERER requests do things and return a renderer
	# note that actual playlist commands take place
	# on the renderer ...

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

	# QUEUE request

	elsif ($path =~ /^queue\/(.*)$/)
	{
		my $command = $1;
		my $request_json = $request->get_decoded_content();
		my $json = Queue::queueCommand($command,$request_json);
		$response = json_response($request,$json);
	}

	# get/set LINUX AUDIO DEVICE
	# This stuff *might* go directly in the HTTP Server

	elsif (!is_win() && $path =~ /^get_audio_devices/)
	{
		my $devices = linuxAudio::getDevices();
		$response = json_response($request,{devices=>$devices});
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
