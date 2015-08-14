#---------------------------------------
# Deamon.pm
#---------------------------------------

package Daemon;
use strict;
use warnings;
use POSIX qw(setsid);
use Fcntl ':flock';
use Utils;
use SSDP;



sub daemonize
{
	my ($SIG,$ssdp) = @_;
	display(2,0,'deamonize() called ...');

	# SIGNAL HANDLING GOT MESSED UP (currently not able to call ref of a function)

	$SIG{'INT'} = sub
	{
		LOG(-1,"SIG_INT - Shutting down $program_name ...");
		$$ssdp->send_byebye(4);
		# remove_pidfile($CONFIG{'PIDFILE'});
		exit(1);
	};
    #	$SIG{'INT'}  = \&exit_daemon();
    #	$SIG{'HUP'}  = \&exit_daemon();
    #	$SIG{'ABRT'} = \&exit_daemon();
    #	$SIG{'QUIT'} = \&exit_daemon();
    #	$SIG{'TRAP'} = \&exit_daemon();
    #	$SIG{'STOP'} = \&exit_daemon();
    #	$SIG{'TERM'} = \&exit_daemon();
	$SIG{'TERM'} = sub
	{
		LOG(-1,"SIG_TERM - Shutting down $program_name ...");
		$$ssdp->send_byebye(4);
		# remove_pidfile($CONFIG{'PIDFILE'});
		exit(1);
	};
	$SIG{'PIPE'} = 'IGNORE'; # SIGPIPE Problem: http://www.nntp.perl.org/group/perl.perl5.porters/2004/04/msg91204.html

	my $pid = fork;
	exit if $pid;
	die "Couldn't fork: $!" unless defined($pid);
}



sub exit_daemon
{
	LOG(-1,"exit_daemon() - Shutting down $program_name ...");
    # $$ssdp->send_byebye(4);
	# remove_pidfile($CONFIG{'PIDFILE'});
	exit(1);
}


sub write_pidfile
{
	my $pidfile = $_[0];
	my $pid = $_[1];
	open(FILE, ">$pidfile");
	flock(FILE, LOCK_EX);
	print FILE $pid;
	flock(FILE, LOCK_UN);
	close(FILE);
}


sub read_pidfile
{
	my $pidfile = $_[0];
	my $pid = -1;
	if (-e $pidfile)
	{
		open(FILE, $pidfile);
		$pid = <FILE>;
		close(FILE);
	}
	chomp ($pid);
	return $pid;
}


sub remove_pidfile
{
	my $pidfile = $_[0];
	if (-e $pidfile)
	{
		unlink($pidfile);
	}
}


1;
