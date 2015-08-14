#---------------------------------------------------
# mbUtils.pm
#---------------------------------------------------
# General purpose routines to access musicBrainz

package x_mbUtils;
use strict;
use warnings;
use XML::Simple;
use Encode qw/_utf8_on encode decode/;
use Data::Dumper;
use appUA;
use Utils;
use MediaFile;      # only for get_fpcalc_info
    

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
        mb_get_xml
        mb_debug_xml
        mb_get_acousticid_xml
        mb_get_object_artist
		
        mb_get_track_info
		mb_find_artist
		
		$xml_reader
		
    );
}

  
# configure modules

$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent = 1;

# working variables

my $ACOUSTIC_CLIENT_ID = '8XaBELgH';  # mine 'bsXu37G9';

our $xml_reader = XML::Simple->new(
    KeyAttr => [],
    ForceArray => [ qw(
		errors
        result
        recording
        track
        medium
        release
        releasegroup
        )],
    GroupTags => {
        results         => 'result',
        recordings      => 'recording',
        tracks          => 'track',
        mediums         => 'medium',
        releases        => 'release',
        releasegroups   => 'releasegroup',
        
        },
    
    # ForceContent => 1
    # KeyAttr' is ['name', 'key', 'id'].
    # ForceArray => [ qr/^id$/ ] );
);



#------------------------------------------------------
# Common Accessors
#------------------------------------------------------

sub mb_get_object_artist
{
    my ($object) = @_;
    my $object_artists = $object->{artists};
    my $artists = $object_artists ? $object_artists->{artist} : undef;
    return 'prh_undefined_artist' if (!$artists);
    $artists = [ $artists ] if (ref($artists) =~ /HASH/);
    
    my $name = '';
    for my $artist (@$artists)
    {
        $name .= $artist->{name};
        $name .= $artist->{joinphrase} if ($artist->{joinphrase});
    }
    $name = 'Various' if ($name eq 'Various Artists');
    return $name;
}


#------------------------------------------------------
# General Cached XML Files
#------------------------------------------------------
 
sub mb_debug_xml
{
    my ($level,$msg,$xml) = @_;
    return if ($level && $level > $debug_level);
    
    my $dump = Dumper($xml);
    my @xml_lines = split(/\n/,$dump);
    shift @xml_lines;
    pop @xml_lines;

    display($level+1,0,"");
    display($level,0,$msg);
    for my $line (@xml_lines)
    {
        display($level,1,$line);
    }
    display($level+1,0,"");
}




