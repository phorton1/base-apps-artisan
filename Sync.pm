#!/usr/bin/perl
#---------------------------------------
# Sync.pm
#---------------------------------------
# Makes a player's library artifact (the mp3 tree plus artisan.db and
# playlists.txt under _data) equal to the librarian's.  Runs on the
# player, which pulls; the librarian only serves.  See docs/notes/sync.md.
#
# The source side (served by any Artisan, used only on the librarian):
#
#    /sync/info             json: db_md5, playlists_md5, art list
#    /sync/db               artisan.db
#    /sync/playlists        playlists.txt
#    /sync/art/<path>       a folder.jpg
#    /media/<id>.mp3        a track, whole (HTTPStream, user agent mpg123)
#
# The player side:
#
#    /sync/plan             fetch + diff, returns the plan (a dry run)
#    /sync/start            runs a sync in a thread
#    /sync/cancel           stops after the current file
#    /sync/restart          restarts the service after a sync is done
#
# The player carries the state of the running command in RAM, in the
# shared variables below, reported on every /webUI/update poll as
# 'busy' and the 'sync' block.  The run ends in the step 'done' with
# the player still busy; the operator reads the summary and restarts,
# as update does.  On error it stops, reports, and lifts busy.

package Sync;
use strict;
use warnings;
use threads;
use threads::shared;
use Digest::MD5;
use File::Copy;
use LWP::UserAgent;
use Pub::Utils;
use Pub::ServiceMain;
use Pub::HTTP::Response;
use artisanUtils;
use artisanPrefs;
use Database;
use SQLite;
use DeviceManager;


my $dbg_sync = 0;
	# 0 = steps and counts
	# -1 = every file

our $SOURCE_PORT = 8091;
our $USER_AGENT = 'mpg123/artisan-sync';
	# HTTPStream sends the whole file, rather than headers only,
	# to a user agent that starts with mpg123
our $FETCH_TIMEOUT = 60;
our $STAGING_NAME = '_staging';


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		$busy
		syncStatus
		syncRequest
		sourceRequest
		setBusy
		clearBusy
	);
};


#-----------------------------------------------
# state
#-----------------------------------------------
# $busy is the System command in progress: '', 'sync' or 'update'.
# %sync is the sync block of the poll; sync_step stays at the step
# that failed and sync_error holds the message.

our $busy:shared = '';

my %sync:shared = (
	step		=> '',
	files_done	=> 0,
	files_total	=> 0,
	bytes_done	=> 0,
	bytes_total	=> 0,
	current		=> '',
	current_size => 0,
	current_done => 0,
	error		=> '',
	cancel		=> 0 );


sub setBusy
{
	my ($what) = @_;
	display($dbg_sync,0,"setBusy($what)");
	$busy = $what;
}

sub clearBusy
{
	display($dbg_sync,0,"clearBusy()");
	$busy = '';
}


sub syncStatus
	# the sync block for the poll, as a plain hash
{
	return {
		sync_step	 	=> $sync{step},
		sync_files_done	=> $sync{files_done},
		sync_files_total => $sync{files_total},
		sync_bytes_done	=> $sync{bytes_done},
		sync_bytes_total => $sync{bytes_total},
		sync_current	=> $sync{current},
		sync_current_size => $sync{current_size},
		sync_current_done => $sync{current_done},
		sync_error		=> $sync{error} };
}


sub setStep
{
	my ($step) = @_;
	display($dbg_sync,0,"sync step $step");
	$sync{step} = $step;
}

sub setError
{
	my ($msg) = @_;
	error("sync: $msg");
	$sync{error} = $msg;
}

sub resetState
{
	$sync{step} = '';
	$sync{files_done} = 0;
	$sync{files_total} = 0;
	$sync{bytes_done} = 0;
	$sync{bytes_total} = 0;
	$sync{current} = '';
	$sync{current_size} = 0;
	$sync{current_done} = 0;
	$sync{error} = '';
	$sync{cancel} = 0;
}


#-----------------------------------------------
# utilities
#-----------------------------------------------

sub fileMD5
{
	my ($filename) = @_;
	my $fh;
	return '' if !open($fh,'<:raw',$filename);
	my $md5 = Digest::MD5->new->addfile($fh)->hexdigest();
	close $fh;
	return $md5;
}


sub stagingDir
{
	return "$data_dir/$STAGING_NAME";
}


