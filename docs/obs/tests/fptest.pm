#------------------------------------------------------------------
# fptest.pm - a program to test some fingerprinting ideas
#------------------------------------------------------------------
# Starting with two 'same' mp3 files (Beach Boys Surfer Girl) I
# ran 'new' fpcalc.exe and got fingerprints.
#
# We attempt to match them bitwise and give a score


package fptest;
use strict;
use warnings;
use Pub::Utils;

my $USE_MY_FPCALC = 0;


# One integer represents about 1/8 of a second
# We will compare at 10 seconds into fp1
# We will compare from 7 to 13 seconds into fp2

my $one_second = 8 * 32;
my $ten_seconds = 10 * $one_second;
	# range of bits to compare

my $fp1_start = $ten_seconds;
	# starting bit number of static fp1 frame (two seconds in)
my $fp2_start = $ten_seconds - 3 * $one_second;
	# starting bit number of sliding fp2 frame (1 second in)
my $slide_size = 6 * $one_second;


print "one_second = $one_second bits\n";
print "ten_seconds = $ten_seconds bits\n";
print "fp1_start = $fp1_start\n";
print "fp2_start = $fp2_start\n";



sub getFingerprint
{
	my ($filename) = @_;

	my $bin_dir = "\\base\\apps\\artisan\\bin\\";
	my $exe = $USE_MY_FPCALC ? "fpcalc_linux_win.0.09.exe" : "fpcalc_prebuilt_1.5.1.exe";
	my $extra = ''; # $USE_MY_FPCALC ? '-set silence_threshold=4096' : '';
		# none of these make any difference

	my $text = `$bin_dir$exe -raw $extra "$filename"`;
	my @lines = split(/\n/,$text);
	for my $line (@lines)
	{
		if ($line =~ s/^FINGERPRINT=//)
		{
			# print "line($filename)=$line";
			my @nums = split(/,/,$line);
			# print "getFingerprint($filename) found ".scalar(@nums)." integers\n";
			return [@nums];
		}
	}
	error("No fingerprint found for $filename");
}


sub getBit
{
	my ($arr,$bit_addr) = @_;
	my $word_num = int($bit_addr/32);
	my $bit_num = $bit_addr % 32;
	my $word = $arr->[$word_num];
	my $set = $word & (1 << $bit_num) ? 1 : 0;
	return $set;
}




sub countBits
	# compare bits from fp1[$fp1_start]
	# to fp2[$start2] for $compare_size bits
{
	my $count = 0;
	my ($fp1,$fp2,$start2,$compare_len) = @_;
	for (my $i=0; $i<$compare_len; $i++)
	{
		my $b1 = getBit($fp1,$fp1_start + $i);
		my $b2 = getBit($fp2,$start2 + $i);
		$count++ if $b1 == $b2;
	}
	# print "    couuntBits($start2)=$count\n";
	return $count;
}


sub compareFiles
{
	my ($fn1,$fn2) = @_;
	display(0,0,"compareFiles()");
	display(0,1,"fn1=$fn1");
	display(0,1,"fn2=$fn2");

	my $fp1 = getFingerprint($fn1);
	return if !$fp1;
	my $len1 = @$fp1;
	my $bits1 = $len1 * 32;

	my $fp2 = getFingerprint($fn2);
	return if !$fp2;
	my $len2 = @$fp2;
	my $bits2 = $len2 * 32;

	my $min_len = $bits2 > $bits1 ? $bits1 : $bits2;
	my $compare_len = $min_len - $ten_seconds - $fp1_start;
	display(0,1,"len_bits1($len1,$bits1) len_bits2($len2,$bits2)  min_len($min_len) compare_len($compare_len)");

	# do the compares, note new highs

	my $highest = 0;
	my $highest_num = 0;
	for my $start2 ($fp2_start .. $fp2_start + $slide_size)
	{
		my $count = countBits($fp1,$fp2,$start2,$compare_len);
		if ($count > $highest)
		{
			my $offset = $start2 - $fp2_start;
			display(0,1,"highest($offset)=$count");
			$highest = $count;
			$highest_num = $start2;
		}
	}

	my $highest_score = $highest/$compare_len;
	display(0,1,sprintf("highest_score($highest_num) count($highest) %0.3f",$highest_score));
}



#--------------------------------------
# main
#--------------------------------------\

# Exact same file

if (1)
{
	# this example should score 100% at when start2 == fp1_start
	# which is offset(768) with current settings.
	# which it does.

	compareFiles(
		'C:\mp3s\albums\Rock\Main\The Beach Boys - The Greatest Hits Vol 1\03 - Surfer Girl.mp3',
		'C:\mp3s\albums\Rock\Main\The Beach Boys - The Greatest Hits Vol 1\03 - Surfer Girl.mp3' );
}


#---------------------------------------------------
# Same recordings, slightly different
#---------------------------------------------------

if (1)
{
	# highest(736)=24427
	# score =  0.969
	# pretty close to 768 ... probably the same exact recording minus a few defects

	compareFiles(
		'C:\mp3s\albums\Rock\Main\The Beach Boys - The Greatest Hits Vol 1\03 - Surfer Girl.mp3',
		'C:\mp3s\singles\Rock\Main\The Beach Boys - Capitol Years Disc 1\08 - Surfer Girl.mp3');
}

if (1)
{
	# highest(1024)=23128
	# score = 0.917
	# apparently the second file starts almost exactly 1 second after the first

	compareFiles(
		'C:\mp3s\albums\Dead\Albums\Terrapin Station\01 - Estimated Prophet.mp3',
		'C:\mp3s\albums\Dead\Albums\The Arista Years Disc 1\01 - Estimated Prophet.mp3' );
}


if (1)
{
	# highest(192)=22544
	# score = 0.894
	# apparently the second file starts more than 2 seconds before the first
	# which is verified by listening to them ..

	compareFiles(
		'C:\mp3s\albums\Dead\Albums\Reckoning\10 - Cassidy.mp3',
		'C:\mp3s\albums\Dead\Albums\The Arista Years Disc 1\13 - Cassidy [Live].mp3' );
}


if (1)
{
	# highest(864)=24766
	# score = 0.982

	compareFiles(
		'C:\mp3s\albums\Dead\Albums\American Beauty\02 - Friend Of The Devil.mp3',
		'C:\mp3s\albums\Dead\Albums\Skeletons From the Closet\11 - Friend of the Devil - The Grateful Dead.mp3' );
}



#---------------------------------------------------
# Try switching order of compares
#---------------------------------------------------

if (1)
{
	# previous
	# 	highest(736)=24427
	# 	score =  0.969
	# new
	# 	highest(800)=24425
	#   0.969
	#
	# I would expect this to give the exact same results.
	# but it doesn't.

	compareFiles(
		'C:\mp3s\singles\Rock\Main\The Beach Boys - Capitol Years Disc 1\08 - Surfer Girl.mp3',
		'C:\mp3s\albums\Rock\Main\The Beach Boys - The Greatest Hits Vol 1\03 - Surfer Girl.mp3');
}


#---------------------------------------------------
# Two similar, but different live versions of a song
#---------------------------------------------------

if (1)
{
	# highest(576)=13651
	# score = 0.541

	compareFiles(
		'C:\mp3s\albums\Dead\Vault\Dicks Picks Vol 20 (Disc 2)\10 - Sugar Magnolia.mp3',
		'C:\mp3s\albums\Dead\Albums\Hundred Year Hall (disc 2)\04 - Sugar Magnolia.mp3' );
}


# BOTTOM LINE
#
# (a) THESE ARE NOT FINGERPRINTS that can be compared directly
# (b) IT WILL BE TOO HARD and TAKE TOO LONG to try to get this to work as-is
#
# There are issus with normalization (volume levels), starting position (slightly
# different starting points), and probably bit-rate (quality).



1;
