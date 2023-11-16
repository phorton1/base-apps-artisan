#-----------------------------------------
# httpUtils.pm
#-----------------------------------------
# Contains routines that are common to http

package httpUtils;
use strict;
use warnings;
use XML::Simple;
use Data::Dumper;
use artisanUtils;

$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

my $dbg_json = 1;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (

		http_header
		http_error
		html_header
		json_header
		json_error

        url_decode

		json

		parseXML
		parseDIDL

		prettyXML
		myDumper

	);
}



sub http_error
{
	my ($msg) = @_;
	error($msg,1);
	return http_header({ status_code => 400 });
}


sub http_header
{
	my ($params) = @_;

	$params ||= {};
	my $status_code = $params->{status_code} || 200;
	my $content_type = $params->{content_type} || 'text/plain';

	my %HTTP_CODES = (
		200 => 'OK',
		206 => 'Partial Content',
		400 => 'Bad request',
		403 => 'Forbidden',
		404 => 'Not found',
		406 => 'Not acceptable',
		501 => 'Not implemented' );

	my @response = ();
	push(@response, "HTTP/1.1 $status_code ".$HTTP_CODES{$status_code});
	push(@response, "Server: $program_name");
	push(@response, "Content-Type: $content_type");
	push(@response, "Content-Length: $params->{'content_length'}") if $params->{'content_length'};
	push(@response, "Date: ".gmtime()." GMT");
    # push(@response, "Last-Modified: "gmtime()." GMT"));

	if (defined($$params{'addl_headera'}))
	{
		for my $header (@{$params->{'addl_headera'}})
		{
			push(@response, $header);
		}
	}

	if (0)
	{
		push(@response,"ETag:");
		push(@response,'Cache-Control "max-age=0, no-cache, no-store, must-revalidate"');
		push(@response,'Pragma "no-cache"');
		push(@response,'Expires "Wed, 11 Jan 1984 05:00:00 GMT"');
	}
	else
	{
		push(@response, 'Cache-Control: no-cache');
	}

	push(@response, 'Connection: close');

	return join("\r\n", @response)."\r\n\r\n";
}


sub html_header
{
	return http_header({ content_type => 'text/html' });
}


sub json_header
{
	return http_header({ content_type => 'application/json' });
}


sub json_error
{
	my ($msg) = @_;
	error($msg,1);
	my $response = json_header();
	$response .= json({error=>$msg});
	return $response;
}



sub json
	# return my json representation of an object
{
	my ($obj) = @_;
	my $response = '';

	display($dbg_json,0,"json obj=$obj ref=".ref($obj),1);

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

			display($dbg_json,1,"json hash($k) = $val = ".ref($val),1);

			if (ref($val))
			{
				display($dbg_json,0,"json recursing");
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
				$val = '"'.$val.'"' if $val !~ /^(true|false)$/;
					# don't quote boolean values.
					# they are provided in perl by specifically
					# using the strings 'true' and 'false'
			}

			$response .= ',' if (length($response));
			$response .= '"'.$k.'":'.$val."\n";
		}

		return '{' . $response . '}';
	}

	display($dbg_json+1,0,"returning quoted string constant '$obj'",1);

	# don't forget to escape it here as well.

    $obj =~ s/([^\x20-\x7f])/"&#".ord($1).";"/eg;
	return "\"$obj\"";
}


sub url_decode
{
	my ($p) = @_;
	display(9,0,"decode[$p]",1);
	$p =~ s/\+/ /g;
	$p =~ s/%(..)/pack("c",hex($1))/ge;
	display(9,1,"=decoded[$p]",1);
	return $p;
}



#----------------------------------------
# XML
#----------------------------------------