sub artFolders
	# the folders that have a folder.jpg according to a database,
	# as { folder_id => path }.  Folder ids are the md5 of the path
	# and so are plain ascii; paths are compared and carried by id
	# because their bytes differ between the json and the databases.
{
	my ($dbh) = @_;
	my $folders = {};
	my $recs = get_records_db($dbh,"SELECT id,path,has_art FROM folders WHERE is_local=1");
	for my $rec (@$recs)
	{
		next if !($rec->{has_art} & 1);
		next if !$rec->{path};
		$folders->{$rec->{id}} = $rec->{path};
	}
	return $folders;
}


sub artList
	# the folder.jpg files this machine has, from its database
	# and the filesystem, as { folder_id => {path,size,mtime} }
{
	my ($dbh) = @_;
	my $art = {};
	my $folders = artFolders($dbh);
	for my $id (keys %$folders)
	{
		my $path = $folders->{$id};
		my @info = stat("$mp3_dir/".dbToFilePath($path)."/folder.jpg");
		next if !@info;
		$art->{$id} = { path => $path, size => $info[7], mtime => $info[9] };
	}
	return $art;
}


sub trackList
	# { id => {path,size,file_md5,timestamp} }
{
	my ($dbh) = @_;
	my $tracks = {};
	my $recs = get_records_db($dbh,"SELECT id,path,size,file_md5,timestamp FROM tracks WHERE is_local=1");
	for my $rec (@$recs)
	{
		$tracks->{$rec->{id}} = $rec;
	}
	return $tracks;
}


#-----------------------------------------------
# source side
#-----------------------------------------------

sub sourceInfo
{
	my $dbh = db_connect();
	my $art = artList($dbh);
	db_disconnect($dbh);
	my @art_list;
	for my $id (sort keys %$art)
	{
		push @art_list, {
			id => $id,
			size => $art->{$id}->{size},
			mtime => $art->{$id}->{mtime} };
	}
	return {
		db_md5 => fileMD5("$data_dir/artisan.db"),
		playlists_md5 => fileMD5("$data_dir/playlists.txt"),
		art => \@art_list };
}


