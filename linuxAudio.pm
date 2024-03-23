#-----------------------------------------
# linuxAudio.pm
#-----------------------------------------
# methods for getting and manipulating the output
# sound device on the rPi.

package linuxAudio;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;


my $dbg_la = 0;


my $laudio_devices;


sub getDevices
{
	my ($force) = @_;
	$force ||= 0;
	display($dbg_la,0,"linuxAudio::getDevices($force)");
	if ($force || !$laudio_devices)
	{
		$laudio_devices = shared_clone({});
		my $current = pactl("get-default-sink") || '';
		display($dbg_la,1,"current=$current");

		my $text = pactl("list sinks");
		my @parts = split(/Sink #/s,$text);
		shift @parts;	# remove text before first sink
		for my $part (@parts)
		{
			my $name = $part =~ /Name: (.*)$/m ? $1 : '';

			# this is pretty crude to get a nice name for each device that I know ...
			# if it has an quoted alsa.name, we use that
			# 	and map some known values to things we want to show
			# otherwise we use the description, whatever that happens to be

			my $use_name = $part =~ /alsa\.card_name = "(.*)"$/m ? $1 : '';
			$use_name = $1 if !$use_name && $part =~ /Description: (.*)$/m;
			display($dbg_la,1,"device($use_name) = $name");

			$use_name = "AVJack" if $use_name =~ /bcm2835 Headphones/;
			$use_name = "HDMI-".$1 if $use_name =~ /vc4-hdmi-(\d+)/;
			$use_name = "PiFi" if $use_name =~ /snd_rpi_hifiberry_dacplus/;

			my $active = $name eq $current ? 1 : 0;
			display($dbg_la,2,"final device($active,$use_name) = $name");
			$laudio_devices->{$use_name} = shared_clone({
				name => $name,
				active => $active, });
		}
	}
	return $laudio_devices;
}


sub setDevice
	# returns '' or an error
{
	my ($id) = @_;
	$id ||= '';
	display($dbg_la,0,"linuxAudio::setDevice($id)");
	my $devices = getDevices();
	my $device = $devices->{$id};
	return error("Could not find linux audio device($id)") if !$device;
	display($dbg_la+1,"device=$device->{name} active=$device->{active}");
	my $text = pactl("set-default-sink $device->{name}");
	error($text) if $text;
	return $text;
}


sub pactl
	# runs a "pactl" command and returns the text
{
	my ($cmd) = @_;
	display($dbg_la,0,"pactl($cmd)");
	my $pactl = "pactl -n pi";
	my $xdg = " XDG_RUNTIME_DIR=/run/user/1000";
	my $sudo_cmd = $AS_SERVICE ? "sudo -u '#1000' $xdg" : '';
	my $text = `$sudo_cmd $pactl $cmd`;
	dbgText($text) if $dbg_la < 0;
	$text =~ s/^\s|\s$//g;
	return $text;
}


sub dbgText
{
	my ($text) = @_;
	for my $line (split(/\n/,$text))
	{
		display($dbg_la+1,0,"--> $line");
	}
}



# OLD
#	$cmd = "aplay --list-pcms";
#	$text = `$sudo_cmd  $cmd`;
#	dispAdd(\$result,1,1,$cmd,$text);
#
#	$cmd = "amixer controls";
#	$text = `$sudo_cmd  $cmd`;
#	dispAdd(\$result,1,1,$cmd,$text);
#		# Returns following from ./artisan.pm NO_SERVICE
#		# 		Simple mixer control 'Master',0
#		# 		  Capabilities: pvolume pswitch pswitch-joined
#		# 		  Playback channels: Front Left - Front Right
#		# 		  Limits: Playback 0 - 65536
#		# 		  Mono:
#		# 		  Front Left: Playback 65536 [100%] [on]
#		# 		  Front Right: Playback 65536 [100%] [on]
#		# 		Simple mixer control 'Capture',0
#		# 		  Capabilities: cvolume cswitch cswitch-joined
#		# 		  Capture channels: Front Left - Front Right
#		# 		  Limits: Capture 0 - 65536
#		# 		  Front Left: Capture 0 [0%] [on]
#		# 		  Front Right: Capture 0 [0%] [on]
#		# Returns following from Service
#		#		Simple mixer control 'PCM',0
#		#		  Capabilities: pvolume
#		#		  Playback channels: Front Left - Front Right
#		#		  Limits: Playback 0 - 255
#		#		  Mono:
#		#		  Front Left: Playback 255 [100%] [0.00dB]
#		#		  Front Right: Playback 255 [100%] [0.00dB]
#
#	$cmd = "amixer -D pulse";
#	$text = `$sudo_cmd  $cmd`;
#	dispAdd(\$result,1,1,$cmd,$text);
#
#	$cmd = "$pactl list sinks short";
#	$text = `$sudo_cmd $cmd`;
#	dispAdd(\$result,0,1,$cmd,$text);
#		# 66	alsa_output.platform-bcm2835_audio.stereo-fallback	PipeWire	s16le 2ch 48000Hz	SUSPENDED
#		# 67	alsa_output.platform-fef00700.hdmi.hdmi-stereo	PipeWire	s32le 2ch 48000Hz	SUSPENDED
#		# 77	bluez_output.06_E4_81_E9_0E_07.1	PipeWire	s16le 2ch 48000Hz	SUSPENDED
#
#	my $audio_devices =
#	{
#		AVJack => "alsa_output.platform-bcm2835_audio.stereo-fallback",
#		HDMI => "alsa_output.platform-fef00700.hdmi.hdmi-stereo",
#		BLSB11 => "bluez_output.06_E4_81_E9_0E_07.1",
#	};
#
#	my $long_name = $audio_devices->{$device};
#	$long_name ||= $audio_devices->{HDMI};
#
#	$cmd = "$pactl set-default-sink $long_name";
#	$text = `$sudo_cmd $cmd`;
#	dispAdd(\$result,0,1,$cmd,$text);
#
#	return http_header().$result."\r\n";





1;
