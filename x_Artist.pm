#-------------------------------------------------------
# Artist.pm
#-------------------------------------------------------
# note on artists and genres
#
# ARTIST TEXT FILES are as persistent as MP3 files themselves.
# REMOVING ARTIST TEXT FILES should only be dont by automated
#    proesses that DONT REMOVE CLASSIFIED ARTISTS, or else
#    manual changes to the text files, like the 'allow_search'
#    bit, will be lost.

package x_Artist;
use strict;
use warnings;
use threads;
use threads::shared;
use Utils;
use Database;
use x_ArtistDefs;
use x_mbUtils;

#share(%stats);

my $last_rebuild_file = "$cache_dir/last_artist_rebuild.txt";
my $artist_cache_dir = "$cache_dir/artists";
mkdir $artist_cache_dir if (!-d $artist_cache_dir);


#--------------------------------------------
# utils
#--------------------------------------------

sub name_parts
{
    my ($name) = @_;
    return split(/\s+/,$name);
}


sub get_artist
{
    my ($params,$dirty_name) = @_;
    my $name = clean_name($dirty_name);
    return $params->{artists}->{$name};
}


sub clean_name
{
    my ($name) = @_;
    #return $name;
    
    $name =~ s/ _ / - /;
    $name =~ s/best of the//i;
    $name =~ s/the best of//i;
    $name =~ s/best of//i;
    $name =~ s/\&|;|\// and /g;
    $name =~ s/, \@ www.emusic.com.*$//;
    $name =~ s/^(De De Vogt|Indigo Girls).*/$1/;
    $name =~ s/\\x00//g;
    $name =~ s/\?//g;
    $name =~ s/\(.*\)//g;
    $name =~ s/featuring.*$//;
    $name =~ s/feat\..*$//;
    $name =~ s/(-|,}and)\s*$//;
    
    while ($name =~ s/\s\s/ /g) {};
    $name = CapFirst($name);
    $name =~ s/ And / and /g;
    return '' if ($name =~ /^-/);
    
    return $name;
}


sub new_artist
    # create new in-memory artist from
    # name, class, and type. Note that we
{
    my ($source,$params,$name,$class,$type) = @_;
    my $artists = $params->{artists};

    return if
        $name eq $ARTIST_UNKNOWN ||
        $name eq $ARTIST_VARIOUS;
        
    # eliminate some other brain dead ones
    
    return if
        $name =~ s/##ILLEGAL CHAR##/#/g ||
            # temp fix
        $name =~ /^\d+$/ ||
        $name =~ /mp3s|cuban artists/ ||
        $name =~ /^assorted/ ||
        $name =~ /^various/i ||
        $name =~ /^unknown/i;

    $name = clean_name($name);
    return if !$name;
    
    if (!$class ||
        $class eq $ARTIST_CLASS_UNRESOLVED ||
        $class eq $ARTIST_CLASS_FROMTAG)
    {
        bump_stat('artist_unclassified_new');
        display(0,0,"new_unclassified_artist($type,$name)");
        # return 1;
    }
    else
    {
        bump_stat('artist_classified_new');
        display(0,0,"NEW_CLASSIFIED_ARTIST($type,$name) class=$class");
    }
    
    if ($artists->{$name})
    {
        error("new_artist() called with existing artist($name)");
        return;
    }
    
    my $rec = db_init_rec('artists');
    $rec->{new} = 1;
    $rec->{name} = $name;
    $rec->{class} = $class;
    $rec->{type} = $type;
    $rec->{source} = $source;
    $rec->{allow_substring_match} = 1 if
        $rec->{type} eq 'person' ||
        name_parts($rec->{name})>1 ||
        $class eq 'Classical';
    $artists->{$name} = $rec;
    return $rec;
}



sub artist_to_text
    # create the textfile representation of the artist
{
    my ($rec) = @_;
    my $text = '';
    
    for my $k (sort(keys(%$rec)))
    {
        next if $k =~ /^(new|changed|txt_exists|txt_changed)$/;
        my $val = $rec->{$k};
        $val = '' if (!defined($val));
        $text .= "$k=$rec->{$k}\n";
    }
    return $text;
}


sub artist_from_text
    # create an in-memory artist from a text representation
    # takes the optional entry to check
    # artist name in the file versus the filename
{
    my ($entry,$text) = @_;
    my $rec = {};
    
    my @lines = split(/\n/,$text);
    for my $line (@lines)
    {
        my $pos = index($line,'=');
        next if ($pos < 1);
        my $lval = substr($line,0,$pos);
        my $rval = substr($line,$pos+1) || '';
        $rec->{$lval} = $rval;
    }
    if ($entry && $rec->{name} ne $entry)
    {
        error("artist text file '$entry' does not contain correct artist name '$rec->{name}'");
        return;
    }
    return $rec;
}


