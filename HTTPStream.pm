#!/usr/bin/perl
#---------------------------------------
# HTTPStream.pm
#---------------------------------------

package HTTPStream;
use strict;
use warnings;
use threads;
use threads::shared;
use Fcntl qw(O_RDONLY);
use Pub::HTTP::Response;
use artisanUtils;
use Database;
use DeviceManager;
use MP3Normalize;


use locale;

my $dbg_stream = 0;


sub stream_media
{
	my ($client,
		$request,
		$content_id ) = @_;

	my $method = $request->{method};
	my $headers = $request->{headers};

	display($dbg_stream,0,"stream_media($method,$content_id)");
	for my $key (keys %$headers)
	{
		display($dbg_stream+1,2,"input header($key) = '$headers->{$key}'");
	}

	return http_error($request,"Unknown Streaming HTTP Method: $method")
		if $method !~ /^(HEAD|GET)$/;

	# get information from database
	# The content ID comes in as 56789ABC678D.XXX
	# where the first chars are the STREAM_MD5 TRACK_ID and
	# XXX is mp3,m4a,wav, etc based on the tracks file extension.
	# Only the TRACK_ID is uesd ... the ext is ignored.

	if ($content_id =~ /^(.*?)\.(\w+)$/)
	{
		my ($id,$ext) = ($1,$2);
		my $track = $local_library->getTrack($id);
        return http_error($request,"track($content_id) not found")
			if !$track;

		my $track_size = $track->{size};
    	LOG(1,"stream_media($id) len=$track_size file=$track->{path}");

        # sanity checks

		return http_error($request,"Content($id) has no path")
			if !$track->{path};	# ?!?!

		my $filename = "$mp3_dir/$track->{path}";
		$filename = dbToFilePath($filename);
		my $normalized = getNormalizedFilename($filename);

		if ($normalized)
		{
			$filename = $normalized;
			my @fileinfo = stat($filename);
			$track_size = $fileinfo[7];
			display($dbg_stream,1,"normalized_size = $track_size");
		}

		return http_error($request,"Content($id) file not found: $filename")
			if !-f $filename;

		my $BUF_SIZE = 30000000;   # $is_wd && $ANDROID ? 16384 : 300000;

		# build headers

		my $to_byte = 0;
		my $is_ranged = 0;
		my $from_byte = 0;
		my $size = $track_size;
		my $content_len = $size;
		my $status_code = 200;
		my $status_word = 'OK';

		if (defined($headers->{range}) &&
			$headers->{range} =~ /^bytes=(\d+)-(\d*)$/)
		{
			$is_ranged = 1;
			$status_code = 206;
			$status_word = 'Partial Content';

			$from_byte = int($1) || 0;
			$to_byte = $2 ? int($2) : '';

			display($dbg_stream+1,1,"Range Request from $from_byte/$content_len to $to_byte");

			if (!$to_byte)
			{
				$to_byte = $from_byte + $BUF_SIZE - 1;
				$to_byte = $size-1 if $to_byte >= $size - 1;
			}

			$content_len = $to_byte - $from_byte + 1;
			display($dbg_stream,1,"Doing Range request from $from_byte to $to_byte = $content_len bytes");
		}

		my $is_mpg123 =
			$headers->{'user-agent'} &&
			$headers->{'user-agent'} =~ /^mpg123/ ? 1 : 0;

		# OK, so what seems to work is that if we DONT get a range request,
		# we JUST return the headers, telling them to Accept-Ranges, then
		# they call us back with another ranged request.
		#
		# mpg123 seems to be an exception, in which case we send the bytes,
		# not just the headers

		my $http_headers = "HTTP/1.1 $status_code $status_word\r\n";

		$http_headers .= "Server: Artisan Perl(".getMachineId().")\r\n";
		$http_headers .= "Content-Type: ".artisanMimeType($filename)."\r\n";
		$http_headers .= "Access-Control-Allow-Origin: *\r\n";
			# all my responses are allowed from any referrer
		$http_headers .= "Content-Length: $content_len\r\n";
		$http_headers .= "Date: ".gmtime()." GMT\r\n";
		$http_headers .= "contentFeatures.dlna.org: ".$track->dlna_content_features()."\r\n";
		$http_headers .= "transferMode.dlna.org: Streaming\r\n";
		$http_headers .= "Accept-Ranges: bytes\r\n";
		$http_headers .= "Content-Range: bytes $from_byte-$to_byte/$track_size"
			if $is_ranged;
		$http_headers .= "Cache-Control: no-cache\r\n";
		$http_headers .= "Connection: close\r\n";

		# $http_headers .= "Content-Disposition: attachment; filename=\"$track->{title}\"\r\n";
		# $http_headers .= "Last-Modified: ".gmtime()." GMT\r\n";

		$http_headers .= "\r\n";

		#-------------------------------------
		# SEND HEADERS
		#-------------------------------------

		display($dbg_stream+1,1,"Sending $method http_header content_len=$content_len is_ranged=$is_ranged");
		display($dbg_stream+1,2,$http_headers);

		if ($quitting)
		{
			warning(0,0,"not sending $method header in stream_media() due to quitting");
			return $RESPONSE_HANDLED;
		}

		my $ok = print $client $http_headers;
		if (!$ok)
		{
			error("Could not send headers for $method");
			return $RESPONSE_HANDLED;
		}

		# As described above

		if ($method eq 'HEAD' || !$content_len)
		{
			display($dbg_stream+1,1,"short ending for HEAD request");
			return $RESPONSE_HANDLED ;

		}
		if (!$is_mpg123 && !$is_ranged)
		{
			display($dbg_stream+1,1,"short ending for !is_mpg123 && !is_ranged");
			return $RESPONSE_HANDLED
		}

		#-------------------------------------
		# STREAMING BYTES
		#-------------------------------------

		display($dbg_stream+1,1,"Opening '$filename'");
		if (!sysopen(ITEM, "$filename", O_RDONLY))
		{
			error("Could not open '$filename' for reading");
			return;
		}
		if ($from_byte)
		{
			display($dbg_stream+1,1,"Seeking to $from_byte");
			sysseek(ITEM, $from_byte, 0);
		}

		display($dbg_stream+1,1,"Sending $from_byte-".($from_byte+$content_len-1)."/$size  content_len($content_len) bytes");

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

			display($dbg_stream,2,"---> send ".($from_byte+$at)."-".($from_byte+$at+$bytes-1)."/$size  content($at:$bytes bytes of $content_len)");

			if ($quitting)
			{
				warning(0,0,"not sending $method header in stream_media() due to quitting");
				$rslt = 0;
				last;
			}

			# Had to use SIGPIPE on Android when WDTV Live failed
			# a write and perl bailed ...

			local $SIG{PIPE} = \&onPipeError;
			sub onPipeError
			{
				my ($sig) = @_;
				error("Caught SIG$sig in stream_media()");
			}


			my $ok = print $client $buf;
			if (!$ok)
			{
				error("could not print $bytes bytes to stream!");
			    $rslt = 0;
				last;
			}
			$at += $bytes;
		}

		display($dbg_stream,1,"finished sending stream rslt=".($rslt?"OK":"ERROR"));
		close(ITEM);
	}
	else    # bad content id
	{
		return http_error($request,"ContentID($content_id) not supported for Streaming Items");
	}

	return $RESPONSE_HANDLED;

}   # stream_media()



1;
