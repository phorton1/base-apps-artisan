#!/usr/bin/perl
#---------------------------------------
# Playlist.pm
#---------------------------------------
# A Playlist is a named, standing selection of the library that plays
# in a chosen order, wraps around, and remembers where it was.  See
# docs/playlists.md for the design this implements.
#
# Definitions come from $data_dir/playlists.txt, read once at startup by
# initPlaylists().  Each playlist's track list is derived from artisan.db
# at that time and held in RAM as a list of track ids in DEFAULT ORDER
# (by path within genre, then track number, then title) with a parallel
# list of album ids.  The current ORDER is a permutation of that list,
# recomputed from the shuffle mode and the seed whenever either changes.
# Nothing about a playlist is ever written to disk.
#
# The blessed Playlist object is deliberately small, because it is
# returned in every /webUI/update response.  The bulky lists live in
# $lists, keyed by playlist name, and never leave this module.
#
#	id				- the name again; what the webUI addresses a playlist by
#	name			- the playlist's identity
#	order			- sort key for the webUI menu; means nothing else
#	default_shuffle	- the mode a playlist starts in the first time it is played
#	uuid			- the library's uuid
#	num_tracks
#	shuffle			- $SHUFFLE_NONE, $SHUFFLE_TRACKS or $SHUFFLE_ALBUMS
#	seed			- fixes the order for TRACKS and ALBUMS; 0 for NONE
#	track_id		- the current track, or '' if the playlist is empty
#	track_index		- 1-based index of track_id in the current order, 0 if none
#	version			- bumped on every position or order change; requests
#					  carry the version they last saw and stale ones are ignored
#	data_version	- bumped on every order change; the webUI reloads its
#					  tracklist when it changes
#
# THE STATE SET
#
# The state a server remembers is, for each playlist by name, its
# shuffle, seed and track_id.  getState() returns that hash and
# setState() applies one, as handed over by the first browser to poll a
# freshly booted server.  $state_id is bumped on every change so that
# browsers store a copy only when something moved; $state_empty is 1
# until the server has state of its own, which is when a handover is
# accepted.  The device renderer's volume and mute ride along in the
# same set but belong to localRenderer; it calls bumpState().

package Playlist;
use strict;
use warnings;
use threads;
use threads::shared;
use Database;
use artisanUtils;


my $dbg_pl = 0;
	#  0 = function headers
	# -1 = big steps
	# -2 = gruesome details
my $dbg_init = 0;
	#  0 = one line per playlist at startup
	# -1 = query lines and counts
my $dbg_shuffle = 1;
	#  0 = orders as they are computed

my $playlists_file = "$data_dir/playlists.txt";

my $playlists:shared = shared_clone({});
	# by name: the small blessed Playlist objects
my $lists:shared = shared_clone({});
	# by name: { ids => [..], albums => [..], order => [..] }
	# ids and albums are in default order; order is a list of
	# indices into them giving the current playing order
my $state_id:shared = 1;
my $state_empty:shared = 1;

my $PRNG_MAX = 2147483647;		# 2^31 - 1, Park-Miller modulus


#-----------------------------------------
# startup
#-----------------------------------------

sub initPlaylists
	# read playlists.txt and derive every track list.
	# called once at startup, after the library is scanned
	# on the librarian, and may be called again after a scan
	# to re-derive the lists; positions survive by track_id.
{
	display($dbg_init,0,"initPlaylists($playlists_file)");

	my $defs = readDefinitions();
	return if !$defs;

	my $dbh = db_connect();
	return if !$dbh;

	for my $def (@$defs)
	{
		my $name = $def->{name};
		my ($ids,$albums) = deriveList($dbh,$def);
		my $num_tracks = scalar(@$ids);

		my $playlist = $playlists->{$name};
		if (!$playlist)
		{
			$playlist = shared_clone({
				id				=> $name,
				name			=> $name,
				order			=> $def->{order},
				default_shuffle	=> $def->{default_shuffle},
				uuid			=> $this_uuid,
				num_tracks		=> 0,
				shuffle			=> $def->{default_shuffle},
				seed			=> 0,
				track_id		=> '',
				track_index		=> 0,
				version			=> 1,
				data_version	=> 1, });
			bless $playlist,'Playlist';
			$playlists->{$name} = $playlist;
			$lists->{$name} = shared_clone({
				ids => [],
				albums => [],
				play_order => [] });
		}
		else
		{
			$playlist->{order} = $def->{order};
			$playlist->{default_shuffle} = $def->{default_shuffle};
		}

		my $list = $lists->{$name};
		@{$list->{ids}} = @$ids;
		@{$list->{albums}} = @$albums;
		$playlist->{num_tracks} = $num_tracks;
		$playlist->{seed} = newSeed()
			if $playlist->{shuffle} != $SHUFFLE_NONE && !$playlist->{seed};
		computeOrder($playlist);
		resolvePosition($playlist);

		display($dbg_init,1,pad($name,14)." order($def->{order}) ".
			"shuffle($playlist->{shuffle}) tracks($num_tracks)");
	}

	# a playlist that left the file is forgotten

	for my $name (keys %$playlists)
	{
		next if grep { $_->{name} eq $name } @$defs;
		display($dbg_init,1,"forgetting playlist($name)");
		delete $playlists->{$name};
		delete $lists->{$name};
	}

	db_disconnect($dbh);
	display($dbg_init,0,"initPlaylists() finished with ".scalar(keys %$playlists)." playlists");
}


