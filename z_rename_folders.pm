#---------------------------------------
# new_library.pm
#---------------------------------------
# attempt to re-organize the tree and keep
# the cachefiles.

use strict;
use warnings;
use Utils;
use x_FileManager;

$debug_level = 2;
$warning_level = 9;
$debug_packages = join('|',(
    'utils',
    'new_library',
    'FileManager',
    ));

    
$logfile = "$log_dir/new_library.log";
#unlink $logfile;
#unlink $error_logfile;


sub rename_if
{
    my ($from_dir,$to_dir) = @_;
    if (-d $from_dir)
    {
        return move_dir($from_dir,$to_dir);
    }
}


#---------------------------------------------
# main
#---------------------------------------------

LOG(0,"new_library.pm started");


if (0)
{
    move_dir("/mp3s/Blues","/mp3s/albums/Blues");
    move_dir("/mp3s/Christmas","/mp3s/albums/Christmas");
    move_dir("/mp3s/Classical","/mp3s/albums/Classical");
    move_dir("/mp3s/Compilations","/mp3s/albums/Compilations");
    move_dir("/mp3s/Country","/mp3s/albums/Country");
    move_dir("/mp3s/Dead","/mp3s/albums/Dead");
    move_dir("/mp3s/Favorite","/mp3s/albums/Favorite");
    move_dir("/mp3s/Folk","/mp3s/albums/Folk");
    move_dir("/mp3s/Friends","/mp3s/albums/Friends");
    move_dir("/mp3s/Jazz","/mp3s/albums/Jazz");
    move_dir("/mp3s/NewOrleans","/mp3s/albums/NewOrleans");
    move_dir("/mp3s/Original Soundtrack","/mp3s/albums/Soundtracks");
    move_dir("/mp3s/Other","/mp3s/albums/Other");
    move_dir("/mp3s/Pat Horton Productions","/mp3s/albums/Productions");
    move_dir("/mp3s/R&B","/mp3s/albums/R&B");
    move_dir("/mp3s/Reggae","/mp3s/albums/Reggae");
    move_dir("/mp3s/Rock","/mp3s/albums/Rock");
    move_dir("/mp3s/SanDiegoLocals","/mp3s/albums/SanDiegoLocals");
    move_dir("/mp3s/World","/mp3s/albums/World");
    move_dir("/mp3s/Zydeco","/mp3s/albums/Zydeco");
    
    move_dir("/mp3s/zSingles","/mp3s/singles");
    move_dir("/mp3s/zUnresolved","/mp3s/unresolved");
}


rename_if(
    "/mp3s/albums/Classical/Beethoven- Symphony No. 9 'Choral'",
    "/mp3s/albums/Classical/Beethoven - Symphony No. 9 'Choral'");

rename_if(
    "/mp3s/albums/Rock/Main/Jimmy Buffett -Meet Me in Margaritaville Disc 1",
    "/mp3s/albums/Rock/Main/Jimmy Buffett - Meet Me in Margaritaville Disc 1");
rename_if(
    "/mp3s/albums/Rock/Main/Jimmy Buffett -Meet Me in Margaritaville Disc 2",
    "/mp3s/albums/Rock/Main/Jimmy Buffett - Meet Me in Margaritaville Disc 2");
    
rename_if(
    "/mp3s/singles/Jazz/Old/John Coltrane - Closer Than A Kiss - Crooner C",
    "/mp3s/singles/Jazz/Old/John Coltrane - Closer Than A Kiss");
    
rename_if(
    "/mp3s/singles/Jazz/Old/John Coltrane - The John Coltrane Anthology - Disc 1",
    "/mp3s/singles/Jazz/Old/John Coltrane - The John Coltrane Anthology (Disc 1)" );
    
rename_if(
    "/mp3s/singles/Jazz/Soft/Norah Jones - December - Single of the Week",
    "/mp3s/singles/Jazz/Soft/Norah Jones - Single of the Week");
    
rename_if(
    "/mp3s/singles/R&B/Curtis Mayfield - Superfunk - The Funkiest Album In The World... Ever [ (Disc 1)",
    "/mp3s/singles/R&B/Curtis Mayfield - Superfunk (Disc 1)");
    
rename_if(
    "/mp3s/singles/Rock/Main/Eric Clapton - Run Back to Your Side - Single",
    "/mp3s/singles/Rock/Main/Eric Clapton - Run Back to Your Side");
    
rename_if(
    "/mp3s/singles/Rock/Main/Neil Young - Decade - Disc 2",
    "/mp3s/singles/Rock/Main/Neil Young - Decade (Disc 2)");


rename_if(
    "/mp3s/albums/Jazz/Soft/Harry Connick Jr_ - She",
    "/mp3s/albums/Jazz/Soft/Harry Connick Jr - She");


