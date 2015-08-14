#!/usr/bin/perl
#---------------------------------------
# dump_db.pm - dump the database

use strict;
use warnings;
use Utils;
use DBI;
use DBD::SQLite;
use Database;

my $LIMIT_RECS = 0;
    # Set this to a non-zero value to only see the first
    # n records from any given database file during dump_recs()
    

$debug_packages .= "|dump_plex_db";


sub connect_plex
    # All we need in order to use my Database api is a dbh
{
    my ($db_name) = @_;
    my $db_dir = "/Users/Pat/AppData/Local/Plex Media Server/Plug-in Support/Databases";
 
    display(0,1,"connect to plex database $db_name");
    my $dsn = "dbi:SQLite:dbname=$db_dir/$db_name";
    my $dbh = DBI->connect($dsn, '', '');
    if (!$dbh)
    {
        error("Unable to connect to Database: ".$DBI::errstr);
        return;
    }
    display(0,1,"connected");
    return $dbh;
}


sub get_tables
{
    my ($dbh) = @_;
    my $tables = get_records_db($dbh,
        "SELECT name FROM sqlite_master ".
        "WHERE type='table' ".
        "ORDER BY name");
    if (!$tables || !@$tables)
    {
        error("Could not get tables from database");
        return;
    }
    return $tables;
}



sub dump_recs
{
    my ($msg,$recs) = @_;
    my $i = 0;
    for my $rec (@$recs)
    {
        display(0,1,$msg);
        for my $k (sort(keys(%$rec)))
        {
            my $val = defined($$rec{$k}) ? "'".$$rec{$k}."'" : 'undef';
            display(_clip 0,2,pad($k,20). "= $val");
        }
        return if ($LIMIT_RECS && $i++>=$LIMIT_RECS);
    }
    
}


sub get_table_columns
{
    my ($dbh,$table) = @_;
    my $recs = get_records_db($dbh,"pragma table_info($table)");
    if (!$recs || !@$recs)
    {
        error("Could not get_table_columns($table)");
        return;
    }
    # dump_recs('column',$recs);
    return $recs;
}


sub get_field_names
{
    my ($dbh,$table) = @_;
    my $columns = get_table_columns($dbh,$table);
    return if (!$columns);
    my @rslt;
    for my $col (@$columns)
    {
        # DBI, or sqlite, doesn't like these column names
        next if ($col->{name} eq 'index');
        next if ($col->{name} eq 'default');
        next if ($col->{name} eq 'limit');
        next if ($col->{name} eq 'order');
        push @rslt,$col->{name};
    }
    return \@rslt;
}


sub dump_table
{
    my ($dbh,$table) = @_;
    display(0,1,"dump_table($table)");
    
    my $field_names = get_field_names($dbh,$table);
    return if (!$field_names);
    my $select = join(',',@$field_names);
    display(2,2,"select=$select");
    
    my $recs = get_records_db($dbh,"SELECT $select FROM $table");
    if (!$recs)
    {
        error("query failed in dump_table($table)");
        return;
    }
    if (!@$recs)
    {
        display(0,2,"no records found");
        return 1;
    }
    dump_recs('record',$recs);
    return 1;
}



sub dump_database
{
    my ($db_name) = @_;
    display(0,0,'');
    display(0,0,"----------------------------------------------------");
    display(0,0,"DATABASE($db_name)");
    display(0,0,"----------------------------------------------------");
    
    my $dbh = connect_plex($db_name);
    return if !$dbh;
    my $tables = get_tables($dbh);
    return if !$tables;
    display(0,1,"found ".scalar(@$tables)." tables");
    for my $table (@$tables)
    {
        #display(0,3,"table=$table->{name}");
        return if !dump_table($dbh,$table->{name});
    }
    $dbh->disconnect();
    return 1;
}



#----------------------------------
# init
#----------------------------------
# need to use dbg_level==3 for first level of indent
# when calling display from main()

display(0,0,"started");

exit 1 if !dump_database('com.plexapp.plugins.library.db');
#exit 1 if !dump_database('com.plexapp.dlna.db');

display(0,0,"finished.");

1;
