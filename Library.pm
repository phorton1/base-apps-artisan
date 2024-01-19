#!/usr/bin/perl
#---------------------------------------
# Library.pm
#---------------------------------------

package Library;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Device;
use base qw(Device);

my $dbg_lib = 1;


my $dbg_meta = 1;


BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
		new_section
		meta_item
		meta_section
		error_section
	);
};



sub new
{
	my ($class,$params) = @_;	# $is_local,$uuid,$friendlyName) = @_;
	display($dbg_lib,0,"Library::new()");
	$params->{type} ||= $DEVICE_TYPE_LIBRARY;
	my $this = $class->SUPER::new($params);
		# $is_local,
		# $DEVICE_TYPE_LIBRARY,
		# $uuid,
		# $friendlyName);
	bless $this,$class;
	return $this;
}





sub new_section
	# start a tag section
{
	my ($use_id,$section_name,$expanded) = @_;
	display($dbg_meta,1,"section $$use_id $section_name");
	my $section =
	{
		id  		=> $$use_id++,
		title       => '',
		TITLE       => $section_name,
		VALUE       => '',
		icon		=> 'false',
		expanded    => $expanded ? 'true' : 'false',
		children     => [],
	};

	$section->{expanded} = 'true' if $expanded;
	return $section;
}



sub meta_item
	# add an item to a section escaping and
	# cleaning up the lval and rval.
	# Note use of escape_tag()!!
{
	my ($use_id,$lval,$rval) = @_;

	$rval = "" if !defined($rval);
	$rval = escape_tag($rval);
	$rval =~ s/\\/\\\\/g;
	$rval =~ s/"/\\"/g;
	$lval =~ s/\\/\\\\/g;
	$lval =~ s/"/\\"/g;
	$lval =~ s/\t/ /g;

	$lval = substr($lval,0,13) if
		$lval !~ /<img src/ &&
		length($lval) > 13;

	display($dbg_meta,2,"item $$use_id  $lval = '$rval'");
	my $item = {
		id => $$use_id++,
		title => '',
		TITLE => $lval,
		VALUE => $rval,
		state => 'open',
		icon => 'false',	# $icon ? $icon : 'false',
	};

	return $item;
}


sub meta_section
	# create a json record for a section of the given name
	# for every lval, rval pais in a hash
{
	my ($use_id,$section_name,$expanded,$rec,$exclude) = @_;
	my $section = new_section($use_id,$section_name,$expanded);

	for my $lval (sort(keys(%$rec)))
	{
		my $rval = $$rec{$lval};
		next if $exclude && $lval =~ /$exclude/;
		push @{$section->{children}},meta_item($use_id,$lval,$rval);
	}
	return $section;
}



sub error_section
	# add a section that consists of an array of errors
{
	my ($use_id,$section_name,$state,$array) = @_;
	my $section = new_section($use_id,$section_name,$state);

	for my $rec (@$array)
	{
		my ($i,$lval,$rval) = (@$rec);
		my $icon = "/webui/images/error_$i.png";
		display($dbg_meta+2,0,"icon($lval)=$icon");
		my $html = "<img src='$icon' width='16' height='16'>&nbsp;$lval";
		push @{$section->{children}},meta_item($use_id,$html,$rval);
	}
	return $section;
}


1;