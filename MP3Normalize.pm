#!/usr/bin/perl
#---------------------------------------
# MP3Normalize.pm
#---------------------------------------
# getNormalizedFilename($filename)
#	called by HTTPStream.pm with the path to a stream
#   (on which fix1252String() has already been called).
#	and if it exists in the 'normlized' subdirectory, returns
#   the '_normalized' filename. Otherwise it returns what was
#   passed in.
#
# checkNormalization($dir,\@files);
# 	Creates or uses '_normalized' subdirectories in folders.
#   If there is a 'normlize.txt' file, it contains parameters
#   and if it is later than normalized files, they will be
#   renormalized.
#
# if there is a '_normalized' subdirectory and no normalize.txt
#   file, the default parameters will be used.
#
# This is a slow process and should be used sparingly.
# Later additions could include "remastring" filters, etc.
#
# The directory starts with a underscore so that it will not be
# scanned by the database.


package MP3Normalize;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;

my $dbg_norm = 0;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		getNormalizedFilename
		checkNormalization
	);
}


my $DEFAULT_COMPRESS_RATIO = 7;		# ratio
my $DEFAULT_COMPRESS_ATTACK = 250;		# ms
my $DEFAULT_COMPRESS_RELEASE = 1200;	# ms
	# compressor settings
my $DEFAULT_LOUDNESS_TARGET = -10;		# db
    # Range is -70.0 - -5.0. Default value is -24.0.
my $DEFAULT_LOUDNESS_RANGE = 8;			# db
	# Range is 1.0 - 50.0. Default value is 7.0.
my $DEFAULT_TRUE_PEAK = -0.5;			#db
	# Range is -9.0 - +0.0. Default value is -2.0.


my @param_fields = qw(
	compress_ratio
	compress_attack
	compress_release
	loudness_target
	loudness_range
	true_peak );



