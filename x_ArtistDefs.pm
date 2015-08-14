#-------------------------------------------------------
# ArtistDefs.pm - constants for artists
#-------------------------------------------------------
# and a lot of text
#
# ARTIST TEXT FILES are as persistent as MP3 files themselves.
# REMOVING ARTIST TEXT FILES should only be dont by automated
#    proesses that DONT REMOVE CLASSIFIED ARTISTS, or else
#    manual changes to the text files, like the 'allow_search'
#    bit, will be lost.


package x_ArtistDefs;
use strict;
use warnings;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
            @artist_field_defs

            $ARTIST_VARIOUS
            $ARTIST_UNKNOWN
            $ARTIST_CLASS_UNRESOLVED
            $ARTIST_CLASS_FROMTAG
            
            $ARTIST_TYPE_PERSON

            $ARTIST_STATUS_NONE
            $ARTIST_STATUS_MB_ERROR
            $ARTIST_STATUS_MB_NOMATCH
            $ARTIST_STATUS_MB_NOMATCH_EXACT
            $ARTIST_STATUS_MB_DUPLICATES
            $ARTIST_STATUS_MB_MATCH
            $ARTIST_STATUS_MB_VERIFIED

            %init_artist_class
            %proper_name
            
        );
}


# artist name constants
# case insenstive maches should be used

our $ARTIST_VARIOUS = 'Various';
our $ARTIST_UNKNOWN = 'Unknown';

our $ARTIST_CLASS_UNRESOLVED = 'unresolved';
our $ARTIST_CLASS_FROMTAG    = 'tag';

our $ARTIST_TYPE_PERSON  = 'person';    # 1
    # integer could be synonymous with is_person()
    # later might add 'fictional'
    
our $ARTIST_STATUS_NONE          = '';              # 0
our $ARTIST_STATUS_MB_ERROR      = 'mb_error';      # 1
our $ARTIST_STATUS_MB_NOMATCH    = 'mb_nomatch';    # 2
our $ARTIST_STATUS_MB_NOMATCH_EXACT = 'mb_nomatch_exact';

our $ARTIST_STATUS_MB_DUPLICATES = 'mb_duplicates'; # 3
our $ARTIST_STATUS_MB_MATCH      = 'mb_match';      # 4
our $ARTIST_STATUS_MB_VERIFIED   = 'mb_verified';   # 5


# artist database record definition

our @artist_field_defs = (
    'name    VARCHAR(128)',
        # The 'cleaned' name of the artist
    'class   VARCHAR(16)',
        # '' or one of my classes
    'type     VARCHAR(16)',
        # '' or person
    'source   VARCHAR(1024)',
        # fully qualified path to the file or folder where
        # we first enountered this artist name;

    # stuff from musicBrainz, essentially
    
    'status  VARCHAR(16)',
    'mb_id   VARCHAR(36)',
    'tags    VARCHAR(256)',

    # unused so far
    
    'allow_substring_match INTEGER',
        # assigned but not used yet
    'aliases    VARCHAR(2048)',
        # tab delimited strings
    'member_of  VARCHAR(2048)',
        # tab delimited strings
    'search_date VARCHAR(30)',
        # YYYY-MM-DD hh:mm:ss +zz:zz 

   
        
    # possibles
    
    # mb_id(s)
    # mb_certainty
    # last_lookup
);





=pod

At their most basic, Artists and Genres are just Names,
essentially random strings, that have been encountered
while scanning files and folders, where we have hints that
they are what they purport to be. But there can also be
random garbage, essentially, in either of the lists, and
therin is the rub.

