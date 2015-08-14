#---------------------------------------
# mbScoreFolder.pm
#---------------------------------------
# score a folder from the bottom up, based
# on artisanID->acousticID, and cache the results

package x_mbScoreFolder;
use strict;
use warnings;
use XML::Simple;
use Encode qw/_utf8_on encode decode/;
use Data::Dumper;
use Digest::MD5 'md5_hex';
use Text::LevenshteinXS qw(distance);
#use Text::Levenshtein qw(distance);
#use Text::Levenshtein::Damerau::XS qw(xs_edistance);
use appUA;
use Utils;
use MediaFile;      # only for get_fpcalc_info
use x_mbUtils;

$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent = 1;

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
        mb_score_folder
    );
}
        

# working variables

my $ACOUSTIC_ID_THRESHOLD = 0.01;
    # don't look at (the trees of) acoustic_id's
    # with scores lower than this

#-------------------------------------------------
# utilities
#-------------------------------------------------

sub set_tree_error
{
    my ($tree,$level,$indent,$msg) = @_;
    $tree->{errors} ||= [];
    push @{$tree->{errors}},$msg;
    warning($level,$indent,$msg);
}
    
sub disp_six
{
    my ($n) = @_;
    $n = sprintf('%0.2f',$n);
    while (length($n)<6) { $n = ' '.$n; };
    return $n;
}


sub take_larger
{
    my ($obj1,$obj2,$field) = @_;
    $obj1->{$field} = $obj2->{$field}
        if ($obj2->{$field} > $obj1->{$field});
}    


sub init_numerical_scores
{
    my ($object) = @_;
    $object->{score}            = 0;
    $object->{meta_score}       = 1;   # for releases and tracks
    $object->{match_count}      = 0;   # integral number of items
    $object->{score_count}      = 0;   # sum of acousticID scores
    $object->{match_pct}        = 0;   # match_count / num_files
    $object->{score_pct}        = 0;   # match_score / num_files
    $object->{fill_match_pct}   = 0;   # match_count / track_count
    $object->{fill_score_pct}   = 0;   # match_score / track_count
}

sub init_object_scores
{
    my ($object) = @_;
    init_numerical_scores($object);
    $object->{artisan_ids}      = {};
}


                
sub init_tree_object
{
    my ($tree,$type,$object,$parent) = @_;
    my $id = $type =~ /medium/ ?
        $parent->{id}.':'.$object->{position} :
        $object->{id};
        
    my $exists = $tree->{$type.'s'}->{$id};
    if (!$exists)
    {
        $object->{_type} = $type;
        $object->{id} = $id if ($type =~ /medium/);
            # it's already there otherwise
            
        if ($type !~ /track/)
        {
            init_object_scores( $object );
            $object->{children} = {};
        }
        
        $tree->{$type.'s'}->{$id} = $object;
    }
    else
    {
        $object = $exists;
    }
    
    if ($parent)
    {
        my $exists = $parent->{children}->{$id};
        if (!$exists)
        {
            $parent->{children}->{$id} = $object;
        }
        else
        {
        }
    }

    
    return $object;
}



sub score_meta_data
{
    my ($db_object,$type,$object) = @_;
    
    # type == track
    #
    #    db_object = FILE (currently called a TRACK)
    #    object = mb_track
    #

    #  db_object = FOLDER
    #  object = mb_release

    if ($type eq 'release')
    {
        my $name1 = uc($db_object->{TITLE});
        my $name2 = uc($object->{title});

        $name1 =~ s/\W//g;
        $name1 =~ s/[^\x20-\x7f]//g;
        $name1  =~ s/\s//g;

        $name2 =~ s/\W//g;
        $name2 =~ s/[^\x20-\x7f]//g;
        $name2  =~ s/\s//g;
        
        my $score;
        if ($name1 eq $name2)
        {
            $score = 0;
        }
        elsif (index($name1,$name2) > 0 ||
               index($name2,$name1) > 0)
        {
            $score = 0.05;
        }
        else
        {
            #my $score = xs_edistance($name1,$name2);
            $score = distance(uc($name1),uc($name2));
            $score = length($name1) if ($score > length($name1));
            $score = (length($name1) - $score) / length($name1);
        }
        
        # convert 0..1 to 1-$WEIGHT ... 1
                
        my $WEIGHT = 0.60;
        $score = 1 - ($WEIGHT * $score);
        display(9,0,"score($name1,$name2)=$score");

        return 1; # $score;        
    }
    
    
    return 1;
}