sub getNormalizedFilename
{
	my ($path) = @_;
	my @parts = split(/\//,$path);
	my $leaf = pop(@parts);
	my $base_path = join('/',@parts);
	my $normalized_name = "$base_path/_normalized/$leaf";
	if (-f $normalized_name)
	{
		display($dbg_norm,0,"Found Normalized $normalized_name");
		return $normalized_name;
	}
	return '';
}





sub checkNormalization
{
	my ($dir,$files) = @_;
	my $params_file = "$dir/normalize.txt";
	my $normal_dir = "$dir/_normalized";

	my $params_exist = -f $params_file ? 1 : 0;
	my $dir_exists = -d $normal_dir ? 1 : 0;
	# display(0,0,'dir($normal_dir) exists="$dir_exits");

	return if !$params_exist && !$dir_exists;

	my $params = {
		compress_ratio => $DEFAULT_COMPRESS_RATIO,
		compress_attack => $DEFAULT_COMPRESS_ATTACK,
		compress_release => $DEFAULT_COMPRESS_RELEASE,
		loudness_target => $DEFAULT_LOUDNESS_TARGET,
		loudness_range => $DEFAULT_LOUDNESS_RANGE,
		true_peak => $DEFAULT_TRUE_PEAK,
	};

	getNormalizationParams($params_file,$params) if $params_exist;

	for my $file (@$files)
	{
		last if !normalizeOne($dir,$normal_dir,$file,$params);
	}
}



sub getNormalizationParams
{
	my ($params_file,$params) = @_;
	display($dbg_norm+1,0,"NORMALIZATION PARAMS $params_file");
	$params->{ts} = getTimestamp($params_file);
	display($dbg_norm+1,1,"ts = $params->{ts}");
	my @lines = getTextLines($params_file);
	for my $line (@lines)
	{
		for my $field (@param_fields)
		{
			if ($line =~ /^$field\s*=\s*(.*)\s*$/i)
			{
				$params->{$field} = $1;
				display($dbg_norm+1,1,"$field = $params->{$field}");
				last;
			}
		}
	}
}



sub doFFMpegCommand
{
	my ($num,$infile,$ofile,$values,$params,$fields) = @_;
	display(0,1,"($num) calling ffmpeg($params)");

	my $use_ofile = $ofile ? "\"$ofile\"" : is_win() ?
		'-f null /dev/NUL' :
		'-f null /def/null' ;
	my $command = "ffmpeg -i \"$infile\" $params $use_ofile 2>&1";
	# print "command($command)\n";

	my $text = `$command` || '';
	my @lines = split(/\n/,$text);
	# print "text=$text" if $num == 4;

	if ($ofile && !-f $ofile)
	{
		error("Could not create $ofile\n$text");
		return 0;
	}

	for my $line (@lines)
	{
		if ($line =~ /^error/i)
		{
			error("$line in ffmpeg($num) $params: $text");
			unlink $ofile if $ofile;
			return 0;
		}

		for my $key (keys %$fields)
		{
			my $re = $fields->{$key};
			if ($line =~ /$re/)
			{
				$values->{$key} = $1;
				$values->{$key} =~ s/^s+|\s+$//g;
			}
		}
	}

	for my $key (keys %$fields)
	{
		if ($values->{$key})
		{
			display(0,2,"$key($values->{$key})");
		}
		else
		{
			error("Could not get $key ffmpeg($num) $params: $text");
			unlink $ofile if $ofile;
			return 0;
		}
	}

	return 1;
}





sub normalizeOne
{
	my ($dir,$normal_dir,$file,$params) = @_;

	my $ifile = fix1252String("$dir/$file");
	my $ofile = fix1252String("$normal_dir/$file");
	my $tmpfile = fix1252String("$normal_dir/temp_$file");
	unlink $tmpfile;

	if (-f $ofile)
	{
		return if !$params->{ts};
		my $ts = getTimestamp($ofile);
		return if $ts ge $params->{ts};
		unlink $ofile;
	}

	display_hash($dbg_norm,0,"NORMALIZING $ifile",$params);
	my_mkdir($normal_dir);
	my $values = {};

	# (1) Get the kbps and mean_volume


	if (0)	 # OLD_WAY
	{
		# ffmpeg -i test.mp3 -af "volumedetect" -vn -sn -dn -f null /dev/NUL
		#	Duration: 00:16:39.37, start: 0.000000, bitrate: 320 kb/s
		#	[Parsed_volumedetect_0 @ 000001fc65bc7380] mean_volume: -28.0 dB

		return if !doFFMpegCommand(1, $ifile, '', $values,
			'-af "volumedetect" -vn -sn -dn', {
			kbps => qr/Duration:.*bitrate: (\d+) kb/,
			use_threshold => qr/\[Parsed_volumedetect.*mean_volume: (.*) dB/,
		});
	}
	else	# NEW WAY
	{
		my $cmd_params =
			"-af loudnorm=".
			"I=$params->{loudness_target}".
			":TP=$params->{true_peak}".
			":LRA=$params->{loudness_range}".
			":print_format=summary";

		return if !doFFMpegCommand(1, $ifile, '', $values, $cmd_params, {
			kbps => qr/Duration:.*bitrate: (\d+) kb/,
			use_threshold 	=> qr/Input Threshold:\s*(.*)\s*LUFS/,
		});
	}
	$values->{kbps} .= 'k';
	$values->{use_threshold} .= 'dB';


	# (2) Run the compressor to $tmpfile
	#
	# ffmpeg -i test.mp3  -b:a 320k -af acompressor=threshold=-28.0dB:ratio=9:attack=200:release=1000test2.mp3
	# 	[out#0/mp3 @ 0000028114edda80] video:0kB audio:15616kB subtitle:0kB other streams:0kB global headers:0kB muxing overhead: 0.004259%
	# 	size=   15616kB time=00:16:39.34 bitrate= 128.0kbits/s speed=50.5x

	my $cmd_params =
		"-b:a $values->{kbps} ".
		"-af acompressor=threshold=$values->{use_threshold}".
		":ratio=$params->{compress_ratio}".
		":attack=$params->{compress_attack}".
		":release=$params->{compress_release}";

	return if !doFFMpegCommand(2, $ifile, $tmpfile, $values, $cmd_params, {
		size => qr/size=\s*(\d+)/,
	});


	# (3) Get new parameters from $tmpfile
	#
	# ffmpeg -i test2.mp3 -af loudnorm=I=-16:TP=-1.5:LRA=11:print_format=summary -f null /dev/NUL
	#	[Parsed_loudnorm_0 @ 000001fdb5f5e600]
	#	Input Integrated:    -30.2 LUFS
	#	Input True Peak:     -10.8 dBTP
	#	Input LRA:            18.5 LU
	#	Input Threshold:     -41.6 LUFS

	$cmd_params = "-b:a $values->{kbps} ".
		"-af loudnorm=".
		"I=$params->{loudness_target}".
		":TP=$params->{true_peak}".
		":LRA=$params->{loudness_range}".
		":print_format=summary";

	return if !doFFMpegCommand(3, $tmpfile, '', $values, $cmd_params, {
		input_integrated 	=> qr/Input Integrated:\s*(.*)\s*LUFS/,
		input_true_peak 	=> qr/Input True Peak:\s*(.*)\s*dBTP/,
		input_lra 			=> qr/Input LRA:\s*(.*)\s*LU$/,
		input_threshold 	=> qr/Input Threshold:\s*(.*)\s*LUFS/,
	});


	# (4) Renormalize the volume levels
	#
	# ffmpeg -i test2.mp3 -b:a 320k  -af loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=-30.2:measured_TP=-10.8:measured_LRA=18.5:measured_thresh=-41.6:offset=-0.7:linear=true:print_format=summary test3.mp3
	#	[out#0/mp3 @ 000002a48a435fc0] video:0kB audio:39039kB subtitle:0kB other streams:0kB global headers:0kB muxing overhead: 0.003585%
	#	size=   39041kB time=00:16:39.39 bitrate= 320.0kbits/s speed=20.3x
	#	[Parsed_loudnorm_0 @ 000002a488c573c0]
	#	Input Integrated:    -30.2 LUFS
	#	Input True Peak:     -10.8 dBTP
	#	Input LRA:            18.5 LU
	#	Input Threshold:     -41.6 LUFS
	#
	#	Output Integrated:   -14.7 LUFS
	#	Output True Peak:     -1.5 dBTP
	#	Output LRA:           12.3 LU
	#	Output Threshold:    -25.6 LUFS
	#
	#	Normalization Type:   Dynamic
	#	Target Offset:        -1.3 LU
	#

	my $cmd_params2 =
		":measured_I=$values->{input_integrated}".
		":measured_TP=$values->{input_true_peak}".
		":measured_LRA=$values->{input_lra}".
		":measured_thresh=$values->{input_threshold}".
		":offset=-0.7:linear=true";

	return if !doFFMpegCommand(4, $tmpfile, $ofile, $values, $cmd_params.$cmd_params2, {
		output_integrated 	=> qr/Output Integrated:\s*(.*)\s*LUFS/,
		output_true_peak 	=> qr/Output True Peak:\s*(.*)\s*dBTP/,
		output_lra 			=> qr/Output LRA:\s*(.*)\s*LU$/,
		output_threshold 	=> qr/Output Threshold:\s*(.*)\s*LUFS/,
	});

	unlink $tmpfile;
	display($dbg_norm,0,"done NORMALIZING $ofile");

}



1;
