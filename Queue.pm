#!/usr/bin/perl
#---------------------------------------
# Queue.pm
#---------------------------------------
# Enqueing folders naturally filters out
# children by keeping a hash of all folders
# in the request and working in a depth first
# manner.
#
# QUEUE STARTING
#
# We *likely* need to differentiate between the
# queue being modified, and the currently playing
# item changing.
#
# The version changing is a signal to the HTML Renderer
# and the webUI in general that it needs to reload the
# queue into Javascript memory.
#
# That is different than the notion that the renderer
# should stop and start immediately playing the new head
# of the queue, which only happens on the first Add,
# but on any subsquent Play commands.
#
# Thus there is a state variable 'needs_start', on the
# queue that is cleared by the renderer.

package Queue;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use DeviceManager;


my $dbg_queue = -1;


my $master_queue:shared = shared_clone({});
	# by renderer id
	# a list of tracks with library_uuid added to each



#--------------------------------------------------
# main API
#--------------------------------------------------

sub getQueue
{
	my ($renderer_uuid) = @_;
	my $queue = $master_queue->{$renderer_uuid};
	display($dbg_queue+2,0,"found queue($renderer_uuid}") if $queue;
	$queue ||= Queue->new($renderer_uuid);
	return $queue;
}

sub new
{
	my ($class,$renderer_uuid) = @_;
	display($dbg_queue,0,"new Queue($renderer_uuid}");
	my $this = shared_clone({
		version => 0,
		renderer_uuid => $renderer_uuid });
	bless $this,$class;
	$this->clear();
	$master_queue->{$renderer_uuid} = $this;
	return $this;
}


sub getNextTrack()
{
	my ($this) = @_;
	display($dbg_queue,0,"getNextTrack($this->{started},$this->{num_tracks},$this->{track_index}");

	my $track = '';
	my $tracks = $this->{tracks};
	if ($this->{track_index} < $this->{num_tracks})
	{
		$this->{track_index}++ if $this->{started};
		$track = $tracks->[$this->{track_index}];
	}
	$this->{started} = 1;
	display($dbg_queue,0,"getNextTrack($this->{started},$this->{num_tracks},$this->{track_index}) returning track=".($track ? $track->{title} : 'undef'));
	return $track;
}



sub queueCommand
	# returns an error on failure, blank on success
	# folders and tracks commands are disjoint and separate
{
	my ($command,$params) = @_;
	display_hash($dbg_queue,0,"queueCommand($command)",$params);

	my $u_version = $params->{version};
	# return error("No version in queue/$command call") if !$u_version;
	my $r_uuid = $params->{renderer_uuid};
	return error("No renderer_uuid in queue/$command call") if !$r_uuid;
	my $renderer = findDevice($DEVICE_TYPE_RENDERER,$r_uuid);
	return error("Could not find renderer $r_uuid") if !$renderer;

	my $queue = getQueue($r_uuid);
	if ($command eq 'add' || $command eq 'play')
	{
		return enqueue($command,$params,$queue);
	}
	elsif ($command eq 'next' || $command eq 'prev')
	{
		my $inc = $command eq 'next' ? 1 : -1;
		$queue->incTrack($inc);
	}
	elsif ($command eq 'next_album' || $command eq 'prev_album')
	{
		my $inc = $command eq 'next_album' ? 1 : -1;
		$queue->incAlbum($inc);
	}
	else
	{
		return errror("unknown queue command '$command'");
	}
	return '';
}


#-----------------------------------------------------
# enqueuing
#-----------------------------------------------------

