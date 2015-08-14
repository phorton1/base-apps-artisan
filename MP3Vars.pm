package MP3Vars;
use strict;
use warnings;

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		
		$WRITE_VERSION
		
        @mp3_genres
        %rva2_channel_types

		%v22_tag_names
		%v23_tag_names_deprecated
		%v23and24_tag_names
		%v23_tag_names
		%v24_tag_names
		%all_v2_tag_names
        %v22_to_v23_id
    );
}



our $WRITE_VERSION = 4;
	# Whether to write files as ID3v2.3 or 2.4
	# Initially used v4, but found that windows explorer didn't
	# understand them so decided to use V3 instead (which it does
	# understand).
	#
	# This needs to be known during reading, which is when we actually
	# map the tags.
	#
	# However, I then decided not to write tags at all, so
	# I prefer the in-memory representation of version 4
	# which drops less stuff.
	

our @mp3_genres = (
    'Blues',
    'Classic Rock',
    'Country',
    'Dance',
    'Disco',
    'Funk',
    'Grunge',
    'Hip-Hop',
    'Jazz',
    'Metal',
    'New Age',
    'Oldies',
    '',				# V1 'Other' genre may mess up my use of the term.  It is a non-genre for me.
    'Pop',
    'R&B',
    'Rap',
    'Reggae',
    'Rock',
    'Techno',
    'Industrial',
    'Alternative',
    'Ska',
    'Death Metal',
    'Pranks',
    'Soundtrack',
    'Euro-Techno',
    'Ambient',
    'Trip-Hop',
    'Vocal',
    'Jazz+Funk',
    'Fusion',
    'Trance',
    'Classical',
    'Instrumental',
    'Acid',
    'House',
    'Game',
    'Sound Clip',
    'Gospel',
    'Noise',
    'AlternRock',
    'Bass',
    'Soul',
    'Punk',
    'Space',
    'Meditative',
    'Instrumental Pop',
    'Instrumental Rock',
    'Ethnic',
    'Gothic',
    'Darkwave',
    'Techno-Industrial',
    'Electronic',
    'Pop-Folk',
    'Eurodance',
    'Dream',
    'Southern Rock',
    'Comedy',
    'Cult',
    'Gangsta',
    'Top 40',
    'Christian Rap',
    'Pop/Funk',
    'Jungle',
    'Native American',
    'Cabaret',
    'New Wave',
    'Psychadelic',
    'Rave',
    'Showtunes',
    'Trailer',
    'Lo-Fi',
    'Tribal',
    'Acid Punk',
    'Acid Jazz',
    'Polka',
    'Retro',
    'Musical',
    'Rock & Roll',
    'Hard Rock',

    # winamp genres

    'Folk',
    'Folk-Rock',
    'National Folk',
    'Swing',
    'Fast Fusion',
    'Bebop',
    'Latin',
    'Revival',
    'Celtic',
    'Bluegrass',
    'Avantgarde',
    'Gothic Rock',
    'Progressive Rock',
    'Psychedelic Rock',
    'Symphonic Rock',
    'Slow Rock',
    'Big Band',
    'Chorus',
    'Easy Listening',
    'Acoustic',
    'Humour',
    'Speech',
    'Chanson',
    'Opera',
    'Chamber Music',
    'Sonata',
    'Symphony',
    'Booty Bass',
    'Primus',
    'Porn Groove',
    'Satire',
    'Slow Jam',
    'Club',
    'Tango',
    'Samba',
    'Folklore',
    'Ballad',
    'Power Ballad',
    'Rhythmic Soul',
    'Freestyle',
    'Duet',
    'Punk Rock',
    'Drum Solo',
    'Acapella',
    'Euro-House',
    'Dance Hall',
    'Goa',
    'Drum & Bass',
    'Club-House',
    'Hardcore',
    'Terror',
    'Indie',
    'BritPop',
    'Negerpunk',
    'Polsk Punk',
    'Beat',
    'Christian Gangsta Rap',
    'Heavy Metal',
    'Black Metal',
    'Crossover',
    'Contemporary Christian',
    'Christian Rock',
    'Merengue',
    'Salsa',
    'Thrash Metal',
    'Anime',
    'JPop',
    'Synthpop',
);