sub readDefinitions
	# returns a list of { name, order, default_shuffle, queries=>[] }
	# or undef with an error if the file is missing or malformed
{
	if (!-f $playlists_file)
	{
		error("no playlists file $playlists_file");
		return;
	}

	my $defs = [];
	my $def;
	my $line_num = 0;
	my %names;
	for my $line (getTextLines($playlists_file))
	{
		$line_num++;
		$line =~ s/\r$//;
		next if $line =~ /^\s*(#.*)?$/;

		if ($line =~ /^playlist\s+(\d+)\s+(\S+)\s+(none|track|album)\s*$/)
		{
			my ($order,$name,$mode) = ($1,$2,$3);
			if ($names{$name})
			{
				error("duplicate playlist($name) at $playlists_file line $line_num");
				return;
			}
			$names{$name} = 1;
			$def = {
				name => $name,
				order => $order + 0,
				default_shuffle =>
					$mode eq 'track' ? $SHUFFLE_TRACKS :
					$mode eq 'album' ? $SHUFFLE_ALBUMS :
					$SHUFFLE_NONE,
				queries => [] };
			push @$defs,$def;
		}
		elsif ($line =~ /^\s+(\S.*?)\s*$/ && $def)
		{
			push @{$def->{queries}},$1;
		}
		else
		{
			error("bad line in $playlists_file at line $line_num: $line");
			return;
		}
	}

	for my $def (@$defs)
	{
		if (!@{$def->{queries}})
		{
			error("playlist($def->{name}) has no query lines in $playlists_file");
			return;
		}
	}

	display($dbg_init+1,1,"read ".scalar(@$defs)." definitions");
	return $defs;
}


sub deriveList
	# run the query lines against artisan.db and return
	# (ids,albums) in default order, each track once
{
	my ($dbh,$def) = @_;
	my $name = $def->{name};
	display($dbg_init+1,1,"deriveList($name)");

	my %seen;
	my $recs = [];
	for my $query (@{$def->{queries}})
	{
		my $exclude = ($query =~ s/\s+minus\s+(.*)$//) ? $1 : '';
		my $sql = "SELECT id,path,tracknum,title,album_title,parent_id ".
			"FROM tracks WHERE instr(path,?) > 0";
		my $args = [ $query ];
		if ($exclude)
		{
			$sql .= " AND instr(path,?) <= 0";
			push @$args,$exclude;
		}
		my $found = get_records_db($dbh,$sql,$args) || [];
		my $added = 0;
		for my $rec (@$found)
		{
			next if $seen{$rec->{id}};
			$seen{$rec->{id}} = 1;
			push @$recs,$rec;
			$added++;
		}
		display($dbg_init+1,2,"'$query' minus '$exclude' found ".scalar(@$found)." added $added");
	}

	my $ids = [];
	my $albums = [];
	for my $rec (sort { default_sort($a,$b) } @$recs)
	{
		push @$ids,$rec->{id};
		push @$albums,albumId($rec);
	}
	return ($ids,$albums);
}


sub normalizedPath
	# the track's path without the filename and without the
	# leading albums/ or singles/, so that the default order
	# groups by genre, then artist and album
{
	my ($path) = @_;
	$path = pathOf($path);
	$path =~ s/^(albums|singles)\///;
	return $path;
}


sub default_sort
{
	my ($a,$b) = @_;
	my $cmp = normalizedPath($a->{path}) cmp normalizedPath($b->{path});
	return $cmp if $cmp;
	$cmp = ($a->{tracknum} || 0) <=> ($b->{tracknum} || 0);
	return $cmp if $cmp;
	return $a->{title} cmp $b->{title};
}



#-----------------------------------------
# access
#-----------------------------------------

sub getPlaylists
	# all playlists, in menu order
{
	my @playlists = sort { $a->{order} <=> $b->{order} } values %$playlists;
	return \@playlists;
}


sub getPlaylist
{
	my ($name,$no_error) = @_;
	my $playlist = $playlists->{$name};
	error("Could not find playlist($name)") if !$playlist && !$no_error;
	return $playlist;
}


sub dbg_info
{
	my ($this,$extra_dbg) = @_;
	$extra_dbg ||= 0;
	return "("._def($this).")" if !$this;

	my $name = "($this->{name}";
	$name .= ",V_$this->{version},$this->{track_index},$this->{num_tracks}"
		if $dbg_pl < $extra_dbg;
	$name .= ",S_$this->{shuffle},$this->{seed},$this->{track_id}"
		if $dbg_pl < $extra_dbg-1;
	$name .= ")";
	return $name;
}



#-----------------------------------------
# order and position
#-----------------------------------------

my $seed_count:shared = 0;

sub newSeed
	# a seed of the moment; the counter keeps seeds taken
	# in the same second apart
{
	$seed_count++;
	my $seed = (time() * 7919 + $$ * 104729 + $seed_count * 15485863) % ($PRNG_MAX - 1);
	return $seed + 1;
}


sub prng_next
	# Park-Miller minimal standard generator in Schrage's form,
	# so that every intermediate value fits in 31 bits and the
	# sequence is identical on 32 and 64 bit Perls.  The seed is
	# in 1 .. 2^31-2 and so is every value returned.
{
	my ($s) = @_;
	my $hi = int($s / 127773);
	my $lo = $s - 127773 * $hi;
	$s = 16807 * $lo - 2836 * $hi;
	$s += $PRNG_MAX if $s <= 0;
	return $s;
}


sub shuffleIndices
	# Fisher-Yates over 0..n-1 driven by the seed
{
	my ($n,$seed) = @_;
	my @idx = (0 .. $n-1);
	my $s = $seed;
	for (my $i=$n-1; $i>0; $i--)
	{
		$s = prng_next($s);
		my $j = $s % ($i + 1);
		@idx[$i,$j] = @idx[$j,$i];
	}
	return \@idx;
}


sub computeOrder
	# recompute the playing order from shuffle and seed
{
	my ($this) = @_;
	my $list = $lists->{$this->{name}};
	my $ids = $list->{ids};
	my $n = scalar(@$ids);
	my $order;

	if (!$n)
	{
		$order = [];
	}
	elsif ($this->{shuffle} == $SHUFFLE_TRACKS)
	{
		$order = shuffleIndices($n,$this->{seed});
	}
	elsif ($this->{shuffle} == $SHUFFLE_ALBUMS)
	{
		# albums in order of first appearance, each with
		# the indices of its tracks in default order

		my $albums = $list->{albums};
		my @album_keys;
		my %album_tracks;
		for (my $i=0; $i<$n; $i++)
		{
			my $key = $albums->[$i];
			push @album_keys,$key if !$album_tracks{$key};
			push @{$album_tracks{$key}},$i;
		}
		my $shuffled = shuffleIndices(scalar(@album_keys),$this->{seed});
		$order = [];
		for my $a (@$shuffled)
		{
			push @$order,@{$album_tracks{$album_keys[$a]}};
		}
	}
	else
	{
		$order = [ 0 .. $n-1 ];
	}

	@{$list->{play_order}} = @$order;
	display($dbg_shuffle,1,"computeOrder($this->{name}) shuffle($this->{shuffle}) seed($this->{seed}) ".
		"first(".($n ? $ids->[$order->[0]] : '').")");
}


sub resolvePosition
	# find track_id in the current order and set track_index,
	# or start the playlist over if it is gone.  Returns the
	# track_id that the position now refers to.
{
	my ($this) = @_;
	my $list = $lists->{$this->{name}};
	my $ids = $list->{ids};
	my $order = $list->{play_order};
	my $n = scalar(@$order);

	if (!$n)
	{
		$this->{track_id} = '';
		$this->{track_index} = 0;
		return '';
	}

	my $want = $this->{track_id};
	if ($want)
	{
		for (my $i=0; $i<$n; $i++)
		{
			if ($ids->[$order->[$i]] eq $want)
			{
				$this->{track_index} = $i + 1;
				return $want;
			}
		}
		display($dbg_pl,1,"track($want) is no longer in playlist($this->{name}); starting over");
	}

	$this->{track_index} = 1;
	$this->{track_id} = $ids->[$order->[0]];
	return $this->{track_id};
}


sub idAt
	# the track id at a 1-based index in the current order
{
	my ($this,$index) = @_;
	my $list = $lists->{$this->{name}};
	return $list->{ids}->[ $list->{play_order}->[$index-1] ];
}


sub albumAt
{
	my ($this,$index) = @_;
	my $list = $lists->{$this->{name}};
	return $list->{albums}->[ $list->{play_order}->[$index-1] ];
}


sub getPlaylistTrack
	# move to a track and return the playlist.
	#   $PLAYLIST_ABSOLUTE       $index is the new 1-based index
	#   $PLAYLIST_RELATIVE       $index is added, wrapping
	#   $PLAYLIST_ALBUM_RELATIVE $index is +1 or -1 albums
	# only the version holder may move the playlist; a request
	# with another version is ignored and the playlist returned
	# unchanged.
{
	my ($this,$version,$mode,$orig_index) = @_;
	display($dbg_pl,0,"getPlaylistTrack($version,$mode,$orig_index) on".dbg_info($this,2));

	if ($version != $this->{version})
	{
		warning($dbg_pl,0,"getPlaylistTrack() skipping stale request".dbg_info($this,2));
		return $this;
	}

	my $num_tracks = $this->{num_tracks};
	my $index = $orig_index;
	if ($mode == $PLAYLIST_RELATIVE)
	{
		$index = $this->{track_index} + $index;
		$index = 1 if $index > $num_tracks;
		$index = $num_tracks if $index < 1;
	}
	elsif ($mode == $PLAYLIST_ALBUM_RELATIVE && $index)
	{
		$index = $this->incAlbum($index > 0 ? 1 : -1);
	}

	$index = 1 if $index < 1;
	$index = $num_tracks if $index > $num_tracks;
	$index = 0 if !$num_tracks;

	if ($this->{track_index} != $index)
	{
		$this->{track_index} = $index;
		$this->{track_id} = $index ? $this->idAt($index) : '';
		$this->{version}++;
		bumpState();
		display($dbg_pl,0,"getPlaylistTrack() returning".dbg_info($this,2));
	}
	else
	{
		display($dbg_pl,0,"getPlaylistTrack() no change".dbg_info($this,2));
	}
	return $this;
}


sub incAlbum
	# the first track of the next album, or of the previous
	# album, in the current order, wrapping.  A playlist that
	# is one album stays where it is.
{
	my ($this,$inc) = @_;
	my $n = $this->{num_tracks};
	return 0 if !$n;
	my $index = $this->{track_index};
	my $album = $this->albumAt($index);

	if ($inc > 0)
	{
		for (my $i=0; $i<$n; $i++)
		{
			$index = $index >= $n ? 1 : $index + 1;
			return $index if $this->albumAt($index) ne $album;
		}
		return $this->{track_index};
	}

	my $first = $this->firstOfAlbum($index);
	my $prev = $first <= 1 ? $n : $first - 1;
	return $first if $this->albumAt($prev) eq $album;
	return $this->firstOfAlbum($prev);
}


sub firstOfAlbum
	# walk back from a 1-based index to the first track
	# of its album in the current order, wrapping
{
	my ($this,$index) = @_;
	my $n = $this->{num_tracks};
	my $album = $this->albumAt($index);
	for (my $i=0; $i<$n; $i++)
	{
		my $prev = $index <= 1 ? $n : $index - 1;
		return $index if $this->albumAt($prev) ne $album;
		$index = $prev;
	}
	return $index;
}


sub sortPlaylist
	# set the shuffle mode, pick a new seed, and start the
	# playlist from the first track of the new order
{
	my ($this,$shuffle) = @_;
	display($dbg_pl,0,"sortPlaylist($shuffle) on".dbg_info($this));

	$this->{shuffle} = $shuffle;
	$this->{seed} = $shuffle == $SHUFFLE_NONE ? 0 : newSeed();
	$this->computeOrder();
	$this->{track_index} = $this->{num_tracks} ? 1 : 0;
	$this->{track_id} = $this->{num_tracks} ? $this->idAt(1) : '';
	$this->{version}++;
	$this->{data_version}++;
	bumpState();

	display($dbg_pl,0,"sortPlaylist() returning".dbg_info($this,2));
	return $this;
}



#-----------------------------------------
# tracks
#-----------------------------------------

sub fetchTracks
	# get full track records for a list of ids, in that order
{
	my ($ids) = @_;
	return [] if !@$ids;

	my $dbh = db_connect();
	return [] if !$dbh;

	my %by_id;
	my @todo = @$ids;
	while (@todo)
	{
		my @chunk = splice(@todo,0,500);
		my $marks = join(',',('?') x scalar(@chunk));
		my $recs = get_records_db($dbh,"SELECT * FROM tracks WHERE id IN ($marks)",\@chunk) || [];
		$by_id{$_->{id}} = $_ for @$recs;
	}
	db_disconnect($dbh);

	my $tracks = [];
	for my $id (@$ids)
	{
		my $rec = $by_id{$id};
		push @$tracks,$rec if $rec;
	}
	return $tracks;
}


sub getTracksSorted
	# tracks $start (0-based) .. $start+$count-1 in the current
	# order, each with pl_idx = its 1-based index in that order
{
	my ($this,$start,$count) = @_;
	display($dbg_pl,0,"getTracksSorted($start,$count)".dbg_info($this));
	my $n = $this->{num_tracks};
	my $ids = [];
	my $end = $start + $count;
	$end = $n if $end > $n;
	for (my $i=$start; $i<$end; $i++)
	{
		push @$ids,$this->idAt($i+1);
	}
	my $tracks = fetchTracks($ids);
	my $pl_idx = $start + 1;
	$_->{pl_idx} = $pl_idx++ for @$tracks;
	display($dbg_pl,0,"getTracksSorted() returning ".scalar(@$tracks)." tracks");
	return $tracks;
}


sub getTracks
	# tracks in DEFAULT order, for the explorer's virtual
	# playlist folders, each with position = 1-based index
{
	my ($this,$start,$count) = @_;
	display($dbg_pl,0,"getTracks($start,$count)".dbg_info($this));
	my $list = $lists->{$this->{name}};
	my $all = $list->{ids};
	my $n = scalar(@$all);
	my $end = $start + $count;
	$end = $n if $end > $n;
	my $ids = [ @$all[$start .. $end-1] ];
	my $tracks = fetchTracks($ids);
	my $position = $start + 1;
	for my $track (@$tracks)
	{
		$track->{position} = $position;
		$track->{pl_idx} = $position;
		$position++;
	}
	return $tracks;
}



#-----------------------------------------
# the state set
#-----------------------------------------

sub stateId		{ return $state_id; }
sub stateEmpty	{ return $state_empty; }

sub bumpState
{
	$state_id++;
	$state_empty = 0;
}


sub getState
	# the playlist half of the state set: by name, the
	# shuffle, seed and track_id of every playlist that
	# has a position
{
	my $state = {};
	for my $playlist (values %$playlists)
	{
		next if !$playlist->{track_id};
		$state->{$playlist->{name}} = {
			shuffle => $playlist->{shuffle},
			seed => $playlist->{seed},
			track_id => $playlist->{track_id} };
	}
	return $state;
}


sub setState
	# apply a handed-over state set to the playlists.
	# names that are not in playlists.txt are dropped.
	# the caller has already decided the handover is
	# acceptable; this bumps the state so that no
	# later handover is.
{
	my ($state) = @_;
	$state ||= {};
	my $applied = 0;
	for my $name (sort keys %$state)
	{
		my $playlist = $playlists->{$name};
		my $rec = $state->{$name};
		if (!$playlist || ref($rec) !~ /HASH/)
		{
			display($dbg_pl,1,"setState() dropping unknown playlist($name)");
			next;
		}
		my $shuffle = $rec->{shuffle} || 0;
		$shuffle = $SHUFFLE_NONE if $shuffle != $SHUFFLE_TRACKS && $shuffle != $SHUFFLE_ALBUMS;
		my $seed = int($rec->{seed} || 0);
		$seed = newSeed() if $shuffle != $SHUFFLE_NONE && ($seed < 1 || $seed >= $PRNG_MAX);
		$seed = 0 if $shuffle == $SHUFFLE_NONE;

		$playlist->{shuffle} = $shuffle;
		$playlist->{seed} = $seed;
		$playlist->{track_id} = $rec->{track_id} || '';
		$playlist->computeOrder();
		$playlist->resolvePosition();
		$playlist->{version}++;
		$playlist->{data_version}++;
		$applied++;
		display($dbg_pl,1,"setState() applied".dbg_info($playlist,2));
	}
	bumpState();
	display($dbg_pl,0,"setState() applied $applied playlists");
	return $applied;
}



1;