#-------------------------------------------------
# pass1 - build the initial tree
#-------------------------------------------------

sub bubble_up
{
    my ($tree,$type,$object,$artisan_info,$child,$final) = @_;
    my $artisan_id = $artisan_info->{artisan_id};
    $final ||= 0;
    
    if (!$final)
    {
        $artisan_info = clone_hash($artisan_info);
        $object->{artisan_ids} ||= {};
        if (my $exists = $object->{artisan_ids}->{$artisan_id})
        {
            warning(2,0,"artisan_id($artisan_id) already exists on $type($object->{id})");
            return $exists;
        }
        $object->{artisan_ids}->{$artisan_id} = $artisan_info;
    }
    $artisan_info->{'mb_'.$type.'_id'} = $object->{id}
        if ($type ne 'tree');
    
    $object->{match_count} ++;
    $object->{score_count} += $artisan_info->{mb_acoustic_score};
    $object->{match_pct}   = $object->{match_count} / $tree->{num_files};
    $object->{score_pct}   = $object->{score_count} / $tree->{num_files};
    
    # for releases and mediums, which have track counts, we
    # calculate the fill percents ..
    
    if ($type =~ /^(release|medium)$/)
    {
        $object->{fill_match_pct} = $object->{match_count} / $object->{track_count};
        $object->{fill_score_pct} = $object->{score_count} / $object->{track_count};
    }
    
    # for other objects (releasegroup and the tree) the
    # fill_percents are the highest of any object found
    # within them, hence we need the child object as well
    
    else
    {
        take_larger($object,$child,'fill_match_pct');
        take_larger($object,$child,'fill_score_pct');
    }        
        
    # calculate the final score (0..101)
    
    $object->{score} =
        $object->{meta_score} * (
            int(100*$object->{score_pct}+5) +
            $object->{fill_score_pct});
    
    display(3,6,"bubble_up($final) ".pad($type,16).' '. # $object->{id}) ".
        "score ".
            disp_six($object->{score}).
        "match count/score/pct".
            add_leading_char($object->{match_count},3,' ').
            disp_six($object->{score_count}).
            disp_six($object->{match_pct}).
        "   fill match/score pct".
            disp_six($object->{fill_match_pct}).
            disp_six($object->{fill_score_pct})
        );
                    
    
    return $artisan_info;
}


sub mb_parse_track_info
    # build the flattened, in memory version of the tree
    # from the sliver given to us in $track_info.
    # 
    # The objects kept in flat hashes on the tree are
    # called tree_objects.  They are initialized from
    # a particular (the first found) instance of a sliver
    # object, but accumulate all of the child objects
    # of all sliver objects of their type. whew.
    
    # We do this by creating 'children' hashes on the tree_objects
    # that mimic the existing arrays on the slivers (i.e. the
    # releases for a releasegroup) that point to the tree
    # version of the object, instead of the sliver version.
    # In the end, the original child objects on the tree_object
    # which just points to a sliver, could be removed.
    
    # Note that we cannot have a 'parent' member on the
    # tree releases or tracks, because they can exist in
    # multiple releasegroups and mediums, respectively.
    
    # We use an id of release_id:medium_position for
    # the medium ids, assuming, as per MB database, that
    # the same medim (which has no proper MB id) cannot
    # occur on multiple MB releases.