my $c = -1;
our %mp3_genres = map {($_, ++$c, lc, $c)} @mp3_genres;


our	%rva2_channel_types = (
    0x00 => 'OTHER',
    0x01 => 'MASTER',
    0x02 => 'FRONT_RIGHT',
    0x03 => 'FRONT_LEFT',
    0x04 => 'BACK_RIGHT',
    0x05 => 'BACK_LEFT',
    0x06 => 'FRONT_CENTER',
    0x07 => 'BACK_CENTER',
    0x08 => 'SUBWOOFER',
);


# version 2.2 tags

our %v22_tag_names =
(
    # v2.2 tags
    'BUF' => 'Recommended buffer size',
    'CNT' => 'Play counter',
    'COM' => 'Comments',
    'CRA' => 'Audio encryption',
    'CRM' => 'Encrypted meta frame',
    'ETC' => 'Event timing codes',
    'EQU' => 'Equalization',
    'GEO' => 'General encapsulated object',
    'IPL' => 'Involved people list',
    'LNK' => 'Linked information',
    'MCI' => 'Music CD Identifier',
    'MLL' => 'MPEG location lookup table',
    'PIC' => 'Attached picture',
    'POP' => 'Popularimeter',
    'REV' => 'Reverb',
    'RVA' => 'Relative volume adjustment',
    'SLT' => 'Synchronized lyric/text',
    'STC' => 'Synced tempo codes',
    'TAL' => 'Album/Movie/Show title',
    'TBP' => 'BPM (Beats Per Minute)',
    'TCM' => 'Composer',
    'TCO' => 'Content type',
    'TCR' => 'Copyright message',
    'TDA' => 'Date',
    'TDY' => 'Playlist delay',
    'TEN' => 'Encoded by',
    'TFT' => 'File type',
    'TIM' => 'Time',
    'TKE' => 'Initial key',
    'TLA' => 'Language(s)',
    'TLE' => 'Length',
    'TMT' => 'Media type',
    'TOA' => 'Original artist(s)/performer(s)',
    'TOF' => 'Original filename',
    'TOL' => 'Original Lyricist(s)/text writer(s)',
    'TOR' => 'Original release year',
    'TOT' => 'Original album/Movie/Show title',
    'TP1' => 'Lead artist(s)/Lead performer(s)/Soloist(s)/Performing group',
    'TP2' => 'Band/Orchestra/Accompaniment',
    'TP3' => 'Conductor/Performer refinement',
    'TP4' => 'Interpreted, remixed, or otherwise modified by',
    'TPA' => 'Part of a set',
    'TPB' => 'Publisher',
    'TRC' => 'ISRC (International Standard Recording Code)',
    'TRD' => 'Recording dates',
    'TRK' => 'Track number/Position in set',
    'TSI' => 'Size',
    'TSS' => 'Software/hardware and settings used for encoding',
    'TT1' => 'Content group description',
    'TT2' => 'Title/Songname/Content description',
    'TT3' => 'Subtitle/Description refinement',
    'TXT' => 'Lyricist/text writer',
    'TXX' => 'User defined text information frame',
    'TYE' => 'Year',
    'UFI' => 'Unique file identifier',
    'ULT' => 'Unsychronized lyric/text transcription',
    'WAF' => 'Official audio file webpage',
    'WAR' => 'Official artist/performer webpage',
    'WAS' => 'Official audio source webpage',
    'WCM' => 'Commercial information',
    'WCP' => 'Copyright/Legal information',
    'WPB' => 'Publishers official webpage',
    'WXX' => 'User defined URL link frame',

    # non-standard v2 flags

    'TCP' => 'iTunes Compilation Flag',
    'CM1' => 'non-standard comment flag',
);


# v2.3 (deprecated in v2.4) tags

