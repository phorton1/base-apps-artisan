#!/usr/bin/perl
#---------------------------------------
# types
#
#     folder = arbitrary container
#     genre  = folder that contains albums
#     album  = folder that contains media
#     track  = media


package item;
    # folders are arbitrary containers
    # not necessarily disk folders ..
use strict;
use warnings;
BEGIN { push @INC,'../'; }
use Utils;


our %items;

my $audio_file_re = '\.(mp3|wma|wav|m4a|m4p|mk4|aif|aif)$';
my $next_id = '000000';


sub new
{
    my ($class,$type,$parent,$title,$path) = @_;
    my $this = {};
    bless $this,$class;
    $this->{id} = $next_id++,
    $this->{type} = $type;
    $this->{title} = $title;
    $this->{children} = {};
    $this->{parent} = $parent;

    if ($parent)
    {
        $parent->{children}->{$this->{id}} = $this;
        if ($type eq 'track')
        {
            $parent->{type} = 'album';
            $parent->{parent}->{type} = 'genre'
                if ($parent->{parent});
        }
    }

    $items{$this->{id}} = $this;
    return $this;
}


sub scan_dir
{
    my ($dir,$parent) = @_;

    my @files;
    my @subdirs;
    display(0,0,"scan_dir($dir)");

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
        elsif ($entry =~ /$audio_file_re/i)
        {
            item->new('track',$parent,$entry,$filename);
            push @files,$entry;
        }
    }
    closedir DIR;
    if (@files && @subdirs)
    {
        error("directory($dir) has both files and subdirectories!");
    }
    for my $subdir (sort(@subdirs))
    {
        my $item = item->new('folder',$parent,$subdir,"$dir/$subdir");
        scan_dir("$dir/$subdir",$item);
    }
}


#------------------------------------------
# main for testing
#------------------------------------------

my $root = item->new('root',undef,'root','');
my $folders = item->new('folder',$root,'Folders','');
my $categories = item->new('folder',$root,'Categories','');
my $genres = item->new('folder',$root,'Genres','');
my $root_dir = "/mp3s/dead";

scan_dir($root_dir,$folders);

for my $id (sort(keys(%items)))
{
    my $item = $items{$id};
    my $type = $item->{type};
    my $level =
        $type eq 'track' ? 3 :
        $type eq 'album' ? 2 :
        $type eq 'genre' ? 1 : 0;

    display(0,0,pad($id,6+($level*4))." $item->{type} $item->{title}");
}


1;