sub enqueue
	# returns an error on failure, blank on success
	# folders and tracks commands are disjoint and separate
{
	my ($command,$params,$queue) = @_;
	display($dbg_queue,0,"enqueue($command)");
	my $l_uuid = $params->{library_uuid};
	return error("No library_uuid in eneueue($command)")
		if !$l_uuid;
	my $library = findDevice($DEVICE_TYPE_LIBRARY,$l_uuid);
	return error("Could not find library $l_uuid in eneueue($command)")
		if !$library;

	# gather the tracks to be added

	my $tracks = [];

	my $folders = $params->{folders};
	if ($folders)
	{
		my @ids = split(/,/,$params->{folders});
		$tracks = enqueueFolders($library,\@ids);
		return if !$tracks;
	}
	else	# $params->{tracks} must be valid
	{
		my @ids = split(/,/,$params->{tracks});
		for my $id (@ids)
		{
			my $track = $library->getTrack($id);
			return error("Could not find track($id)") if !$track;
			push @$tracks,$track;
		}
	}

	# add the tracks to the queue
	# if 'play' we insert them at the current track index, and if so
	# they will will have a native position starting at 0, and will
	# take over the pl_idx of the item at that position.

	my $num_tracks = scalar(@$tracks);

	my $q_tracks = $queue->{tracks};
	my $q_index = $queue->{track_index};
	my $q_num = @$q_tracks;



	display($dbg_queue,0,"$command $num_tracks tracks track_index($q_index)");

	if ($command eq 'play' && $q_num)
	{
		# splice not implemented for shared arrays
		# so first we work from the end of the array backwards
		# - bumping all the positions
		# - manually move the items from q_index to q_index+num_tracks
		#   bumping their pl_idx's as we go
		# we grab the last pl_idx that is moved to become the new
		#   first one for the new tracks

		$queue->{needs_sort} = 1;
			# the queue will no longer be in pl_idx order

		my $pl_idx;
		for (my $i=$q_num-1; $i>=0; $i--)
		{
			my $track = $q_tracks->[$i];
			$track->{position} += $num_tracks;
			display(0,1,"track($i)=$track->{title}");
			if ($i >= $q_index)
			{
				$pl_idx = $track->{pl_idx};
				$track->{pl_idx} += $num_tracks;
				display(0,2,"moving track($i) to ".($i + $num_tracks));
				$q_tracks->[$i + $num_tracks] = $track;
			}
		}

		# then we assign the vacated slots to the new tracks

		my $pos = 0;
		for (my $i=0; $i<$num_tracks; $i++)
		{
			my $track = $tracks->[$i];
			$track->{library_uuid} = $l_uuid;
			$track->{position} = $pos++;
			$track->{pl_idx} += $pl_idx++;
			$q_tracks->[$i + $q_index] = $track;
		}

		$queue->{needs_start} = 1;
	}
	else
	{
		push @$q_tracks,@$tracks;
		my $pos = $q_num;
		for (my $i=$q_num; $i<$q_num + $num_tracks; $i++)
		{
			my $track = $q_tracks->[$i];
			$track->{library_uuid} = $l_uuid;
			$track->{position} += $pos;
			$track->{pl_idx} += $pos;
			$pos++;
		}

		# Add does not immediately start playing
		$queue->{needs_start} = 1 if $command eq 'play';
	}


	$queue->{num_tracks} += $num_tracks;
	$queue->{started} = 0 if $queue->{needs_start};
	$queue->{version}++;

	display($dbg_queue,0,"Queue(V_$queue->{version}) num($queue->{num_tracks}) idx($queue->{track_index}) needs_start($queue->{needs_start})");
	if ($dbg_queue < 0)
	{
		my $i = 0;
		for my $track (@$q_tracks)
		{
			display($dbg_queue+1,1,"track[$i] pos($track->{position}) idx($track->{pl_idx}) l_uuid($track->{library_uuid}) $track->{title}");
			$i++;
		}
	}
}


