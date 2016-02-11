#!/usr/bin/perl
#---------------------------------------

# prh - stations.txt is not compatible between android and windows (line endings)

# Station.pm
#
# This module maintains a set of 'radio stations' or 'rotations',
# which are lists of songs that can be played by the renderer.
#
# A "STATIONS" integer is kept as a member on the track and folder
# database records. It is an integer member, interpreted bitwise.
#
# Usage:
#
#   init_stations_static() - static initialization reads or creates
#      and writes the list of stations
#
#   setDefaultStations() - set some useful defaults for testing
#   clearAllStationBits() - remove all station bits for testing
#
#   getStations() - returns a list of all the available stations
#   getStation(station_num) - returns the particular station
#   setStationList() - generates a list of songs for the station
#      according to the existing station bits on tracks, the
#      shuffle setting, and the unplayed_first setting.  The
#      resultant list of integers are the trackIDs of the
#      songs in the rotation.  They are written out to a cached
#      binary file, which is then random accessed by getStationSong.
#      Calling setStationList generally resets the station track_index
#      to -1 to start over from the beginning.
#
#   getNumTracks() - number of tracks in the stationList
#   getTrackIndex() - the currently playing song, 1 based
#   setTrackIndex(track_index) - set the currently playing song
#        value should be from 0..getNumTracks(), where 0 means
#
#   getTrackID(track_index)
#      Returns the trackID of the song at the given track_index
#      within the station. 0 means that no trackID (song) was found
#   getNextTrackID()
#   getPrevTrackID()
#       return the next/previous trackID with wrapping
#   getIncTrackID(inc == -1 or 1)
#       an alternative method to calling getNext/Prev
#


# prh - a database would be better for stations so that
# we could update one value (i.e. track_index) without
# re-writing the whole file

package Station;
use strict;
use warnings;
use threads;
use threads::shared;
use Library;
use Database;
use Utils;

our $SHUFFLE_NONE = 0;
our $SHUFFLE_TRACKS = 1;
our $SHUFFLE_ALBUMS = 2;

our $dbg_station = 2;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
        $NUM_STATIONS
		$station_datafile

        getStation
        getStations
    );
}


#-----------------------------
# CONSTANTS
#-----------------------------

my @station_fields = (qw(
    station_num
    track_index
    num_tracks
    shuffle
    unplayed_first
    name
    ));

our $NUM_STATIONS = 32;
    # Number of radio stations.
    # Empty ones will be created and therafter
    # maintained in the station_datafile
    
our $station_datafile = "$cache_dir/stations.txt";
    # A file containing the records for the stations.
my $stations_dir = "$cache_dir/stations";
mkdir $stations_dir if (!(-d $stations_dir));


#---------------------------
# VARIABLES
#---------------------------

my %g_stations:shared;
    # a global hash, by station_num, of Station objects.
        
    

#------------------------------------------
# Construction
#------------------------------------------

sub new
{
    my ($class,$station_num) = @_;
    my $this = shared_clone({});
    bless $this,$class;

    $this->{station_num} = $station_num;
    $this->{name} = "station($station_num)";

    $this->{num_tracks} = 0;
    $this->{track_index} = 0;
    $this->{shuffle} = $SHUFFLE_NONE;
    $this->{unplayed_first} = 0;    
    
    $g_stations{$this->{station_num}} = $this;
    return $this;
}


sub new_from_line
{
    my ($class,$line) = @_;
    my $this = shared_clone({});
    bless $this,$class;

    @{$this}{@station_fields} = split(/\t/,$line);
    
    $g_stations{$this->{station_num}} = $this;
    return $this;
}