{
    my ($tree,$folder,$file,$track_info,$artisan_id) = @_;
    display(2,0,"mb_parse_track_info($artisan_id) num_files=$tree->{num_files}");
    if (!$track_info->{results})
    {
        warning(1,0,"no track_info results for artisan_id($artisan_id) ...");
        return 1;
    }
    if (ref($track_info->{results}) !~ /ARRAY/)
    {
        warning(1,0,"no array track_info results for for artisan_id($artisan_id) ...");
        #print Dumper($track_info);
        return 1;
    }
    
    # print Dumper($track_info);
    
    for my $result (@{$track_info->{results}})
    {
        my $acoustic_id = $result->{id};
        if ($result->{score} < $ACOUSTIC_ID_THRESHOLD)
        {
            warning(1,0,"skipping acoustic_id($acoustic_id}  score=$result->{score}");
            next;
        }
        display(3,1,"acoustic_id($acoustic_id) score=$result->{score}");

        for my $recording (@{$result->{recordings}})
        {
            my $recording_id = $recording->{id};
            display(3,2,"recording_id($recording_id)");

            for my $releasegroup (@{$recording->{releasegroups}})
            {
                my $releasegroup_id = $releasegroup->{id};
                display(3,3,"releasegroup_id($releasegroup_id)");
                my $tree_releasegroup = init_tree_object(
                    $tree,'releasegroup',$releasegroup,$tree);

                for my $release (@{$releasegroup->{releases}})
                {
                    my $release_id = $release->{id};
                    display(3,4,"release_id($release_id)");
                    my $tree_release = init_tree_object(
                        $tree,'release',$release,$tree_releasegroup);
                    $tree_release->{meta_score} = score_meta_data(
                        $folder,'release',$tree_release);

                    for my $medium (@{$release->{mediums}})
                    {
                        # a medium has no id ... it has a position integer
                        my $medium_position = $medium->{position};
                        display(3,5,"medium_position($medium_position)");
                        my $tree_medium = init_tree_object(
                            $tree,'medium',$medium,$tree_release);

                        for my $track (@{$medium->{tracks}})
                        {
                            my $track_id = $track->{id};
                            display(3,6,"track_id($track_id)");
                            my $tree_track = init_tree_object(
                                $tree,'track',$track,$tree_medium);
                            
                            # first time we have seen this track
                            # at this point we create the leaf artisan_info
                            # record and score the meta_info for the track
                            
                            if (!$tree_track->{artisan_info})
                            {
                                my $artisan_info = {
                                    artisan_id => $artisan_id,
                                    mb_track_id => $track_id,
                                    mb_recording_id => $recording_id,
                                    mb_acoustic_id => $acoustic_id,
                                    mb_acoustic_score => $result->{score},
                                };
                                $tree_track->{artisan_info} = $artisan_info;
                                $tree_track->{meta_score} = score_meta_data(
                                    $file,'track',$tree_track),
                                $tree_track->{artisan_id} = $artisan_id;
                            }

                            # Give an error if different artisan_ids are
                            # assigned to the same track, which means that we
                            # either have duplicate copies of the song, perhaps
                            # at different bitrates or something like that,
                            # in the folder, or the MB database is incorrect.
                            
                            elsif ($tree_track->{artisan_info}->{artisan_id} ne $artisan_id )
                            {
                                set_tree_error($tree,1,0,"multiple artisan_ids($artisan_id and $tree_track->{artisan_info}->{artisan_id} for track($track_id)");
                                return 1; #  !!!
                            }

                            # We also enforce our assumption that there will be
                            # exactly one track that points to a given recording.
                            # I may need to remove this if (a) it's not true, and
                            # (b) there's no useful information on a recording.
                            # Otherwise, I need to go down another level.
                            
                            elsif ($tree_track->{artisan_info}->{mb_recording_id} ne $recording_id )
                            {
                                error("multiple recording_ids($recording_id and $tree_track->{artisan_info}->{recording_id} for track($track_id)");
                                return; #  !!!
                            }
                            
                            # We can now bubble the results up                            
                        
                            my $artisan_info = $tree_track->{artisan_info};
                            my $new_info = bubble_up($tree,'medium',$tree_medium,$artisan_info);
                            $new_info = bubble_up($tree,'release',$tree_release,$new_info);
                            $new_info = bubble_up($tree,'releasegroup',$tree_releasegroup,$new_info,$tree_release);
                            $new_info = bubble_up($tree,'tree',$tree,$new_info,$tree_releasegroup);

                       
                        }   # for each track
                        
                        delete $tree_medium->{tracks};

                    }   # for each medium

                    delete $tree_release->{mediums};
                    
                }   # for each release

                delete $tree_releasegroup->{releases};

            }   # for each releasegroup
        }   # for each recording_id
    }   # for each acoustic_id

    return 1;
    
}   # mb_score_track()



