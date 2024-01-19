#!/usr/bin/perl
#---------------------------------------
# Update.pm
#---------------------------------------
# Check for local and remote GIT changes, allowing
# for UI to choose to "stash" local changes if neeeded.

package Update;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;

my $WAIT_FOR_UPDATE = 20;


my $dbg_git = -1;
my $dbg_checks = -1;
my $dbg_update = -1;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		checkForUpdates
		$update_available
		$stash_needed
		doUpdates
	);
}


my $in_update:shared = 0;

my $update_available:shared = 0;
my $stash_needed:shared = 0;



sub checkForUpdates
{
	return if $in_update;
	$in_update = 1;
	display($dbg_checks+1,0,"checkForUpdates()");
	my $thread = threads->create(\&checkUpdatesThread);
	$thread->detach();
}



sub checkUpdatesThread
{
	display($dbg_checks+1,0,"checkUpdatesThread() started");
	checkDoUpdate(0,'/base/apps/artisan');
	checkDoUpdate(0,'/base/Pub');
	$in_update = 0;
	display($dbg_checks+1,0,"checkUpdatesThread() finished");
}



sub gitCommand
	# reports error and and returns 0 if an error detected
	# returns 1 and sets $retval from the command otherwise
{
	my ($doit,$repo,$command,$retval) = @_;
	$$retval = '' if $retval;
	display($doit?0:$dbg_git,0,"gitCommand($command)");
	my $rslt = `git -C $repo $command 2>&1`;
	if ($rslt =~ /error/si)
	{
		error("repo($repo) command($command) $rslt");
		return 0;
	}
	display($doit?0:$dbg_git+1,0,"rslt=$rslt");
	$$retval = $rslt if $retval;
	return 1;
}



sub checkDoUpdate
{
	my ($doit,$repo) = @_;
	display($dbg_checks+1,0,"checkUpdate($doit,$repo)");

	# no text

	my $text = '';
	my $this_available = 0;
	my $this_stash_needed = 0;

	return 0 if !gitCommand($doit,$repo,'remote update');
	return 0 if !gitCommand($doit,$repo,'status',\$text);
	if ($text =~ /Your branch is behind .* and can be fast-forwarded/)
	{
		display($dbg_checks,0,"UPDATE_NEEDED($repo)",0,$UTILS_COLOR_MAGENTA);
		$this_available = 1;
		$update_available = 1;
	}
	if ($this_available)
	{
		return 0 if !gitCommand($doit,$repo,'diff',\$text);
		if ($text)
		{
			display($dbg_checks,0,"STASH_NEEDED($repo)",0,$UTILS_COLOR_MAGENTA);
			$this_stash_needed = 1;
			$stash_needed = 1;
		}
		if ($doit)
		{
			return 0 if $this_stash_needed && !gitCommand($doit,$repo,'stash');
			return 0 if !gitCommand($doit,$repo,'pull');
		}
	}

	return 1;
}



sub doUpdates
{
	my $start = time();
	LOG(0,"DOING UPDATES");
	while ($in_update)
	{
		display(0,1,"waiting for in_update to clear");
		if (time() > $start + $WAIT_FOR_UPDATE)
		{
			error("Timed out waiting for in_update to clear");
			return 0;
		}
		sleep(1);
	}

	if (checkDoUpdate(1,'/base/Pub') &&
		checkDoUpdate(1,'/base/apps/artisan'))
	{
		LOG(0,"UPDATE COMPLETED");
		$update_available = 0;
		$stash_needed = 0;
		return 1;
	}

	return 0;
}



1;
