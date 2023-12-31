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



my $dbg_queue = 0;


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
		renderer_uuid => $renderer_uuid,
		needs_start => 0 });
	bless $this,$class;
	$this->clear();
	$master_queue->{$renderer_uuid} = $this;
	return $this;
}


sub queue_error
{
	my ($rslt,$msg) = @_;
	$rslt->{error} = error($msg,1);
	return $rslt;
}


sub queueCommand
	# returns a hash that *may* contain an error,
	# a single track, a list of tracks, and/or a
	# copy of the queue
	#
	# 	error => implies an error
	#   queue => returned for most commands that change the queue
	#   tracks => subset of tracks returned for get_tracks($start,$count)
	#   track => the track after a next, prev, that returns a track
{
	my ($command,$post_params) = @_;
	my $dbg = $command eq 'get_queue' ? $dbg_queue + 2 : $dbg_queue;
	display_hash($dbg,0,"queueCommand($command)",$post_params);

	my $rslt = {};

	my $r_uuid = $post_params->{renderer_uuid};
	return queue_error($rslt,"No renderer_uuid in queue/$command call")
		if !$r_uuid;

	# html_renderers are allowed to establish a queue even
	# though there is currently no Device associated with them.
	# $renderer is not used, it is just a safety check.

	if ($r_uuid !~ /^html_renderer/)
	{
		my $renderer = findDevice($DEVICE_TYPE_RENDERER,$r_uuid);
		return queue_error($rslt,"Could not find renderer $r_uuid")
			if !$renderer;
	}

	my $queue = getQueue($r_uuid);
	if ($command eq 'add' || $command eq 'play')
	{
		$queue->enqueue($rslt,$command,$post_params);
	}
	elsif ($command eq 'next' || $command eq 'prev')
	{
		my $inc = $command eq 'next' ? 1 : -1;
		$queue->incTrack($rslt,$inc);
	}
	elsif ($command eq 'next_album' || $command eq 'prev_album')
	{
		my $inc = $command eq 'next_album' ? 1 : -1;
		$queue->incAlbum($rslt,$inc);
	}
	elsif ($command eq 'play_track')
	{
		my $pl_idx = $post_params->{pl_idx};
		if (!defined($pl_idx))
		{
			queue_error($rslt,"No pl_idx in Queue::play_track");
		}
		else
		{
			$pl_idx = 0 if $pl_idx < 0;
			$pl_idx = $queue->{num_tracks}-1 if $pl_idx > $queue->{num_tracks}-1;
			$queue->{track_index} = $pl_idx;
			$queue->{needs_start}++;
			$rslt->{track} = $queue->{tracks}->[$pl_idx];
		}
	}

	elsif ($command eq 'get_tracks')
	{
		$rslt = { tracks=>[] };
		my $start = $post_params->{start};
		my $count = $post_params->{count};
		if ($start < $queue->{num_tracks})
		{
			my $avail = $queue->{num_tracks} - $start;
			$count = $avail if $count > $avail;
			for (my $i=0; $i<$count; $i++)
			{
				my $rec = $queue->{tracks}->[$i + $start];
				push @{$rslt->{tracks}},$rec;
			}
		}
		display($dbg_queue,2,"got ".scalar(@{$rslt->{tracks}})." tracks for queue get_tracks json");
	}

	# support for html_renderers

	elsif ($command eq 'get_queue')
	{
		# no-op - returns queue below
	}
	elsif ($command eq 'clear')
	{
		$queue->clear();
	}
	elsif ($command eq 'restart')
	{
		$queue->restart($rslt);
	}
	elsif ($command eq 'shuffle')
	{
		my $how = $post_params->{how};
		if (!defined($how))
		{
			queue_error($rslt,"No how defined in queue_command(shuffle)");
		}
		else
		{
			$queue->shuffle($rslt,$how);
		}
	}
	else
	{
		queue_error($rslt,"unknown queue command '$command'");
	}

	$rslt->{queue} = $queue->copyMinusTracks()
		if !$rslt->{error};
	return $rslt;
}


#-----------------------------------------------------
# enqueuing
#-----------------------------------------------------
# Special support for remoteArtisanLibrary passes the enqueue
# request to the

sub enqueue
	# returns 1 success, sets $$error otherwise
	# folders and tracks commands are disjoint and separate
{
	my ($this,$rslt,$command,$post_params) = @_;
	display($dbg_queue,0,"enqueue($command)");
	my $l_uuid = $post_params->{library_uuid};

	return queue_error($rslt,"No library_uuid in eneueue($command)")
		if !$l_uuid;
	my $library = findDevice($DEVICE_TYPE_LIBRARY,$l_uuid);
	return queue_error($rslt,"Could not find library $l_uuid in eneueue($command)")
		if !$library;

	# gather the tracks to be added

	my $tracks = [];
	if ($library->{remote_artisan})
	{
		$tracks = $library->getQueueTracks($rslt,$post_params);
	}
	else
	{
		$tracks = getQueueTracks($rslt,$library,$post_params);
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

	my $q_tracks = $this->{tracks};
	my $q_index = $this->{track_index};
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
			$track->{pl_idx} = $pl_idx++;
			$q_tracks->[$i + $q_index] = $track;
		}

		$rslt->{track} = $q_tracks->[$q_index];
		$this->{needs_start}++;
	}
	else
	{
		push @$q_tracks,@$tracks;

		for (my $i=$q_num; $i<$q_num + $num_tracks; $i++)
		{
			my $track = $q_tracks->[$i];
			$track->{library_uuid} = $l_uuid;
			$track->{position} = $pos;
			$track->{pl_idx} = $pos;
			$pos++;
		}

		# Add does not immediately start playing
		if ($command eq 'play')
		{
			$this->{needs_start}++;
			$rslt->{track} = $q_tracks->[0];
		}
	}

	$this->{num_tracks} += $num_tracks;
	$this->{version}++;

	display($dbg_queue,0,"Queue($this->{version}) num($this->{num_tracks}) idx($this->{track_index}) needs_start($this->{needs_start})");
	if ($dbg_queue < 0)
	{
		my $i = 0;
		for my $track (@$q_tracks)
		{
			display($dbg_queue+1,1,"track[$i] pos($track->{position}) idx($track->{pl_idx}) l_uuid($track->{library_uuid}) $track->{title}");
			$i++;
		}
	}

	return 1;
}