our %v23_tag_names_deprecated = (

    'EQUA' => 'v3 Equalization',
        # replaced by EQU2, 'Equalisation (2)'
    'IPLS' => 'v3 Involved people list',
        # This frame is replaced by the two frames
        # TMCL, 'Musician credits list', and
        # TIPL, 'Involved people list'
    'RVAD' => 'v3 Relative volume adjustment',
        # replaced by RVA2, 'Relative volume adjustment (2)'

    # prh - we're gonna drop all these
    # and only accept TYER from old files

    'TDAT' => 'v3 Date',
        # replaced by TDRC, 'Recording time'
    'TIME' => 'v3 Time',
        # replaced by TDRC, 'Recording time'
    'TRDA' => 'v3 Recording dates',
        # replaced by TDRC, 'Recording time'

    'TORY' => 'v3 Original release year',
        # replaced by TDOR, 'Original release time'
    'TSIZ' => 'v3 Size',
        # REMOVED
    'TYER' => 'v3 Year',
        # replaced by TDRC, 'Recording time'

);


# tags common to v2.3 and v2.4

my %v23and24_tag_names =
(
    'AENC' => 'Audio encryption',
    'APIC' => 'Attached picture',
    'COMM' => 'Comments',
    'COMR' => 'Commercial frame',
    'ENCR' => 'Encryption method registration',
    'ETCO' => 'Event timing codes',
    'GEOB' => 'General encapsulated object',
    'GRID' => 'Group identification registration',
    'LINK' => 'Linked information',
    'MCDI' => 'Music CD identifier',
    'MLLT' => 'MPEG location lookup table',
    'OWNE' => 'Ownership frame',
    'PCNT' => 'Play counter',
    'POPM' => 'Popularimeter',
    'POSS' => 'Position synchronisation frame',
    'PRIV' => 'Private frame',
    'RBUF' => 'Recommended buffer size',
    'RVRB' => 'Reverb',
    'SYLT' => 'Synchronized lyric/text',
    'SYTC' => 'Synchronized tempo codes',
    'TALB' => 'Album/Movie/Show title',
    'TBPM' => 'BPM (beats per minute)',
    'TCOM' => 'Composer',
    'TCON' => 'Content type',
    'TCOP' => 'Copyright message',
    'TDLY' => 'Playlist delay',
    'TENC' => 'Encoded by',
    'TEXT' => 'Lyricist/Text writer',
    'TFLT' => 'File type',
    'TIT1' => 'Content group description',
    'TIT2' => 'Title/songname/content description',
    'TIT3' => 'Subtitle/Description refinement',
    'TKEY' => 'Initial key',
    'TLAN' => 'Language(s)',
    'TLEN' => 'Length',
    'TMED' => 'Media type',
    'TOAL' => 'Original album/movie/show title',
    'TOFN' => 'Original filename',
    'TOLY' => 'Original lyricist(s)/text writer(s)',
    'TOPE' => 'Original artist(s)/performer(s)',
	'TORY' => 'Original release date',
    'TOWN' => 'File owner/licensee',
    'TPE1' => 'Lead performer(s)/Soloist(s)',
    'TPE2' => 'Band/orchestra/accompaniment',
    'TPE3' => 'Conductor/performer refinement',
    'TPE4' => 'Interpreted, remixed, or otherwise modified by',
    'TPOS' => 'Part of a set',
    'TPUB' => 'Publisher',
	'TSO2' => '2nd Copyright',
    'TRCK' => 'Track number/Position in set',
    'TRSN' => 'Internet radio station name',
    'TRSO' => 'Internet radio station owner',
    'TSRC' => 'ISRC (international standard recording code)',
    'TSSE' => 'Software/Hardware and settings used for encoding',
    'TXXX' => 'User defined text information frame',
    'UFID' => 'Unique file identifier',
    'USER' => 'Terms of use',
    'USLT' => 'Unsychronized lyric/text transcription',
    'WCOM' => 'Commercial information',
    'WCOP' => 'Copyright/Legal information',
    'WOAF' => 'Official audio file webpage',
    'WOAR' => 'Official artist/performer webpage',
    'WOAS' => 'Official audio source webpage',
    'WORS' => 'Official internet radio station homepage',
    'WPAY' => 'Payment',
    'WPUB' => 'Publishers official webpage',
    'WXXX' => 'User defined URL link frame',

    # non standard flags

    'TCMP' => 'iTunes Compilation Flag',
    'NCON' => 'Musicmatch privat flag',

	# shouldn't be in v2.3
    'TSOP' => 'Performer sort order',
    'TSST' => 'Set subtitle',

);



