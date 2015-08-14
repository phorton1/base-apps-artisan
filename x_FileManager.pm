#------------------------------------------------------------
# FileManager.pm
#------------------------------------------------------------
# The FileManager exists to allow me to delete, move and
# rename files and directories in /mp3 and keep the fpcalc_info
# cache for the individual media files up to date.
#
# It does NOT keep the databae up to date, as it is very
# quick to rebuild the database from the cached text files.
# Apart from the fpcalc cachefile, all other cachefiles in
# the system are organized by artisan_id or other unique id's,
# and as such do not need to be moved when files/directories
# change. However, at some point we may want routines that
# minimize the size of these cache's to just the active
# things, as over time, we will have extra cache_files for
# things that we are no longer interested in.
#
# For now del_file and del_dir are not implemented and we
# rely on such a cache cleanup to eventually be done. Esp
# since if we then rename a file back to an old filename,
# we might get invalid fpcalc info!

package FileManager;
use strict;
use warnings;
use Utils;
use File::Copy;

my $DOIT = 1;

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
        move_file
        move_dir
        del_file
        del_dir
    );
}


# The api keeps movement of files and directies separate
# even though they devolve in the implementation.
# This is to prevent accidental misuse.


sub move_file
{
    my ($from_name,$to_name) = @_;
    display(2,0,"move_file($from_name,$to_name)");
    return mv_item(0,0,$from_name,$to_name);
}

sub move_dir
{
    my ($from_name,$to_name) = @_;
    display(2,0,"move_dir($from_name,$to_name)");
    return mv_item(0,1,$from_name,$to_name);
}

sub del_file
{
    my ($from_name) = @_;
    display(2,0,"del_file($from_name");
    return mv_item(1,0,$from_name,'');
}

sub del_dir
{
    my ($from_name) = @_;
    display(2,0,"del_dir($from_name");
    return mv_item(1,1,$from_name,'');
}


sub mv_item
{
    my ($delete,$is_dir,$from_name,$to_name) = @_;
    my $what = $is_dir ? 'directory' : 'file';
    
    if (!$from_name || (!$delete && !$to_name))   # can't name a file '0'!
    {
        $from_name ||= '';
        $to_name ||= '';
        error("mv_item($is_dir,$from_name,$to_name) empty parameter");
        return;
    }
    if ($from_name !~ /^$mp3_dir_RE\// ||
        (!$delete && $to_name !~ /^$mp3_dir_RE\//))
    {
        error("mv_item($is_dir,$from_name,$to_name) only works in the /mp3s directory");
        return;
    }
    if ((!$is_dir && !(-f $from_name)) ||
        ($is_dir && !(-d $from_name)))
    {
        error("mv_item($is_dir,$from_name) $what does not exist");
        return;
    }
    if (!$delete && -e $to_name)
    {
        error("mv_item($is_dir,$to_name) destination already exists");
        return;
    }
    
    if ($delete)
    {
        LOG(0,"unlink $from_name");
        if ($DOIT && !unlink($from_name))
        {
            error("mv_item() could not unlink $what($from_name): $!");
            return;
        }
        bump_stat("unlink_$what")
    }
    else
    {
        LOG(0,"move   $from_name");
        LOG(1,"to $to_name");
        
        if ($DOIT && !move($from_name,$to_name))
        {
            error("mv_item($is_dir,$to_name) could not move $what: $!");
            return;
        }
        bump_stat("move_$what")
    }
    
    return rename_cache_files($is_dir,$from_name,$to_name);
        # should never fail
        
    return 1;
}
    
    
    
sub rename_cache_files
{
    my ($is_dir,$from_name,$to_name) = @_;
    my $dir = "$cache_dir/fpcalc_info";
    my $from = make_cache_name($is_dir,$from_name);
    my $to = make_cache_name($is_dir,$to_name);
    display(2,0,"rename_cache_files($is_dir,$from_name,$to_name)");
    display(2,1,"cache_names($from,$to)");
    
    if (!$is_dir)
    {
        if (!$to)
        {
            LOG(0,"remove cache_file($from)");
            if ($DOIT && !unlink("$dir/$from"))
            {
                error("Could not unlink cachefile($dir/$from): $!");
                return;
            }
            bump_stat("cache_files_deleted");
        }
        else
        {
            LOG(0,"move cache_file($from)");
            LOG(1,"to $to");
            if ($DOIT && !move("$dir/$from","$dir/$to"))
            {
                error("Could not move cachefile($dir/$from,$dir/$to): $!");
                return;
            }
            bump_stat("cache_files_renamed");
        }
        return 1;
    }
            
    # do a directory
    
    my $what = $to ? 'rename' : 'delete';
    bump_stat("cache_dirs_$what"."d");
    
    if (!opendir(DIR,$dir))
    {
        error("Could not open cache dir $dir");
        return;
    }
    my %do_rename;
    while (my $entry = readdir(DIR))
    {
        display(4,2,"entry=$entry");
        if (index($entry,$from) == 0)
        {
            my $to_file = ''; 
            my $from_file = "$dir/$entry";
            
            if ($to_name)
            {
                substr($entry,0,length($from)) = $to;
                $to_file = "$dir/$entry";
                if (-e $to_file)
                {
                    error("destination cachefile $to_file already exists!!!!");
                    return;
                }
            }
            
            $do_rename{$from_file} = $to_file;
        }
    }
    closedir DIR;
    
    if (keys(%do_rename))
    {
        display(2,0,"found ".scalar(keys(%do_rename))." items to $what");
        for my $from (sort(keys(%do_rename)))
        {
            my $to = $do_rename{$from};
            LOG(0,"$what  $from");
            LOG(1," to $to") if ($to);
            if ($to)
            {
                if ($DOIT && !move($from,$to))
                {
                    error("Could not move cachefile($from) to $to: $!");
                    return;
                }
                bump_stat("cache_files_renamed");
            }
            else
            {
                if ($DOIT && !unlink($from))
                {
                    error("Could not unlink cachefile($from): $!");
                    return;
                }
                bump_stat("cache_files_deleted");
            }
        }
    }
    else
    {
        warning(0,0,"rename_cache_files directory($from_name,$to_name) did not find any cachefiles to $what");
    }

    return 1;
}



sub make_cache_name
{
    my ($is_dir,$name) = @_;
    return '' if (!$name);
    
    $name =~ s/^$mp3_dir_RE\///;
    $name =~ s/\//\./g;
    if ($is_dir)
    {
        $name .= '.';
    }
    else
    {
        $name .= '.txt';
    }
    return $name;
}


1;
