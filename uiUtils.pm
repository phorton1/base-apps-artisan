#-----------------------------------------
# uiUtils.pm
#-----------------------------------------
# Contains routines that are common to
# the uiModules.

package uiUtils;
use strict;
use warnings;
use Utils;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		standard_pane
		http_header
		http_error
		html_header
		json_header
		json_error
        url_decode
		json
	);
}



sub http_header
{
	my ($content_type,$status_code) = @_;
	$content_type ||= 'text/plain';
	$status_code ||= 200;
	
	my $response = HTTPServer::http_header({
		'statuscode' => 200,
		'content_type' => $content_type });
}

sub http_error
{
	my ($msg) = @_;
	error($msg);
	return http_header('text/plain',400);
}


sub html_header
{
	return http_header('text/html');
}


sub json_header
{
	return http_header('application/json');
}



sub json_error
{
	my ($msg) = @_;
	error($msg);
	my $response = json_header();
	$response .= json({error=>$msg});
	return $response;
}



sub json
	# return the json representation of an object
{
	my ($obj) = @_;
	my $response = '';
	
	display($dbg_webui+2,0,"obj=$obj ref=".ref($obj));
	
	if ($obj =~ /ARRAY/)
	{
		for my $ele (@$obj)
		{
			$response .= "," if (length($response));
			$response .= json($ele)."\n";
		}
		return "[". $response . "]";
	}
	
	if ($obj =~ /HASH/)
	{
		for my $k (keys(%$obj))
		{
			my $val = $$obj{$k};
			$val = '' if (!defined($val));
			
			display($dbg_webui+2,0,"json($k) = $val = ".ref($val));
			
			if (ref($val))
			{
				display($dbg_webui+1,0,"json recursing");
				$val = json($val);
			}
			else
			{
				# convert high ascii characters (é = 0xe9 = 233 decimal)
				# to &#decimal; html encoding.  jquery clients must use
				# obj.html(s) and NOT obj.text(s) to get it to work
				#
				# this is pretty close to what Utils::escape_tag() does,
				# except that it escapes \ to \x5c and does not escape
				# double quotes.
				
			    $val =~ s/([^\x20-\x7f])/"&#".ord($1).";"/eg;

				# escape quotes and backalashes

				$val =~ s/\\/\\\\/g;
				$val =~ s/"/\\"/g;
				$val = '"'.$val.'"';
			}

			$response .= ',' if (length($response));
			$response .= '"'.$k.'":'.$val."\n";
		}
		
		return '{' . $response . '}';
	}
	
	display($dbg_webui+2,0,"returning quoted string constant '$obj'");
	
	# don't forget to escape it here as well.
	
    $obj =~ s/([^\x20-\x7f])/"&#".ord($1).";"/eg;
	return "\"$obj\"";
}


sub url_decode
{
	my ($p) = @_;
	display(9,0,"decode[$p]");
	$p =~ s/\+/ /g;
	$p =~ s/%(..)/pack("c",hex($1))/ge;
	display(9,1,"=decoded[$p]");
	return $p;
}


sub standard_pane
	# returns a 'standard pane' html file
	# for renderer, explorer, or prefs pane_names
	# by combining the artisan.html template with
	# the javascript and html for the given pane.
{
	my ($pane_name,$is_mobile) = @_;
	my $response = html_header();
	
	my $mobile = $is_mobile ? '/mobile' : '';
	
	$response .= getTextFile("webui$mobile/artisan.html");

	my $theme = uiPrefs::getPreference($is_mobile?'THEME_MOBILE':'THEME');
	my $header_stuff =
		"<link rel='stylesheet' type='text/css' href='/webui/easyui/themes/$theme/easyui.css'>\n".
		"<link rel='stylesheet' type='text/css' href='/webui/easyui/themes/icon.css'>\n".
		"<link rel='stylesheet' type='text/css' href='/webui$mobile/artisan_$theme.css'>\n".
		"<link rel='stylesheet' type='text/css' href='/webui$mobile/artisan.css'>\n";


	my $client_area = getTextFile("webui/$pane_name.html");

	$response =~ s/<!-- INSERT CLIENT_AREA HERE -->/$client_area/;
	$response =~ s/<!-- INSERT HEADER_STUFF HERE -->/$header_stuff/;

	return $response;
}

			


1;