sub artist_from_text_file
    # create an in-memory artist record from
    # a file given by $filename. $entry may be ''
    # to bypass name consistency checking
{
    my ($entry,$filename) = @_;
    my $text = getTextFile($filename);
    if (!$text)
    {
        error("No text in artist file:$filename");
        return;
    }
    return artist_from_text($entry,$text);
}



sub artists_from_text
    # update the database directly from any artist
    # text files that have changed since the last rebuild
    # called at the start of init_artists()
{
    my ($params) = @_;
    my $artists = $params->{artists};
    my $last = getTextFile($last_rebuild_file);
    $last =~ s/\s$//gs;
    $last ||= '';
    LOG(0,"artists_from_text() last_rebuild=$last");
    
    if (!opendir(DIR,$artist_cache_dir))
    {
        error("Could not opendir($artist_cache_dir)");
        return;
    }
    
    while (my $entry = readdir(DIR))
    {
        next if ($entry !~ /\.txt$/);
        my $filename = "$artist_cache_dir/$entry";
        $entry =~ s/\.txt$//;
        
        # mark any existing in-memory records
        # as having a text file on disk, and presume
        # it's up to date
        
        my @info = stat($filename);
        my $ts = $info[9];
        my $exists = $artists->{$entry};
        if ($exists)
        {
            $exists->{txt_exists} = 1;
            $exists->{txt_changed} = 0;
            if ($ts <= $last)
            {
                display(2,1,"artists_from_text(unchanged) last=$last ts=$ts entry=$entry");
                next
            }
            display(2,1,"arists_from_text(out_of_date) = $entry");
        }
        else
        {
            display(2,1,"artists_from_text(new) last=$last ts=$ts entry=$entry");
        }

        # process this text file into memory
        
        my $rec = artist_from_text_file($entry,$filename);
        return 1 if (!$rec);

        # tell the db whether to use insert or update, and
        # remember separately whether the text file needs writing
        # so henceforth, txt changed must be set if changed is set
        # at this moment in the process, they can be different.

        $rec->{new} = 1 if (!$exists);
        $rec->{changed} = 1 if ($exists);
        $rec->{txt_exists} = 1;
        $rec->{txt_changed} = 0;
        $artists->{$entry} = $rec;
    }
    
    return 1;  
}



sub add_default_artists
{
    my ($params) = @_;
    my $artists = $params->{artists};
    
    LOG(0,"init_artists() adding default artists");
    for my $name (sort(keys(%init_artist_class)))
    {
        my $use_name = clean_name($name);
        warning(2,0,"Clean name($use_name) differs from default artist name($name)")
            if ($use_name ne $name);
        
        if (!$artists->{$use_name})
        {
            my $ac = $init_artist_class{$name};
            my ($type,$class) = (@$ac);
            my $artist = new_artist('default',$params,$use_name,$class,$type);
        }
    }
}    
    



#--------------------------------------------
# api
#--------------------------------------------

sub init_artists
    # done using in memory hash of artists_by_name
    # at beginning of scan
{
    my ($params,$rebuild) = @_;

    $params->{artists} ||= {};
    my $artists = $params->{artists};
    $rebuild = 1 if (!defined($rebuild));
    LOG(0,"init_artists() rebuild=$rebuild");

    # remove old artists from database if cleaning
    # must remove text files by hand ...

    if ($rebuild &&
        (!db_do($params->{dbh},'DROP TABLE artists') ||
     	 !db_do($params->{dbh},'CREATE TABLE artists ('.
                join(',',@artist_field_defs).')')))
    {
        error("Could not clear artists database");
    }

    # get existing artists from db
    
    my $recs = get_records_db($params->{dbh},"SELECT * FROM artists ORDER BY name");
    LOG(1,"init_artists() found ".scalar(@$recs)." existing artists");
    bump_stat('artists_init_db',scalar(@$recs));
    for my $rec (@$recs)
    {
        $rec->{txt_changed} = 1;
        display(2,2,"existing_db_artist=$rec->{name}");
        $artists->{$rec->{name}} = $rec;
    }
        
    # update any changed artists from text files
    
    return if !artists_from_text($params);

    # add any missing default (hard coded) artists
    
    add_default_artists($params);

    # return to caller
    
    LOG(0,"init_artists() ending with ".scalar(keys(%$artists))." artists");
    return 1;
}