sub sourceRequest
	# /sync/info, /sync/db, /sync/playlists, /sync/art/<path>
{
	my ($request,$what) = @_;
	display($dbg_sync,0,"sourceRequest($what)");

	if ($what eq 'info')
	{
		return json_response($request,sourceInfo());
	}
	elsif ($what eq 'db')
	{
		return Pub::HTTP::Response->new($request,
			{filename => "$data_dir/artisan.db"},
			200,'application/octet-stream');
	}
	elsif ($what eq 'playlists')
	{
		return Pub::HTTP::Response->new($request,
			{filename => "$data_dir/playlists.txt"},
			200,'text/plain');
	}
	elsif ($what =~ s/^art\///)
	{
		my $id = $what;
		my $folder = $local_library->getFolder($id);
		return http_error($request,"no folder for art id($id)")
			if !$folder;
		my $filename = "$mp3_dir/".dbToFilePath($folder->{path})."/folder.jpg";
		return http_error($request,"no art at $folder->{path}")
			if !-f $filename;
		return Pub::HTTP::Response->new($request,
			{filename => $filename},
			200,'image/jpeg');
	}
	return http_error($request,"unknown sync source request($what)");
}


#-----------------------------------------------
# player side: requests
#-----------------------------------------------

sub syncRequest
	# /sync/plan, /sync/start, /sync/cancel
{
	my ($request,$what) = @_;
	display($dbg_sync,0,"syncRequest($what)");

	return json_error($request,"this machine is the librarian")
		if $librarian_dir;

	if ($what eq 'plan')
	{
		return json_error($request,"$busy in progress") if $busy;
		my ($plan,$err) = makePlan();
		return json_error($request,$err) if $err;
		return json_response($request,$plan);
	}
	elsif ($what eq 'start')
	{
		return json_error($request,"$busy in progress") if $busy;
		resetState();
		setBusy('sync');
		my $thread = threads->create(\&runSync);
		$thread->detach();
		return json_response($request,{ started => 1 });
	}
	elsif ($what eq 'cancel')
	{
		return json_error($request,"no sync in progress")
			if $busy ne 'sync';
		display($dbg_sync,0,"sync cancel requested");
		$sync{cancel} = 1;
		return json_response($request,{ cancel => 1 });
	}
	elsif ($what eq 'restart')
	{
		return json_error($request,"sync is not done")
			if $busy ne 'sync' || $sync{step} ne 'done';
		setStep('restart');
		LOG(0,"sync restarting service");
		restartService('artisan');
		return json_response($request,{ restart => 1 });
	}
	return json_error($request,"unknown sync request($what)");
}


#-----------------------------------------------
# fetch
#-----------------------------------------------

sub sourceBase
{
	my $ip = getPref('MASTER_LIBRARY_IP') || '';
	return '' if !$ip;
	return "http://$ip:$SOURCE_PORT";
}


sub newUA
{
	my $ua = LWP::UserAgent->new(timeout => $FETCH_TIMEOUT);
	$ua->agent($USER_AGENT);
	return $ua;
}


sub fetchToFile
	# GET $url into $filename, calling $cb with each chunk's length.
	# Returns '' or an error message.
{
	my ($ua,$url,$filename,$cb) = @_;
	display($dbg_sync+1,1,"fetch $url");
	my $fh;
	return "could not create $filename: $!"
		if !open($fh,'>:raw',$filename);
	my $resp = $ua->get($url, ':content_cb' => sub {
		my ($chunk) = @_;
		print $fh $chunk;
		&$cb(length($chunk)) if $cb;
	});
	close $fh;
	if (!$resp->is_success())
	{
		unlink $filename;
		return "$url: ".$resp->status_line();
	}
	return '';
}


sub fetchJson
{
	my ($ua,$url) = @_;
	my $resp = $ua->get($url);
	return (undef,"$url: ".$resp->status_line()) if !$resp->is_success();
	my $data = my_decode_json($resp->content());
	return (undef,"$url: bad json") if !$data;
	return ($data,'');
}


#-----------------------------------------------
# plan
#-----------------------------------------------

sub makePlan
	# fetch the librarian's info and database into the tmpfs
	# and compute the diff.  Returns ($plan,$error).
	# The plan holds the lists and totals; it is returned by
	# /sync/plan and used by runSync().
{
	my $base = sourceBase();
	return (undef,"no MASTER_LIBRARY_IP in this player's artisan.prefs")
		if !$base;

	my $ua = newUA();
	my ($info,$err) = fetchJson($ua,"$base/sync/info");
	return (undef,"MASTER_LIBRARY_IP ".getPref('MASTER_LIBRARY_IP').
		" is not answering: $err") if $err;

	my $src_db = "$temp_dir/sync_artisan.db";
	my $src_pl = "$temp_dir/sync_playlists.txt";
	$err = fetchToFile($ua,"$base/sync/db",$src_db);
	return (undef,$err) if $err;
	$err = fetchToFile($ua,"$base/sync/playlists",$src_pl);
	return (undef,$err) if $err;

	# tracks

	my $sdbh = db_connect($src_db);
	my $src = trackList($sdbh);
	my $src_folders = artFolders($sdbh);
	db_disconnect($sdbh);

	my $ldbh = db_connect();
	my $loc = trackList($ldbh);
	my $loc_art = artList($ldbh);
	db_disconnect($ldbh);

	my $plan = {
		add => [],
		remove => [],
		rename => [],
		art_add => [],
		art_remove => [],
		data => { db => 0, playlists => 0 },
		bytes => 0 };

	for my $id (sort { $src->{$a}->{path} cmp $src->{$b}->{path} } keys %$src)
	{
		my $s = $src->{$id};
		my $l = $loc->{$id};
		if ($l && $l->{path} ne $s->{path} && -f "$mp3_dir/".dbToFilePath($l->{path}))
		{
			push @{$plan->{rename}}, { id => $id, from => $l->{path}, to => $s->{path} };
			$l = { %$l, path => $s->{path} };
		}
		if (!$l ||
			$l->{file_md5} ne $s->{file_md5} ||
			!-f "$mp3_dir/".dbToFilePath($l->{path}))
		{
			push @{$plan->{add}}, {
				id => $id,
				path => $s->{path},
				size => $s->{size},
				file_md5 => $s->{file_md5},
				timestamp => $s->{timestamp} };
			$plan->{bytes} += $s->{size};
		}
	}
	for my $id (sort { $loc->{$a}->{path} cmp $loc->{$b}->{path} } keys %$loc)
	{
		next if $src->{$id};
		push @{$plan->{remove}}, $loc->{$id}->{path};
	}

	# art, by folder id; the path comes from the source database
	# (the same bytes as the local one), never from the json

	my $src_art = {};
	for my $a (@{$info->{art}})
	{
		$src_art->{$a->{id}} = $a;
	}
	for my $id (sort { $src_folders->{$a} cmp $src_folders->{$b} } keys %$src_art)
	{
		my $s = $src_art->{$id};
		my $l = $loc_art->{$id};
		my $path = $src_folders->{$id};
		next if !$path;
		next if $l &&
			$l->{size} == $s->{size} &&
			abs($l->{mtime} - $s->{mtime}) <= 2;
		push @{$plan->{art_add}}, {
			id => $id,
			path => $path,
			size => $s->{size},
			mtime => $s->{mtime} };
		$plan->{bytes} += $s->{size};
	}
	for my $id (sort { $loc_art->{$a}->{path} cmp $loc_art->{$b}->{path} } keys %$loc_art)
	{
		next if $src_art->{$id};
		push @{$plan->{art_remove}}, $loc_art->{$id}->{path};
	}

	# data

	$plan->{data}->{db} = fileMD5("$data_dir/artisan.db") ne $info->{db_md5} ? 1 : 0;
	$plan->{data}->{playlists} = fileMD5("$data_dir/playlists.txt") ne $info->{playlists_md5} ? 1 : 0;

	$plan->{files} =
		scalar(@{$plan->{add}}) +
		scalar(@{$plan->{art_add}});
	$plan->{source} = getPref('MASTER_LIBRARY_IP');

	display($dbg_sync,0,"plan: add(".scalar(@{$plan->{add}}).
		") remove(".scalar(@{$plan->{remove}}).
		") rename(".scalar(@{$plan->{rename}}).
		") art_add(".scalar(@{$plan->{art_add}}).
		") art_remove(".scalar(@{$plan->{art_remove}}).
		") db($plan->{data}->{db}) playlists($plan->{data}->{playlists})".
		" bytes($plan->{bytes})");

	return ($plan,'');
}


#-----------------------------------------------
# run
#-----------------------------------------------

sub cancelled
{
	return 0 if !$sync{cancel};
	setError("cancelled");
	return 1;
}


sub runSync
	# the thread.  Each step sets sync_step; any error stops
	# the run with sync_step at that step and sync_error set.
{
	my $err = eval { doSync() };
	$err = "died: $@" if $@;
	if ($err)
	{
		setError($err) if !$sync{error};
		clearBusy();
		return;
	}
	setStep('done');
	LOG(0,"sync done; waiting for the operator to restart");
	# busy stays set until /sync/restart; the restart clears everything
}


sub doSync
	# returns '' or an error message
{
	my $staging = stagingDir();

	# 1. fetch and 2. plan

	setStep('fetch');
	my ($plan,$err) = makePlan();
	return $err if $err;
	setStep('plan');
	return "cancelled" if cancelled();

	$sync{files_total} = $plan->{files};
	$sync{bytes_total} = $plan->{bytes};

	my $base = sourceBase();
	my $ua = newUA();

	# 3. pull

	setStep('pull');
	my_mkdir($staging) if !-d $staging;
	my_mkdir("$staging/art") if !-d "$staging/art";

	# discard anything in staging that is not a verified file
	# from a previous run

	my %keep;
	for my $add (@{$plan->{add}})
	{
		$keep{$add->{id}} = $add;
	}
	if (opendir(my $dh,$staging))
	{
		for my $entry (readdir($dh))
		{
			next if $entry =~ /^\./ || $entry eq 'art';
			my $filename = "$staging/$entry";
			my $add = $keep{$entry};
			if (!$add || -s $filename != $add->{size} ||
				fileMD5($filename) ne $add->{file_md5})
			{
				display($dbg_sync,1,"discarding staged $entry");
				unlink $filename;
			}
		}
		closedir $dh;
	}

	for my $add (@{$plan->{add}})
	{
		return "cancelled" if cancelled();
		my $filename = "$staging/$add->{id}";
		$sync{current} = $add->{path};
		$sync{current_size} = $add->{size};
		$sync{current_done} = 0;
		if (-f $filename)
		{
			display($dbg_sync,1,"staged already: $add->{path}");
			$sync{bytes_done} += $add->{size};
		}
		else
		{
			display($dbg_sync+1,1,"pull $add->{path}");
			my $err = fetchToFile($ua,"$base/media/$add->{id}.mp3",$filename,
				sub { $sync{bytes_done} += $_[0]; $sync{current_done} += $_[0]; });
			return $err if $err;
			my $md5 = fileMD5($filename);
			if ($md5 ne $add->{file_md5})
			{
				unlink $filename;
				return "md5 mismatch on $add->{path}";
			}
			utime $add->{timestamp},$add->{timestamp},$filename
				if $add->{timestamp};
		}
		$sync{files_done}++;
	}

	for my $art (@{$plan->{art_add}})
	{
		return "cancelled" if cancelled();
		my $filename = "$staging/art/$art->{id}";
		$sync{current} = "$art->{path}/folder.jpg";
		$sync{current_size} = $art->{size};
		$sync{current_done} = 0;
		my $url = "$base/sync/art/$art->{id}";
		my $err = fetchToFile($ua,$url,$filename,
			sub { $sync{bytes_done} += $_[0]; $sync{current_done} += $_[0]; });
		return $err if $err;
		return "size mismatch on $art->{path}/folder.jpg"
			if -s $filename != $art->{size};
		utime $art->{mtime},$art->{mtime},$filename;
		$sync{files_done}++;
	}
	$sync{current} = '';

	# 4. place

	setStep('place');
	for my $add (@{$plan->{add}})
	{
		my $from = "$staging/$add->{id}";
		my $to = "$mp3_dir/".dbToFilePath($add->{path});
		my_mkdir($to,1);
		return "could not place $add->{path}: $!"
			if !rename($from,$to);
	}
	for my $art (@{$plan->{art_add}})
	{
		my $from = "$staging/art/$art->{id}";
		my $to = "$mp3_dir/".dbToFilePath($art->{path})."/folder.jpg";
		my_mkdir($to,1);
		return "could not place $art->{path}/folder.jpg: $!"
			if !rename($from,$to);
	}

	# 5. rename, in two passes through staging so that
	# swapped paths cannot collide

	setStep('rename');
	my %old_dirs;
	for my $ren (@{$plan->{rename}})
	{
		my $from = "$mp3_dir/".dbToFilePath($ren->{from});
		my $tmp = "$staging/$ren->{id}";
		return "could not rename $ren->{from}: $!"
			if !rename($from,$tmp);
		$old_dirs{pathOf($from)} = 1;
	}
	for my $ren (@{$plan->{rename}})
	{
		my $tmp = "$staging/$ren->{id}";
		my $to = "$mp3_dir/".dbToFilePath($ren->{to});
		my_mkdir($to,1);
		return "could not rename to $ren->{to}: $!"
			if !rename($tmp,$to);
	}

	# 6. remove

	setStep('remove');
	for my $path (@{$plan->{remove}})
	{
		my $filename = "$mp3_dir/".dbToFilePath($path);
		if (-f $filename)
		{
			return "could not remove $path: $!"
				if !unlink($filename);
		}
		$old_dirs{pathOf($filename)} = 1;
	}
	for my $path (@{$plan->{art_remove}})
	{
		my $dir = "$mp3_dir/".dbToFilePath($path);
		my $filename = "$dir/folder.jpg";
		unlink($filename) if -f $filename;
		$old_dirs{$dir} = 1;
	}
	removeEmptyDirs(\%old_dirs);

	# 7. data

	setStep('data');
	if ($plan->{data}->{playlists})
	{
		return "could not copy playlists.txt: $!"
			if !copy("$temp_dir/sync_playlists.txt","$data_dir/playlists.txt");
	}
	if ($plan->{data}->{db})
	{
		my $new_db = "$data_dir/artisan.db.new";
		return "could not copy artisan.db: $!"
			if !copy("$temp_dir/sync_artisan.db",$new_db);
		return "could not replace artisan.db: $!"
			if !rename($new_db,"$data_dir/artisan.db");
	}

	# staging is empty of files now; remove it

	rmdir "$staging/art";
	rmdir $staging;

	LOG(0,"sync done: ".$sync{files_done}." files, ".$sync{bytes_done}." bytes");
	return '';
}


sub removeEmptyDirs
	# remove any of the given directories that are now empty,
	# and their parents up to but not including $mp3_dir
{
	my ($dirs) = @_;
	my @list = sort { length($b) <=> length($a) } keys %$dirs;
	for my $dir (@list)
	{
		while ($dir && length($dir) > length($mp3_dir) && $dir =~ /^\Q$mp3_dir\E\//)
		{
			last if !-d $dir;
			last if !rmdir($dir);
			display($dbg_sync,1,"removed empty ".mp3_relative($dir));
			$dir = pathOf($dir);
		}
	}
}


1;
