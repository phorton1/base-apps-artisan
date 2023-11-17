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
use artisanUtils;
use Database;
use DeviceManager;


my $dbg_stream = -1;


sub stream_media
	# $FH will be closed after this call
{
	my ($FH,
        $method,
        $headers,
        $content_id ) = @_;

	display($dbg_stream,0,"stream_media($method,$content_id)");
	for my $key (keys %$headers)
	{
		display($dbg_stream+1,2,"input header($key) = '$headers->{$key}'");
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
	# The content ID comes in as 56789ABC678D.XXX
	# where the first chars are the STREAM_MD5 TRACK_ID and
	# XXX is mp3,m4a,wav, etc based on the tracks file extension.
	# The TRACK_ID is uesd ... the XXX is ignored.

	if ($content_id =~ /^(.*?)\.(\w+)$/)
	{
		my $id = $1;
		my $track = $local_library->getTrack($id);

        if (!$track)
        {
			error("Content($id) not found in media library");
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream' });
			return;
        }
    	LOG(1,"stream_media($id) len=$track->{size} file=$track->{path}");

        # sanity checks

		if (!$track->{path})	# ?!?!
		{
			error("Content($id) has no path");
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream' });
			return;
		}
		my $filename = "$mp3_dir/$track->{path}";
		if (!-f $filename)
		{
			error("Content($id) file not found: $filename");
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream' });
			return;
		}


		my $BUF_SIZE = 3000000;   # $is_wd && $ANDROID ? 16384 : 300000;

		# build headers

		my $to_byte = 0;
		my $is_ranged = 0;
		my $from_byte = 0;
		my $content_len = $track->{size};
		my $statuscode = 200;

		if (defined($headers->{RANGE}) &&
			$headers->{RANGE} =~ /^bytes=(\d+)-(\d*)$/)
		{
			$is_ranged = 1;
			$statuscode = 206;
			$from_byte = int($1) || 0;
			$to_byte = $2 ? int($2) : '';

			display($dbg_stream,1,"Range Request from $from_byte/$content_len to $to_byte");

			$to_byte ||= $content_len - 1;
			$to_byte = $content_len-1 if $to_byte >= $content_len - 1;
			$content_len = $to_byte - $from_byte + 1;
			display($dbg_stream+1,1,"Doing Range request from $from_byte to $to_byte = $content_len bytes");
		}


		# OK, so what seems to work is that if we DONT get a range request,
		# we JUST return the headers, telling them to Accept-Ranges, then
		# they call us back with another ranged request ?!?!
		#
		# On DLNABrowser if I just start returning bytes on the initial
		# request, it fails with "could not print" to device ... and
		# then it calls back with a range request, and sometimes same
		# seemed to happen with WMP.  So far, all devices (WMP, DLNABrowser
		# and the embedded HTML media player) seem to work with this approach.

		# All types in my library 				MP3, WMA, M4A
		# 	First WMA = /albums/Pop/Old/Frank/Frank Sinatra - Harmony
		# 	First M4A = /albums/Rock/Alt/Billy McLaughlin - The Bow and the Arrow
		# All possible types in my library: 	MP3, WMA, M4A, WAV
		#
		# Tested						MP3		WMA		M4A		WAV
		#
		#	localRenderer $mp file		X		X		X		-
		#	localRenderer $mp stream	X		X		X		-
		#	WMP							X		X		X		-
		#	DLNABrowser					X		X		X		-
		#	HTML embedded				X		0		X		-
		#
		#      HTML embedded works the same on:
		#			Win10 Firefox
		#			iPad Chrome
		#			Xiamoi phone Chrome
		#
		# Thus far, the only unuspported playback is WMA in HTML embedded player
		# as I presume WAV would work with all of them. Unfortunately 962 tracks
		# or almost 10% of my library is WMA.


		my @addl_headers = ();

		if (1)
		{
			# push @addl_headers, "Content-Disposition: attachment; filename=\"$track->{titles}\"";
			push @addl_headers, "contentFeatures.dlna.org: ".$track->dlna_content_features();
			push @addl_headers, 'transferMode.dlna.org: Streaming';
			push @addl_headers, "Accept-Ranges: bytes";
			if ($is_ranged)
			{
				push @addl_headers, "Content-Range: bytes $from_byte-$to_byte/$track->{size}";
			}
		}

		#-------------------------------------
		# SEND HEADERS
		#-------------------------------------

		my $http_header = http_header({
			statuscode => $statuscode,
			content_type => $track->mimeType(),
			content_length => $content_len,
			addl_headers => \@addl_headers });
		display($dbg_stream,1,"Sending $method http_header content_len=$content_len is_ranged=$is_ranged");
		display($dbg_stream+1,2,$http_header);

		if ($quitting)
		{
			warning(0,0,"not sending $method header in stream_media() due to quitting");
			return;
		}

		my $ok = print $FH $http_header;
		if (!$ok)
		{
			error("Could not send headers for $method");
			return;
		}
		return if ($method eq 'HEAD' || !$content_len);
			# This is the way I remember it working
		return if !$is_ranged;
			# This is apparently the way it works.
			# See above comment

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
		#    error("No Transfermode for: $item->{path}");
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