sub mb_build_tree
{
    my ($tree,$folder,$files) = @_;
    
    my $missing_id = '000';
    for my $file (@$files)
    {
        # give a warning, but don't score missing artisan_ids
        # however, add them to the list as unmatched, under a phony id
        
        if (!$file->{ARTISAN_ID})
        {
            set_tree_error($tree,0,0,"no artisan id for file $file->{FULLNAME}");
            $tree->{artisan_ids}->{'missing_'.$missing_id++} = 0;
            next;
        }

        $tree->{artisan_ids}->{$file->{ARTISAN_ID}} = 0;
		
		my $media_file = MediaFile->new($file->{FULLNAME});
        my $fpcalc_info = $media_file->get_fpcalc_info();
        if (!$fpcalc_info)
        {
            set_tree_error($tree,0,0,"could not get fpcalc_info for $file->{FULLNAME}");
            next;
        }
                                                     
        my $track_info = mb_get_track_info($file->{ARTISAN_ID},$fpcalc_info);
        if (!$track_info)
        {
            # if null, it means that there was a bad connection
            # to acousticID.com, and we have to bail and try
            # again later.
            set_tree_error($tree,0,0,"no mb_track_info for $file->{ARTISAN_ID}");
            next;
        }
            
        return if !mb_parse_track_info($tree,$folder,$file,$track_info,$file->{ARTISAN_ID});
    }

    $tree->{unmatched_count} = $tree->{num_files} - $tree->{match_count};
    # print Dumper($tree)."\n";
    
    return 1;

}


#----------------------------------------------------------
# pass2 - sort the tree
#----------------------------------------------------------
# What we want is the best set of releasegroups, releases,
# and mediums that match all of the files that had
# aoustic ids, where 'best' is generally defined as the
# minimum set that will accomplish the goal.
#
# To do this we sort the items in the tree at each level
# by their metascore * score_pct.fill_pct, then walk the
# tree until we have matched all the files. This develops
# a new score for the tree, releases, and medium that is based
# on the files it 'used'.
#
# Note that this algorithm is not perfect, which would
# require walking and scoring every possible combination
# of releasegroups - releases - mediums, a multi-factorial
# problem.

sub mb_sort_children
    # sort the children of the object by score
    # and place the sorted list of ids on the parent.
    # if the child entity is the best one of it's kind found
    # on the tree, set the tree's best=>{entity_type).
    # child_field gets an 's' so, release becomes releases, etc
{
    my ($object) = @_;
    my $children = $object->{children};
    display(3,0,"mb_sort_children $object->{_type}($object->{id}) num_children=".scalar(keys(%$children)));

    # sort the records
    
    my @sorted_ids = sort {
        $children->{$b}->{score} <=> $children->{$a}->{score} }
        keys (%$children);
    $object->{sorted_children_ids} = \@sorted_ids;
    
    # recurse to children
    
    if ($object->{_type} !~ /^release$/)
    {
        for my $child_id (@sorted_ids)
        {
            mb_sort_children($children->{$child_id});
        }
    }                            

}   # mb_sort_entity()
    


#----------------------------------------------------------
# pass3 - walk the tree
#----------------------------------------------------------

sub init_final_scores
{
    my ($object) = @_;
    init_numerical_scores($object);
    $object->{best_children} = [];
    $object->{old_artisan_ids} = $object->{artisan_ids};
    $object->{artisan_ids} = {};
}


sub final_tree_object
{
    my ($object,$parent,$no_scores) = @_;
    init_final_scores($object) if (!$no_scores);
    if ($parent)
    {
        push @{$parent->{best_children}},$object;
        $object->{parent} = $parent;
    }
}


