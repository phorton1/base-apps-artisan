#!/usr/bin/perl
#---------------------------------------
# dump_db.pm - dump the database

use strict;
use warnings;
use Utils;
use Database;
$debug_packages .= "|dump_db";

#----------------------------------
# init
#----------------------------------

display(0,0,"started");
Database::db_initialize();
my $dbh = db_connect();

my @tables = (
    #'artists',
    # 'VITEMS',
    #'TRACKS',
     'FOLDERS'
    );

for my $table (@tables)
{
    display(0,2,"$table");
    my $fields = Database::get_table_fields($dbh,$table);
    for my $field (@$fields)
    {
        display(0,3,"field: $field");
    }

    my $query = "SELECT ".join(',',@$fields)." FROM $table";
    my $recs = get_records_db($dbh,$query);
    for my $rec (@$recs)
    {
        display(0,3,"$table record");
        for my $f (@$fields)
        {
            display(0,4,"$f = '".(defined($$rec{$f})?$$rec{$f}:'undef')."'");
        }
    }
}


my $params = ['Special'];
my $recs = get_records_db($dbh,"SELECT * FROM FOLDERS WHERE FULLPATH=? ORDER BY ID",$params);
display(0,0,"Recs = $recs num=".scalar(@$recs));

db_disconnect($dbh);
display(0,0,"finished.");

1;