Artists come from

    folder (imposed album) names
    filenames (imposed artist) names
    tags in media files (mp3/wma/etc)
        artist
        album_artist
            the semantics in tags are iffy.
            basically i have pre-filtered them to
            these two semantics at this time, and
            only (once) have allowed author/composer
            to be used for the artist, when an artist
            could not otherwise be found in the tags,
            but this assumption is premade by the api's
            to the perl tag routines, so I don't know
            that much about what's under it. Thus,
            for now, these are the only two tags,
            and my MediaFile filter (without what
            are currently called 'default values),
            provides all the tag inputs to the system.
            title
            album
            this gets really iffy, but an artist could
            also come from the tag for the track title
            and/or the album title using heuristics.
            I don't currently do this, only applying
            those heuristics to file and folder names,
            which, particularly for the classified folder
            trees, more or less invariantly carry an
            'imposed' artist name separated by ' - ' from 
            and 'imposted' album name.
    internet lookups
        likewise, once we start looking into artists
        on the net we may find a variety of names of
        interest, from as important ones as figuring
        out a reliable artist name to display for
        an album or track, to more obscure and complicated
        relationships like aliases, membership, additional
        contributors, etc.
        
        And all of a sudden you find yourself wanting
        to duplicate the whole musicBrainze relationship model.
        This goes to the 'class' that will be assigned
        to the artist, after this analysis.
    constants
        There are a few artist names that are special
        predefined reserved words. The semantics
        of these constants depend on the context.
        
        'various'
            multiple unnamed artists
            prefered for a folder name
            means that more than one artist
            is associated with the track or album
            implies that we think it's ok
        'unknown'
            means that we don't know who
            to attribute a folder or track to, but
            the folder either contains one track, or
            we had external hints that the contained
            tracks were all by the same artist.
            in general, unknown is not used in
            track filenames, though it could be
            passed back as a tag, it's equivilant
            to '' for tags.
            
        In practice, for folder names, unknown means
        we havn't done our homework and various means
        that we think that's ok, or somebody else told
        us it was ok.
        
        INVARIANT: unknown should never be in a track filename
            
        IN PRACTICE: Folder names with unknown as the artist
            will be scanned ad naseum and should be attributed
            manually as necessary (creating new classified artists
            like 'Brazilian Musicians') to prevent, ultimately,
            repeated attempts to identify the artists. More later
            


artist =

    class - a classified artist is one that I have deemed
        to be the most important in the system.
        
        It is important enough to always show in artist listings.
        
        The class value is a string that provides a default
        genre for items that can be said to primarily belong
        to the artist. 
        
        The genres defined by classified artists are, likewise
        deemed to be the most important in the system and
        to always show in genre listings. Thus, classifying
        an artist creates a classified genre, in asmuch as
        genres, like artists can be a mess.
        
        The artist class also provides a default location
        in the system for placing new albums (folders) associated
        with the artist
        
        A folder name for an artist (Xmas, Quincy Jones, Theo)
        may be found in more than one location. The artist class
        is realy just my 'default genre', and 'default location'
        for the artist.

        Otherwise, the class is a set of constants that
        tell where the artist was first encountered:
        
        'unresolved'
        
            came from a folder or filename in the /unresolved
            following my dash '-' naming convention.
            
            By definition, any (new) artists in the /albums or /singles
            folders are classified according to their location

        'tag'
        
            the artist name was first encountered as
            a tag in a media file. In this sense it
            really doesn't matter if it was an album_artist,
            or an 'artist' tag, esp to the degree these
            tags are pre-filtered by MediaFile. 'tag'
            just means 'here's a name, see if you can
            do anything with it'
           
        ''
            for the time being, we are going to consider that
            any other artists we bring into the system as a
            result of net lookups will be classified, and if
            not, '' means they came from an internet lookup
            but have not yet been classified.
            
        other constants
        
            there may be other constants introduced into the
            system as a result of evolution.  For instance
            perhaps I will want a 'class' of artists called
            'Sound Engineer', that does not map to anything
            in the genre tree.
            
            On the other hand, if I'm going to have genres,
            that would imply a 'genre' of 'songs with song
            engineer credits', which would not be too bad.

    type (all constants)
    
        person
        band = group, ensemble, orchestra, ensemble, etc)
            i choose this identifier over 'group' because
            group 'type=group' in code would be hard to identify
            where as 'type=band' would clue me in faster as to
            what kind of thing we are typing (an artist)
        fictional (not used yet)
            'Hootie' is not a fictional member of 'Hootie and the Blowfish'
            'The Hot Licks' are not a fictional member of 'Dan Hicks and the Hot Licks'
            In general, I don't keep track of fictional subnames.
            There are real people, and there bands.

    alias (multiple strings)
    
        different exact spellings for the artist used
        in attempting to place initial new items from
        unknown artists, we must not only search through
        artists, but their aliases as well.
        
    member_of (multiple strings)
        'David Crosby' type person and is a member of
            'Crosby, Stills, Nash, and Young' has an alias of
                'CSNY' and has type
                band
        'Frank Sinatra' is type person and is a member of
            'Frank Sinatra and Ella Fitzgerald' which is of type
                band
        'Banny Goodman' is type person and is a member of
            'The Hot Band' which is type band and is a member of'
                'Count Bassie and The Hot Band' which is of type
                    band
    
        Basicallly member_of is used in top down searches for
        works related to the arrist, and bottom up attributions
        of particular items
        
        'The Bird Song' by 'Count Bassie and the Hot Band'
            is attributable to 'Couut Basie', 'The Hot Band',
            and 'Benny Goodman'
    
        The class of 'The Bird Song' would be given by the
            class of 'Count Bassie and the Hot Band'.
            
        The class of 'The Bird Song' could be
        *initially determined* by taking the first class found,
        breadth first, through the artist membership tree
        taking the first actual class (not unresolved, tag,
        or '') found.
        
    allow_substring_match - 0/1

        set to 1 by default for artists of type 'person',
        or (bands) who's name is more than one word,
        or whose  class is 'classical'.
        Can be manually set in text files for other
        bands with sufficiently unique names (Phish, Cubanismo)
        
        Matching artist names must be done on a word basis,
        so substring in this context means matching consecutive
        strings of vords, not a call to substr()!

        When trying to identify a new work we *may*
        establish it's class based on the class of an
        an existing artist's name, and THEN try to
        figure out the rest of the string.
                
        Substring matches generally work for artists of type
        'person' ... Frank Sinatra is a common subname
        within a 'band' name. They also generally work
        for bands if the name is sufficiently unique,
        like the Count Bassie Orchestera, but fail on
        bands like 'Air', 'Train', and 'War'.

        if an artist name is allowed a substring match,
        so are it's aliases.
        
        Note that 'Crosby' is NOT an alias of "David Crosby',
        even though 'Crosby Stills Nash and Young' happens
        to exist as a band!



    status
    
        Independent of the class, there is a field which
        tells how far we have gone to lookup the artist
        on the net.  '' means we have never done a lookup.
        
        official
        
            the artist has been verified to exist,
            with a high degree of certainty, on one ore
            more internet sites. This means that one
            or more 'id's will be assigned to this artist.
            
        ambiguous
        
            the artist search has turned up more than
            one exact match which needs to be disabmbiguated
            
        none
        
            the artist has been searched and no results
            of a sufficiantly high degree of certainty
            could be found. So, classified artists with
            a status of 'none' means that they are friends,
            me, or otherwise, an artist name that I created
            
        unsearched
        
