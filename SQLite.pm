#--------------------------------------------------
# SQLite.pm
#--------------------------------------------------
# Generic handled based interface to SQLite database(s)

package SQLite;
use strict;
use warnings;
use DBI;
use Utils;

my $dbg_sqlite = 2;



BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		
        sqlite_connect
        sqlite_disconnect

        get_records_db
        get_record_db
        db_do
    );
};



sub sqlite_connect
{
	my ($db_name, $user, $password) = @_;
	
	# 2015-06-28 The sqlite_unicode flag is important to
	# writing a database that can be read by android sdk,
	# and did not seem to negatively alter the windows version.
	
	$password ||= '';
    display($dbg_sqlite,0,"db_connect");
	my $dsn = "dbi:SQLite:dbname=$db_name";
	my $dbh = DBI->connect($dsn,$user,$password,{sqlite_unicode => 1,});
    if (!$dbh)
    {
        error("Unable to connect to Database: ".$DBI::errstr);
        exit 1;
	}
	return $dbh;
}


sub sqlite_disconnect
{
	my ($dbh) = @_;
    display($dbg_sqlite,0,"db_disconnect");
    if (!$dbh->disconnect())
    {
        error("Unable to disconnect from database: ".$DBI::errstr);
        exit 1;
    }
}



sub get_records_db
{
    my ($dbh,$query,$params) = @_;
    $params = [] if (!defined($params));

    display($dbg_sqlite,0,"get_records_db($query)".(@$params?" params=".join(',',@$params):''));

    # not needed
	# implement SELECT * FROM table
    #
	#if ($query =~ s/SELECT\s+\*\s+FROM\s+(\S+)(\s|$)/###HERE###/i)
    #{
    #    my $table = $1;
    #    my $fields = join(',',@{get_table_fields($dbh,$table)});
    #    $query =~ s/###HERE###/SELECT $fields FROM $table /;
    #}
	
	
	my $sth = $dbh->prepare($query);
    if (!$sth)
    {
        error("Cannot prepare database query($query): $DBI::errstr");
        return; # [];
    }
	if (!$sth->execute(@$params))
    {
        error("Cannot execute database query($query): $DBI::errstr");
        return; #  [];
    }

    my @recs;
	while (my $data = $sth->fetchrow_hashref())
	{
		push(@recs, $data);
    }
    if ($DBI::err)
    {
        error("Data fetching query($query): $DBI::errstr");
        return;
    }

    display($dbg_sqlite,1,"get_records_db() found ".scalar(@recs)." records");
    return \@recs;
}


sub get_record_db
{
    my ($dbh,$query,$params) = @_;
    display($dbg_sqlite,0,"get_record_db()");
    my $recs = get_records_db($dbh,$query,$params);
    return $$recs[0] if ($recs && @$recs);
    return undef;
}


sub db_do
    # general call to the database
    # used for insert, update, and delete
{
	my ($dbh,$query,$params) = @_;

	# display
	
	my $param_str = 'no params';
	if (defined($params) && @$params)
	{
		for my $p (@$params)
		{
			$p = 'undef' if (!defined($p));
			$param_str .= ',' if ($param_str);
			$param_str .= $p;
		}
	}
    display($dbg_sqlite,0,"db_do($query) $param_str");

    $params = [] if (!defined($params));
	my $sth = $dbh->prepare($query);
    if (!$sth)
    {
        error("Cannot prepare insert query($query): $DBI::errstr");
        return;
    }
    if (!$sth->execute(@$params))
    {
        error("Cannot execute insert query($query): $DBI::errstr)");
        return;
    }
    return 1;
}


1;
