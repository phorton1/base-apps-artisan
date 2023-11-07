#------------------------------------
# LOG.pm
#------------------------------------

package HTTPLog;
use strict;
use warnings;
use threads;
use threads::shared;
use XML::Simple;
use artisanUtils;

BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
        log_request
        $http_logfile
        parse_header_line
        $eol_marker
    );
};

# public

our $eol_marker = '##EOL##';
our $http_logfile = "$log_dir/artisan_http.log";
unlink $http_logfile;


my $dbg_this = 3;

sub parse_header_line
{
    my ($hash,$line) = @_;
    $line =~ s/\s*$//;
    my $pos = index($line,':');
    my $lval = lc(substr($line,0,$pos));
    my $rval = substr($line,$pos+1);
    $rval =~ s/^\s*//g;
    $lval =~ s/\s*$//g;
    $lval =~ s/-/_/g;
    $$hash{$lval} = $rval;
}



sub log_request
{
    my ($service,           # SSDP or HTTP
        $ip,                # ip of caller
        $port,              # port of caller
        $pre_data,          # the unadulterated http request (headers)
        $post_xml) = @_;   # the unadulterated post data

    # we don't log anything (M-SEARCH) from
    # InternetGatewayDevice or our own webui

    return if ($pre_data =~ /InternetGatewayDevice/s);
    return if ($pre_data =~ /Server:OS 1.0 UPnP\/1\.0 Realtek\/V1.3/);
    return if ($pre_data =~ /SERVER: Artisan 1\.0/);
    return if ($pre_data =~ /GET \/webui\//s);

    # parse the post data into xml

    my @xml_lines;
    if (defined($post_xml))
    {
		use Data::Dumper;
		$Data::Dumper::Indent = 1;
		my $dump = Dumper($post_xml);
		@xml_lines = split(/\n/,$dump);
		shift @xml_lines;
		pop @xml_lines;
    }

    # parse the first line GET/POST/M-SEARCH/NOTIFY blah

    my @lines = split(/\n/,$pre_data);
    chomp(@lines);
    my $request = shift(@lines);
    $request =~ s/(\s*\*)*\s*HTTP.*$//;
    pop @lines;

    # parse the headers

    my %headers;
    for my $line (@lines)
    {
        $line =~ s/\s*$//;
        parse_header_line(\%headers,$line);
    }

     if (!open(LOGFILE,">>$http_logfile"))
    {
        error("Could not open $http_logfile for writing");
    }
    else
    {
        print LOGFILE today()."\t".now()."\t".
            $service."\t".
            $ip."\t".
            $port."\t".
            $request."\t".
            join($eol_marker,@lines)."\t".
            join($eol_marker,@xml_lines)."\n";

        close LOGFILE;
    }

    my $use_dbg = $dbg_this;
    $use_dbg += 1 if ($service eq 'SSDP' || $request eq 'GET /ServerDesc.xml');

    display($use_dbg,0,"$service ".pad("$ip:$port", 22)." ".$request);
    for my $key (sort(keys(%headers)))
    {
        display($use_dbg+1,1,pad($key.':',15).$headers{$key});
    }
    if (@xml_lines)
    {
        display($use_dbg+1,1,"XML");
        for my $line (@xml_lines)
        {
            display($use_dbg+1,2,$line);
        }
    }
}


1;
