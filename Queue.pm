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
use httpUtils;
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
	# returns blank or error except for get_tracks
	# which tracks to be jsonified and returned
{
	my ($command,$post_params) = @_;
	display_hash($dbg_queue,0,"queueCommand($command)",$post_params);

	my $u_version = $post_params->{version};
	# return error("No version in queue/$command call") if !$u_version;
	my $r_uuid = $post_params->{renderer_uuid};
	return error("No renderer_uuid in queue/$command call") if !$r_uuid;
	my $renderer = findDevice($DEVICE_TYPE_RENDERER,$r_uuid);
	return error("Could not find renderer $r_uuid") if !$renderer;

	my $queue = getQueue($r_uuid);

	if ($command eq 'add' || $command eq 'play')
	{
		return enqueue($command,$post_params,$queue);
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
	elsif ($command eq 'play_track')
	{
		my $pl_idx = $post_params->{pl_idx};
		return error("No pl_idx in Queue::play_track") if !defined($pl_idx);
		$pl_idx = 0 if $pl_idx < 0;
		$pl_idx = $queue->{num_tracks}-1 if $pl_idx > $queue->{num_tracks}-1;
		$queue->{track_index} = $pl_idx;
		$queue->{started} = 0;
		$queue->{needs_start} = 1;
	}

	elsif ($command eq 'get_tracks')
	{
		# this wont work.
		# queue commands are using post
		# and this has url params;

		my $tracks = [];
		my $start = $post_params->{start};
		my $count = $post_params->{count};

		if ($start < $queue->{num_tracks})
		{
			my $avail = $queue->{num_tracks} - $start;
			$count = $avail if $count > $avail;
			for (my $i=0; $i<$count; $i++)
			{
				my $rec = $queue->{tracks}->[$i + $start];
				push @$tracks,$rec;
			}
		}

		display($dbg_queue,2,"got ".scalar(@$tracks)." tracks for queue get_tracks json");
		return $tracks;
	}
	else
	{
		return error("unknown queue command '$command'");
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
	my ($command,$post_params,$queue) = @_;
	display($dbg_queue,0,"enqueue($command)");
	my $l_uuid = $post_params->{library_uuid};
	return error("No library_uuid in eneueue($command)")
		if !$l_uuid;
	my $library = findDevice($DEVICE_TYPE_LIBRARY,$l_uuid);
	return error("Could not find library $l_uuid in eneueue($command)")
		if !$library;

	# gather the tracks to be added

	my $tracks = [];

	my $folders = $post_params->{folders};
	if ($folders)
	{
		my @ids = split(/,/,$post_params->{folders});
		$tracks = enqueueFolders($library,\@ids);
		return error("Could not enqueuFolders") if !$tracks;
	}
	else	# $post_params->{tracks} must be valid
	{
		my @ids = split(/,/,$post_params->{tracks});
		for my $id (@ids)
		{
			my $track = $library->getTrack($id);
			return error("Could not find track($id)") if !$track;
			push @$tracks,$track;
		}
	}

	# Add adds the tracks at the end of the queue and Play
	# inserts them into the queue at the current position
	# so that they immediately start playing without upsetting
	# the overall order of the current, possibly sorted, playlist.
	#
	# However, there is a difference between the 'ordinal' sort
	# order and the order the tracks may be in at the moment of
	# insertion for Play. THE NOMINAL ORDER OF TRACKS IS THE
	# ORDER THEY WERE ADDED, OR PLAYED, and once sorted(Off),
	# that transient order they happened to be in during the
	# Play command can never be recreaated.
	#
	# A subsequent sort(Off) will put them in the order
	# they were added or played, without regards for the
	# fact that they were inserted in the middle of a
	# sorted list.
	#
	# tracks are ALWAYS in the list in pl_idx order ..

	my $num_tracks = scalar(@$tracks);

	my $q_tracks = $queue->{tracks};
	my $q_index = $queue->{track_index};
	my $q_num = @$q_tracks;
	my $pos = $q_num;
		# nominal position - tracks always added at the end
		# even if they happen to start playing immediately

	display($dbg_queue,0,"$command $num_tracks tracks track_index($q_index)");

	if ($command eq 'play' && $q_num)
	{
		# splice not implemented for shared arrays
		# so first we work from the end of the array backwards
		# 	to the insert point, manually moving the items to
		#   new slots passed the current end of the array
		#   to make room for the new tracks, while bumping
		#   their pl_idx's as we go

		for (my $i=$q_num-1; $i>=$q_index; $i--)
		{
			my $track = $q_tracks->[$i];
			display(0,1,"track($i)=$track->{title}");
			$track->{pl_idx} += $num_tracks;
			display(0,2,"moving track($i) to ".($i + $num_tracks));
			$q_tracks->[$i + $num_tracks] = $track;
		}

		# then we assign the vacated slots to the new tracks

		my $pl_idx = $q_index;
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

	return '';
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
		my $album_id = albumId($track);

		$idx++;
		$track = $tracks->[$idx];
		while ($idx < $num && albumId($track) eq $album_id)
		{
			$idx++;
			$track = $tracks->[$idx];
		}
	}
	elsif ($inc < 0 && $idx)
	{
		$moved = 1;
		my $track = $tracks->[$idx];
		my $album_id = albumId($track);

		$idx--;
		$track = $tracks->[$idx];

		# find end of previous album

		while ($idx && albumId($track) eq $album_id)
		{
			$idx--;
			$track = $tracks->[$idx];
		}

		# if its not the same album_id, find the beginning

		if (albumId($track) ne $album_id)
		{
			$album_id = albumId($track);
			while ($idx && albumId($track) eq $album_id)
			{
				$idx--;
				$track = $tracks->[$idx];
			}

			# and finally, if its a different album_id, bump $idx

			$idx++ if albumId($track) ne $album_id;
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
	# restart the queue, which MAY need resorting by pl_idx
	# which is different than re-shuffling
{
	my ($this) = @_;
	display($dbg_queue,0,"restart()");
	$this->{track_index} = 0;
	$this->{needs_start} = 1;
	$this->{started} = 0;
}



sub random_album
	# sorting within a random index of albums
	# then, if a tracknum is provided, by that, and
	# finally by the track title.
{
    my ($albums,$aa,$bb) = @_;
    my $cmp = $albums->{albumId($aa)} <=> $albums->{albumId($bb)};
    return $cmp if $cmp;
    return $aa->{position} <=> $bb->{position};
}



sub shuffle
{
	my ($this,$how) = @_;
	display($dbg_queue,0,"shuffle($how)");

	my $old_recs = $this->{tracks};
	my $new_recs = shared_clone([]);

    if ($how == $SHUFFLE_TRACKS)
    {
        for my $rec (@$old_recs)
        {
            $rec->{pl_idx} = int(rand($this->{num_tracks} + 1));
	    }
		my $pl_idx = 0;
        for my $rec (sort {$a->{pl_idx} <=> $b->{pl_idx}} @$old_recs)
        {
			$rec->{pl_idx} = $pl_idx++;
            push @$new_recs,$rec;
        }
    }
    elsif ($how == $SHUFFLE_ALBUMS)
    {
        my %albums;
        for my $rec (@$old_recs)
        {
			my $album_id = albumId($rec);
			if (!$albums{$album_id})
			{
				$albums{$album_id} = int(rand($this->{num_tracks} + 1));
			}
		}
		my $pl_idx = 0;
        for my $rec (sort {random_album(\%albums,$a,$b)} @$old_recs)
        {
			$rec->{pl_idx} = $pl_idx++;
            push @$new_recs,$rec;
		}
    }

	# sort the records by the DEFAULT SORT ORDER

    else	# proper default sort order
    {
		my $pl_idx = 0;
        for my $rec (sort {$a->{position} <=> $b->{position}} @$old_recs)
        {
			$rec->{pl_idx} = $pl_idx++;
            push @$new_recs,$rec;
        }
    }

	$this->{shuffle} = $how;
	$this->{tracks} = $new_recs;
	$this->{track_index} = 0;
	$this->{started} = 0;
	$this->{needs_start} = 1;
	$this->{version} ++;
   	display($dbg_queue,0,"shuffle($how) finished");

}


1;
