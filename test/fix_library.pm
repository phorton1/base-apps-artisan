#---------------------------------------
# fix_library.pm
#---------------------------------------
use strict;
use warnings;
use artisanUtils;
use Database;
use Library;
# use Library2;
use FreeDB;
use appUA;

display(0,0,"started");

if (0)
{
    Database::db_initialize();
    Library::scanner_thread(1);
}
elsif (0)
{
    my $free_db = FreeDB->new(); #DEBUG=>1);
    my %discs = $free_db->getdiscs(
            "Grateful Dead Built To Last",
            ['title','rest'] );
    my @selecteddiscs = $free_db->ask4discurls(\%discs);
    my %discinfo = $free_db->getdiscinfo($selecteddiscs[0]);
    $free_db->outstd(\%discinfo);
}
else
{
    #my $url = 'http://musicbrainz.org/ws/2/releastquery=Built%20To%last%22we%20will%20rock%20you%22%20AND%20arid:0383dadf-2a4e-4d10-a46a-e9e041da8eb3';
    my $url = 'http://www.freedb.org/~cddb/cddb.cgi?';
    $url .= 'words=Grateful+Dead+Built+To+Last&';
    $url .= 'fields=title&grouping=none&allcats=YES';

    display(0,0,"GET $url");
    my $response = $ua->get($url);
    display(0,0,"response returned ".$response->status_line);
    display(0,0,$response->as_string);
}




# All official freedb servers are running cddbp at port 8880 and http at port 80. The path for http-access is /~cddb/cddb.cgi.


display(0,0,"finished");



#Search: 	All
#Select
#Artist 	Title 	Track 	Rest
#Categories: 	All
#Select
#Blues 	Classical 	Country 	Data
#Folk 	Jazz 	Misc 	New Age
#Reggae 	Rock 	Soundtrack
#Grouping: 	By category

1;
