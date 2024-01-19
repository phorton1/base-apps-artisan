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


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw(
		doUpdates
	);
}




sub gitCommand
	# reports error and and returns 0 if an error detected
	# returns 1 and sets $retval from the command otherwise
{
	my ($repo,$command,$retval,$no_error) = @_;
	$$retval = '' if $retval;
	display($dbg_git,0,"gitCommand($command)");
	my $rslt = `git -C $repo $command 2>&1`;
	if (!$no_error && $rslt =~ /error/si)
	{
		error("repo($repo) command($command) $rslt");
		return 0;
	}
	display($dbg_git+1,0,"rslt=$rslt");
	$$retval = $rslt if $retval;
	return 1;
}



sub updateOne
{
	my ($repo) = @_;
	display($dbg_update+1,0,"updateOne($repo)");

	# no text

	my $text = '';
	my $stash = 0;

	return 0 if !gitCommand($repo,'remote update');
	return 0 if !gitCommand($repo,'status',\$text);

	if ($text =~ /Your branch is behind .* and can be fast-forwarded/)
	{
		LOG(-2,"UPDATING($repo)");
		return 0 if !gitCommand($repo,'diff',\$text,1);
		return 0 if $text && !gitCommand($repo,'stash');
		return 0 if !gitCommand($repo,'pull');
	}

	return 1;
}



sub doUpdates
{
	LOG(-1,"UPDATING SYSTEM");
	if (updateOne('/base/Pub') &&
		updateOne('/base/apps/artisan'))
	{
		LOG(-1,"UPDATE COMPLETE");
		return 1;
	}
	return 0;
}



1;