sub parseXML
	# shows debugging at $dbg
	# shows input and output at $dbg_details
	# dumps raw.txt, pretty.txt, and xml.txt if $dump
{
	my ($data,$params) = @_;
	$params ||= {};

	my $what        = $params->{what} || 'xml';
	my $show_hdr  	= $params->{show_hdr} || 0;
	my $show_dump   = $params->{show_dump} || 0;
	my $addl_level  = $params->{addl_level} || 0;
	my $dump 		= $params->{dump} || 0;

	my $decode_didl = $params->{decode_didl} || 0;
	my $raw         = $params->{raw} || 0;
	my $pretty      = $params->{pretty} || 0;
	my $my_dump     = $params->{my_dump} || 0;
	my $dumper	    = $params->{dumper} || 0;

	my $filename = "$temp_dir/$what";
	display(0,$addl_level,"parseXML($what) bytes=".length($data),1)
		if $show_hdr;

	display(0,$addl_level+1,"RAW($what)\n$data",1) if $raw && $show_dump;
	printVarToFile(1,"$filename.raw.txt",$data,1) if $raw && $dump;

	$data = decode_didl($data) if $decode_didl;

	if ($pretty)
	{
		my $pretty = prettyXML($data,0);
		display(0,$addl_level+1,"PRETTY($what)\n$pretty",1) if $show_dump;
		printVarToFile(1,"$filename.pretty.txt",$pretty,1) if $dump;
	}

    my $xml;
	my $xmlsimple = XML::Simple->new();
    eval { $xml = $xmlsimple->XMLin($data) };
    if ($@)
    {
        error("Unable to parse xml from $what:".$@);
        return;
    }
	if (!$xml)
	{
		error("No parsed xml return for $what!!");
		return;
	}

	if ($my_dump)
	{
		my $mine = myDumper($xml,1);
		display(0,$addl_level+1,"MY_DUMPER($what)\n$mine",1) if $show_dump;
		printVarToFile(1,"$filename.my_dumper.txt",$mine,1) if $dump;
	}

	if ($dumper)
	{
		my $ddd =
			"-------------------------------------------------\n".
			Dumper($xml).
			"-------------------------------------------------\n";
		display(0,$addl_level+1,"DUMPER($what)\$ddd") if $show_dump;
		printVarToFile(1,"$filename.dumper.txt",$ddd,1) if $dump;
	}

	return $xml;
}


sub prettyXML
	# return a pretty printed version of the XML
{
	my ($data,$decode_didl) = @_;
	$decode_didl = 1 if !defined($decode_didl);

	$data =~ s/\r\n/ /sg;
	$data =~ s/\n/ /sg;
	$data =~ s/^\s+//sg;
	$data =~ s/\s+$//sg;
	$data = decode_didl($data) if $decode_didl == 1;

	my $level = 0;
	my $retval = "-------------------------------------------------\n";

	while ($data && $data =~ s/^(.*?)<(.*?)>//)
	{
		my $text = $1;
		my $token = $2;
		$text = decode_didl($text) if $decode_didl == 2;
		$retval .= $text if length($text);

		$data =~ s/^\s+//;

		my $closure = $token =~ /^\// ? 1 : 0;
		my $self_contained = $token =~ /\/$/ ? 1 : 0;
		my $text_follows = $data =~ /^</ ? 0 : 1;
		$level-- if !$self_contained && $closure;

		$retval .= indent($level) if !length($text);  # if !$closure;
		$retval .= "<".$token.">";
		$retval .= "\n" if !$text_follows || $closure;

		$level++ if !$self_contained && !$closure && $token !~ /^.xml/;
	}

	$retval .= "-------------------------------------------------\n";
	return $retval;
}


sub myDumper
{
	my ($obj,$level,$started) = @_;
	$level ||= 0;
	$started ||= 0;

	my $text;
	my $retval = '';
	$retval .= "-------------------------------------------------\n"
		if !$level;

	if ($obj =~ /ARRAY/)
	{
		$retval .= indent($level)."[\n";
		for my $ele (@$obj)
		{
			$retval .= myDumper($ele,$level+1,1);
		}

		$retval .= indent($level)."]\n";
	}
	elsif ($obj =~ /HASH/)
	{
		$started ?
			$retval .= indent($level) :
			$retval .= ' ';
		$retval .= "{\n";
		for my $k (keys(%$obj))
		{
			my $val = $obj->{$k};
			$retval .= indent($level+1)."$k =>";
			$retval .= myDumper($val,$level+2,0);
		}
		$retval .= indent($level)."}\n";
	}
	else
	{
		my @lines = split(/\n/,$obj);
		for my $line (@lines)
		{
			$retval .= indent($level) if $started;
			$started = 1;
			$retval .= "'$line'\n";
		}
	}

	$retval .= "-------------------------------------------------\n"
		if !$level;
	return $retval;
}


sub indent
{
	my ($level) = @_;
	$level = 0 if $level < 0;
	my $txt = '';
	while ($level--) {$txt .= "  ";}
	return $txt;
}


1;
