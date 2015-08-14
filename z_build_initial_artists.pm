#---------------------------------------
# build_initial_artistrs.pm
#---------------------------------------
# build /junk/artists.pm from the database
# and some constants in this file

use strict;
use warnings;
use Utils;
use MediaFile;

$debug_level = 1;
$warning_level = 0;
$debug_packages = join('|',(
    'fix_library',
    'Utils',    
    'FileManager',
    'MediaFile'
    ));

    
$logfile = "$log_dir/fix_library.log";
unlink $logfile;
unlink $error_logfile;

my $exclude_re = '\/_';
my $scan_dir = $mp3_dir;


#-----------------------------------------
# framework
#-----------------------------------------

sub myPersonalMimeType
    # my audio types = mp3|wma|wav|m4a|m4p|aif
{
    my ($filename) = @_;
    return 'audio/mpeg' if ($filename =~ /\.mp3$/i);
    if (1)
    {
        return 'audio/x-m4a'    if ($filename =~ /\.m4a$/i);
        return 'audio/x-ms-wma' if ($filename =~ /\.wma$/i);
        return 'audio/x-wav'    if ($filename =~ /\.wav$/i);
    }
    return '';
}


sub do_to_all
    # only count stats on 2nd (full) pass
{
    my ($dir,$part,$fxn_file,$fxn_dir) = @_;
    return 1 if $exclude_re && ($dir =~ /$exclude_re/);
    bump_stat("$part total_dirs");
    
    display(3,0,$dir);

    my @files;
    my @subdirs;
    if (!opendir(DIR,$dir))
    {
        error("Could not opendir $dir");
        return;
    }
    
    while (my $entry=readdir(DIR))
    {
        next if ($entry =~ /^\./);
        my $filename = "$dir/$entry";
        if (-d $filename)
        {
            push @subdirs,$entry;
        }
        elsif (my $mime_type = myPersonalMimeType($entry))
        {
            bump_stat("$part total_files");
            push @files,$entry;
        }
    }
    closedir DIR;

    # do_to_each directory, if fxn provided

    return if (@files && $fxn_dir && !&$fxn_dir($part,$dir,@files));

    # do_to_each file, if fxn provided

    for my $file (@files)
    {
        return if $fxn_file && !&$fxn_file($part,"$dir/$file");
    }

    # process the subdirectories

    for my $subdir (@subdirs)
    {
        return if !do_to_all("$dir/$subdir",$part,$fxn_file,$fxn_dir);
    }

    return 1;
}



#---------------------------------------------
# build_artists ... 
#---------------------------------------------
# Build a list of 'classified artists', i.e. the
# 'classes' and 'imposed artists' for the 'albums'
# in my directory structure.
#
# There are two special 'artists' in use in
# my classified directories. Album directory
# names that start with 'Various - ' or
# 'Original Soundtrack - ' will not be parsed
# into the artist tree.
#
# 'Classes' are the 'imposed' genres based on
# my directory structure.  There is a special
# class of 'unresolved'.
#
# This logic can be transfered to Library to build
# the artist database as things progress. For now
# it takes advantage of the fact that I carefully
# cleaned all the 'resolved' 'classes' and 'artists'
# in /mp3/albums and /mp3/singles. Note that it has
# to run all the way through before the class of a
# an artist can be given, as they may be remapped,
# and that generally, we don't consider 'unresolved'
# directory and filenames as being good candidates.
#
# Set the following var to 1 to see the unresolved
# artists, or leave it as 0 to develop a clean list
# of only the artists and classes in /albums,
# and /singles

my %artist_class;
my %class_artists;
my %unresolved_artists;

my $old_display_class = '';