sub mb_walk_tree
    # walk the existing tree, creating the final result tree
    # we are done when we have matched all the tree's artisan ids
    # using artisan_ids found at the medium level
{
    my ($tree) = @_;
    my $need = $tree->{match_count};
    final_tree_object($tree);
    display(2,0,"mb_walk_tree()");

    for my $releasegroup_id (@{$tree->{sorted_children_ids}})
    {
        my $set_releasegroup = 0;
        my $releasegroup = $tree->{releasegroups}->{$releasegroup_id};
        display(3,1,"mb_walk_tree releasegroup($releasegroup_id)");

        for my $release_id (@{$releasegroup->{sorted_children_ids}})
        {
            my $set_release = 0;
            my $release = $tree->{releases}->{$release_id};
            display(3,2,"mb_walk_tree release($release_id)");

            for my $medium_id (@{$release->{sorted_children_ids}})
            {
                my $set_medium = 0;
                my $medium = $tree->{mediums}->{$medium_id};
                display(3,3,"mb_walk_tree medium($medium_id)");

                for my $track_id (keys(%{$medium->{children}}))
                {
                    my $track = $medium->{children}->{$track_id};
                    my $artisan_info = $track->{artisan_info};
                    my $artisan_id = $artisan_info->{artisan_id};
                    next if $tree->{artisan_ids}->{$artisan_id};
                    $tree->{artisan_ids}->{$artisan_id} = $artisan_info;
                   
                    $artisan_info->{position} = $track->{position};
                    
                    display(3,4,"mb_walk_tree track($track->{id})=$artisan_id");
 
                    final_tree_object($releasegroup,$tree) if (!$set_releasegroup);
                    final_tree_object($release,$releasegroup) if (!$set_release);
                    final_tree_object($medium,$release) if (!$set_medium);
                    final_tree_object($track,$medium,1);

                    $set_medium = 1;
                    $set_release = 1;
                    $set_releasegroup = 1;
                    
                    bubble_up($tree,'medium',$medium,$artisan_info,$track,1);
                    bubble_up($tree,'release',$release,$artisan_info,$medium,1);
                    bubble_up($tree,'releasegroup',$releasegroup,$artisan_info,$release,1);
                    bubble_up($tree,'tree',$tree,$artisan_info,$releasegroup,1);
                    
                }
                clean_result_object($medium,'tracks');
            }
            clean_result_object($release,'mediums');
        }
        clean_result_object($releasegroup,'releases');
        return 1 if ($tree->{match_count} == $need);
    }
    
    if ($tree->{match_count} != $need)
    {
        set_tree_error($tree,0,0,"could not find all needed tracks!");
    }
    
    return 1;
}
                    
            

#---------------------------------------------
# pass4 - clean up the resulting tree
#---------------------------------------------

sub clean_result_object
{
    my ($object,$child_field,$root) = @_;
    
    display(3,0,"clean_result_object($object) $child_field");
    

    # change the tracks into an array of items
    # sorted by position, and remove their
    # artisan_info and meta_score fields 
    
    if ($child_field eq 'tracks')
    {
        $object->{tracks} = [];
        my $tracks = $object->{best_children};
        if ($tracks)
        {
            for my $track (sort {
                $a->{position} <=> $b->{position}
                } (@$tracks))
            {
                # delete $track->{artisan_info}->{artisan_id};
                delete $track->{meta_score};
                delete $track->{artisan_info};
                delete $track->{parent};
                push @{$object->{tracks}},$track;
            }
        }
    }
    else
    {
        $object->{$child_field} = $object->{best_children};
    }
    
    delete $object->{parent};
    delete $object->{children};
    delete $object->{best_children};
    delete $object->{sorted_children_ids};
    delete $object->{old_artisan_ids};
    delete $object->{artisan_ids} if (!$root);
    
    if (1 && !$root)
    {
        delete $object->{match_count};
        delete $object->{score_count};
        delete $object->{match_pct};
        delete $object->{score_pct};
        delete $object->{fill_match_pct};
        delete $object->{fill_score_pct};
        delete $object->{meta_score};
        delete $object->{score};
    }
}


sub clean_tree
{
    my ($tree) = @_;
    clean_result_object($tree,'releasegroups',1);
    delete $tree->{releases};
    delete $tree->{mediums};
    delete $tree->{tracks};
    $tree->{_type} = 'result';
    
    # change artisan ids from hash into an array
    my $artisan_ids = $tree->{artisan_ids};
    $tree->{artisan_ids} = [];
    for my $artisan_id (sort {
        
        compare_artisan_ids($artisan_ids,$a,$b)
        
        } (keys(%$artisan_ids)))
    {
        push @{$tree->{artisan_ids}},
            $artisan_ids->{$artisan_id};
    }
    
    delete $tree->{releasegroups}
        if (!scalar(@{$tree->{releasegroups}}));
        
    # print Dumper($tree);
}


#----------------------------------------------------------
# mb_score_folder - main entry point
#----------------------------------------------------------

