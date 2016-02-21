#-----------------------------------------
# WebUI.pm
#-----------------------------------------
# The webUI is a javascript application based
# on the EasyUI and JQuery libraries.
#
# There is a single persistent page loaded into
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
use Utils;

use Database;
use MediaFile;
use Library;
use Station;
use Renderer;

use uiUtils;
use uiExplorer;
use uiRenderer;
use uiStation;

my $MIN_JS_CSS = 1;
	# serve up .min file if they exist

# reminder of the user agents from various devices

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
	my ($get_param) = @_;  # ,$headers,$post_xml) = @_;
	if ($get_param !~ /update/)
	{
		display($dbg_webui-1,0,"--> web_ui($get_param) called");
	}
	
	# parse query parameters
	
	my $params = {};
	my ($path,$query) = split(/\?/,$get_param,2);
	if ($query)
	{
		my @parts = split(/&/,$query);
		for my $part (@parts)
		{
			my ($l,$r) = split(/=/,$part,2);
			display(9,1,"param($l)=$r");
			$params->{$l} = $r;
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
				$type eq 'gif' ? 'image/gif' :
				$type eq 'png' ? 'image/png' :
				$type eq 'js'  ? 'text/javascript' :
				$type eq 'css' ? 'text/css' :
				$type eq 'html' ? 'text/html' :
				$type eq 'json' ? 'application/json' :
				'text/plain';
				
			$response = http_header($content_type);
			
			if ($type eq 'js' || $type eq 'css')
			{
				my $filename2 = $filename;
				$filename2 =~ s/$type$/min.$type/;
				display(5,0,"checking MIN: $filename2");
				if (-f "$artisan_perl_dir/webui/$filename2")
				{
					display($dbg_webui-1,0,"serving MIN: $filename2");
					$filename = $filename2;
				}
			}
				
			my $text = getTextFile("$artisan_perl_dir/webui/$filename",1);
			$text = process_html($text) if ($type eq 'html');
			$response .= $text."\r\n";
		}
	}
	
	# module dispatcher
	
	elsif ($path =~ s/^explorer\///)
	{
		$response = uiExplorer::explorer_request($path,$params);
	}
	elsif ($path =~ s/^renderer\///)
	{
		$response = uiRenderer::renderer_request($path,$params);
	}
	elsif ($path =~ s/^station\///)
	{
		$response = uiStation::station_request($path,$params);
	}

	# unknown request
	
	else	
	{
		$response = http_error("web_ui(unknown request): $get_param");
	}

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
		display($dbg_webui-1,0,"including $filename  id='$id'");
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
			display($dbg_webui-1,0,"including javascript $filename");
			my $eol = "\r\n";
			# my $text = getTextFile($filename,1);
			
			my $text = $eol.$eol."<script type=\"text\/javascript\">".$eol.$eol;
			my $lines = getTextLines($filename);
			for my $line (@$lines)
			{
				chomp $line;
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
	display($dbg_webui-1,0,"scale($pixels = $factor) $filename");
	
	my $text .= getTextFile("$artisan_perl_dir/webui/$filename",1);
	$text =~ s/url\("icons\.gif"\);/url("icons$pixels.gif");/sg;
	$text =~ s/font-size: 10pt;/'font-size: '.int($factor*10).'pt;'/sge;
	$text =~ s/(\s*)((-)*(16|32|48|64|80|96|112|128|144))px/' '.int($factor*$2).'px'/sge;
	# printVarToFile(1,"/junk/test.css",$text);

	my $response = http_header('text/css');
	$response .= $text;
	$response .= "\r\n";
	return $response;
}
	


1;
