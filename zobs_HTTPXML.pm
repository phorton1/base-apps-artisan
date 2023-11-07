#---------------------------------------
# HTTPXML.pm
#---------------------------------------
# Filtering is a waste of time.
# As long as it's valid XML, let the client filter it.

package HTTPXML;
use strict;
use warnings;
use Date::Format;
use artisanUtils;
use Library;

# Turned PRETTY off while trying to get WD to play (which stopped working)
# and it hard crashed WDTV Live !!!

my $PRETTY = 0;
    # indent the xml
my $SHOW_SOURCES = 0;
    # show where tags came from (i.e. album_title_##TITLE##)


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
        xml_header
        xml_footer
        xml_directory
        xml_item
        xml_item_detail
        xml_serverdescription
		filter_lines
    );
};


my $url_base = "http://$server_ip:$server_port";

sub filter_lines
    # filter lines for generating DIDL XML
    # a line may be commented out by starting it with #
    # DIDL requres the use of &lt; &gt; and &quot;, but
    # so <,> and " are replaced before outputting
    # Subsitution variables from the record passed
    # in ($item) may be specified with ##FIELD_NAME##,
    # and those items will be further url_encoded(),
    # as required.
{
    my ($indent,$item,$in_text) = @_;
    my @lines = split("\n",$in_text);
    my $out_text = '';
    my $indent_text = '';
    while ($indent-- > 0) { $indent_text .= '    '; }
    for my $line (@lines)
    {
        next if ($line =~ /^\s*#/);
        $line =~ s/"/&quot;/g;
        $line =~ s/</&lt;/g;
        $line =~ s/>/&gt;/g;
        while ($line =~ s/##(\w+)##/##HERE##/)
        {
            my $field = $1;
            my $val = encode_xml($item->{$field} || '');
            $line =~ s/##HERE##/$val/;
        }

        $line =~ s/\s*$//;
        if ($PRETTY)
        {
            $out_text .= $indent_text;
        }
        else
        {
            $line =~ s/^\s*//;
        }
        $out_text .= $line.($PRETTY ? "\n" : ' ');
    }
    return $out_text;
}




sub xml_header
{
    my ($what) = @_;   # 0=Browse, 1=Search
    my $response_type = ($what ? 'Search' : 'Browse').'Response';
	my $xml = <<EOXML;
<s:Envelope
    xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
    s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <s:Body>
        <u:$response_type xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">
        <Result>
EOXML
    $xml .= filter_lines(1,undef,<<EOXML);
<DIDL-Lite
    xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
    xmlns:sec="http://www.sec.co.kr/dlna"
    xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
    xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" >
EOXML
	return $xml;
}


$system_update_id = time();

sub xml_footer
{
	my ($num_search,
        $num_total,
        $what) = @_;

    # $system_update_id++;
	# for testing responsiveness
	
    my $response_type = ($what ? 'Search' : 'Browse').'Response';
    my $xml .= filter_lines(1,undef,<<EOXML);
</DIDL-Lite>
EOXML
	$xml .= <<EOXML;
        </Result>
        <NumberReturned>$num_search</NumberReturned>
        <TotalMatches>$num_total</TotalMatches>
        <UpdateID>$system_update_id</UpdateID>
        </u:$response_type>
    </s:Body>
</s:Envelope>
EOXML
    return $xml;
}



sub xml_directory
{
	my ($rec) = @_;
    display($dbg_xml,0,"xml_directory($$rec{id})");

    my $container = (00 && $rec->{dirtype} eq 'album') ?
        'object.container.album.musicAlbum' :
        'object.container';

    my ($src_title,$src_artist,$src_album_artist, $src_genre) = $SHOW_SOURCES ?
        ('folder_title_','folder_artist_','folder_album_artist_','folder_genre_') :
        ('','','','');
		
	my $art_uri = !$rec->{has_art} ? '' :
		"http://$server_ip:$server_port/get_art/$rec->{id}/folder.jpg";
		

	return filter_lines(2,$rec,<<EOXML);
<container
    id="##id##"
    parentID="##parent_id##"
    searchable="1"
    restricted="1"
    childCount="##num_elements##" >
    <dc:title>$src_title##title##</dc:title>
    <upnp:class>$container</upnp:class>
    <upnp:artist>$src_artist##artist##</upnp:artist>
    <upnp:albumArtist>$src_album_artist##artist##</upnp:albumArtist>
    <upnp:genre>$src_genre##genre##</upnp:genre>
    <upnp:genre>$src_genre##genre##2</upnp:genre>
    <dc:date>##year##</dc:date>
    <upnp:albumArtURI>$art_uri</upnp:albumArtURI>
</container>
EOXML
}


sub xml_item
    # BubbleUP supports audio, video, images, and audio/x-scpls.
    # so, even if we want to send object.textItem, we cannot
	#
	# The commented items are not shown in BubbleUp
	# (not sure about art_uri on tracks and other players)
	# (not sure about containers for class audioItem..
	# We don't send following fields (by DLNA type)
	# object: parentID, creator, restricted, upnp:writeStatus
	# item: refID
	# audioItem:
	#    dc:description,
	#    upnp:longDescription,
	#    dc:publisher,
	#    dc:language,
	#    dc:relation,
	#    dc:rights
	# musicTrack
	#    upnp:playlist,
	#	 upnp:storageMedium,
	#    dc:contributor,
	# Nothing from containers, EXCEPT, we send
	# albumArtURI, which *should* be a container
	# level object, but is needed to make cover show
	# in stand alone players
	# container
	#    childCount
	#    createClass
	#    searchClass
	#    searchable
	# album (container)
	#     upnp:storageMedium
	#     dc:longDescription
	#     dc:description
	#     dc:publisher
	#     dc:contributor
	#     dc:date
	#     dc:relation
	#     dc:rights
	#     upnp:producer
	#     upnp:toc
    # <upnp:playbackCount>0</upnp:playbackCount>
    # <sec:preference>0</sec:preference>
    # <sec:modificationDate>1932</sec:modificationDate>
{
	my ($item,$parent) = @_;
    display($dbg_xml,0,"xml_item($$item{id})");
	
    my ($src_album,$src_title,$src_artist,$src_genre,$src_albumArtist) = $SHOW_SOURCES ?
        ('item_album_', 'item_title_','item_artist_','item_genre_','item_albumArtist_') :
        ('','','','','');
	
	my $dlna_stuff = get_dlna_stuff($item);
	my $pretty_duration = secs_to_duration(int($item->{duration}/1000));
	
	# get art from parent folder
	
	my $art_uri = !$parent->{has_art} ? '' :
		"http://$server_ip:$server_port/get_art/$parent->{id}/folder.jpg";
	
	my $mime_type = Library->myMimeType($item->{type});
	
    my $text = filter_lines(3,$item,<<EOXML);
<item id="##id##" parentID="##parent_id##" restricted="1">
    <dc:title>$src_title##title##</dc:title>
	<upnp:class>object.item.audioItem</upnp:class>
	<upnp:genre>$src_genre##genre##</upnp:genre>
	<upnp:artist>$src_artist##artist##</upnp:artist>
    <upnp:album>$src_album##album_title##</upnp:album>
    <upnp:originalTrackNumber>##tracknum##</upnp:originalTrackNumber>
    <dc:date>##year_str##</dc:date>
	<upnp:albumArtURI>$art_uri</upnp:albumArtURI>
    <upnp:albumArtist>$src_albumArtist##album_artist##</upnp:albumArtist>
    #
    # had to be careful with the <res> element, as
    # WDTVLive did not work when there was whitespace (i.e. cr's)
    # in my template ... so note the >< are on the same line.
    #
    <res
        # bitrate="##bitrate##"
        size="##size##"
        duration="$pretty_duration"
        protocolInfo="http-get:*:##$mime_type##:$dlna_stuff"
    >$url_base/media/##id##.##type##</res>
</item>
EOXML

	display(9,0,"xml_item($item->{id})=$text");
	return $text;
}


sub get_dlna_stuff
	# DLNA.ORG_PN - media profile
{
	my ($item) = @_;
	my $type = $item->{TYPE};
	my $mime_type = Library->myMimeType($type);
	my $contentfeatures = '';

    # $contentfeatures .= 'DLNA.ORG_PN=LPCM;' if $mime_type eq 'audio/L16';
    $contentfeatures .= 'DLNA.ORG_PN=LPCM;' if $mime_type eq 'audio/x-aiff';
    $contentfeatures .= 'DLNA.ORG_PN=LPCM;' if $mime_type eq 'audio/x-wav';
    $contentfeatures .= 'DLNA.ORG_PN=WMABASE;' if $mime_type eq 'audio/x-ms-wma';
    $contentfeatures .= 'DLNA.ORG_PN=MP3;' if $mime_type eq 'audio/mpeg';
    # $contentfeatures .= 'DLNA.ORG_PN=JPEG_LRG;' if $mime_type eq 'image/jpeg';
    # $contentfeatures .= 'DLNA.ORG_PN=JPEG_TN;' if $mime_type eq 'JPEG_TN';
    # $contentfeatures .= 'DLNA.ORG_PN=JPEG_SM;' if $mime_type eq 'JPEG_SM';

	# DLNA.ORG_OP=ab
	#   a - server supports TimeSeekRange
	#   b - server supports RANGE
    # $contentfeatures .= 'DLNA.ORG_OP=00;' if ($item->{TYPE} eq 'image');
	$contentfeatures .= 'DLNA.ORG_OP=01;';
    # $contentfeatures .= 'DLNA.ORG_OP=00;';

	# todo: DLNA.ORG_PS - supported play speeds
	# DLNA.ORG_CI - for transcoded media items it is set to 1
	$contentfeatures .= 'DLNA.ORG_CI=0;';

	# DLNA.ORG_FLAGS - binary flags with device parameters
	$contentfeatures .= 'DLNA.ORG_FLAGS=01500000000000000000000000000000';
    # $contentfeatures .= 'DLNA.ORG_FLAGS=00D00000000000000000000000000000';

	return $contentfeatures;
}





1;
