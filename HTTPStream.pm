#!/usr/bin/perl
#---------------------------------------
# HTTPStream.pm
#---------------------------------------
# inspired by: http://www.adp-gmbh.ch/perl/webserver/
# modified from pDNLA server

package HTTPServer;    # continued ...
use strict;
use warnings;
use threads;
use threads::shared;
use Fcntl;
use Socket;
use IO::Select;
use XML::Simple;
use Utils;
use Database;
use Library;
use HTTPXML;


sub stream_media
{
	my ($content_id,
        $method ,
        $headers,
        $FH,
        $model_name,
        $client_ip) = @_;

	display($dbg_stream,0,"stream_media($content_id)");
	for my $key (keys %$headers)
	{
		display($dbg_stream+1,2,"header $key=$headers->{$key}");
	}
	
	if ($method !~ /^(HEAD|GET)$/)
	{
		error("Unknown Streaming HTTP Method: $method");
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream' });
		return;
	}

	# get information from database

	if ($content_id =~ /^([a-z]*\d+)\.(\w+)$/)
	{
		my $id = $1;
		my $dbh = db_connect();
		my $item = get_track($dbh,$id);
		db_disconnect($dbh);
		
        if (!$item)
        {
			error("Content($id) not found in media library");
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream' });
			return;
        }
    	LOG(1,"stream_media($id) len=$item->{SIZE} file=$item->{FULLNAME}");

        # sanity checks

		if (!$item->{FULLNAME})
		{
			error("Content($id) has no FULLNAME");
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream' });
			return;
		}
		my $filename = "$mp3_dir/$item->{FULLNAME}";
		if (!-f $filename)
		{
			error("Content($id) file not found: $filename");
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream' });
			return;
		}

		# vestigial kludge
		
		my $is_wd = $headers->{USER_AGENT} =~ /INTEL_NMPR\/2\.1 DLNADOC\/1\.50 dma\/3\.0 alphanetworks/ ? 1 : 0;
		my $BUF_SIZE = 3000000;   # $is_wd && $ANDROID ? 16384 : 300000;
		
		# build headers

		my $to_byte = 0;
		my $is_ranged = 0;
		my $from_byte = 0;
		my $content_len = $item->{SIZE};
		my $statuscode = 200;

		if (defined($headers->{RANGE}) &&
			$headers->{RANGE} =~ /^bytes=(\d+)-(\d*)$/)
		{
			$is_ranged = 1;
			$statuscode = 206;
			$from_byte = int($1) || 0;
			my $to_byte = $2 ? int($2) : 0;
			
			display($dbg_stream,1,"Range Request from $from_byte/$content_len to $to_byte");

			$to_byte = $item->{SIZE}-1 if (!$to_byte);
			$to_byte = $item->{SIZE}-1 if ($to_byte >= $item->{SIZE});
			$content_len = $to_byte - $from_byte + 1;
			display($dbg_stream+1,1,"Doing Range request from $from_byte to $to_byte = $content_len bytes");
		}
		
		my @additional_header = ();
		# there is already a "Connection: close" header in the
		# defaults in the method http_header()
		# push @additional_header, "Connection: keep-alive";
		
		push @additional_header, "Content-Type: $item->{MIME_TYPE}";
		push @additional_header, "Content-Length: $content_len";
		#push @additional_header, "Content-Disposition: attachment; filename=\"$item->{NAME}\"";
		push @additional_header, "Accept-Ranges: bytes";
        push @additional_header, "contentFeatures.dlna.org: ".HTTPXML::get_dlna_stuff($item);
		push @additional_header, 'transferMode.dlna.org: Streaming';
		push @additional_header, "Content-Range: bytes $from_byte-$to_byte/$item->{SIZE}"
			if ($is_ranged);

		# SEND HEADERS
		
		display($dbg_stream+1,1,"Sending $method headers content_len=$content_len is_ranged=$is_ranged");
		
		if ($quitting)
		{
			warning(0,0,"not sending $method header in stream_media() due to quitting");
		}
		
		my $ok = print $FH http_header({
			'statuscode' => $statuscode,
			'additional_header' => \@additional_header,
			'log' => 'httpstream' });
		if (!$ok)
		{
			error("Could not send headers for $method");
			return;
		}
		return 1 if ($method eq 'HEAD' || !$content_len);

		# if (defined($$CGI{'TRANSFERMODE.DLNA.ORG'}))
		# {
		#	if ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Streaming')
		#	{

		display($dbg_stream+1,1,"Opening '$filename'");
		if (!sysopen(ITEM, "$filename", O_RDONLY))
		{
			error("Could not open '$filename' for reading");
			return;
		}
		if ($from_byte)
		{
			display(2,1,"Seeking from_position=$from_byte");
			sysseek(ITEM, $from_byte, 0);
		}
		display($dbg_stream+1,1,"Loop to send $content_len actual bytes of content");
		
		my $at = 0;
		my $rslt = 1;
		my $buf = undef;
		my $bytes_left = $content_len;
		while ($bytes_left)
		{
			my $bytes = $bytes_left;
			$bytes = $BUF_SIZE if ($bytes > $BUF_SIZE);
			$bytes_left -= $bytes;
			my $got=sysread(ITEM, $buf, $bytes);
			if ($got != $bytes)
			{
				error("Could only read $got of $bytes bytes at $at from $filename");
			    $rslt = 0;
				last;
			}
			if (length($buf) != $bytes)
			{
				error("Huh? buffer mismatch got=$got bytes=$bytes at=$at buffer_len=".length($buf)." in $filename");
			    $rslt = 0;
				last;
			}
			display($dbg_stream+1,2,"Sending $bytes bytes at=$at of=$content_len remain=$bytes_left");
			
			if ($quitting)
			{
				warning(0,0,"not sending $method header in stream_media() due to quitting");
				$rslt = 0;
				last;
			}
			
			# Had to use SIGPIPE on Android when WDTV Live failed
			# a write and perl bailed ...

			$SIG{PIPE} = \&onPipeError;
			sub onPipeError
			{
				my ($sig) = @_;
				error("Caught SIG$sig in stream_media()");
			}
				
			
			my $ok = print $FH $buf;
			if (!$ok)
			{
				error("could not print $bytes bytes to stream!");
			    $rslt = 0;
				last;
			}
			$at += $bytes;
		}
		
		display($dbg_stream+1,1,"finished sending stream rslt=".($rslt?"OK":"ERROR"));
		close(ITEM);
		return $rslt;

		#    }       # STREAM IT
		#    else    # unknown TRANSFERMODE.DLNA.ORG
		#	 {
		#		error("Transfermode $$CGI{'TRANSFERMODE.DLNA.ORG'} not supported");
		#		print $FH http_header({
		#			'statuscode' => 501,
		#			'content_type' => 'text/plain' });
		#	 }
		# }
		# else # TRANSFERMODE.DLNA.ORG is not set
		# {
		#    error("No Transfermode for: $item->{FULLNAME}");
		#	 print $FH http_header({
		#		'statuscode' => 200,
		#		'additional_header' => \@additional_header,
		#		'log' => 'httpstream' });
		# }
	}
	else    # bad content id
	{
		error("ContentID($content_id) not supported for Streaming Items");
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream'});
	}

}   # stream_media()


1;