sub static_init_stations
{
    my $lines;
    
    unlink $station_datafile if $is_new_database;
    
    my $exists = -f $station_datafile ? 1 : 0;
    
    if ($exists)
    {
        $lines = getTextLines($station_datafile);
        if ($lines && @$lines)
        {
            for my $line (@$lines)
            {
                chomp($line);
                Station->new_from_line($line);
            }
        }
    }
    else
    {
        for my $i (1..$NUM_STATIONS)
        {
            if (!$g_stations{$i})
            {
                my $station = Station->new($i);
                $station->{name} = 'notes' if ($i == 32);
            }
        }
        write_stations();
    }
    return $exists;
}


sub write_stations
{
    my $text = '';
    for my $i (1..$NUM_STATIONS)
    {
        my $station = $g_stations{$i};
        $text .= join("\t",@{$station}{@station_fields})."\n";
    }
    
	# text files to export to android must be written
	# in binary mode with just \n's
    
    if (!printVarToFile(1,$station_datafile,$text,1))
    {
        error("Could not write to station datafile $station_datafile");
        return;
    }
    return 1;
}


sub station_bit
{
    my ($this) = @_;
    return 1 << ($this->{station_num} - 1);
}



sub getStations
{
    return \%g_stations;
}


sub getStation
{
    my ($station_num) = @_;
    my $station = $g_stations{$station_num};
    # display(0,0,"getStation($station_num) = $station->{name}");
    return $station;
}

sub getStationFilename
{
    my ($this) = @_;
    return "$stations_dir/station_list_$this->{station_num}.data";
}


#-------------------------------------------
# default stations / clear all
#-------------------------------------------

sub clearAllStationBits
    # clear the station bits on all tracks and folders
{
    my ($station_num) = @_;
    display(0,0,"clearStations("._def($station_num).") called");
    
    my $mask = 0;
    if (defined($station_num))
    {
        if (!$station_num || $station_num<0 || $station_num>$NUM_STATIONS)
        {
            error("illegal station_num($station_num) in clearStations");
            return;
        }
        $mask = ~$station_num;
    }
        
    my $dbh = db_connect();
    
    if (!db_do($dbh,"UPDATE TRACKS SET STATIONS=STATIONS & $mask"))
    {
        error("Could not clear TRACKS stations($mask)");
        return;
    }
    if (!db_do($dbh,"UPDATE FOLDERS SET STATIONS=STATIONS & $mask"))
    {
        error("Could not clear FOLDERS stations($mask)");
        return;
    }
 
    display(0,0,"clearStations() finished");
    db_disconnect($dbh);
    return 1;
}


sub setDefaultStations
{
    clearAllStationBits();

    setDefaultStation(2,'work',
        ["albums/Work"]);

    setDefaultStation(3,'dead',
        ["albums/Dead",
         "singles/Dead"],
        {shuffle => $SHUFFLE_ALBUMS});
    setDefaultStation(4,'favorite',
        ["albums/Favorite",
         "singles/Favorite"],
        {shuffle => $SHUFFLE_ALBUMS});
    setDefaultStation(5,'jazz',
        ["albums/Jazz/Old",
		 "albums/Jazz/Soft",
		 "albums/Jazz/Swing",
         "singles/Jazz"],
        {shuffle => $SHUFFLE_TRACKS});
    setDefaultStation(6,'blues',
        ["albums/Blues",
         "singles/Blues"],
        {shuffle => $SHUFFLE_TRACKS});
    
    # setDefaultStation(7,'albums',["albums"]);
    # setDefaultStation(8,'singles',["singles"]);

    setDefaultStation(9,'world',
        ["albums/World minus /Tipico",
         "singles/World"],
        {shuffle => $SHUFFLE_ALBUMS});
    setDefaultStation(10,'orleans',
        ["albums/NewOrleans",
         "albums/Zydeco"],
        {shuffle => $SHUFFLE_TRACKS});
    setDefaultStation(11,'reggae',
        ["albums/Reggae",
         "singles/Reggae"],
        {shuffle => $SHUFFLE_TRACKS});
    setDefaultStation(12,'rock',
        ["albums/Rock",
         "albums/SanDiegoLocals",
         "singles/Rock"],
        {shuffle => $SHUFFLE_TRACKS});
    setDefaultStation(13,'R&B',
        ["albums/R&B",
         "singles/R&B"],
        {shuffle => $SHUFFLE_TRACKS});
    setDefaultStation(14,'country',
        ["albums/Country",
         "singles/Country"],
        {shuffle => $SHUFFLE_TRACKS});
    setDefaultStation(15,'classical',
        ["albums/Classical minus /Baroque",
         "singles/Classical minus /Baroque"],
        {shuffle => $SHUFFLE_ALBUMS});
    setDefaultStation(16,'xmas',
        ["albums/Christmas",
         "singles/Christmas"],
        {shuffle => $SHUFFLE_TRACKS});
    
    setDefaultStation(17,'friends',
        ["albums/Productions minus Sweardha Buddha",
		 "albums/Friends"],
        {shuffle => $SHUFFLE_ALBUMS});
    
    setDefaultStation(18,'folk',
        ["albums/Folk",
         "singles/Folk"],
        {shuffle => $SHUFFLE_TRACKS});
    setDefaultStation(19,'compilations',
        ["albums/Compilations",
         "singles/Compilations"],
        {shuffle => $SHUFFLE_ALBUMS});
    setDefaultStation(20,'soundtrack',
        ["albums/Soundtracks"],
        {shuffle => $SHUFFLE_ALBUMS});
    setDefaultStation(21,'other',
        ["albums/Other",
         "singles/Other"],
        {shuffle => $SHUFFLE_TRACKS});
    
    write_stations();
}


