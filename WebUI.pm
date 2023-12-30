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
use artisanUtils;
use Device;
use DeviceManager;
use httpUtils;
use uiLibrary;
use Queue;


my $dbg_webui = 1;
	# 0 = show basic calls
	# -1 = show building of html files with js and css
	# -2 = show fancytree scaling pct
my $dbg_update = 1;
	# specific to update calls
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


sub web_ui
{
	my ($path_with_query,$post_data) = @_;
	$path_with_query ||= 'artisan.html';

	if ($path_with_query !~ /^update/)
	{
		display($dbg_webui,0,"--> web_ui($path_with_query) called");
	}
	else
	{
		display($dbg_update,0,"UPDATE CALLED: $path_with_query");
	}

	# parse query parameters

	my $params = {};
	my ($path,$query) = split(/\?/,$path_with_query,2);
	if ($query)
	{
		my @parts = split(/&/,$query);
		for my $part (@parts)
		{
			my ($l,$r) = split(/=/,$part,2);
			display(9,1,"param($l)=$r");
			$params->{$l} = defined($r) ? $r : '';
		}
	}


    # deliver static files

	my $response = undef;
	if ($path =~ /^((.*\.)(js|css|gif|png|html|json))$/)
	{
		my $filename = $1;
		my $type = $3;
		my $query = $5;

		# scale fancytree CSS file if it has scale param

		if (!(-f "$artisan_perl_dir/webui/$filename"))
		{
			$response = http_error("web_ui(): Could not open file: $filename");
		}
		elsif ($params->{scale} &&
			   $filename =~ /ui\.fancytree\.css$/)
		{
			$response = scale_fancytree_css($filename,$params->{scale});
		}
		else
		{
			my $content_type =
				$type eq 'js'  ? 'text/javascript' :
				$type eq 'css' ? 'text/css' :
				$type eq 'gif' ? 'image/gif' :
				$type eq 'png' ? 'image/png' :
				$type eq 'html' ? 'text/html' :
				$type eq 'json' ? 'application/json' :
				'text/plain';

			# add CORS cross-origin headers to the main HTML file
			# allow cross-origin requests to iPad browsers
			# which would not call /get_art/ to get our album art URIs otherwise

			# Modified to allow most generous CORS options while messing with
			# 	cross-origin webUI request, but this is not, per se, specifically
			# 	needed for those.

			my $addl_headers = [];
			if ($type eq 'html')
			{
				push @$addl_headers,"Access-Control-Allow-Origin: *";			# was http://$server_ip:$server_port";
				push @$addl_headers,"Access-Control-Allow-Methods: GET";		# OPTIONS, POST, SUBSCRIBE, UNSUBSCRIBE
			}

			$response = http_header({
				content_type => $content_type,
				addl_headers => $addl_headers });

			if ($SEND_MINIFIED_JS_AND_CSS && ($type eq 'js' || $type eq 'css'))
			{
				my $filename2 = $filename;
				$filename2 =~ s/$type$/min.$type/;
				display(5,0,"checking MIN: $filename2");
				if (-f "$artisan_perl_dir/webui/$filename2")
				{
					display($dbg_webui,1,"serving MIN: $filename2");
					$filename = $filename2;
				}
			}

			my $text = getTextFile("$artisan_perl_dir/webui/$filename",1);
			$text = process_html($text) if ($type eq 'html');
			$response .= $text."\r\n";
		}
	}

	# debugging

	elsif ($path =~ s/^debug_output\///)
	{
		my $color = $path =~ /^ERROR/ ?
			$DISPLAY_COLOR_ERROR :
			$UTILS_COLOR_LIGHT_GREEN;

		Pub::Utils::_setColor($color);
		print "REMOTE: ".url_decode($path)."\n";
		Pub::Utils::_setColor($DISPLAY_COLOR_NONE);
		$response = html_header();
	}

	# device requests

	elsif ($path =~ /^getDevices\/(renderer|library)$/)
	{
		$response = getDevicesJson($1);
	}
	elsif ($path =~ /^getDevice\/(renderer|library)-(.*)$/)
	{
		my ($singular,$uuid) = ($1,$2);
		$response = getDeviceJson($singular,$uuid);
	}


	# NEW UPDATE SYNTAX

	elsif ($path eq 'update')
	{
		my $update_id = $params->{update_id} || 0;
		return json_error("No update_id in UPDATE call")
			if !$update_id;

		# The HTML Renderer can call without a UUID at this time

		my $renderer_uuid = $params->{renderer_uuid} || '';
		warning($dbg_update,0,"No renderer_uuid in UPDATE call!")
			if !$renderer_uuid;

		my $data = {
			update_id => $system_update_id };

		$data->{libraries} = getDevicesData($DEVICE_TYPE_LIBRARY)
			if $update_id != $system_update_id;

		if ($renderer_uuid)
		{
			my $renderer = findDevice($DEVICE_TYPE_RENDERER,$renderer_uuid);
			return json_error("could not find renderer '$renderer_uuid'") if !$renderer;

			my $error = $renderer->doCommand('update',$params);

			return json_error("renderer_request($path) error: $error")
				if $error;
			$data->{renderer} = $renderer;
		}

		$response = json_header().my_encode_json($data);

	}

	# dispatch renderer request directly to object
	# note that actual playlist commands take place
	# on the renderer ...
	#
	# renderer/update is no longer called.

	elsif ($path =~ s/^renderer\///)
	{
		return json_error("could not find renderer uuid in '$path'")
			if $path !~ s/^(.*?)\///;
		my $uuid = $1;

		# Get the renderer, do the command, return error if it fails,
		# or return the render as json if it succeeds.

		my $renderer = findDevice($DEVICE_TYPE_RENDERER,$uuid);
		return json_error("could not find renderer '$uuid'") if !$renderer;
		my $error = $renderer->doCommand($path,$params);
		return json_error("renderer_request($path) error: $error")
			if $error;
		$response = json_header().my_encode_json($renderer);
	}

	# pass library requests to PM sub module

	elsif ($path =~ s/^library\///)
	{
		my $post_params = $path =~'get_queue_tracks' ? my_decode_json($post_data) : '';
		display_hash($dbg_post_params,0,"decoded post_params",$post_params) if $path =~ 'get_queue_tracks';
		$response = uiLibrary::library_request($path,$params,$post_params);
	}

	# queue request

	elsif ($path =~ /^queue\/(.*)$/)
	{
		my $command = $1;
		my $post_params = my_decode_json($post_data);
		my $rslt = Queue::queueCommand($command,$post_params);
		$response = json_header().my_encode_json($rslt);
	}

	# unknown request

	else
	{
		$response = http_error("web_ui(unknown request): $path_with_query");
	}

	return $response;
}



sub getDeviceJson
{
	my ($type,$uuid) = @_;

	display($dbg_webui,0,"getDeviceJson($type,$uuid)");
	my $device  = findDevice($type,$uuid);
	return http_error("Could not get getDeviceJson($type,$uuid)")
		if !$device;
	my $response = json_header();
	$response .= my_encode_json($device);
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
	my ($type) = @_;
	my $result = getDevicesData($type);
	my $response = json_header();
	$response .= my_encode_json($result);
	return $response;
}





#----------------------------------------------------
# process html
#----------------------------------------------------

sub process_html
{
	my ($html,$level) = @_;
	$level ||= 0;

	while ($html =~ s/<!-- include (.*?) -->/###HERE###/s)
	{
		my $id = '';
		my $spec = $1;
		$id = $1 if ($spec =~ s/\s+id=(.*)$//);

		my $filename = "$artisan_perl_dir/webui/$spec";
		display($dbg_webui+1,0,"including $filename  id='$id'");
		my $text = getTextFile($filename,1);

		$text =~ s/{id}/$id/g;

		$text = process_html($text,$level+1);
		$text = "\n<!-- including $filename -->\n".
			$text.
			"\n<!-- end of included $filename -->\n";

		$html =~ s/###HERE###/$text/;
	}

	if (0 && !$level)
	{
		while ($html =~ s/<script type="text\/javascript" src="\/(.*?)"><\/script>/###HERE###/s)
		{
			my $filename = $1;
			display($dbg_webui+1,0,"including javascript $filename");
			my $eol = "\r\n";
			# my $text = getTextFile($filename,1);

			my $text = $eol.$eol."<script type=\"text\/javascript\">".$eol.$eol;
			my @lines = getTextLines($filename);
			for my $line (@lines)
			{
				$line =~ s/\/\/.*$//;
				$text .= $line.$eol;
			}

			while ($text =~ s/\/\*.*?\*\///s) {};
			$text .= $eol.$eol."</script>".$eol.$eol;
			$html =~ s/###HERE###/$text/s;
		}
	}

	return $html;
}


#----------------------------------------------------
# scale_css
#----------------------------------------------------

sub scale_fancytree_css
	# algorithmically scale fancy tree css file
	# requires that icons$pixels.gif created by hand
	# scale font-size pts, and certain px values
{
	my ($filename,$pixels) = @_;
	my $factor = $pixels/16;
	display($dbg_webui+2,0,"scale($pixels = $factor) $filename");

	my $text .= getTextFile("$artisan_perl_dir/webui/$filename",1);
	$text =~ s/url\("icons\.gif"\);/url("icons$pixels.gif");/sg;
	$text =~ s/font-size: 10pt;/'font-size: '.int($factor*10).'pt;'/sge;
	$text =~ s/(\s*)((-)*(16|32|48|64|80|96|112|128|144))px/' '.int($factor*$2).'px'/sge;
	# printVarToFile(1,"/junk/test.css",$text);

	my $response = http_header({ content_type => 'text/css' });
	$response .= $text;
	$response .= "\r\n";
	return $response;
}



1;
