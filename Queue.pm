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
# should stop and start immediately playing the head
# of the queue, which only happens on the first Add,
# but on any subsquent Play commands.
#
# To the degree that I envison a single Renderer per
# device, it is sufficient that there is a state variable
# 'needs_start', on the queue that is cleared by the
# renderer.
#
# NO Queue track_index
#
# There is no notion of an index within a Queue.
# The queue always plays the 0th item and pops
# it off when finished (on a subsequent call to
# getNextTrack().
#
# To the degree that in the future Queues may be saveable
# as Playlists, the paradigm is to FIRST build the Queue
# for the Playlist, THEN SAVE IT, and only after that,
# possibly, start playing it. This will be an artifice to
# the degree that the whole thing is built to start playing
# them right away.  The user would have to Pause the initial
# Play and then Add Tracks, Save, and then unpause.


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
# Queue Object
#--------------------------------------------------

sub getQueue
{
	my ($renderer_uuid) = @_;
	my $queue = $master_queue->{$renderer_uuid};
	display($dbg_queue,0,"found queue($renderer_uuid}") if $queue;
	$queue ||= Queue->new($renderer_uuid);
	return $queue;
}

sub new
{
	my ($class,$renderer_uuid) = @_;
	display($dbg_queue,0,"new Queue($renderer_uuid}");
	my $this = shared_clone({
		started => 0,
		needs_start => 0,
		renderer_uuid => $renderer_uuid,
		version => 1,
		shuffle => $SHUFFLE_NONE,
		tracks => shared_clone([]) });
	bless $this,$class;

	$master_queue->{$renderer_uuid} = $this;
	return $this;
}


sub getNextTrack()
{
	my ($this) = @_;
	my $started = $this->{started};
	my $tracks = $this->{tracks};
	my $num_tracks = @$tracks;
	display($dbg_queue,0,"getNextTrack($started) num($num_tracks)");


	shift @$tracks if $started;
	my $track = $tracks->[0];
	$this->{started} = 1;
	display($dbg_queue,0,"getNextTrack($started) returning num($num_tracks) track=".($track ? $track->{title} : 'undef'));
	return $track;
}




#-----------------------------------------------------
# enqueuing
#-----------------------------------------------------

sub queueCommand
	# returns an error on failure, blank on success
	# folders and tracks commands are disjoint and separate
{
	my ($command,$params) = @_;
	display_hash($dbg_queue,0,"queueCommand($command)",$params);
	for my $required qw(update_id renderer_uuid library_uuid)
	{
		return error("No $required in queue/$command call")
			if !$params->{$required};
	}

	my $r_uuid = $params->{renderer_uuid};
	my $l_uuid = $params->{library_uuid};

	my $library = findDevice($DEVICE_TYPE_LIBRARY,$l_uuid);
	return error("Could not find library $l_uuid") if !$library;
	my $renderer = findDevice($DEVICE_TYPE_RENDERER,$r_uuid);
	return error("Could not find renderer $r_uuid") if !$renderer;

	# gather the tracks to be added

	my $queue = getQueue($r_uuid);
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
	# if adding at the front, we need to adjust the positions and pl_idx's
	# before unshifting them all as a group.

	my $num_tracks = scalar(@$tracks);

	my $q_tracks = $queue->{tracks};

	if ($command eq 'play')
	{
		for my $track (@$q_tracks)
		{
			$track->{position} += $num_tracks;
			$track->{pl_idx} += $num_tracks;
		}
		unshift @$q_tracks,@$tracks;
		for (my $i=0; $i<$num_tracks; $i++)
		{
			$queue->{needs_start} = 1;
			my $track = $q_tracks->[$i];
			$track->{library_uuid} = $l_uuid;
			$track->{position} = $i + 1;
			$track->{pl_idx} = $i + 1;
		}
	}
	else
	{
		my $q_numtracks = @$q_tracks;
		my $position = $q_numtracks + 1;
		for my $track (@$tracks)
		{
			$queue->{needs_start} = 1 if !$q_numtracks;
			$track->{library_uuid} = $l_uuid;
			$track->{position} = $position;
			$track->{pl_idx} = $position;
			$position++;
			push @$q_tracks,$track;
		}
	}

	$queue->{version}++;
	$queue->{started} = 0 if $queue->{needs_start};

	display($dbg_queue,0,"Queue($renderer->{name},V_$queue->{version}) num(".scalar(@{$queue->{tracks}}).") needs_start($queue->{needs_start})");
	if ($dbg_queue < 0)
	{
		for my $track (@$q_tracks)
		{
			display($dbg_queue+1,1,"track pos($track->{position}) idx($track->{pl_idx}) l_uuid($track->{library_uuid}) $track->{title}");
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



1;