sub finalize_artists
    # Write any changed artist database records,
    # and any changed artists text files (for
    # artists that have classes).
{
    my ($params) = @_;
    my $dbh = $params->{dbh};
    my $artists = $params->{artists};
    LOG(0,"finalize artists");

    # skip known constant artist names, but
    # allow them in the tree for simplicity
    
    for my $name (sort(keys(%$artists)))
    {
        my $artist = $artists->{$name};
        next if
            $artist->{name} eq $ARTIST_VARIOUS ||
            $artist->{name} eq $ARTIST_UNKNOWN;
            
        if ($artist->{new})
        {
            bump_stat("artist_db_new");
            display(2,1,"artist_db_new($name)");
            if (!insert_record_db($dbh,'artists',$artist,'name'))
            {
                error("Could not insert new artist($name)");
                return;
            }
        }
        elsif ($artist->{changed})
        {
            bump_stat("artist_db_changed");
            display(2,1,"artist_db_changed($name)");
            if (!update_record_db($dbh,'artists',$artist,'name'))
            {
                error("Could not update artist($name)");
                return;
            }
        }
        else
        {
            bump_stat("artist_db_unchanged");
        }

        # ONLY WRITE TEXT FILES FOR CLASSIFIED ARTISTS
        
        if ($artist->{class} &&
            $artist->{class} ne $ARTIST_CLASS_UNRESOLVED &&
            $artist->{class} ne $ARTIST_CLASS_FROMTAG &&
            (!$artist->{txt_exists} ||
             $artist->{txt_changed}))
        {
            if (!$artist->{txt_exists})
            {
                bump_stat('artist_text_new');
                LOG(1,"artist_text_new($name)");
            }
            else
            {
                bump_stat('artist_text_changed');
                display(2,1,"artist_text_changed($name)");
            }
            
            my $text_filename = "$artist_cache_dir/$name.txt";
            if (!printVarToFile(1,$text_filename,artist_to_text($artist)))
            {
                error("Could not write artist text file $text_filename");
                return;
            }
        }
        else
        {
            bump_stat('artist_text_unchanged');
        }
    }
    
    my $now = time();
    printVarToFile(1,$last_rebuild_file,$now);
    $params->{dbh}->commit();
    
    return 1;
}


#-----------------------------------
# main for testing
#-----------------------------------
# CANNOT CALL THIS BEFORE ARTISTAN THREADS!


sub set_changed
{
    my ($artist,$field,$value) = @_;
    
    my $old_val = $artist->{$field} || '';
    if ($value ne $old_val)
    {
        bump_stat('artist_changed_$field');
        $artist->{$field} = $value;
        $artist->{changed} = 1;
        $artist->{text_changed} = 1 if ($artist->{class})
    }
}
    
    

sub test_run
{
    $debug_level = 0;
    $debug_packages .= '|artist';

    LOG(0,"artist.pm started");
    db_initialize();
    my $dbh = db_connect();
	$dbh->{AutoCommit} = 0;    
    my $params = { dbh => $dbh };
    init_artists($params,0);

    # build the artist statuses ...
    # this could be done in finalize artist,
    # or new_artist or something too .

    display(0,0,'----------------------------------------------');
    display(0,0,"process artists");
    display(0,0,'----------------------------------------------');
        
    for my $name (sort(keys(%{$params->{artists}})))
    {
        my $artist = $params->{artists}->{$name};
        next if $artist->{status} eq $ARTIST_STATUS_MB_ERROR;
            # had an error on a previous run
                 
        my $info = mb_find_artist($artist);
        bump_stat("artist_status: $info->{status}");
        
        my $changed = 0;
        $changed = 1 if set_changed($artist,'status',$info->{status});
        $changed = 1 if set_changed($artist,'tags',$info->{tags});
        $changed = 1 if set_changed($artist,'mb_id',$info->{mb_id});
        $changed = 1 if set_changed($artist,'score',$info->{score});

        $changed = 1 if !$artist->{class} && set_changed($artist,'type',$info->{type});
        
        $artist->{count} = $info->{count};
        $artist->{match} = $info->{match};
        
        bump_stat($changed ? "artist_changed" : "artist_unchanged");
    }

    # Show the classified artists

    for my $match_type (reverse(
            $ARTIST_STATUS_NONE,
            $ARTIST_STATUS_MB_ERROR,
            $ARTIST_STATUS_MB_NOMATCH,
            $ARTIST_STATUS_MB_NOMATCH_EXACT,
            $ARTIST_STATUS_MB_DUPLICATES,
            $ARTIST_STATUS_MB_MATCH,
            $ARTIST_STATUS_MB_VERIFIED,
        ))
    {
        display(0,0,'----------------------------------------------');
        display(0,0,"$match_type artists");
        display(0,0,'----------------------------------------------');
        
        for my $name (sort(keys(%{$params->{artists}})))
        {
            my $artist = $params->{artists}->{$name};
            next if ($artist->{status} ne $match_type);
            display(_clip 0,1,
                pad($artist->{match} || 0,2)." / ".
                pad($artist->{count} || 0,3)."  ".
                pad($artist->{status},12)." ".
                pad($artist->{type},7)." ".
                pad($artist->{class},20)." ".
                pad($artist->{name},40)." ".
                $artist->{tags});
        }
    }

    
    finalize_artists($params);

    db_disconnect($dbh);    # nested calls allowed?
    dump_stats();
    LOG(0,"artist.pm finished");
}

print "artist_as_library=$modules_as_libraries\n";
test_run() if (!$modules_as_libraries);


1;