sub setDefaultStation
{
    my ($station_num,$name,$paths,$params) = @_;
    $params ||= {};
    
    my $station = $g_stations{$station_num};
    $station->{name} = $name;
    $station->{track_index} = 0;
    $station->{num_tracks} = 0;

    my $dbh = db_connect();
    my $bit = $station->station_bit();
    
    for my $path (@$paths)
    {
        display(0,1,"setDefaultStation($station_num) path=$path");
		
		my $query1 = "UPDATE TRACKS SET STATIONS=STATIONS | $bit ".
					 "WHERE instr(FULLNAME,?) > 0";
		my $query2 = "UPDATE FOLDERS SET STATIONS=STATIONS | $bit ".
					 "WHERE FULLPATH=? OR (instr(FULLPATH,?) > 0";
					 
		# limited to one exclude per spec now
		# could have comma delimited excluces
		
		my $exclude = ($path =~ s/\s+minus\s+(.*)$//) ? $1 : '';
		my $args1 = [ $path."/" ];
		my $args2 = [ $path, $path."/" ];
		if ($exclude)
		{
			display(0,2,"exclude='$exclude'");
			push @$args1,$exclude;
			push @$args2,$exclude;
			$query1 .= " AND instr(FULLNAME,?) <= 0";
			$query2 .= " AND instr(FULLPATH,?) <= 0";
		}
		$query2 .= ")";
		
		display(9,2,"DO1 $query1 ARGS=".join(',',@$args1));
        db_do($dbh,$query1,$args1);

		display(9,2,"DO2 $query1 ARGS=".join(',',@$args1));
        db_do($dbh,$query2,$args2);
    }
    
    db_disconnect($dbh);
          
    $station->setStationList($params);
}

               
    
    
#------------------------------------------
# generate the station list ("rotation")
#------------------------------------------


sub by_album_tracknum
{
    my ($albums,$a,$b) = @_;
    my $cmp = $albums->{$a->{PARENT_ID}} <=> $albums->{$b->{PARENT_ID}};
    return $cmp if $cmp;
    $cmp = ($a->{TRACKNUM} || 0) <=> ($b->{TRACKNUM} || 0);
    return $cmp if $cmp;
    return $a->{TITLE} cmp $b->{TITLE};
}
    
                                                  
    
    
sub setStationList
    # for a particular station, given params hash,
    # shuffle, unplayed_first, etc, develop a list of
    # trackIDs, constituting the "stationList" or "rotation"
    # for the station.
    #
    # These integer trackIDs are written as dwords to
    # a binary file "station_list_N.data", where the
    # first dword is the number of trackIDs??.
{
    my ($this,$params) = @_;
    $this->{shuffle} = $params->{shuffle} if defined($params->{shuffle});
    $this->{unplayed_first} = $params->{unplayed_first} if defined($params->{unplayed_first});

    # get records for this station
    
    my $dbh = db_connect();
    my $bit = $this->station_bit();
    my $recs = get_records_db($dbh,
        "SELECT ID, PARENT_ID, TRACKNUM, TITLE, FULLNAME FROM TRACKS ".
        "WHERE STATIONS & $bit ".
        "ORDER BY PATH, TRACKNUM, FULLNAME");
    
    my $num_tracks = 0;
    if (!$recs || !@$recs)
    {
        warning(0,0,"No tracks found for station($this->{station_num})");
    }
    else
    {
        $num_tracks = @$recs;
    }
    db_disconnect($dbh);

    # sort them according to shuffle
    
    my @result;
    if ($this->{shuffle} == $SHUFFLE_TRACKS)
    {
        for my $rec (@$recs)
        {
            $rec->{position} = int(rand($num_tracks + 1));
        }
        for my $rec (sort {$a->{position} <=> $b->{position}} @$recs)
        {
            push @result,$rec->{ID};
        }
    }
    elsif ($this->{shuffle} == $SHUFFLE_ALBUMS)
    {
        my %albums;
        for my $rec (@$recs)
        {
            $albums{ $rec->{PARENT_ID} } = int(rand($num_tracks + 1));
        }
        for my $rec (sort {by_album_tracknum(\%albums,$a,$b)} @$recs)
        {
            push @result,$rec->{ID};
        }
    }
    else
    {
        @result = map($_->{ID},@$recs);
    }
    
    # write them to the binary data file
    
    my $fh;
    my $filename = $this->getStationFilename();
    if (!open($fh,">$filename"))
    {
        error("Could not open $filename for writing");
        return;
    }
    binmode $fh;
	
	# 0th dword is num_tracks
	
    if (!print $fh pack('L*',$num_tracks, @result))
    {
        error("Could not print to $filename");
        return;
    }
    close $fh;
    
    # reset and write the station
    
    $this->{num_tracks} = $num_tracks;

    # prh - this is where the search for the previous song goes
    
    # The only time it makes sense to keep the track_number alive
    # is if we were previously sorted by track and we are sorting
    # by track again, or possibly on (unimplmented) unplayed_first
    # changes. So I'm just gonna see how it goes with just
    # restarting the list every time.

    $this->{track_index} = 0;

    write_stations();
    return 1;
}




#------------------------------------------
# accessors
#------------------------------------------

sub getNumTracks
{
    my ($this) = @_;
    return $this->{num_tracks};
}

sub getTrackIndex
{
    my ($this) = @_;
    return $this->{track_index};
}

sub setTrackIndex
{
    my ($this,$track_index) = @_;
    if ($track_index < 0 || $track_index > $this->{num_tracks})
    {
        error("setTrackIndex($track_index) out of range($this->{num_tracks})");
        return;
    }
    $this->{track_index} = $track_index;
}


sub getTrackID
{
    my ($this,$track_index) = @_;
    if ($track_index < 0 || $track_index > $this->{num_tracks})
    {
        error("getTrackID($track_index) out of range($this->{num_tracks})");
        return 0;
    }

    my $fh;
    my $data;
    my $track_num = 0;
    my $filename = $this->getStationFilename();
    if (!open($fh,"<$filename"))
    {
        error("Could not open $filename for reading");
    }
    else
    {
        binmode $fh;
        
        if (!seek($fh, $track_index * 4, 0))
        {
            error("Could not seek to $track_index*4 in $filename");
        }
        elsif (!read($fh,$data,4))
        {
            error("Could not resd from $filename");
        }
        else
        {
            $track_num = unpack('L',$data);
        }
    }
    
    display($dbg_station,0,"getTrackID($track_index) returning $track_num");
    return $track_num;
}

    
sub getIncTrackID
{
    my ($this,$inc) = @_;
    
    $this->{track_index} += $inc;
    $this->{track_index} = 1 if $this->{track_index} > $this->{num_tracks};
    $this->{track_index} = $this->{num_tracks} if $this->{track_index} < 1;
    
    write_stations();
    
    return $this->getTrackID($this->{track_index});
}


sub getNextTrackID
{
    my ($this) = @_;
    return $this->getIncTrackID(1);
}


sub getPrevTrackID
{
    my ($this) = @_;
    return $this->getIncTrackID(-1);
}



#------------------------------------------
# station manipulation for UI
#------------------------------------------


sub setTrackStationBit
    # toggle the given track's bit for this station.
    # and propogate the change to it's parent folders
    # I think returning is ok - $dbh will disconnect
    # itself when it goes out of scope. The set bit
    # is optional, and will force the track into the
    # given state.
{
    my ($this,$track_id,$set) = @_;
    display($dbg_station,0,"setTrackStationBit($track_id,$set)");
    
    my $dbh = db_connect();
    my $track = get_record_db($dbh,"SELECT STATIONS,PARENT_ID FROM TRACKS WHERE ID='$track_id'");
    if (!$track)
    {
        error("Track($track_id) not found in toggleTrackStation");
        return;
    }
    
    my $bit = $this->station_bit();
    my $operator = '|';
    my $mask = $bit;
    if (!$set)
    {
        $mask = ~$mask;
        $operator = '&';
    }

    # set the bit in the track
    
    display($dbg_station,1,"setting track($track_id) bit(".hx($bit).") to $set ".
        "mask='".hx($mask)."' operator='$operator'");
    
    if (!db_do($dbh,
        "UPDATE TRACKS ".
        "SET STATIONS = (STATIONS $operator $mask) ".
        "WHERE ID='$track_id'"))
    {
        error("Could not update track($track_id) for '$operator $mask' in toggleTrackStation");
        return;
    }

    # propogate to parents
    
    return if !$this->propagate_to_parents(
        $dbh,
        $track->{PARENT_ID},
        $bit,
        $set,
        $operator,
        $mask );

    display($dbg_station,0,"setTrackStationBit() finished");
    db_disconnect($dbh);
    return 1;
}


    
sub setFolderStationBit
    # Toggle a folders station value.
    # The change is invariantly forced on all children,
    # and propogated to parents. The set bit
    # is optional, and will force the folder into the
    # given state.
{
    my ($this,$folder_id,$set) = @_;
    display($dbg_station,0,"setFolderStationBit($folder_id)");
    
    my $dbh = db_connect();
    my $folder = get_record_db($dbh,"SELECT STATIONS,PARENT_ID,FULLPATH FROM FOLDERS WHERE ID='$folder_id'");
    if (!$folder)
    {
        error("Folder($folder_id) not found in toggleFolderStation");
        return;
    }

    my $bit = $this->station_bit();
    my $on = $folder->{STATIONS} & $bit;    
    my $mask = $bit;
    my $operator = '|';

    if (!$set)
    {
        $mask = ~$mask;
        $operator = '&';
    }
        
    # force the change on all children tracks

    display($dbg_station,2,"folder=$folder fullpath=$folder->{FULLPATH}");
    
    if (!db_do($dbh,
        "UPDATE TRACKS SET ".
        "STATIONS = (STATIONS $operator $mask) ".
        "WHERE instr(FULLNAME,?) > 0",
        [$folder->{FULLPATH}.'/']))
    {
        error("Could not update children tracks of folder($folder_id)");
        return;
    }
    
    # force the change on all children folders
    
    if (!db_do($dbh,
        "UPDATE FOLDERS SET ".
        "STATIONS = (STATIONS $operator $mask) ".
        "WHERE instr(FULLPATH,?) > 0",
        [$folder->{FULLPATH}.'/']))
    {
        error("Could not update children folders of folder($folder_id)");
        return;
    }

    # if folder was already set, short ending
    
    if ($set == $on)
    {
        display($dbg_station,1,hx($bit)." already set($set) for folder($folder) short ending in toggleFolderStation()");
        return 1;
    }

    # set the bit in the folder
    
    display($dbg_station,1,"setting folder($folder_id) bit(".hx($bit).") to $set ".
        "mask='".hx($mask)."' operator='$operator'");
    
    if (!db_do($dbh,
        "UPDATE FOLDERS ".
        "SET STATIONS = (STATIONS $operator $mask) ".
        "WHERE ID='$folder_id'"))
    {
        error("Could not update folder($$folder_id) for '$operator $mask' in toggleTrackStation");
        return;
    }
    
    # propogate to parents
    
    return if !$this->propagate_to_parents(
        $dbh,
        $folder->{PARENT_ID},
        $bit,
        $set,
        $operator,
        $mask );

    display($dbg_station,0,"setFolderStationBit() finished");
    db_disconnect($dbh);
    return 1;
}



sub propagate_to_parents
    # Propogate to Parents
    #
    # if we are turning off, then we can just walk the
    # parent chain and set it's bits off.
    #
    # But if we are turning the bit on, as we walk
    # the parent chain, we have to re-check for any
    # other tracks that are on for the parent.
    #
    # The loop can stop when we encounter a parent
    # who is already (which should NOT be our immediate
    # parent if we are turning the bit off).
{
    my ($this,
        $dbh,
        $parent_id,
        $bit,
        $set,
        $operator,
        $mask ) = @_;

    while ($parent_id)
    {
        my $parent = get_record_db($dbh,"SELECT PARENT_ID,STATIONS,FULLPATH FROM FOLDERS WHERE ID='$parent_id'");
        if (!$parent)
        {
            error("Could not get parent($parent_id) in propagate_to_parents");
            return;
        }

        # short ending if parent already in correct state
        
        my $on = $parent->{STATIONS} & $bit ? 1 : 0;
        if ($on == $set)
        {
            display($dbg_station+1,2,"ending loop on parent ($parent_id) who is already $on for station $this->{station_num}");
            last;
        }
        
        # if are turning on, we check for any off tracks
        # in children of this folder.
        
        if ($set)
        {
            display($dbg_station+1,1,"checking parent($parent_id) for any OFF children");
            
            my $found = get_record_db($dbh,
                "SELECT ID FROM TRACKS WHERE ".
                    "(NOT (STATIONS & $bit)) AND ".
                    "instr(FULLNAME,?) > 0",
                [$parent->{FULLPATH}.'/']);
            if ($found)
            {
                display($dbg_station+1,2,"ending loop on parent ($parent_id) who has children still in station");
                last;
            }
        }
        
        # otherwise, update the parent and spin the loop again

        display($dbg_station,2,"setting parent($parent_id) bit(".hx($bit).") to $set ");
            
        if (!db_do($dbh,
            "UPDATE FOLDERS ".
            "SET STATIONS = (STATIONS $operator $mask) ".
            "WHERE ID='$parent_id'"))
        {
            error("Could not update parent($parent_id) for '$operator $mask' in toggleTrackStation");
            return;
        }
        
        $parent_id = $parent->{PARENT_ID};
    }

    return 1;
}
    
# set Database var telling it that this module is loaded,
# so it will call setDefaultStations if it's the first time
# on the database.

$HAS_STATION_MODULE = 1;


if (0)
{
	# Caled from artisan.pm after initalize_database
	static_init_stations();
	
	# called from Library.pm:
	setDefaultStations();
}


1;