# v2.4 (only) tags

our %v24_only_tag_names =
(
    'ASPI' => 'v4 Audio seek point index',
    'EQU2' => 'v4 Equalisation (2)',
    'RVA2' => 'v4 Relative volume adjustment (2)',
    'SEEK' => 'v4 Seek frame',
    'SIGN' => 'v4 Signature frame',
    'TDEN' => 'v4 Encoding time',
    'TDOR' => 'v4 Original release time',
    'TDRC' => 'v4 Recording time',
    'TDRL' => 'v4 Release time',
    'TDTG' => 'v4 Tagging time',
    'TIPL' => 'v4 Involved people list',
    'TMCL' => 'v4 Musician credits list',
    'TMOO' => 'v4 Mood',
    'TPRO' => 'v4 Produced notice',
    'TSOA' => 'v4 Album sort order',
    'TSOT' => 'v4 Title sort order',
);


our %v23_tag_names =
(
	(%v23_tag_names_deprecated),
	(%v23and24_tag_names),
);

our %v24_tag_names =
(
	(%v23and24_tag_names),
	(%v24_only_tag_names)
);

our %all_v2_tag_names =
(
	(%v22_tag_names),
	(%v23_tag_names_deprecated),
	(%v23and24_tag_names),
	(%v24_only_tag_names)
);
	
	

# mapping from v2 to v3

our %v22_to_v23_id =
(
    'BUF' => 'RBUF',
    'CNT' => 'PCNT',
    'COM' => 'COMM',
    'CRA' => 'AENC',

    # V3 does not have an equivilant of CRM
    # 'CRM' => 'Encrypted meta frame',
    # all frames in V3 may be encrypted, and
    # so this probably maps to APIC, etc.
    # We will error on this frame type with
    # an undefined V2 mappping

    'ETC' => 'ETC0',
    'EQU' => 'EQUA',
    'GEO' => 'GEOB',
    'IPL' => 'IPLS',
    'LNK' => 'LINK',
    'MCI' => 'MCDI',
    'MLL' => 'MLLT',
    'PIC' => 'APIC',
    'POP' => 'POPM',
    'REV' => 'RVRB',
    'RVA' => 'RVAD',
    'SLT' => 'SYLT',
    'STC' => 'SYTC',
    'TAL' => 'TALB',
    'TBP' => 'TBPM',
    'TCM' => 'TCOM',
    'TCO' => 'TCON',
    'TCR' => 'TCOP',
    'TDA' => 'TDAT',
    'TDY' => 'TDLY',
    'TEN' => 'TENC',
    'TFT' => 'TFLT',
    'TIM' => 'TIME',
    'TKE' => 'TKEY',
    'TLA' => 'TLAN',
    'TLE' => 'TLEN',
    'TMT' => 'TMED',
    'TOA' => 'TOAL',
    'TOF' => 'TOFN',
    'TOL' => 'TOLY',
    'TOR' => 'TORY',
    'TOT' => 'TOAL',
    'TP1' => 'TPE1',
    'TP2' => 'TPE2',
    'TP3' => 'TPE3',
    'TP4' => 'TPE4',
    'TPA' => 'TPOS',
    'TPB' => 'TPUB',
    'TRC' => 'TSRC',
    'TRD' => 'TRDA',
    'TRK' => 'TRCK',
    'TSI' => 'TSIZ',
    'TSS' => 'TSSE',
    'TT1' => 'TIT1',
    'TT2' => 'TIT2',
    'TT3' => 'TIT3',
    'TXT' => 'TEXT',
    'TXX' => 'TXXX',
    'TYE' => 'TYER',
    'UFI' => 'UFID',
    'ULT' => 'USLT',
    'WAF' => 'WOAF',
    'WAR' => 'WOAR',
    'WAS' => 'WORS',
    'WCM' => 'WCOM',
    'WCP' => 'WCOP',
    'WPB' => 'WPUB',
    'WXX' => 'WXXX',

    # drop non-standard frames

    'TCP' => '',
    'CM1' => '',

);



1;
