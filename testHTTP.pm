#!/usr/bin/perl
#---------------------------------------
# testHTTP.pm
#---------------------------------------
# Do a timing test to get an url 100 times

use strict;
use warnings;
use threads;
use threads::shared;
use Time::HiRes qw(time);
use LWP::UserAgent;
use Pub::Utils;

my $ua = LWP::UserAgent->new();
$ua->timeout(5);

my $default_url = 'http://10.237.50.101:8091/artisan.html';

my $url = $ARGV[0] || $default_url;

my $start = time();

display(0,0,"getting url=$url");

for (my $i=0; $i<100; $i++)
{
	display(0,1,"get url=$url");
	my $response = $ua->get($url,{TIMEOUT=>3});
    if (!$response->is_success())
    {
        error("Could not get url: $url");
        exit(1);
    }
}

my $elapsed = time() - $start;

display(0,0,"elapsed = ".roundTwo($elapsed)." seconds");


1;