sub getQueueTracks
{
	my ($rslt,$library,$post_params) = @_;
	display_hash($dbg_queue+1,0,"getQueueTracks post_params",$post_params);
	my $tracks = [];
	my $folders = $post_params->{folders};
	if ($folders)
	{
		my @ids = split(/,/,$post_params->{folders});
		$tracks = getQueueFolders($rslt,$library,\@ids);
		return '' if !$tracks;
	}
	else	# $post_params->{tracks} must be valid
	{
		my @ids = split(/,/,$post_params->{tracks});
		for my $id (@ids)
		{
			my $track = $library->getTrack($id);
			if (!$track)
			{
				return queue_error($rslt,"Could not find track($id)");
			}
			push @$tracks,$track;
		}
	}
	return $tracks;
}



sub getQueueFolders
	# Note that folders can contain both Albums/Playlists and Subfolders
	# and that we do them in the order returned by getSubItems()
{
	my ($rslt,$library,$ids,$tracks,$visited) = @_;
	display($dbg_queue,0,"getQueueFolders(".scalar(@$ids).")");

	$tracks ||= [];
	$visited ||= {};

	for my $id (@$ids)
	{
		if (!$visited->{$id})
		{
			$visited->{$id} = 1;
			my $folder = $library->getFolder($id);
			return queue_error($rslt,"Could not get folder($id)")
				if !$folder;

			if ($folder->{dirtype} eq 'album' ||
				$folder->{dirtype} eq 'playlist')
			{
				my $folder_tracks = $library->getSubitems('tracks',$folder->{id},0,9999999);
				return !queue_error($rslt,"Could not get folder_tracks($id)") if !$folder_tracks;
				display($dbg_queue,1,"enquing ".scalar(@$folder_tracks)." from folder$folder->{title}");
				push @$tracks,@$folder_tracks;
			}
			else
			{
				my $sub_folders = $library->getSubitems('folders',$folder->{id},0,9999999);
				return !queue_error($rslt,"Could not get sub_folders($id)") if !$sub_folders;
				for my $sub_folder (@$sub_folders)
				{
					display($dbg_queue+1,1,"enquing subfolder($folder->{title})");
					my $rslt = getQueueFolders($rslt,$library,[$sub_folder->{id}],$tracks,$visited);
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

sub copyMinusTracks
{
	my ($this) = @_;
	# return the queue minus the tracks
	my $rslt = {};
	for my $key (keys %$this)
	{
		next if $key eq 'tracks';
		$rslt->{$key} = $this->{$key};
	}
	return $rslt;
}


sub clear
{
	my ($this) = @_;
	$this->{version}++;
	$this->{track_index} = 0;
	$this->{num_tracks} = 0;
	$this->{shuffle} = $SHUFFLE_NONE;
	$this->{tracks} = shared_clone([]);
}


sub incTrack
{
	my ($this,$rslt,$inc) = @_;
	display($dbg_queue,0,"incTrack($this->{renderer_uuid},$this->{num_tracks},$this->{track_index},$this->{version}) inc=$inc");
	my $new_idx = $this->{track_index} + $inc;

	if ($new_idx >= 0 && $new_idx <= $this->{num_tracks})
	{
		$this->{track_index} = $new_idx;

		# anytime needs start is set to 1,
		# we we will set the track into the result
		# for the html_renderer ..

		$this->{needs_start}++;
		if ($new_idx < $this->{num_tracks})
		{
			$rslt->{track} = $this->{tracks}->[$new_idx];
		}
		display($dbg_queue,0,"incTrack($inc) returning idx($new_idx)");
	}
	else
	{
		queue_error($rslt,"new_idx($new_idx) out of range in incTrack($inc)");
	}
}



sub incAlbum
	# backwards will go to beginning of album if there is no other album
	# forwards will stop the queue if there is no other album
	# prh - should have an error param for boundry conditions ...
{
	my ($this,$rslt,$inc) = @_;
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
	else
	{
		queue_error($rslt,"idx out of range in incAlbum($inc)");
	}

	if ($moved)
	{
		$this->{track_index} = $idx;
		$this->{needs_start}++;
		if ($idx < $this->{num_tracks})
		{
			$rslt->{track} = $this->{tracks}->[$idx];
		}
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
	my ($this,$rslt) = @_;
	$this->{track_index} = 0
		if $this->{track_index} >= $this->{num_tracks};
	$this->{needs_start}++;
	if ($this->{num_tracks})
	{
		$rslt->{track} = $this->{tracks}->[$this->{track_index}];
	}
	display($dbg_queue,0,"restart($this->{track_index}) needs_start($this->{needs_start})");
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
	my ($this,$rslt,$how) = @_;
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
	$this->{needs_start}++;
	$this->{version} ++;
	if ($this->{num_tracks})
	{
		$rslt->{track} = $this->{tracks}->[0];
	}
   	display($dbg_queue,0,"shuffle($how) finished");

}


1;
