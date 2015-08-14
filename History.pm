#---------------------------------------
# History.pm
#---------------------------------------
# Maintains a set of persistent text files that give
# the history of noted changes to media track files.
#
# This history is kept in text files in _data/change_history
# that have the following structure.  Times are stored in
# GMT, but returned local time zone.
#
#      import_date=2015-06-20 11:51:20
#      time_stamp=2007-03-02 22:50:31 found at 2017-03-03 12:31:25
#      time_stamp=2009-05-15 09:36:32 found at 2012-09-08 02:02:02
#      
# The list is kept sorted by the "FOUND AT" times, so the last
# entry in the file gives the current timestamp to use for the
# file.

package History;
use strict;
use warnings;
use Time::Local;
use Utils;


BEGIN
{
    use Exporter qw( import );
	our @EXPORT = qw (

		new_track_change_history
		get_track_change_history
		add_track_change_history_event
		write_track_change_history
		delete_track_change_history
			get_first_history_timestamp
			get_last_history_timestamp
		get_oldest_history_timestamp
		compare_path_diff
    );
};


my $dbg_history = 2;
 

my $history_dir = "$cache_dir/change_history";
mkdir $history_dir if (!-d($history_dir));


#----------------------------------------
# utilities
#----------------------------------------

sub dateToGMTText
{
	my ($t) = @_;
	my $s = appUtils::timeToGMTDateTime($t);
	$s =~ s/^(\d\d\d\d):(\d\d):(\d\d)/$1-$2-$3/;
	return $s;
}


sub dateToLocalText
{
	my ($t) = @_;
	my $unix = localtime($t);
	my $s = appUtils::unixToTimestamp($unix);
	$s =~ s/^(\d\d\d\d):(\d\d):(\d\d)/$1-$2-$3/;
	return  $s;	
}


sub dateFromGMTText
{
	my ($ts) = @_;
	$ts =~ /(\d\d\d\d).(\d\d).(\d\d).(\d\d):(\d\d):(\d\d)/;
    return timegm($6,$5,$4,$3,($2-1),$1);
}


sub dateFromLocalText
{
	my ($ts) = @_;
	$ts =~ /(\d\d\d\d).(\d\d).(\d\d).(\d\d):(\d\d):(\d\d)/;
    return timelocal($6,$5,$4,$3,($2-1),$1);
}