sub mb_score_folder
    # as the slivers for each track are parsed, the virtual
    # tree is flattened out by objects_with_ids into hashes
    # on the tree, in keeping with the MB database design.
    # Mediums do not show up in this flattened hierarchy.
{
    my ($folder,$files) = @_;
    my $num_files = scalar(@$files);
    my $tree = read_mb_score_cache($folder,$files);
    return $tree if ($tree);

    if ($debug_level)
    {
        display(1,0,"mb_score_folder $folder->{ID}:$folder->{FULLPATH} num_files=$num_files");
    }
    else
    {
        display(0,0,"mb_score_folder()");
    }
    bump_stat("mb_score_folder");
    
    $tree = {
        id          => 'root',
        _type       => 'tree',
        num_files   => $num_files,
        releasegroups => {},
            # release groups duplicated by {children}
            # hash built on the tree ...
        releases => {},
        mediums => {},
        tracks => {},
    };

    # initialize scores, build the treee
    # sort, and walk it
    
    init_object_scores($tree);
    return if !mb_build_tree($tree,$folder,$files);
    mb_sort_children($tree);
    return if !mb_walk_tree($tree);
    
    # clean up the result set
    # and write the cache

    clean_tree($tree);
    return if !write_mb_score_cache($folder,$files,$tree);
    return $tree;
    
}   # mb_score_foler() 



sub compare_artisan_ids
    # compare two artisan ids, sorting them by
    # releasegroup-release-medium-track_number
{
    my ($artisan_ids,$a,$b) = @_;
    
    my $a1 = $artisan_ids->{$a};
    my $a2 = $artisan_ids->{$b};
    
    my $k1 =
        $a1->{mb_releasegroup_id}.
        $a1->{mb_release_id}.
        $a1->{mb_medium_id};
        
    my $k2 =
        $a1->{mb_releasegroup_id}.
        $a1->{mb_release_id}.
        $a1->{mb_medium_id};
    
    return $k1 cmp $k2 if ($k1 ne $k2);
    return $a1->{position} <=> $a2->{position};
}
    

#------------------------------------------------------
# cache files
#------------------------------------------------------

sub get_cachefile_name
{
    my ($folder) = @_;
    my $name = $folder->{FULLPATH};
    $name =~ s/^$mp3_dir_RE\///;
    $name =~ s/\//./g;
    $name .= '.xml';
    my $dir = "$cache_dir/folder_scores";
    mkdir $dir if !(-d $dir);
    return "$dir/$name";
}

sub get_cache_version
    # return an md5 hash of the concatenation of
    # all the filenames in the directory, so that
    # we can detect if any have been added, removed
    # or changed, so that we can invalidate the cache
    # if they have
{
    my ($files) = @_;
    my $key = '';
    for my $file (@$files)
    {
        $key .= $file->{NAME}.$file->{SIZE}.$file->{TIMESTAMP};
    }
    return md5_hex($key);
}
    

sub read_mb_score_cache
{
    my ($folder,$files) = @_;
    my $cachefile_name = get_cachefile_name($folder);
    return if !(-f $cachefile_name);
    
    my $text = getTextFile($cachefile_name);
    if (!$text)
    {
        error("empty cachefile $cachefile_name");
        return;
    }
    my $tree = $xml_reader->XMLin($text);
    if (!$tree)
    {
        error("bad xml from $cachefile_name");
        return;
    }
    if (!$tree->{version} ||
         $tree->{version} ne get_cache_version($files))
    {
        warning(0,0,"files associated with cachefile changed($cachefile_name) - not using cache");
        return;
    }
    
    if (0)
    {
        print "----------------------\n";
        print Dumper($tree);
        print "----------------------\n";
    }
    
    mb_debug_xml(3,"cached_mb_folde_score",$tree);
    display(2,1,"using mb_score_cache($cachefile_name)");
    return $tree;
}    



my $xml_writer = XML::Simple->new(
    NoAttr=> 1,
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
    RootName=>'folder_score',
);
    
    
sub write_mb_score_cache
{
    my ($folder,$files,$tree) = @_;
    my $cachefile_name = get_cachefile_name($folder);
    if (-f $cachefile_name)
    {
        warning(0,0,"overwriting $cachefile_name");
    }
    $tree->{version} = get_cache_version($files);
    #print Dumper($tree);
    
    my $text = $xml_writer->XMLout($tree);
    if (!$text)
    {
        error("could not generate text for tree for $cachefile_name");
        return;
    }
    
    $text = encode('utf8',$text);
    my $rslt = printVarToFile(1,$cachefile_name,$text);
    display(2,0,"write_cache_tree() returning $rslt");
    return $rslt;    
    
}


    
    




1;