sub mb_get_xml
{
    my ($dbg_xml,$directory,$id,$method,$url,$params) = @_;
    display(4,0,"get_xml($id,".uc($method).",$directory)");

    my $text = '';
    my $dir = "$cache_dir/$directory";

    if (!-d $dir)
    {
        mkdir $dir;
    }
    elsif (-f "$dir/$id.xml")
    {
        display(4,1,"getting from cache");
        $text = getTextFile("$dir/$id.xml");
        if (!$text)
        {
            error("Could not read cache $dir/$id.xml .. trying to get it from web");
        }
    }

    if (!$text)
    {
        display(0,1,"getting $directory($id) from net");
            sleep 1;
        my $response = ($method eq 'post') ?
            $ua->post($url,$params) :
            $ua->get($url);

        display(4,2,"response returned ".$response->status_line());
        display(4,2,$response->as_string());
        if (!$response->is_success())
        {
            error("bad response from $directory $method $url");
            return;
        }

        $text = $response->as_string();
        $text =~ s/^.*\n\n//s;
        if (!$text)
        {
            error("No xml in result from $directory $method $url");
            return;
        }
        printVarToFile(1,"$dir/$id.xml",$text);
    }

    # see notes in write_tree_cache() on xml encoding
    
    # $text = my_decode_utf8($text);
    
    if (0)
    {
        my $new_text = $text;
        while ($new_text =~ s/((....)...[\x80-\xff]+...(....))//)
        {
            my $bytes = $1;
            my $bytes2 = decode('UTF-8',$bytes);
            display_bytes(0,0,'UTF8',$bytes);
            display_bytes(0,0,'normal',$bytes2);
        }
    }
    
    my $xml = $xml_reader->XMLin($text);
    if (!$xml)
    {
        error("bad xml from $directory $method $url");
        return;
    }

    mb_debug_xml($dbg_xml,"xml",$xml);
    return $xml;
}



sub my_decode_utf8
    # Kebâ€™ Moâ€™
    # Keb E2 80 99  Mo
    #
    # File contains E2 80 99, and no combination
    # of decoders, etc, wants to change that to '
    #
    # $text = unescape_tag($text);
    # $text = decode('UTF-8',$text);
    # $text =~ s/\xE2\x80\x99/'/g;
    # $text = decode("UTF-8", $text);
    # $text = decode("iso-8859-1", $text);
    # $text = decode("utf8", $text);
    # _utf8_on($text);
    # utf8::decode($text);
    # utf8::upgrade($text);
    #
    #
    #
    # Then the problem is compounded for latin characters.
    # Even if I could decode them, they are not liked by the
    # xml parser.  Which means I have to wait, and look at
    # every string in the xml, or conver them to bogus pure
    # ascii.  I'm not sure  is even in the latin ISO-8859-1 set.
    # and I think komodo, at least, is using Western European
    # (CP-1252), anyways ...
{    
    my ($s) = @_;
    $s =~ s/\xE2\x80\x99/'/g;
    $s =~ s/\xC3\xA9/e/;     # é acute
    $s =~ s/\xC3\xAD/i/g;    # í acute not liked by xml
    $s =~ s/\xC5\xBE/z/g;    #  smile not liked by xml
    return $s;
}


sub mb_get_acousticid_xml
{
    my ($dbg_xml,$directory,$id,$method,$url,$params) = @_;
    display(4,0,"get_acousticid_xml($id,$method,$url)");
    my $xml = mb_get_xml($dbg_xml,$directory,$id,$method,$url,$params);
    return if !$xml;
    if ($xml->{status} ne 'ok')
    {
        error("bad xml status ($xml->{status})  from $directory $method $url");
        return;
    }
    return $xml;
}


#-----------------------------------------------------------
# Specific Cached XML Files
#-----------------------------------------------------------

sub mb_get_track_info
    # calls acousticID.org with a fingerprint for a file
    # (given by artisan_id), and asks it to return everything
    # known about the acoustic_id's associated with the
    # fingerprint, and cache the result in /cache/mb_track_info
    #
    # Note that we are calling acousticID.org which is
    # hooked up to musicBrains.org, but is a different site.
	#
	# PRH - *should* call this with fpcalc_id (in x_mbScoreFolder)
	# because multiple artisan_id's could have the same fpcalc_id,
	# and the call to the net will return based on fpcalc_id.
	# Not sure how that effects usage of the items ... 
	
{
    my ($artisan_id,$info) = @_;
    display(3,0,"mb_get_track_info($artisan_id)");

    my $url = 'http://api.acoustid.org/v2/lookup';
    my %params = (
        format => 'xml',
        client => $ACOUSTIC_CLIENT_ID,
        duration => $info->{duration},
        fingerprint => $info->{fingerprint},
        meta => 'recordings recordingids releasegroups releasegroupids releases tracks',
            # other possibilities: compress usermeta sources
    );
    return mb_get_acousticid_xml(3,'mb_track_info',$artisan_id,'post',$url,\%params);
}


#-----------------------------------------------------
# artists
#-----------------------------------------------------

use x_ArtistDefs;

sub mb_find_artist
{
    my ($rec) = @_;
    
    my $name = $rec->{name};
    my $type = $rec->{type};

    # use a strict mapping for certain really important names
    
    $name = $proper_name{$name} if $proper_name{$name};
    
    # remove some remaining punctuation
    # before calling musicBrains web api
    # prh - may prefer to url_encode these
    # prh - need to url encode latin charset
    
    $name =~ s/"//g;
    $name =~ s/''/'/g;
    $name =~ s/://;
    
    # init the return value
    # and do the web lookup
    # short ending if no xml
    # or set the count of returned artists
    
    my $info = {
        status => $ARTIST_STATUS_MB_ERROR,
        type   => '',
        mb_id  => '',
        score  => 0,
        count  => 0,
        match  => 0,
        tags   => ''
    };
        
    my $url = "http://musicbrainz.org/ws/2/artist/?query=artist:\"$name\"";
    my $xml = get_xml(2,'artist_xml',$name,'get',$url);
    return $info if (!$xml);
    debug_xml(2,"music brain artist",$xml);
    my $artist_list = $xml->{'artist-list'};
    my $artists = $artist_list->{artist};
    $artists = [$artists] if (ref($artists) =~ /HASH/);
    $info->{count} = $artist_list->{count};

    # compare the list to the name passed in
    # by changing &/and to plus, removing leading 'the'
    # and removing any punctuation (except plus)
    
    my $found;
    $name =~ s/\s(&|and)\s/+/g;
    $name =~ s/(^|\s)the\s+//;
    $name =~ s/[^+A-Za-z0-9 ]//g;
    for my $artist (@$artists)
    {
        my $name2 = $artist->{name};
        $name2 =~ s/\s(&|and)\s/+/g;
        $name2 =~ s/(^|\s)the\s+//;
        $name2 =~ s/[^+A-Za-z0-9 ]//g;
        
        if (uc($name) eq uc($name2))
        {
            $found = $artist;
            $info->{match}++;
        }
    }

    # set the status based on the count
    # and number of matches
    
    if ($info->{match} > 1)
    {
        $info->{status} = $ARTIST_STATUS_MB_DUPLICATES;
    }
    elsif ($info->{match} == 1)
    {
        $info->{status} = $ARTIST_STATUS_MB_MATCH;
    }
    elsif ($info->{count})
    {
        $info->{status} = $ARTIST_STATUS_MB_NOMATCH_EXACT;
    }
    else
    {
        $info->{status} = $ARTIST_STATUS_MB_NOMATCH;
    }
    
    # set information fields
    # it is up to the client to not use these willy-nilly

    if ($found)
    {
        $info->{score} = $found->{'ext:score'} || 0;
        $info->{type} = lc($found->{type} || '');
        $info->{mb_id} = $found->{id};
    
        my $tags = $found->{'tag-list'} ?$ found->{'tag-list'}->{tag} : undef;
        if ($tags)
        {
            $tags = [$tags] if (ref($tags) =~ /HASH/);
            for my $tag (@$tags)
            {
                $tag->{name} =~ s/[^\x20-xff]//g;
                if ($tag->{name})
                {
                    $info->{tags} .= ' ' if ($info->{tags});
                    $info->{tags} .= $tag->{name};
                }
            }
        }
    }
    
    display(_clip 0,1,"mb_find_artist ".
        pad($info->{score},3)."   ".
        pad($info->{match},2)."/".
        pad($info->{count},3)." ".
        pad($info->{status},16)." ".
        pad($info->{type},9)." ".
        $rec->{name});
    
    return $info;

}


#-------------------------------------------------
# old obsolete routines
#-------------------------------------------------

sub obs_get_acoustic_ids
    # get acoustic_ids from the fpcalc()
    # fingerprint, and proceed to build the
    # tree based on those ids.
{
    my ($info) = @_;
    my $artisan_id = $info->{artisan_id};

    display(2,0,"get_acoustic_ids($artisan_id)");

    my $url = 'http://api.acoustid.org/v2/lookup';
    my %params = (
        format => 'xml',
        client => $ACOUSTIC_CLIENT_ID,
        duration => $info->{duration},
        fingerprint => $info->{fingerprint},
        meta => 'recordings recordingids releasegroups releases tracks usermeta sources',
        # meta => 'recordingsids',
        # meta => 'recordings+recordingids+releases+releaseids+releasegroups+releasegroupids+tracks+compress+usermeta+sources',
    );

    my $xml = get_acousticid_xml(3,'acoustic_id',$artisan_id,'post',$url,\%params);
    return if !$xml;
    my $acoustic_ids = $xml->{results}->{result};
    if (!$acoustic_ids)
    {
        error("no acoustic_ids found for $artisan_id");
        return;
    }
    display(2,1,"ref(acoustic_ids) = ".ref($acoustic_ids));
    
    exit 1;
    
    if (ref($acoustic_ids) =~ /ARRAY/)
    {
        warning(1,2,"multiple acoustic_ids found for $artisan_id");
    }
    else
    {
        $acoustic_ids = [ $acoustic_ids ];
    }
    for my $acoustic_id (@$acoustic_ids)
    {
        if (!$acoustic_id->{id} || !$acoustic_id->{score})
        {
            warning(0,3,"skipping bad acoustic_id or score");
            next;
        }        
        #return if !
        get_recording_ids($info,$acoustic_id);
    }
    
    return 1;
}
    
    
sub obs_get_recording_ids
    # get recording_ids from the acoustic_id
    # and call get_release_ids for each one
{
    my ($info,$acoustic_id) = @_;
    my $artisan_id = $info->{artisan_id};

    display(1,0,"get_recording_ids($acoustic_id->{id})");
    display(1,1,"acoustic_score=$acoustic_id->{score}");

    my $url = 'http://api.acoustid.org/v2/lookup';
    $url .= "?format=xml&client=$ACOUSTIC_CLIENT_ID&meta=recordingids&trackid=$acoustic_id->{id}";
    my $xml = get_acousticid_xml(3,'recording_id',$acoustic_id->{id},'get',$url);
    return if !$xml;

    my $recording_ids = $xml->{results}->{result}->{recordings}->{recording};
    if (!$recording_ids)
    {
        error("no recordsings found for $artisan_id (acoustic_id=$acoustic_id->{id})");
        return;
    }
    
    display(2,1,"ref(recording_ids) = ".ref($recording_ids));
    if (ref($recording_ids) =~ /ARRAY/)
    {
        warning(1,2,"multiple recording_ids for  $artisan_id (acoustic_id=$acoustic_id->{id})");
    }
    else
    {
        $recording_ids = [ $recording_ids ];
    }

    for my $recording_id (@$recording_ids)
    {
        if (!$recording_id->{id})
        {
            warning(0,3,"skipping bad recording_id");
            next;
        }        
        #return if !
        get_release_ids($info,$recording_id);
    }

    return 1;
}


    

sub obs_get_release_ids
    # get musicbrains release_ids from the acousticID
    # recording_id and call get_release_info for each one
{
    my ($info,$recording_id) = @_;
    my $artisan_id = $info->{artisan_id};

    display(1,0,"get_release_ids($recording_id->{id})");
    my $url = "http://musicbrainz.org/ws/2/recording/?query=rid:$recording_id->{id}";
    my $xml = get_xml(3,'release_id',$recording_id->{id},'get',$url);
    return if (!$xml);

    debug_xml(3,"music brain release",$xml);
    my $recording_list = $xml->{'recording-list'};
    my $count = $recording_list->{count};
    my $recording = $recording_list->{recording};
    my $release_list = $recording->{'release-list'};
    my $releases = $release_list->{release};
    
    if (!$recording_list || !$count || !$recording || !$release_list || !$releases)
    {
        error("Could not get recording_list, count, recording, or release list for $artisan_id");
        return;
    }

    get_artist($recording->{'artist-credit'}->{'name-credit'});
    display(2,1,"ref(releases=$releases)=".ref($releases));

    if (ref($releases) =~ /ARRAY/)
    {
        warning(1,2,"multiple releases for recording_id=$recording_id->{id}");
    }
    else
    {
        $releases = [ $releases ];
    }
    
    for my $release (@$releases)
    {
        return if !get_release_info($info,$release);
    }    
    
    return 1;
}



sub obs_get_release_info
    # get musicbrainz recording release info
    # from a recording_id
{
    my ($info,$release) = @_;
    my $artisan_id = $info->{artisan_id};

    display(1,0,"get_release_info($release->{id})");

    my $medium_list = $release->{'medium-list'};
    my $medium = $medium_list->{medium};
    my $track_list = $medium->{'track-list'};
    my $track = $track_list->{track};

    display(1,1,"mb release status=$release->{status}")
        if ($release->{status});
    display(1,1,"release_group=$release->{'release-group'}->{type}")
        if ($release->{'release-group'}->{type});
    display(1,1,"track_count=$medium_list->{'track-count'}");
    display(1,1,"track_number=$track->{number}");
    
    #display_bytes(0,3,"album",$release->{title});
    $release->{title} =~ s/\x{2019}/'/g;
    display(1,1,"album=$release->{title}");
    
    #display_bytes(0,3,"title",$track->{title});
    $track->{title} =~ s/\x{2019}/'/g;
    display(1,1,"title=$track->{title}");
    display(2,1,"album_id=$release->{id}");
    
    # remember all the albums this acoustic_id finger
    # print appears on for use by client.
    
    $info->{albums} = {} if (!$info->{albums});
    $info->{albums}->{$release->{title}} = 1;
    
    return 1;
}


sub obs_get_track_info
{
    my ($path) = @_;
    display(0,0,"get_track_info($path)");
    
    my $minfo = MediaFile->new($path);
        # never fails
        # if it has a artisan_id, that means
        # there's a usable fingerprint to proceed with
        # and is faster than leting get_fpcalc_info fail (again)
        
    my $artisan_id = $minfo->{artisan_id};
    if (!$artisan_id)
    {
        error("no artisan id for $path");
        return;
    }
    
    my $info = $minfo->get_fpcalc_info();
        # should not fail if artisan_id
    if (!$info)
    {
        error("no fpcalc_info for $path");
        return;
    }
    $info->{artisan_id} = $artisan_id;
    
    # add onto, and return the info record
    
    # return if (!
    get_acoustic_ids($info);
    return $info;
}



1;
