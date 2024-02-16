#-----------------------------------------
# XMLSoap.pm
#-----------------------------------------
# Contains parseXML, Soap, and didle routines
#
# notes on xml and encoding.
#
# for example, the 'é' in 'Les Lables de Légende'
# came in as orig(C3 A9) from the mb_track_info file
# C:/mp3s/_data/mb_track_info/7ca4892022582c2b90c8bdca8657c888.xml
# was being written as (E9) to my my file:
# C:\mp3s\_data\unresolved_albums\albums.Blues.Old.Buddy Guy - The Treasure Untold.xml
# and then would not re-parse in xml_simple
#
# C3 A9 is the UTF-8 encoding of the latin ascii character E9
# it gets changed automatically on reading to E9 by xml_simple
# but we have to manually convert it back, here ...
#
# Note that this is different than unescape_tags(), below
#
# use Encode qw/encode decode/;
# $text = encode('UTF-8',$text);
# change single ascii byte E9 for é into two bytes C3 A9


package XMLSoap;
use strict;
use warnings;
use XML::Simple;
use JSON;
use Error qw(:try);
use Data::Dumper;
use artisanUtils;

$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

my $xmlsimple = XML::Simple->new(
	KeyAttr => [],						# don't convert arrays with 'id' members to hashes by id
	ForceArray => [						# identifiers that we want to always be arrayed
		'container',					# folders within ContentDirectory1 Results
		'item',							# tracks within ContentDirectory1 Results
		'res',							# resource infos within ContentDirectory1 tracks (to find highest bitrate)
		'upnp:albumArtURI',				# art_uris within a track
		'upnp:artist',					# artists have roles
		'desc',							# generaized array of descriptors
	],
	SuppressEmpty => '',				# empty elements will return ''
);




my $dbg_json = 1;



BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (

		parseXML
		parseDIDL

		soap_header
		soap_footer

		encode_xml
		encode_didl
		decode_didl
		encode_content

		prettyXML
		myDumper
	);
}



sub encode_didl
	# does lightweight didl encoding
{
	my ($string) = @_;
	# $string =~ s/"/&quot;/g;
	$string =~ s/</&lt;/sg;
	$string =~ s/>/&gt;/sg;
	return $string;
}

sub decode_didl
	# does lightweight didl encoding
{
	my ($string) = @_;
	# $string =~ s/&quot;/"/g;
	$string =~ s/&lt;/</sg;
	$string =~ s/&gt;/>/sg;
	return $string;
}


sub encode_xml
	# does encoding of inner values within didl
	# for returning xml to dlna clients
	# Note double encoding of ampersand as per
	# http://sourceforge.net/p/minidlna/bugs/198/
	# USING DECIMAL ENCODING
{
	my $string = shift;
    $string =~ s/([^\x20-\x7f])/"&#".ord($1).";"/eg;
	$string =~ s/&/&amp;/g;
	return $string;
}


sub encode_content
	# temporary routine? to change '&' into 'and'
	# and then encode_xml.  perhaps that should
	# just be done in encode_xml, but this code is
	# very fragile, and this is currently working.
{
	my $string = shift;
	$string =~ s/&/&amp;/g;
	return encode_xml($string);
}


sub unused_decode_xml
	# called by specific to XML encoding
	# Note double encoding of ampersand as per
	# http://sourceforge.net/p/minidlna/bugs/198/
{
	my $string = shift;
	$string =~ s/&amp;/&/g;
    $string =~ s/\\#(\d+);/chr($1)/eg;
	return $string;
}



sub soap_header
{
	my $text = '<?xml version="1.0"?>'."\r\n";
	$text .= '<SOAP-ENV:Envelope ';
	$text .= 'xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" ';
	$text .= 'SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"';
	$text .= '>';
	$text .= '<SOAP-ENV:Body>';
	return $text;
}

sub soap_footer
{
	my $text = '';
	$text .= "</SOAP-ENV:Body>";
	$text .= '</SOAP-ENV:Envelope>'."\r\n";
    return $text;
}





#----------------------------------------
# XML
#----------------------------------------

my $dbg_xml = 1;

sub parseXML
	# shows debugging at $dbg
	# shows input and output at $dbg_details
	# dumps raw.txt, pretty.txt, and xml.txt if $dump
{
	my ($data,$params) = @_;
	$params ||= {};

	display_hash($dbg_xml,0,"parseXML(params)",$params);

	my $dbg 		= $params->{dbg} || 0;
	my $dbg_name    = $params->{dbg_name} || 'parseXML';
	my $dump_dir 	= $params->{dump_dir} || '';
	my $decode_didl = $params->{decode_didl} || 0;
	my $raw         = $params->{raw} || 0;
	my $pretty      = $params->{pretty} || 0;
	my $my_dump     = $params->{my_dump} || 0;
	my $dumper	    = $params->{dumper} || 0;

	my $filename = "$dump_dir/$dbg_name";
	display($dbg,0,"parseXML($dbg_name) bytes=".length($data),1);

	printVarToFile(1,"$filename.raw.txt",$data,1) if $raw && $dump_dir;

	$data = decode_didl($data) if $decode_didl;

	if ($pretty)
	{
		my $pretty = prettyXML($data,0);
		printVarToFile(1,"$filename.pretty.txt",$pretty,1) if $dump_dir;
	}

    my $xml;
    eval { $xml = $xmlsimple->XMLin($data) };
    if ($@)
    {
        $params->{error} = error("Unable to parse xml from $dbg_name:".$@);
        return;
    }
	if (!$xml)
	{
		$params->{error} = error("Empty xml from $dbg_name!!");
		return;
	}

	if ($my_dump)
	{
		my $mine = myDumper($xml,1);
		printVarToFile(1,"$filename.my_dumper.txt",$mine,1) if $dump_dir;
	}

	if ($dumper)
	{
		my $ddd =
			"-------------------------------------------------\n".
			Dumper($xml).
			"-------------------------------------------------\n";
		printVarToFile(1,"$filename.dumper.txt",$ddd,1) if $dump_dir;
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
