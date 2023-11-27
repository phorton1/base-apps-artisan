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


my $dbg_webui = 1;
	# 0 = show basic calls
	# -1 = show building of html files with js and css
	# -2 = show fancytree scaling pct


my $SEND_MINIFIED_JS_AND_CSS = 1;
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

sub web_ui
{
	my ($path_with_query) = @_;  # ,$headers,$post_xml) = @_;
	$path_with_query ||= 'artisan.html';

	if ($path_with_query !~ /update/)
	{
		display($dbg_webui,0,"--> web_ui($path_with_query) called");
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

			my $addl_headers = [];
			if ($type eq 'html')
			{
				push @$addl_headers,"Access-Control-Allow-Origin: http://$server_ip:$server_port";
				push @$addl_headers,"Access-Control-Allow-Methods: GET";	# POST, GET, OPTIONS
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

	# device requests

	elsif ($path =~ /^getDevicesHTML\/(renderers|libraries|plsources)$/)
	{
		return getDevicesHTML($1);
	}
	elsif ($path =~ /^getDevice\/(renderer|library|plsource)-(.*)$/)
	{
		my ($singular,$uuid) = ($1,$2);
		return getDeviceJson($singular,$uuid);
	}

	# dispatch renderer request directly to object
	# note that actual playlist commands take place
	# on the renderer ...

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
		return json_header().json($renderer);
	}

	# pass request to sub module

	elsif ($path =~ s/^library\///)
	{
		$response = uiLibrary::library_request($path,$params);
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
	my ($singular,$uuid) = @_;
	my $type =
		$singular eq 'renderer' ? $DEVICE_TYPE_RENDERER :
		$singular eq 'library'  ? $DEVICE_TYPE_LIBRARY  : '';

	display($dbg_webui,0,"getDeviceJson($type,$uuid)");
	my $device;
	if ($uuid eq 'local')
	{
		$device = $local_library if $type eq $DEVICE_TYPE_LIBRARY;
		$device = $local_renderer if $type eq $DEVICE_TYPE_RENDERER;
	}
	else
	{
		$device = findDevice($type,$uuid);
	}
	return http_error("Could not get getDeviceJson($singular,$uuid)")
		if !$device;
	my $response = json_header();
	$response .= json($device);
	return $response;
}



sub getDevicesHTML
{
	my ($plural) = @_;	# plural
	my $type =
		$plural eq 'renderers' ? $DEVICE_TYPE_RENDERER :
		$plural eq 'libraries' ? $DEVICE_TYPE_LIBRARY  : '';
	my $devices = getDevicesByType($type);
	my $single = $plural;
	$single =~ s/libraries/library/;
	$single =~ s/s$//;	# singular

	display($dbg_webui,0,"getDevicesHTML($type)");

	my $text = '';

	if ($plural eq 'renderers')		# add the 'Local' renderer for the webUI
	{
		display($dbg_webui,1,"$single webUI Local renderer");

		$text .= "<input type=\"radio\" ";
		$text .= "id=\"$single-html_renderer\" ";
		$text .= "onclick=\"javascript:selectDevice('$single','html_renderer');\" ";
		$text .= "name=\"$plural\">";
		$text .= "<label for=\"$single-html_renderer\">Local</label><br>\n";
	}

	for my $device (@$devices)
	{
		display($dbg_webui,1,"$single $device->{name}");

		$text .= "<input type=\"radio\" ";
		$text .= "id=\"$single-$device->{uuid}\" ";
		$text .= "onclick=\"javascript:selectDevice('$single','$device->{uuid}');\" ";
		$text .= "name=\"$plural\">";
		$text .= "<label for=\"$single-$device->{uuid}\">$device->{name}</label><br>\n";
	}
	my $response = http_header({content_type => 'text/html' });
	$response .= $text."\r\n";
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
