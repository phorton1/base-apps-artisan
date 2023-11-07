#---------------------------------------
# build_initial_artists.pm
#---------------------------------------
use strict;
use warnings;
use artisanUtils;
use Database;
use File::Copy;
use MP3Info;
use MediaFile;
use Library;


$debug_level = 0;
$warning_level = 0;
$debug_packages = join('|',(
    'utils',    # needed to see stats
    'build_initial_artists',
    'mediafile',
    'mp3.*',
    ));

my $exclude_re = '\/_';

$logfile = "$log_dir/build_initial_artists.log";
unlink $logfile;
unlink $error_logfile;

my %artisan_ids;

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

    display(1,0,$dir);

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
# functions
#---------------------------------------------


sub check_media_file
{
    my ($part,$path) = @_;
    display(1,0,"$part - $path");

    my $info = MediaFile->new($path);
    if (!$info)
    {
        error("Could not create MediaFile($path)");
        return;
    }

    my $errors = $info->get_errors();
    if ($errors)
    {
        display(0,0,"check_media_file $path");
        for my $e (@$errors)
        {
            display(0,1,severity_to_str($$e[0])." - ".$$e[1]);
        }
    }

    if ($info->get_highest_error() >= $ERROR_HARD)
    {
        error("There was a hard error in MediaFile($path)");
        bump_stat("HARD ERRORS");
        #return;
    }

    elsif (!$info->{artisan_id})
    {
        error("No artisan_id for $path");
        bump_stat("NO ARTISAN ID");
        #return 1;
    }

    else
    {
        my $exists = $artisan_ids{$info->{artisan_id}};
        if ($exists)
        {
            bump_stat("DUPLICATE ARTISAN ID");
            error("DUPLICATE ARTISAN_ID $info->{artisan_id}");
            error("    prev = $exists");
            error("    this = $path");
        }
        $artisan_ids{$info->{artisan_id}} = $path;
    }

    return 1;
}


#---------------------------------------------
# Analyze DB
#---------------------------------------------

my %artists;

sub fixName
{
    my ($name) = @_;
    if (0)
    {
        $name =~ s/[&,:;+\-]/ , /g;
        $name =~ s/[^, 0-9A-Za-z]/ /g;
        while ($name =~ s/\s\s/ /g) {};
    }
    return CapFirst($name);
}


sub get_artist
{
    my ($artist) = @_;
    $artist ||= '';
    return undef if !$artist;
    display(1,0,"artist: $artist");

    $artist = fixName($artist);
    my $rec = $artists{$artist};
    if (!$rec)
    {
        $artists{$artist} = $rec = {artist=>0, album_artist=>0};
        $$rec{name} = $artist;
    }
    display(1,1,"get_artist returning $rec");
    return $rec;
}


sub bump
{
    my ($a,$what,$inc) = @_;
    return if (!$a || !$what);
    $inc = 1 if (!defined($inc));
    $$a{$what} ||= 0;
    $$a{$what} += $inc;
}


sub addstr
{
    my ($a,$key,$str) = @_;
    return if (!$a || !$key || !$str);
    display(5,0,"addstr($$a{name},$key,$str)");
    if (!$a->{$key} || $a->{$key} !~ /(^|,)$str(,|$)/)
    {
        $a->{$key} ||= '';
        $a->{$key} .= ' | ' if ($a->{$key});
        $a->{$key} .= $str;
    }
}


sub analyze_db
{
    my $dbh = db_connect();
    my $recs = get_records_db($dbh,"SELECT * FROM TRACKS ORDER BY FULLNAME");
    for my $rec (@$recs)
    {
        $rec->{TITLE} = $rec->{NAME} if (!$rec->{TITLE});
        bump(get_artist($rec->{ARTIST}),'artist');
        bump(get_artist($rec->{ALBUM_ARTIST}),'album_artist');
    }

    display(0,0,"found ".scalar(keys(%artists))." artists");

    # n x n compare of artists

    my $exclude_common_names = 'Air|Johnny|War|King|Train|Aventura|Robert|Rodgers|Unknown|Rem|Seal|Beck';

    display(0,0,"--------------------- artists -----------------------");
    for my $j (sort(keys(%artists)))
    {
        next if (!$j);
        my $aj = get_artist($j);
        my $str = pad($aj->{artist} || '',4).pad($aj->{album_artist} || '',4);
        display(0,1,pad($str,12)."$j");
        next if $j =~ /^($exclude_common_names)$/;

        for my $k (sort(keys(%artists)))
        {
            next if (!$k);
            next if ($j eq $k);
            if (index($k,$j) >= 0)
            {
                addstr(get_artist($j),'includes',$k);
                addstr(get_artist($k),'included',$j);
            }
        }
    }

    display(0,0,"--------------------- included -----------------------");
    for my $j (sort(keys(%artists)))
    {
        my $rec = $artists{$j};
        next if !$rec->{included};
        display(0,1,pad($j,60)."<= ".$rec->{included});
    }

    display(0,0,"--------------------- includes -----------------------");
    for my $j (sort(keys(%artists)))
    {
        my $rec = $artists{$j};
        next if !$rec->{includes};
        display(0,1,pad($j,60)."=> ".$rec->{includes});
    }

    display(0,0,"--------------------- top 100 -----------------------");

    my $count = 100;
    for my $rec (sort {$b->{artist} <=> $a->{artist}} values(%artists))
    {
        my $str = pad($rec->{artist} || '',4).pad($rec->{album_artist} || '',4);
        display(0,1,pad($str,12)."$rec->{name}");
        last if ($count-- <= 0);
    }

    db_disconnect($dbh);
}



#---------------------------------------------
# main
#---------------------------------------------

LOG(0,"fix_library.pm started");

if (0)
{
    my $scan_dir = "/mp3s";
    do_to_all($scan_dir,'artisan',\&check_media_file);
}
elsif (0)
{
    db_initialize();
    Library::scanner_thread(1);
}
elsif (1)
{
    db_initialize();
    analyze_db();
}

dump_stats('');
LOG(0,"fix_library.pm finished");

1;