sub build_artists
{
    my ($prog_part,$path,@files) = @_;
    return if (!@files);
    
    display(2,0,"build_artists($path)");
    
    my @parts = split(/\//,$path);
    my $album_part = pop(@parts);
    
    my $num = 0;
    my $class = '';
    my $part = pop @parts;
    while ($part !~ /^(albums|singles|mp3s)$/)
    {
        $part .= ' ' if ($class);
        $class = $part.$class;
        $part = pop @parts;
        $num++;
    }
    if (!$class)
    {
        error("no class found for $path");
        return 1;
    }
    if ($num > 2)
    {
        error("class $class has $num parts in $path");
        return 1;
    }
    
    display(0,1,"class=$class") if ($class ne $old_display_class);
    $old_display_class = $class;
    
    @parts = split(/ - /,$album_part);
    
    if (@parts == 1 && $class =~ /Dead/)
    {
        my $artist = 'Grateful Dead';
        $artist = 'Jerry Garcia' if ($class =~ /Jerry/);
        unshift @parts,$artist;
    }
    elsif (@parts == 1)
    {
        error("no artist for $class: $album_part");
        return 1;
    }
    elsif (@parts > 2)
    {
        # prh
        # set 0 to not see part errors on unresolved files
        # set 1 to see part errors on unresolved files
        
        error("more than 2 parts for $class: $album_part")
            if (0 || $class ne 'unresolved');
        
        return 1;
    }

    # artists get moved out of Xmas if they are
    # found in another directory, it just so happens
    # that the only one we want to move out of Productions
    # at this time is Theo, and Zydeco just happens to
    # fall later.
    
    my ($artist,$title) = (@parts);
    $class = 'Dead' if ($artist eq 'Grateful Dead');
    if ($artist ne 'Various' &&
        $artist ne 'Original Soundtrack' &&
        $class ne 'unresolved')
    {
        my $exists = $artist_class{$artist};
        if ($exists && $exists ne $class)
        {
            next if ($class eq 'Christmas');
                # don't move artists INTO christmas
            
            # give a warning, but invariantly move
            # out of these directories
            
            if ($exists eq 'Christmas' ||
                $exists =~ /Productions/)
            {
                warning(0,0,"reassigning artist '$artist' from class $exists to $class");
            }
            
            # otherwise, leave the artist where they were, and
            # we consideer these to be denormalizaton problems.
            
            else
            {
                warning(0,0,"$artist exists in more than one class. NOT reassigning from $exists to $class!");
                return 1;
            }
            
            # remove the artist from the old class
            # and get rid of empty classes ..

            delete $class_artists{$exists}->{$artist};
            delete $class_artists{$exists} if !keys(%{$class_artists{$exists}});
        }
        
        # add the artist to the class
        # with a count of number of albums they have
        
        $artist_class{$artist} = $class;
        $class_artists{$class} ||= {};
        $class_artists{$class}->{$artist} ||= 0;
        $class_artists{$class}->{$artist} += scalar(@files);
    }
    elsif ($class eq 'unresolved')
    {
        $unresolved_artists{$artist} ||= 0;
        $unresolved_artists{$artist} += scalar(@files);
    }
    
    return 1;
}


#---------------------------------------------
# main
#---------------------------------------------
# Note that, as a result of re-assignments, the class
# of an artist CANNOT simply be derived from the directory
# structure.  

LOG(0,"fix_library.pm started");

# CREATE THE CLASSES AND ARTISTS

do_to_all($scan_dir,'pass0',undef,\&build_artists);

# We have a pretty good idea of what is going on
# at this point.  There is now a clean list of
# classified artists.  Some things I'd like to cleanup.
#
# There are 'proper text substring' Combined Artists,
# where more than one existing artist is in the album
# directory name.  Like "Miles Davis and Quincy Jones",
# contains both "Miles Davis" AND "Quincy Jones".
#
# There are also artists where substring matching would not
# work. in all kinds of names.  Air, Beck, and Train are unsafe and
# Prince and Rush are really questionable.

# At this point we decide to create a cache of artists.
# The library will only 'classify' an artist if it doesn't
# know it, and will use existing classified artists, as
# long as the cache exists.
#
# So, the library still needs this full pass process, in
# case the artist cache needs to get rebuilt.  Yet, I think
# I want be able to modify, by hand, this list of artists.
# There needs to be some way to introduce special knowledge
# into the system, like 'it's ok for matching on "Miles Davis",
# but not to match on "Air" or "War", and for me to make
# explicit decisions to have an artist named "Dan Hicks"
# who is a 'member' of two bands, even tho there is no album
# attributable to just Dan Hicks.
#
# So, we *may* write PERMANENT files to the /mp3/_artists
# directory. They will NOT be deleted when you delete
# everything else in the cache.  They should be deleted
# with care, as there 

# There are /unresolved albums from "Bob Dylan and Johnny Cash",
# that did not get pulled earlier because there was no exact
# match for the combined artist name, and the task now becomes
# pulling /unresolved combined artist names over to /singles
# when one part of the artist name is well known.
#
#
# Van Morrison & Linda Gail Lewis
# I don't have a resolved 'Bach'
# I don't have the 'other' person in the following:
# mispelled Beetoven
# Afro, Afri


# debugging display from here on out

if (0)
{
    display(0,0,"");
    display(0,0,"--------------------------------");
    display(0,0,"Classified artists");
    display(0,0,"--------------------------------");
    for my $artist (sort(keys(%artist_class)))
    {
        my $class = $artist_class{$artist};
        display(0,2,pad($artist,60)." = $artist_class{$artist}");
    }
}

if (0)
{
    display(0,0,"");
    display(0,0,"--------------------------------");
    display(0,0,"unclassified artists");
    display(0,0,"--------------------------------");
    for my $artist (sort(keys(%unresolved_artists)))
    {
        display(0,2,pad($unresolved_artists{$artist},6)." $artist");
    }
}

if (0)
{
    display(0,0,"");
    display(0,0,"--------------------------------");
    display(0,0,"Artists by Class");
    display(0,0,"--------------------------------");
    for my $class (sort(keys(%class_artists)))
    {
        display(0,2,$class);
        my $artist_counts = $class_artists{$class};
        for my $artist (sort(keys(%$artist_counts)))
        {
            display(0,3,pad($$artist_counts{$artist},6).pad($artist,60));
        }
    }
}


if (0)
{
    display(0,0,"");
    display(0,0,"--------------------------------");
    display(0,0,"Artists with join clauses");
    display(0,0,"--------------------------------");
    for my $artist (sort(keys(%artist_class)))
    {
        my @parts = split(/\sand\s|&|,/i,$artist);
        if (@parts > 1)
        {
            for (@parts) { $_ =~ s/^\s|\s$//g; }
            display(0,2,pad($artist,60)." => ".join(' | ',@parts));
        }
    }
}



#------------------------------------------
# fixup the existing artists
#------------------------------------------

$artist_class{'Bach'} = "Classical";
$artist_class{'Brahms'} = "Classical";
$artist_class{'Handel'} = "Classical";
$artist_class{'Pachelbel'} = "Classical";
$artist_class{'Mussorgsky'} = "Classical";
$artist_class{'Ravel'} = "Classical";
$artist_class{'Bill Morrissey'} = "Rock Alt";
$artist_class{'Bob Marley'} = "Reggae";
$artist_class{'Dan Hicks'} = "Favorite";
$artist_class{'Horace Trahan'} = "Zydeco";
$artist_class{'Huey Lewis'} = "Rock Main";
$artist_class{'Jimmy Thackery'} = "Blues New";
$artist_class{'Johnny Cash'} = "Rock Main";
$artist_class{'Junior Walker'} = "Blues Old";
$artist_class{'Linda Gail Lewis'} = "Favorite";
$artist_class{'Pete Seeger'} = "Folk";
$artist_class{'Chet Atkins'} = "Country";
$artist_class{'Ella Fitzgerald'} = "Jazz Old";
$artist_class{'David Crosby'} = "Rock Soft";
$artist_class{'Graham Nash'} = "Rock Soft";
    # has an album
$artist_class{'Paul Simon'} = "Rock Soft";
$artist_class{'George Harrison'} = "Rock Main";
$artist_class{'Bob Seger'} = "Rock Main";
$artist_class{'Buffalo Springfield'} = "Rock Soft";
$artist_class{'John Denver'} = "Rock Soft";
    # has 4 songs
$artist_class{'George Clinton'} = 'R&B';
$artist_class{'Paul McCartney'} = "Rock Soft";

my %no_match;
$no_match{'Air'} = 1;
$no_match{'Beck'} = 1;
$no_match{'War'} = 1;
$no_match{'Yes'} = 1;
$no_match{'Train'} = 1;
$no_match{'Prince'} = 1;
$no_match{'Rush'} = 1;
$no_match{'Indigo Girls'} = 1;

my %addl_artists;

if (0)
{
    display(0,0,"");
    display(0,0,"--------------------------------");
    display(0,0,"New Artists");
    display(0,0,"--------------------------------");
    
    for my $potential (sort(keys(%unresolved_artists)))
    {
        # next if ($potential =~ /_/);
        my $try = $potential;
        $try =~ s/'//g;
        for my $artist (sort(keys(%artist_class)))
        {
            next if ($no_match{$artist});
            next if ($artist eq $potential);
            
            my $try2 = $artist;
            $try2 =~ s/'//g;
            if (index(uc($try),uc($try2)) >= 0)
            {
                display(0,2,pad($potential,60)." <= ".$artist);
                $artist_class{$potential} = $artist_class{$artist};
                $addl_artists{$potential} = $artist_class{$artist};
                last;
            }
        }
    }
}


if (0)
{
    display(0,0,"");
    display(0,0,"--------------------------------");
    display(0,0,"Potential New Artists ");
    display(0,0,"--------------------------------");
    for my $artist (sort(keys(%addl_artists)))
    {
        display(0,2,pad($artist,60)." $addl_artists{$artist}");
    }
}


#------------------------------------------------------
# move additional folders from unresolved to singles
#------------------------------------------------------

my %move_albums;

sub move_albums
{
    my ($prog_part,$path,@files) = @_;
    my @path_parts = split(/\//,$path);
    my $album_part = pop(@path_parts);
    my @parts = split(' - ',$album_part);
    my ($artist,$title) = (@parts);
    my $class = $artist_class{$artist};
    
    return 1 if (!@files);
    return 1 if ($path !~ /^$mp3_dir_RE\/unresolved/);
    return 1 if (@parts != 2);
    return 1 if (!$artist || !$title);
    return 1 if ($artist =~ /_/);
    return 1 if ($artist eq 'Various');
    return 1 if ($artist eq 'Original Soundtrack');
    
    return 1 if (!$class);

    display(0,0,"move_albums($path)");

    $move_albums{$path} = $class;
    return 1;
}




if (0)
{
    do_to_all($scan_dir,'move',undef,\&move_albums);

    display(0,0,"");
    display(0,0,"--------------------------------");
    display(0,0,"Move albums");
    display(0,0,"--------------------------------");
    
    for my $from (sort(keys(%move_albums)))
    {
        my $class = $move_albums{$from};
        $class =~ s/ /\//g;
        
        my $to = $from;
        $to =~ s/Light-Classical/Light Classical/;
        $to =~ s/$mp3_dir_RE\/unresolved\//$mp3_dir\/singles\/$class\//;
        display(0,0,"==>$to");
        
        exit 1 if (!move_dir($from,$to));
    }
}


#-------------------------------------------------------
# whew ... write out artist text files
#-------------------------------------------------------

if (1)
{
    display(0,0,"");
    display(0,0,"--------------------------------");
    display(0,0,"Final Artists ");
    display(0,0,"--------------------------------");
    
    my $text = "#-------------------------------------------------------\n";
    $text .= "# artist.pm - generated by fix_library.pm on ".today()."\n";
    $text .= "#-------------------------------------------------------\n";
    $text .= "# artists and their classes\n";
    $text .= "\n";
    $text .= "my \%artist_class;\n";
    $text .= "\n";
    
    for my $artist (sort(keys(%artist_class)))
    {
        display(0,2,pad($artist,60)." $artist_class{$artist}");
        $text .= pad('$artist_class{"'.$artist.'"}',50);
        $text .= ' = "'.$artist_class{$artist}.'";'."\n";
    }
    $text .= "\n";
    $text .= "\n";
    $text .= "\n";
    $text .= "1;\n";
    $text .= "\n";
    $text .= "#-------------------------------------------------------\n";
    $text .= "# end of artist.pm\n";
    $text .= "#-------------------------------------------------------\n";

    printVarToFile(1,"/junk/artist.pm",$text);
}


    
display(0,0,"");
LOG(0,"fix_library.pm finished");

1;