sub compare_path_diff
    # compare two paths and show the shortest
	# string that shows the difference.
{
    my ($s1,$s2) = @_;
	
	my @parts1 = split(/\//,$s1);
	my @parts2 = split(/\//,$s2);
	
	while (@parts1 && @parts2)
	{
		last if ($parts1[0] ne $parts2[0]);
		shift @parts1;
		shift @parts2;
	}
	
	return (join('/',@parts1),join('/',@parts2));
}


#----------------------------------------
# api
#----------------------------------------


sub delete_track_change_history
{
	my ($stream_md5) = @_;
	my $filename = "$history_dir/$stream_md5.txt";
	return 1; #unlink $filename;
}


sub get_first_history_timestamp
{
	my ($history) = @_;
	return $history->[0]->{timestamp};
}


sub get_last_history_timestamp
{
	my ($history) = @_;
	return $history->[@$history-1]->{timestamp};
}


sub get_oldest_history_timestamp
{
	my ($history) = @_;
	my $earliest;
	for my $item (@$history)
	{
		$earliest = $item->{timestamp}
			if (!$earliest || $item->{timestamp} < $earliest);
	}
	return $earliest;
}


sub add_track_change_history_event
{
	my ($history,$time_stamp,$note) = @_;
	$note ||= '';
	my $found_at = time();
	
	display($dbg_history-1,0,"add_track_change_history_event($time_stamp)=".dateToLocalText($time_stamp));
	display($dbg_history+1,1,"found_at=".dateToLocalText($found_at));
			
	push @$history,{found_at=>$found_at, timestamp=>$time_stamp, note=>$note};
}


sub new_track_change_history
{
	my ($stream_md5,$initial_timestamp,$initial_note) = @_;
	$initial_note ||= '';
	display($dbg_history+1,0,"new_track_change_history($stream_md5,$initial_timestamp,$initial_note)");

	my $import_date = time();
	my $found_at_date = $import_date;
	
	# debug in local time

	display($dbg_history+1,1,"  gmt(".
			dateToGMTText($import_date).",".
			dateToGMTText($found_at_date).",".
			dateToGMTText($initial_timestamp).")");
	display($dbg_history+1,1,"local(".
			appUtils::gmtToLocalTime(dateToGMTText($import_date)).",".
			appUtils::gmtToLocalTime(dateToGMTText($found_at_date)).",".
			appUtils::gmtToLocalTime(dateToGMTText($initial_timestamp)).")");
			
	my $filename = "$history_dir/$stream_md5.txt";
	if (-f $filename)
	{
		error("history file ($filename) already exists in new_track_change_history()");
		return;
	}
	
	my $history = [{timestamp=>$initial_timestamp, found_at=>$found_at_date, note=>$initial_note }];
	return $history;

}


sub get_track_change_history
	# returns record with timestamps in numeric format
	# compatible with library (gmt or not) ...
{
	my ($stream_md5) = @_;
	my $filename = "$history_dir/$stream_md5.txt";
	if (!open(IFILE,"<$filename"))
	{
		# warning(0,0,"no history found for stream_md5($stream_md5)");
		return;
	}
	my @lines = <IFILE>;
	close IFILE;
	
	my $history = [];
	
	display($dbg_history,0,"get_track_change_history($stream_md5)");
	
	for my $line (@lines)
	{
		chomp($line);
		$line =~ s/\s+$//;
		if ($line =~ /^(.*)\s+time_stamp=(.*?)(\s+note=(.*))$/)
		{
			my ($fa,$ts,$note) = ($1,$2,$4);
			$note ||= '';
			my $timestamp = dateFromGMTText($ts);
			my $found_at = dateFromGMTText($fa);
			if (!$timestamp)
			{
				error("Could not convert timestamp($ts) for found_at($fa) in $stream_md5.txt");
				return;
			}
			if (!$found_at)
			{
				error("Could not convert found_at($fa) for timestamp($ts) in $stream_md5.txt");
				return;
			}

			display($dbg_history,1,"time_stamp ".dateToLocalText($timestamp)." found at ".dateToLocalText($found_at));
			push @$history,{timestamp=>$timestamp, found_at=>$found_at, note=>$note};
		}
		else
		{
			error("Unknown line: $line in $stream_md5.txt");
			return;
		}
	}	
	if (!@$history)
	{
		error("No history timestamps found in $stream_md5.txt");
		return;
	}
	
	return $history;
}

	
sub write_track_change_history
{
	my ($stream_md5,$history) = @_;
	if (!@$history)
	{
		error("No history timestamps found in write_track_change_history($stream_md5.txt)");
		return;
	}
	
	my $text = '';
	for my $item (@$history)
	{
		$text .= dateToGMTText($item->{found_at}).
		    "  time_stamp=".dateToGMTText($item->{timestamp}).
			($item->{note} ? "  note=$item->{note}" : ''). "\n";
	}
	
	my $filename = "$history_dir/$stream_md5.txt";
	my $rslt = printVarToFile(1,$filename,$text);
	if (!$rslt)
	{
		error("Could not write history to $filename");
	}
	return $rslt;
}




sub fix_timestamps
{
	display(0,0,"fix_timestamps() called");
	if (!opendir(DIR,$history_dir))
	{
		error("Could not opendir $history_dir");
	}
	my @entries = readdir(DIR);
	closedir(DIR);

	my $num = 0;
	for my $entry (@entries)
	{
		if ($entry =~ /^(.*)\.txt$/)
		{
			display(3,1,$entry);
			my $id = $1;
			my $history = get_track_change_history($id);
			exit 1 if !$history;
			exit 1 if !write_track_change_history($id,$history);
			$num++;
		}
	}

	display(0,0,"fix_timestamps() finished $num entries");
}


if (0)
{
	fix_timestamps();
}



1;
