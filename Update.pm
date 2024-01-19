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


my $dbg_git = 0;
my $dbg_update = 0;


sub gitCommand
	# reports error and and returns 0 if an error detected
	# returns 1 and sets $retval from the command otherwise
{
	my ($repo,$command,$retval,$no_error) = @_;
	display($dbg_git,0,"gitCommand($repo) $command");
	my $rslt = `git -C $repo $command 2>&1`;
	$$retval = $rslt;
	if (!$no_error && $rslt =~ /error/si)
	{
		error("repo($repo) command($command) $rslt");
		return 0;
	}
	display($dbg_git+1,0,"rslt=$rslt");
	return 1;
}


sub updateOne
	# returns -1 on error, 0 if no update needed, 1 if update done
	# last result from git will be in $text if there is an error
{
	my ($repo,$text) = @_;
	display($dbg_update+1,0,"updateOne($repo)");
	return -1 if !gitCommand($repo,'remote update',$text);
	return -1 if !gitCommand($repo,'status',$text);
	if ($$text =~ /Your branch is behind .* and can be fast-forwarded/)
	{
		return -1 if !gitCommand($repo,'diff',$text,1);
		return -1 if $$text && !gitCommand($repo,'stash',$text);
		return -1 if !gitCommand($repo,'pull',$text);
		return 1;
	}
	return 0;
}


sub doSystemUpdate
	# returns blank or an error message
{
	LOG(-1,"UPDATING SYSTEM");
	my $text = '';
	my $pub = updateOne('/base/Pub',$text);
	my $artisan = $pub >= 0 ?  updateOne('/base/apps/artisan',$text) : 0;
	if (!$pub && !$artisan)
	{
		$text = 'Nothing to do!';
		$pub = -1;
	}
	return $text if $pub<0 || $artisan<0;
	return '';
}


1;