sub enqueueFolders
	# Note that folders can contain both Albums/Playlists and Subfolders
	# and that we do them in the order returned by getSubItems()
{
	my ($library,$ids,$tracks,$visited) = @_;
	display($dbg_queue,0,"enqueueFolders(".scalar(@$ids).")");

	$tracks ||= [];
	$visited ||= {};

	for my $id (@$ids)
	{
		if (!$visited->{$id})
		{
			$visited->{$id} = 1;
			my $folder = $library->getFolder($id);
			return !error("Could not get folder($id)") if !$folder;

			if ($folder->{dirtype} eq 'album' ||
				$folder->{dirtype} eq 'playlist')
			{
				my $folder_tracks = $library->getSubitems('tracks',$folder->{id},0,9999999);
				return !error("Could not get folder_tracks($id)") if !$folder_tracks;
				display($dbg_queue,1,"enquing ".scalar(@$folder_tracks)." from folder$folder->{title}");
				push @$tracks,@$folder_tracks;
			}
			else
			{
				my $sub_folders = $library->getSubitems('folders',$folder->{id},0,9999999);
				return !error("Could not get sub_folders($id)") if !$sub_folders;
				for my $sub_folder (@$sub_folders)
				{
					display($dbg_queue+1,1,"enquing subfolder($folder->{title})");
					my $rslt = enqueueFolders($library,[$sub_folder->{id}],$tracks,$visited);
					return if !$rslt;
				}
			}
		}
	}

	return $tracks;
}



#--------------------------------------------------
# Queue Object
#--------------------------------------------------

sub clear
{
	my ($this) = @_;
	$this->{version}++;
	$this->{started} = 0;
	$this->{needs_start} = 0;
	$this->{track_index} = 0;
	$this->{num_tracks} = 0;
	$this->{shuffle} = $SHUFFLE_NONE;
	$this->{tracks} = shared_clone([]);
}


sub incTrack
{
	my ($this,$inc) = @_;
	display($dbg_queue,0,"incTrack($this->{renderer_uuid},$this->{num_tracks},$this->{track_index},$this->{version}) inc=$inc");
	my $new_idx = $this->{track_index} + $inc;

	if ($new_idx >= 0 && $new_idx <= $this->{num_tracks})
	{
		$this->{track_index} = $new_idx;
		$this->{needs_start} = 1;
		$this->{started} = 0;
		display($dbg_queue,0,"incTrack($inc) returning idx($new_idx)");
	}
	else
	{
		return error("new_idx($new_idx) out of range in incTrack($inc)");
	}
}


sub incAlbum
	# backwards will go to beginning of album if there is no other album
	# forwards will stop the queue if there is no other album
{
	my ($this,$inc) = @_;
	display($dbg_queue,0,"incAlbum($this->{renderer_uuid},$this->{num_tracks},$this->{track_index},V_$this->{version}) inc=$inc");

	my $tracks = $this->{tracks};
	my $num = $this->{num_tracks};
	my $idx = $this->{track_index};
	my $moved = 0;

	if ($inc > 0 && $idx < $num)
	{
		$moved = 1;
		my $track = $tracks->[$idx];
		my $album_id = $track->{parent_id};

		$idx++;
		$track = $tracks->[$idx];
		while ($idx < $num && $track->{parent_id} eq $album_id)
		{
			$idx++;
			$track = $tracks->[$idx];
		}
	}
	elsif ($inc < 0 && $idx)
	{
		$moved = 1;
		my $track = $tracks->[$idx];
		my $album_id = $track->{parent_id};

		$idx--;
		$track = $tracks->[$idx];

		# find end of previous album

		while ($idx && $track->{parent_id} eq $album_id)
		{
			$idx--;
			$track = $tracks->[$idx];
		}

		# if its not the same album_id, find the beginning

		if ($track->{parent_id} ne $album_id)
		{
			$album_id = $track->{parent_id};
			while ($idx && $track->{parent_id} eq $album_id)
			{
				$idx--;
				$track = $tracks->[$idx];
			}

			# and finally, if its a different album_id, bump $idx

			$idx++ if $track->{parent_id} ne $album_id;
		}
	}

	if ($moved)
	{
		$this->{track_index} = $idx;
		$this->{needs_start} = 1;
		$this->{started} = 0;
		display($dbg_queue,0,"incAlbum($inc) returning idx($idx)");
	}
	else
	{
		display($dbg_queue,0,"incAlbum($inc) no change");
	}
}



sub restart
	# restart the queue, which MAY need resorting
{
	my ($this) = @_;
	display($dbg_queue,0,"restart()");
	$this->{track_index} = 0;
	$this->{needs_start} = 1;
	$this->{started} = 0;
}


1;