rename_if(
    "/mp3s/albums/Folk/Abbys mix - Abbys mix",
    "/mp3s/albums/Folk/Various - Abbys Mix");

rename_if(
    "/mp3s/albums/Dead/Vault/Two From The Vault - Disc 1",
    "/mp3s/albums/Dead/Vault/Two From The Vault (Disc 1)");

rename_if(
    "/mp3s/albums/Dead/Vault/Two From The Vault - Disc 2",
    "/mp3s/albums/Dead/Vault/Two From The Vault (Disc 2)");

rename_if(
    "/mp3s/albums/Compilations/Josh's Music - MP3 Explosion",
    "/mp3s/albums/Compilations/Various - MP3 Explosion");

rename_if(
    "/mp3s/albums/Compilations/Josh's Music - Trevor's MP3's",
    "/mp3s/albums/Compilations/Various - Trevor's MP3's");

rename_if(
    "/mp3s/albums/Compilations/Josh's Music - Unclassified",
    "/mp3s/albums/Compilations/Various - Unclassified");

rename_if(
    "/mp3s/albums/Compilations/Teardrops - Classical Italian Love Songs",
    "/mp3s/albums/Compilations/Various - Teardrops _ Classical Italian Love Songs");

rename_if(
    "/mp3s/albums/Other/The Benedictine Monks of Santo Domingo d - Chant",
    "/mp3s/albums/Other/The Benedictine Monks of Santo Domingo - Chant I");

rename_if(
    "/mp3s/albums/Other/The Benedictine Monks of Santo Domingo d - Chant II",
    "/mp3s/albums/Other/The Benedictine Monks of Santo Domingo - Chant II");

rename_if(
    "/mp3s/albums/Productions/Bands/Sweardha Buddha - Sweardha Buddha-1981-Disc1",
    "/mp3s/albums/Productions/Bands/Sweardha Buddha - Sweardha Buddha Live Remix (Disc 1)");

rename_if(
    "/mp3s/albums/Productions/Bands/Sweardha Buddha - Sweardha Buddha-1981-Disc2",
    "/mp3s/albums/Productions/Bands/Sweardha Buddha - Sweardha Buddha Live Remix (Disc 2)");

rename_if(
    "/mp3s/albums/Productions/Bands/Swerdha Buddha - Live 1987 (Disc 1)",
    "/mp3s/albums/Productions/Bands/Swerdha Buddha - Sweardha Buddha Live (Disc 1)");
    
rename_if(
    "/mp3s/albums/Productions/Bands/Swerdha Buddha - Live 1987 (Disc 2)",
    "/mp3s/albums/Productions/Bands/Swerdha Buddha - Sweardha Buddha Live (Disc 2)");

rename_if(
    "/mp3s/albums/Productions/Bands/Swerdha Buddha - Sweardha Buddha Live (Disc 1)",
    "/mp3s/albums/Productions/Bands/Sweardha Buddha - Sweardha Buddha Live (Disc 1)" );

rename_if(
    "/mp3s/albums/Productions/Bands/Swerdha Buddha - Sweardha Buddha Live (Disc 2)",
    "/mp3s/albums/Productions/Bands/Sweardha Buddha - Sweardha Buddha Live (Disc 2)" );

rename_if(
    "/mp3s/albums/Reggae/Bob Marley and he Wailers - Legend",
    "/mp3s/albums/Reggae/Bob Marley and the Wailers - Legend");

rename_if(
    "/mp3s/singles/Reggae/Bob Marley & The Wailers - Uprising",
    "/mp3s/singles/Reggae/Bob Marley and the Wailers - Uprising");
    

rename_if(
    "/mp3s/albums/World/African/Radio Download - Unknown Album",
    "/mp3s/albums/World/African/Various - Radio Download");

rename_if(
    "/mp3s/albums/World/African/Sarafina - Sarafina",
    "/mp3s/albums/World/African/Original Soundtrack - Sarafina");

rename_if(
    "/mp3s/albums/World/Latin/Brazilian Samba - Brazilian Samba",
    "/mp3s/albums/World/Latin/Various - Brazilian Samba");

rename_if(
    "/mp3s/albums/World/Latin/cuban artists - cuba wihout borders",
    "/mp3s/albums/World/Latin/Various - Cuba Without Borders");
    
rename_if(
    "/mp3s/albums/World/Latin/yerba buena - vaiven de mar",
    "/mp3s/albums/World/Latin/Not Yerba Buena - Vaiven de Mar");

rename_if(
    "/mp3s/albums/World/Latin/Not Yerba Buena - Vaiven de Mar",
    "/mp3s/albums/World/Latin/Yerba Buena - Vaiven de Mar");

rename_if(
    "/mp3s/singles/World/African/Radio Download - Martinique Radio",
    "/mp3s/singles/World/African/Various - Martinique Radio Download");
    
LOG(0,"new_library.pm finished");

1;
