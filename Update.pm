#!/usr/bin/perl
#---------------------------------------
# Update.pm
#---------------------------------------
# Check for GIT updates and apply them

package Update;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;

my $dbg_upd = 0;
my $dbg_checks = -1;

my $SHOW_UNSTAGED_ERROR = 1;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		checkForUpdates
		updateAvailable
	);
}


my $in_update_check:shared = 0;
my $pub_needed:shared = 0;
my $artisan_needed:shared = 0;

sub updateAvailable
{
	return $pub_needed || $artisan_needed;
}



sub checkForUpdates
{
	if ($in_update_check)
	{
		error("checkForUpdates() re-entered");
		return;
	}
	if (!$pub_needed || !$artisan_needed)
	{
		$in_update_check = 1;
		display($dbg_checks+1,0,"checkForUpdates()");
		my $thread = threads->create(\&checkUpdatesThread);
		$thread->detach();
	}
	else
	{
		display($dbg_checks+1,0,"checkForUpdates() both already needed");
	}
}



sub checkUpdatesThread
{
	display($dbg_checks+1,0,"checkUpdatesThread() started");
	return if !$pub_needed && !checkUpdate('/base/Pub',\$pub_needed);
	return if !$artisan_needed && !checkUpdate('/base/apps/artisan',\$artisan_needed);
	$in_update_check = 0;
	display($dbg_checks+1,0,"checkUpdatesThread() finished");
}


sub checkUpdate
	# returns 1 on success
	# returns 0 on error
	# sets var if update is needed
{
	my ($repo,$update_needed) = @_;
	display($dbg_checks+1,0,"checkUpdate($repo)");

	# 'remote update' can return blank if no remote update needed

	my $text = '';
	return 0 if !gitCommand(\$text,$repo,'remote update',$dbg_checks);
	return 1 if !$text;

	return 0 if !gitCommand(\$text,$repo,'status',$dbg_checks);
	if (!$text)
	{
		error("unexpected blank result from git(status) $repo");
		return 0;
	}

	if ($text =~ /Your branch is behind .* and can be fast-forwarded/)
	{
		display($dbg_checks,0,"UPDATE_NEEDED($repo)",0,$UTILS_COLOR_MAGENTA);
		$$update_needed = 1;
	}
	return 1;
}


sub gitCommand
	# reports error and and returns 0 if an error detected
	# returns 1 and sets $retval from the command otherwise
{
	my ($retval,$repo,$command,$dbg) = @_;
	$dbg ||= 0;
	$$retval = '';
	display($dbg,0,"gitCommand($command)");
	my $rslt = `git -C $repo $command 2>&1`;
	if ($rslt =~ /error/si)
	{
		error("repo($repo) command($command) $rslt");
		return 0;
	}
	display($dbg,0,"rslt=$rslt");
	$$retval = $rslt;
	return 1;
}



1;