=cut


our %init_artist_class;
    # constants to be hidden in some artitsDefs.pm
$init_artist_class{"Aaron Neville"}                     = ['person', "NewOrleans"];
$init_artist_class{"Air"}                               = ['band',   "Rock Alt"];
$init_artist_class{"Al Green"}                          = ['person', "R&B"];
$init_artist_class{"Al Jarreau"}                        = ['person', "Jazz Soft"];
$init_artist_class{"Alain Peters"}                      = ['person', "World Main"];
$init_artist_class{"Albert Collins"}                    = ['person', "Blues Old"];
$init_artist_class{"Alfredo Escudero"}                  = ['person', "World Tipico"];
$init_artist_class{"Ali Farka Toure"}                   = ['person', "World African"];
$init_artist_class{"Anderson-Bruford-Wakeman-Howe"}     = ['band',   "Rock Alt"];
$init_artist_class{"Andy Williams"}                     = ['person', "Christmas"];
$init_artist_class{"Arrested Development"}              = ['band',   "Rock Alt"];
$init_artist_class{"Asleep At The Wheel"}               = ['band',   "Country"];
$init_artist_class{"B.B. King"}                         = ['person', "Blues Old"];
$init_artist_class{"Bach"}                              = ['person', "Classical"];
$init_artist_class{"Bach, Handel, and Pachelbel"}       = ['band',   "Classical"];
$init_artist_class{"Baroque"}                           = ['band',   "Classical"];
$init_artist_class{"Beat Farmers"}                      = ['band',   "SanDiegoLocals"];
$init_artist_class{"Beethoven"}                         = ['person', "Classical"];
$init_artist_class{"Bela Fleck"}                        = ['person', "Jazz Soft"];
$init_artist_class{"Big Al Carson"}                     = ['person', "NewOrleans"];
$init_artist_class{"Big Head Todd & the Monsters"}      = ['band',   "Rock Alt"];
$init_artist_class{"Bill Morrissey"}                    = ['person', "Rock Alt"];
$init_artist_class{"Bill Morrissey & Greg Brown"}       = ['band',   "Rock Alt"];
$init_artist_class{"Billie Holliday"}                   = ['person', "Jazz Old"];
$init_artist_class{"Billy Joel"}                        = ['person', "Rock Soft"];
$init_artist_class{"Billy Lee and the Swamp Critters"}  = ['band',   "Productions Other"];
$init_artist_class{"Billy McLaughlin"}                  = ['person', "Rock Alt"];
$init_artist_class{"Bing Crosby"}                       = ['person', "Christmas"];
$init_artist_class{"Blacksmith Union"}                  = ['band',   "SanDiegoLocals"];
$init_artist_class{"Blue By Nature"}                    = ['band',   "Blues New"];
$init_artist_class{"Blues Traveler"}                    = ['band',   "Rock Main"];
$init_artist_class{"Bob Dylan"}                         = ['person', "Rock Main"];
$init_artist_class{"Bob Dylan & Johnny Cash"}           = ['band',   "Rock Main"];
$init_artist_class{"Bob Dylan & Pete Seeger"}           = ['band',   "Rock Main"];
$init_artist_class{"Bob Dylan & Van Morrison"}          = ['band',   "Rock Main"];
$init_artist_class{"Bob Marley"}                        = ['person', "Reggae"];
$init_artist_class{"Bob Marley and the Wailers"}        = ['band',   "Reggae"];
$init_artist_class{"Bob Seger"}                         = ['person', "Rock Main"];
$init_artist_class{"Bonnie Raitt"}                      = ['person', "Rock Main"];
$init_artist_class{"Boozoo Chavis"}                     = ['person', "Zydeco"];
$init_artist_class{"Brahms"}                            = ['person', "Classical"];
$init_artist_class{"Brian Setzer Orchestra"}            = ['band',   "Jazz Swing"];
$init_artist_class{"Bruce Hornsby & The Range"}         = ['band',   "Rock Main"];
$init_artist_class{"Bruce Springsteen"}                 = ['person', "Rock Alt"];
$init_artist_class{"Buckwheat Zydeco"}                  = ['person', "Zydeco"];
$init_artist_class{"Buddha Pests"}                      = ['band',   "Productions Bands"];
$init_artist_class{"Buddy Guy"}                         = ['person', "Blues Old"];
$init_artist_class{"Buena Vista Social Club"}           = ['band',   "World Latin"];
$init_artist_class{"Buffalo Springfield"}               = ['band',   "Rock Soft"];
$init_artist_class{"CJ Hutchins"}                       = ['person', "Friends"];
$init_artist_class{"Caetano Veloso"}                    = ['person', "World African"];
$init_artist_class{"Cannonball Adderley"}               = ['person', "Jazz Old"];
$init_artist_class{"Carl Erca and Friends"}             = ['person', "Jazz New"];
$init_artist_class{"Cat Stevens"}                       = ['person', "Rock Soft"];
$init_artist_class{"Cesaria Evora"}                     = ['person', "World Tipico"];
$init_artist_class{"Charles Mingus"}                    = ['person', "Jazz Old"];
$init_artist_class{"Charlie Parker"}                    = ['person', "Jazz Old"];
$init_artist_class{"Chet Atkins"}                       = ['person', "Country"];
$init_artist_class{"Chicago"}                           = ['band',   "Rock Main"];
$init_artist_class{"Chris Duarte Group"}                = ['band',   "Blues New"];
$init_artist_class{"Chris Rea"}                         = ['person', "Rock Alt"];
$init_artist_class{"Chune"}                             = ['band',   "SanDiegoLocals"];
$init_artist_class{"Cirque Du Soleil"}                  = ['band',   "World Main"];
$init_artist_class{"Counting Crows"}                    = ['band',   "Rock Main"];
$init_artist_class{"Cowboy Mouth"}                      = ['band',   "NewOrleans"];
$init_artist_class{"Creedence Clearwater Revival"}      = ['band',   "Rock Main"];
$init_artist_class{"Crosby & Nash"}                     = ['band',   "Rock Soft"];
$init_artist_class{"Crosby, Stills & Nash"}             = ['band',   "Rock Soft"];
$init_artist_class{"Crosby, Stills, Nash & Young"}      = ['band',   "Rock Soft"];
$init_artist_class{"Crusaders"}                         = ['band',   "R&B"];
$init_artist_class{"Cubanismo"}                         = ['band',   "World Latin"];
$init_artist_class{"Curtis Mayfield"}                   = ['person', "R&B"];
$init_artist_class{"Dan Hicks"}                         = ['person', "Favorite"];
$init_artist_class{"Dan Hicks & the Acoustic Warriors"} = ['band',   "Favorite"];
$init_artist_class{"Dan Hicks and the Hot Licks"}       = ['band',   "Favorite"];
$init_artist_class{"Dave Brubeck"}                      = ['person', "Jazz Old"];
$init_artist_class{"Dave Grusin"}                       = ['person', "Jazz Old"];
$init_artist_class{"Dave Hole"}                         = ['person', "Blues New"];
$init_artist_class{"Dave Matthews Band"}                = ['band',   "Favorite"];
$init_artist_class{"David Benoit"}                      = ['person', "Christmas"];
$init_artist_class{"David Bowie"}                       = ['person', "Rock Alt"];
$init_artist_class{"David Crosby"}                      = ['person', "Rock Soft"];
$init_artist_class{"David Taylor and Mary O'Brian"}     = ['person', "SanDiegoLocals"];
$init_artist_class{"De La Soul"}                        = ['band',   "Rock Alt"];
$init_artist_class{"Dead Can Dance"}                    = ['band',   "World Main"];
$init_artist_class{"DeadEnuf"}                          = ['band',   "Productions Bands"];
$init_artist_class{"Delbert McClinton"}                 = ['person', "Favorite"];
$init_artist_class{"Delbert McClinton & Bonnie Raitt"}  = ['band',   "Rock Main"];
$init_artist_class{"Delbert McClinton & T Graham Brown"} =['band',    "Favorite"];
$init_artist_class{"Delbert Mcclinton & Marcia Ball"}   = ['band',   "Favorite"];
$init_artist_class{"Denny Lunsford"}                    = ['person', "Friends"];
$init_artist_class{"Diana Krall"}                       = ['person', "Jazz Soft"];
$init_artist_class{"Dianne Reeves"}                     = ['person', "Jazz Soft"];
$init_artist_class{"Dire Straits"}                      = ['person', "Rock Main"];
$init_artist_class{"Donald Fagen"}                      = ['person', "Rock Alt"];
$init_artist_class{"Donovan"}                           = ['person', "Rock Soft"];
$init_artist_class{"Doobie Brothers"}                   = ['band',   "Rock Main"];
$init_artist_class{"Dorindo Cardenas"}                  = ['person', "World Tipico"];
$init_artist_class{"Duffy Bishop Band"}                 = ['band',   "Blues New"];
$init_artist_class{"Duke Ellington"}                    = ['person', "Jazz Old"];
$init_artist_class{"Duke Robillard"}                    = ['person', "Jazz Swing"];
$init_artist_class{"Eagles"}                            = ['band',   "Rock Main"];
$init_artist_class{"Earl Thomas"}                       = ['person', "Blues Soft"];
$init_artist_class{"Earth, Wind & Fire"}                = ['band',   "R&B"];
$init_artist_class{"Echo & the Bunnymen"}               = ['band',   "Rock Alt"];
$init_artist_class{"Edith Piaf"}                        = ['person', "Other"];
$init_artist_class{"Ella Fitzgerald"}                   = ['person', "Jazz Old"];
$init_artist_class{"Ellis Marsalis"}                    = ['person', "Jazz Old"];
$init_artist_class{"Elton John"}                        = ['person', "Rock Main"];
$init_artist_class{"Elvis Costello"}                    = ['person', "Rock Main"];
$init_artist_class{"Emerson"}                           = ['band',   "SanDiegoLocals"];
$init_artist_class{"Eric Clapton"}                      = ['person', "Rock Main"];
$init_artist_class{"Ernestine Anderson"}                = ['person', "Jazz New"];
$init_artist_class{"Etta James"}                        = ['person', "Blues Old"];
$init_artist_class{"Everly Brothers"}                   = ['person', "Country"];
$init_artist_class{"Everly Brothers, Chet Atkins & Mark Knop"} = ['band',   "Country"];
$init_artist_class{"Fania All Stars"}                   = ['band',   "World African"];
$init_artist_class{"Faure"}                             = ['person', "Classical"];
$init_artist_class{"Fiona Apple"}                       = ['person', "Rock Soft"];
$init_artist_class{"Fleetwood Mac"}                     = ['band',   "Rock Main"];
$init_artist_class{"Forgotten Space"}                   = ['band',   "Productions Originals"];
$init_artist_class{"Frank Sinatra"}                     = ['person', "Jazz Vocal"];
$init_artist_class{"Fujiyama-Geisha"}                   = ['person', "Other"];
$init_artist_class{"Gallowglass"}                       = ['band',   "Other"];
$init_artist_class{"Gary Brown"}                        = ['person', "Jazz Soft"];
$init_artist_class{"Gatlin Brothers"}                   = ['band',   "Country"];
$init_artist_class{"George Clinton"}                    = ['person', "R&B"];
$init_artist_class{"George Harrison"}                   = ['person', "Rock Main"];
$init_artist_class{"Gipsy Kings"}                       = ['band',   "World Latin"];
$init_artist_class{"Gordon Lightfoot"}                  = ['person', "Rock Soft"];
$init_artist_class{"Graham Nash"}                       = ['person', "Rock Soft"];
$init_artist_class{"Grateful Dead"}                     = ['band',   "Dead"];
$init_artist_class{"Green Day"}                         = ['band',   "Rock Alt"];
$init_artist_class{"Greyboy"}                           = ['band',   "SanDiegoLocals"];
$init_artist_class{"Group Therapy"}                     = ['band',   "Friends"];
$init_artist_class{"Gypsy Kings"}                       = ['band',   "World Latin"];
$init_artist_class{"Handel"}                            = ['person', "Classical"];
$init_artist_class{"Harry Connick Jr"}                  = ['person', "Jazz Soft"];
$init_artist_class{"Hellecasters"}                      = ['band',   "Rock Alt"];
$init_artist_class{"Holdstock and Murphey"}             = ['band',   "Other"];
$init_artist_class{"Holst"}                             = ['person', "Classical"];
$init_artist_class{"Horace Trahan"}                     = ['person', "Zydeco"];
$init_artist_class{"Horace Trahan and The New Ossun Express"} = ['band',   "Zydeco"];
$init_artist_class{"Hot Rod LIncon"}                    = ['band',   "SanDiegoLocals"];
$init_artist_class{"Huey Lewis"}                        = ['person', "Rock Main"];
$init_artist_class{"Huey Lewis & the News"}             = ['band',   "Rock Main"];
$init_artist_class{"Iggy Pop"}                          = ['person', "Rock Alt"];
$init_artist_class{"Indigo Girls"}                      = ['band',   "Rock Soft"];
$init_artist_class{"Israel Kamakawiwo'ole"}             = ['person', "World Main"];
$init_artist_class{"It's A Beautiful Day"}              = ['band',   "Rock Main"];
$init_artist_class{"Jack Johnson"}                      = ['person', "Rock Alt"];
$init_artist_class{"Jaime Valle"}                       = ['person', "SanDiegoLocals"];
$init_artist_class{"James Brown"}                       = ['person', "R&B"];
$init_artist_class{"James Taylor"}                      = ['person', "Rock Soft"];
$init_artist_class{"Jane's Addiction"}                  = ['band',   "Rock Alt"];
$init_artist_class{"Janis Joplin"}                      = ['person', "Rock Main"];
$init_artist_class{"Jean Luc Ponty"}                    = ['person', "Jazz Soft"];
$init_artist_class{"Jerry Garcia"}                      = ['person', "Dead Jerry"];
$init_artist_class{"Jethro Tull"}                       = ['person', "Rock Main"];
$init_artist_class{"Jim Croce"}                         = ['person', "Rock Soft"];
$init_artist_class{"Jimmy Buffett"}                     = ['person', "Rock Main"];
$init_artist_class{"Jimmy Cliff"}                       = ['person', "Reggae"];
$init_artist_class{"Jimmy Page"}                        = ['person', "Rock Alt"];
$init_artist_class{"Jimmy Thackery"}                    = ['person', "Blues New"];
$init_artist_class{"Jimmy Thackery & The Drivers"}      = ['band',   "Blues New"];
$init_artist_class{"Jobim"}                             = ['person', "World Main"];
$init_artist_class{"Joe Jackson"}                       = ['person', "Rock Alt"];
$init_artist_class{"Joe Williams"}                      = ['person', "Jazz Old"];
$init_artist_class{"Joey Miller"}                       = ['person', "Jazz New"];
$init_artist_class{"John Brown's Body"}                 = ['band',   "Reggae"];
$init_artist_class{"John Coltrane"}                     = ['person', "Jazz Old"];
$init_artist_class{"John Denver"}                       = ['person', "Rock Soft"];
$init_artist_class{"John Lee Hooker"}                   = ['person', "Blues Old"];
$init_artist_class{"John Lennon"}                       = ['person', "Rock Main"];
$init_artist_class{"John Mayer"}                        = ['person', "Rock Alt"];
$init_artist_class{"John Philip Sousa"}                 = ['person', "Other"];
$init_artist_class{"John Pizzarelli"}                   = ['person', "Jazz Old"];
$init_artist_class{"John Prine"}                        = ['person', "Folk"];
$init_artist_class{"John Scofield"}                     = ['person', "Jazz Soft"];
$init_artist_class{"Johnny Cash"}                       = ['person', "Rock Main"];
$init_artist_class{"Johnny Dyer"}                       = ['person', "Blues New"];
$init_artist_class{"Jon Shain"}                         = ['person', "Folk"];
$init_artist_class{"Joni Mitchell"}                     = ['person', "Rock Soft"];
$init_artist_class{"Jonny Lang"}                        = ['person', "Blues New"];
$init_artist_class{"Junior Walker"}                     = ['person', "Blues Old"];
$init_artist_class{"Junior Walker And The All-Stars"}   = ['band',   "Blues Old"];
$init_artist_class{"Junior Walker and the Allstars"}    = ['band',   "Blues Old"];
$init_artist_class{"Keb Mo"}                            = ['person', "Blues Soft"];
$init_artist_class{"Keb' Mo' & Lyle Lovett"}            = ['band',   "Blues Soft"];
$init_artist_class{"Kenny Wayne Shepherd"}              = ['person', "Blues New"];
$init_artist_class{"Kevin Hurley"}                      = ['person', "Rock Soft"];
$init_artist_class{"Kevin Irlen"}                       = ['person', "Friends"];
$init_artist_class{"Kevin MacLeod"}                     = ['person', "World Main"];
$init_artist_class{"Kodo"}                              = ['band',   "World Main"];
$init_artist_class{"Larry Carlton"}                     = ['person', "Jazz Old"];
$init_artist_class{"Latcho and Andrea"}                 = ['band',   "World Latin"];
$init_artist_class{"Lenny Morgan"}                      = ['person', "World Main"];
$init_artist_class{"Linda Gail Lewis"}                  = ['person', "Favorite"];
$init_artist_class{"Little Feat"}                       = ['band',   "Rock Main"];
$init_artist_class{"Lizz Wright"}                       = ['person', "Jazz Soft"];
$init_artist_class{"Lloyd Jones"}                       = ['person', "Blues New"];
$init_artist_class{"Los Guajiros de Cuba"}              = ['band',   "World Latin"];
$init_artist_class{"Lou Reed"}                          = ['person', "Rock Main"];
$init_artist_class{"Louis Armstrong"}                   = ['person', "Jazz Old"];
$init_artist_class{"Lucinda Williams"}                  = ['person', "Country"];
$init_artist_class{"Ludwig von Beethoven"}              = ['person', "Classical"];
$init_artist_class{"Lynyrd Skynyrd"}                    = ['band',   "Rock Main"];
$init_artist_class{"Maceo Parker"}                      = ['person', "Jazz Old"];
$init_artist_class{"Mannheim Steamroller"}              = ['band',   "Christmas"];
$init_artist_class{"Mano Chao"}                         = ['person', "World Tipico"];
$init_artist_class{"Marc Broussard"}                    = ['person', "Blues Soft"];
$init_artist_class{"Marcia Ball"}                       = ['person', "NewOrleans"];
$init_artist_class{"Mariah Carey"}                      = ['person', "Christmas"];
$init_artist_class{"Mark Johnston"}                     = ['person', "Friends"];
$init_artist_class{"Mark Jordon"}                       = ['person', "Rock Alt"];
$init_artist_class{"Mark Knopfler"}                     = ['person', "Rock Soft"];
$init_artist_class{"Marklyn Retzer"}                    = ['person', "Friends"];
$init_artist_class{"Mars Hotel"}                        = ['band',   "Productions Bands"];
$init_artist_class{"Mavericks"}                         = ['band',   "Country"];
$init_artist_class{"Michael McDonald"}                  = ['person', "R&B"];
$init_artist_class{"Michael Trask"}                     = ['person', "SanDiegoLocals"];
$init_artist_class{"Miles Davis"}                       = ['person', "Jazz Old"];
$init_artist_class{"Miles Davis & John Coltrane"}       = ['band',   "Jazz Old"];
$init_artist_class{"Miles Davis And Quincy Jones"}      = ['band',   "Jazz Old"];
$init_artist_class{"Minor Threat"}                      = ['band',   "Rock Alt"];
$init_artist_class{"Modest Mouse"}                      = ['band',   "Rock Alt"];
$init_artist_class{"Mondo Head"}                        = ['band',   "World Main"];
$init_artist_class{"Mozart"}                            = ['person', "Classical"];
$init_artist_class{"Mussorgsky"}                        = ['person', "Classical"];
$init_artist_class{"Mussorgsky & Ravel"}                = ['band',   "Classical"];
$init_artist_class{"Mya Rose"}                          = ['person', "Folk"];
$init_artist_class{"Nat King Cole"}                     = ['person', "Jazz Old"];
$init_artist_class{"Nat King Cole & Ella Fitzgerald"}   = ['band',   "Jazz Old"];
$init_artist_class{"Nat King Cole & Frank Sinatra"}     = ['band',   "Jazz Vocal"];
$init_artist_class{"Nat King Cole Trio"}                = ['band',   "Jazz Old"];
$init_artist_class{"Neil Young"}                        = ['person', "Rock Main"];
$init_artist_class{"Nenito Vargas"}                     = ['person', "World Tipico"];
$init_artist_class{"Nestor Guestrin"}                   = ['person', "Classical"];
$init_artist_class{"New Riders of the Purple Sage"}     = ['band',   "Favorite"];
$init_artist_class{"Night Shift"}                       = ['band',   "Rock Alt"];
$init_artist_class{"Nighthawks"}                        = ['band',   "Blues New"];
$init_artist_class{"Norah Jones"}                       = ['person', "Jazz Soft"];
$init_artist_class{"Norman Brown"}                      = ['person', "Jazz Soft"];
$init_artist_class{"Oaxaca Pan Flutes"}                 = ['band',   "World Main"];
$init_artist_class{"Omar And The Howlers"}              = ['band',   "Blues New"];
$init_artist_class{"Osvaldo Ayala"}                     = ['person', "World Tipico"];
$init_artist_class{"Ottmar Liebert"}                    = ['person', "World Main"];
$init_artist_class{"Pachelbel"}                         = ['person', "Classical"];
$init_artist_class{"Pat Horton"}                        = ['person', "Productions Originals"];
$init_artist_class{"Pat Horton and Friends"}            = ['band',   "Productions Other"];
$init_artist_class{"Paul McCartney"}                    = ['person', "Rock Soft"];
$init_artist_class{"Paul Simon"}                        = ['person', "Rock Soft"];
$init_artist_class{"Paul Simon & George Harrison"}      = ['band',   "Rock Main"];
$init_artist_class{"Pedro Angel"}                       = ['person', "World Latin"];
$init_artist_class{"Pepe Romero"}                       = ['person', "Classical"];
$init_artist_class{"Pete Seeger"}                       = ['person', "Folk"];
$init_artist_class{"Peter Gabriel"}                     = ['person', "Rock Main"];
$init_artist_class{"Phish"}                             = ['band',   "Favorite"];
$init_artist_class{"Pink Floyd"}                        = ['band',   "Rock Main"];
$init_artist_class{"Prince"}                            = ['person', "R&B"];
$init_artist_class{"Putamayo"}                          = ['band',   "World Latin"];
$init_artist_class{"Quicksilver Messenger Service"}     = ['band',   "Rock Alt"];
$init_artist_class{"Quincy Jones"}                      = ['person', "Jazz Old"];
$init_artist_class{"Randy Travis"}                      = ['person', "Country"];
$init_artist_class{"Ravel"}                             = ['person', "Classical"];
$init_artist_class{"Ravi Shankar"}                      = ['person', "World Main"];
$init_artist_class{"Ray Charles"}                       = ['person', "Jazz Old"];
$init_artist_class{"Rebecca and David Randall"}         = ['band',   "SanDiegoLocals"];
$init_artist_class{"Rickie Lee Jones"}                  = ['person', "Rock Soft"];
$init_artist_class{"Rio Grande"}                        = ['band',   "Country"];
$init_artist_class{"Rita's Simple World"}               = ['band',   "Productions Bands"];
$init_artist_class{"Robert Cray"}                       = ['person', "Blues Old"];
$init_artist_class{"Roscoe Chenier"}                    = ['person', "NewOrleans"];
$init_artist_class{"Roy Rogers"}                        = ['person', "Blues New"];
$init_artist_class{"Rush"}                              = ['band',   "Rock Main"];
$init_artist_class{"Sam McClarty"}                      = ['person', "Friends"];
$init_artist_class{"Sam Pacetti"}                       = ['person', "Rock Soft"];
$init_artist_class{"Sammy y Sandra"}                    = ['band',   "World Tipico"];
$init_artist_class{"Sankai"}                            = ['band',   "World African"];
$init_artist_class{"Santana"}                           = ['band',   "Rock Main"];
$init_artist_class{"Schubert"}                          = ['person', "Classical"];
$init_artist_class{"Sharon Isbin"}                      = ['person', "World Main"];
$init_artist_class{"Shawn Colvin"}                      = ['person', "Rock Alt"];
$init_artist_class{"Simon & Garfunkel"}                 = ['band',   "Rock Soft"];
$init_artist_class{"Simply Red"}                        = ['band',   "Rock Alt"];
$init_artist_class{"Sly and the Family Stone"}          = ['band',   "R&B"];
$init_artist_class{"Smoky Greenwell"}                   = ['person', "Blues New"];
$init_artist_class{"Soul Coughing"}                     = ['band',   "Rock Alt"];
$init_artist_class{"Southwest German Chamber Orchestra"} = ['band',   "Classical"];
$init_artist_class{"Squirrel Nut Zippers"}              = ['band',   "Rock Alt"];
$init_artist_class{"Stanley Clark"}                     = ['person', "Jazz Old"];
$init_artist_class{"Steely Dan"}                        = ['person', "Rock Main"];
$init_artist_class{"Stephan Stills"}                    = ['person', "Rock Soft"];
$init_artist_class{"Stephan Stills & Graham Nash"}      = ['band',   "Rock Soft"];
$init_artist_class{"Steve Schulman"}                    = ['person', "Productions Bands"];
$init_artist_class{"Stevie Wonder"}                     = ['person', "R&B"];
$init_artist_class{"Storyhill"}                         = ['band',   "Rock Soft"];
$init_artist_class{"Stray Cats"}                        = ['band',   "Jazz Swing"];
$init_artist_class{"String Cheese Incident"}            = ['band',   "Rock Alt"];
$init_artist_class{"Strunz & Farah"}                    = ['band',   "World Main"];
$init_artist_class{"Sweardha Buddha"}                   = ['band',   "Productions Bands"];
$init_artist_class{"Tchaikovsky"}                       = ['person', "Christmas"];
$init_artist_class{"The Allman Brothers Band"}          = ['band',   "Rock Main"];
$init_artist_class{"The Atoll"}                         = ['band',   "R&B"];
$init_artist_class{"The Be Good Tanyas"}                = ['band',   "Folk"];
$init_artist_class{"The Beach Boys"}                    = ['band',   "Rock Main"];
$init_artist_class{"The Beatles"}                       = ['band',   "Rock Main"];
$init_artist_class{"The Benedictine Monks of Santo Domingo"} = ['band',   "Other"];
$init_artist_class{"The Billy McLaughlin Group"}        = ['band',   "Rock Alt"];
$init_artist_class{"The Blue Louvres"}                  = ['band',   "Productions Bands"];
$init_artist_class{"The Bobs"}                          = ['band',   "Other"];
$init_artist_class{"The Cure"}                          = ['band',   "Rock Alt"];
$init_artist_class{"The Dells"}                         = ['band',   "Jazz Soft"];
$init_artist_class{"The Mighty Mighty Bosstones"}       = ['band',   "Rock Alt"];
$init_artist_class{"The Monkees"}                       = ['band',   "Rock Soft"];
$init_artist_class{"The Moody Blues"}                   = ['band',   "Rock Main"];
$init_artist_class{"The Notting Hillbillies"}           = ['band',   "Rock Soft"];
$init_artist_class{"The Persuasions"}                   = ['band',   "Other"];
$init_artist_class{"The Radiators"}                     = ['band',   "NewOrleans"];
$init_artist_class{"The Rolling Stones"}                = ['band',   "Rock Main"];
$init_artist_class{"The Samples"}                       = ['band',   "Rock Alt"];
$init_artist_class{"The Wailin' Jennys"}                = ['band',   "Folk"];
$init_artist_class{"Theo and the Zydeco Patrol"}        = ['band',   "Zydeco"];
$init_artist_class{"Tito Puente"}                       = ['person', "Jazz Soft"];
$init_artist_class{"Tondo"}                             = ['band',   "World African"];
$init_artist_class{"Train"}                             = ['band',   "Rock Alt"];
$init_artist_class{"U2"}                                = ['band',   "Rock Main"];
$init_artist_class{"Ulpiano Vergara"}                   = ['person', "World Tipico"];
$init_artist_class{"Van Morrison"}                      = ['person', "Favorite"];
$init_artist_class{"Van Morrison & Bob Dylan"}          = ['band',   "Rock Main"];
$init_artist_class{"Van Morrison & Linda Gail Lewis"}   = ['band',   "Favorite"];
$init_artist_class{"Vangelis"}                          = ['person', "Other"];
$init_artist_class{"Virginia La Iacona"}                = ['person', "World Main"];
$init_artist_class{"Walter Becker"}                     = ['person', "Rock Alt"];
$init_artist_class{"War"}                               = ['band',   "Rock Main"];
$init_artist_class{"Wendy Luck"}                        = ['person', "Other"];
$init_artist_class{"Willie and Lobo"}                   = ['band',   "World Main"];
$init_artist_class{"Yerba Buena"}                       = ['person', "World Latin"];
$init_artist_class{"Yes"}                               = ['band',   "Rock Main"];
$init_artist_class{"ZZ Top"}                            = ['band',   "Rock Main"];


our %proper_name;
$proper_name{'Beethoven'}   = 'Ludwig Van Beethoven';
$proper_name{'Brahms'}      = 'Johannes Brahms';


1;

