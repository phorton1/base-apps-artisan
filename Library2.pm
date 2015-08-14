#--------------------------------------------------------------
# Library (continued), Metadata, Virtual Directories and Files
#--------------------------------------------------------------

package Library;    # continued ...
use strict;
use warnings;
use threads;
use threads::shared;
use File::Basename;
use Utils;
use Database;
use MediaFile;



my %highest_error_tree_descriptor = (
	title => 'By Highest Error',
	icon => 'highest_error_icon.png',
	class_fxn => \&by_highest_error,
);

my %genre_tree_descriptor = (
	title => 'By Genre',
	icon => 'genre_icon.png',
	class_fxn => \&by_genre,
	#post_fxn => \&by_genre_post,
);


my %decade_tree_descriptor = (
	title => 'By Decade',
	icon => 'genre_icon.png',
	class_fxn => \&by_decade,
	#post_fxn => \&by_genre_post,
);


our %virtual_trees = (	
	'a' => \%genre_tree_descriptor,
	'b' => \%decade_tree_descriptor,
	'c' => \%highest_error_tree_descriptor,
);




#---------------------------------------------------
# FrameWork
#---------------------------------------------------
# build them in memory first

sub init_virtual_tree
{
	my ($tree) = @_;
	$tree->{vitem_by_vid} = {};
	$tree->{vitem_by_path} = {};
	$tree->{next_idx} = 1;
}


sub get_folder_by_path
{
	my ($params,$path) = @_;
	return $params->{folders}->{$path};
}

sub get_track_by_path
{
	my ($params,$path) = @_;
	return $params->{tracks}->{$path};
}



sub create_virtual_path
	# utility to create virtual nodes as needed
	# to map the REAL TRACK at "$ignore_part/$map_part",
	# into the virtual tree given by the $prefix at the
	# front of $virtual part
{
	my ($params,$virtual_part,$ignore_part,$map_part) = @_;
	display($dbg_vlibrary+1,0,"create_virtual_path($virtual_part,$ignore_part,$map_part");
	
	# $virtual_part =~ s/^\//;
	
	my @vparts = split(/\//,$virtual_part);
	my $prefix = $vparts[1];
	my $vtree = $virtual_trees{$prefix};
	my $vitem_by_vid = $vtree->{vitem_by_vid};
	my $vitem_by_path = $vtree->{vitem_by_path};
	
	# create the virtual folders if they don't yet exist
	# example does this in memory, but will be in database
	# assumes that the virtual root, a0, already exists
	
	my $vid = 0;
	my $vitem;
	my $vpath = "";
	# /$prefix";
	
	for my $vpart (@vparts)
	{
		next if (!$vpart);
		my $parent_vid = $vid;
		$vpath .= "/$vpart";
		$vitem = $vitem_by_path->{$vpath};

		#dbg_hash(3,1,'vid_by_path',$vid_by_path);
		display($dbg_vlibrary+2,1,"check vpath($vpath)=".(defined($vid) ? $vid : 'undef'));

		if (!defined($vitem))
		{
			$vitem  = new_vitem(
				$params,
				$prefix,
				'virt_folder',
				$parent_vid,
				$vpath,
				0,
				$vpart );
			return if (!$vitem);
		}
		else
		{
			display($dbg_vlibrary+2,1,"vexists($vid) vpath=$vpath");
		}
		$vid = $vitem->{ID};
	}
	
	# At this point we have the virtual id of
	# the virtual folder that will serve as the
	# parent of the referenced virtual items.
	# Map the real folders to (possibly new) virtual
	# folders, and bump the parent's num_elements
	
	my $part_num = 0;
	my @mparts = split(/\//,$map_part);
	my $real_path = $ignore_part;
	for my $mpart (@mparts)
	{
		my $parent_vid = $vid;
		$vpath .= "/$mpart";
		$real_path .= "/$mpart";
		$vitem = $vitem_by_path->{$vpath};

		my $type =
			$part_num == @mparts - 1 ? 'ref_track' :
			$part_num == @mparts - 2 ? 'ref_album' :
			'ref_folder';
			
		if (!$vitem)
		{
			# get the real folder of the item
			
			my $real_item = $type =~ /track/ ?
				get_track_by_path($params,$real_path)  :
				get_folder_by_path($params,$real_path) ;
				
			if (!$real_item)
			{
				error("Could not get real_item($type) for path=$real_path");
				return;
			}

			$vitem = new_vitem(
				$params,
				$prefix,
				$type,
				$parent_vid,
				$vpath,
				$real_item->{ID});
			return if (!$vitem);
		}
		else
		{
			display($dbg_vlibrary+2,1,"mexists($vid) vpath=$vpath");
		}
		$vid = $vitem->{ID};
		$part_num ++;
	}
		
	return $vitem;
}



sub new_vitem
	# utility to create new virtual item cannot fail
	# returns the vid of the new item
{
	my ($params,
		$prefix,		# a,b,c, etc
		$type,			# virt_folder, ref_folder, ref_album, ref_track
		$parent_vid,    # the numeric parent vid (no prefix)
		$vpath,         # the virtual path (titles separated by /'s)
		$ref_id,		# optional reference to real thing
		$title) = @_;	# optional virtual title

	$ref_id ||= '';
	$title ||= '';
	my $vtree = $virtual_trees{$prefix};
	my $vid = get_next_index($params,$prefix);
	display($dbg_vlibrary+1,1,"new_vitem($prefix,$type,$parent_vid,$ref_id,$title)=$vid  vpath=$vpath");

	my $rec = db_init_rec('VITEMS');
	$rec->{prefix}    	= $prefix,
	$rec->{type}      	= $type,
	$rec->{ID}		  	= $vid,
	$rec->{PARENT_ID} 	= $parent_vid,
	$rec->{FULLPATH}    = $vpath;
	$rec->{NUM_ELEMENTS} = 0;
	$rec->{TITLE} 		= $title if ($title);
	$rec->{ref_id} 		= $ref_id if ($ref_id);
	$rec->{new} = 1;
	
	# bump parent count and stats
	
	my $parent = $vtree->{vitem_by_vid}->{$parent_vid};
	if ($parent)
	{
		$parent->{NUM_ELEMENTS}++
	}
	else
	{
		# warning(0,0,"no parent($parent_vid) to bump for($vid)");
	}
	
	bump_stat("vitems_created($prefix)");
	
	# add it to the tree
	
	add_to_vtree($vtree,$rec);
	display($dbg_vlibrary+1,0,"new_vitem() returning vid=$vid");
	return $rec;
}
	
	
sub add_to_vtree
{
	my ($vtree,$rec) = @_;
	$vtree->{vitem_by_vid}->{$rec->{ID}} = $rec;
	$vtree->{vitem_by_path}->{$rec->{FULLPATH}} = $rec;
}



sub get_next_index
	# probably a lot faster to do this in memory
{
	my ($params,$prefix) = @_;
	my $vtree = $virtual_trees{$prefix};
	$vtree->{next_idx} ||= 1;
	return $prefix.$vtree->{next_idx}++;
}
	
	
	

sub build_virtual_tree
{
	my ($params,$prefix) = @_;
	LOG(0,"build_virtual_tree($prefix)");
	my $vtree = $virtual_trees{$prefix};
	my $class_fxn = $vtree->{class_fxn};

	init_virtual_tree($vtree);
	
	# get the existing database records, if any
	
	my $vitems = get_records_db($params->{dbh},"SELECT * FROM VITEMS WHERE prefix='$prefix'");
	if ($vitems && @$vitems)
	{
		bump_stat("vitems_existing($prefix)",scalar(@$vitems));
		display($dbg_vlibrary,0,"found ".scalar(@$vitems)." existing vitems for vtree($prefix)");
		for my $vitem (@$vitems)
		{
			my $vid = $vitem->{ID};			
			display($dbg_vlibrary+1,1,"vitem($vid,$vitem->{type},$vitem->{PARENT_ID}) = $vitem->{FULLPATH}");
			add_to_vtree($vtree,$vid,$vitem);
			$vid =~ s/^$prefix//;
			$vtree->{next_idx} = $vid if $vid > $vtree->{next_idx};
		}
	}
	
	# create the root node if it doesn't exist
	
	my $root = "/$prefix";
	my $root_vid = $vtree->{vid_by_path}->{$root};
	#dbg_hash(3,1,'vid_by_path',$vtree->{vid_by_path});
	
	if (!defined($root_vid))
	{
		display($dbg_vlibrary,0,"creating new root vid($root)");
		my $vitem = new_vitem(
			$params,
			$prefix,
			'virt_folder',
			0,				# parent
			"/$prefix",		# path
			undef,			# ref_id,
			$vtree->{title});
		return if (!$vitem);
		
		if ($vitem->{ID} ne $prefix.'1')
		{
			error("huh? created root virtual item and it's ID is not '$prefix"."1': $vitem->{ID}");
			return;
		}
	}

	#---------------------------------------------
	# scan the tracks
	#---------------------------------------------
	
	my $tracks = $params->{tracks};
	for my $tid (sort(keys(%$tracks)))
	{
		return if !&$class_fxn($params,$prefix,$tracks->{$tid});
	}

	# add the newly built records to the database
	# see kludge note about 'ID' field in insert_record_db()

	display($dbg_vlibrary+1,0,"------------------------------------------------");
	display($dbg_vlibrary,0,"writing records to database");
	display($dbg_vlibrary+1,,0,"------------------------------------------------");
	
	my $vitems_by_path = $vtree->{vitem_by_path};
	for my $path (sort(keys(%$vitems_by_path)))
	{
		my $vitem = $vitems_by_path->{$path};
		next if (!$vitem->{new});
		display($dbg_vlibrary+1,1,"$vitem->{ID}  $vitem->{FULLPATH}");
		if (!insert_record_db($params->{dbh},'VITEMS',$vitem,'ID'))
		{
			error("Could not insert VITEM($vitem->{ID}:$vitem->{FULLPATH})");
			# return;
		}
		bump_stat("vitems($prefix)_written_to_db");
	}
	
	$params->{dbh}->commit();
	
	# cleanup memory and return
	
	init_virtual_tree($vtree);
	return 1;
	
}	# build_virtual_tree



#----------------------------------------------------
# virtual accessors
#----------------------------------------------------

sub add_virtual_roots
{
	my ($dbh,$recs) = @_;
	my $roots = get_records_db($dbh,"SELECT * FROM VITEMS WHERE PARENT_ID='0' ORDER BY prefix");
	display($dbg_vlibrary,0,"adding ".scalar(@$roots)." virtual roots");
	for my $rec (@$roots)
	{
		resolve_item($dbh,'virt_root',$rec,1);
	}
	
	push @$recs,@$roots;
}


sub get_virtual_item
{
	my ($dbh,$table,$vid) = @_;
	display($dbg_vlibrary,0,"get_virtual_item($table,$vid)");
	my $item = get_record_db($dbh,"SELECT * FROM VITEMS WHERE ID='$vid'");
	if (!$item)
	{
		error("Could not get $table($vid)");
		return;
	}
	return resolve_item($dbh,$table,$item,0);
}



sub resolve_item
{
	my ($dbh,$table,$item,$as_subitems) = @_;
	display($dbg_vlibrary+1,0,"resolve_item($table,$item->{ID})");
	if ($table eq 'TRACKS' && $item->{type} ne 'ref_track')
	{
		error("resolve_item_$table($item->{ID}) expected a ref_track, got '$item->{type}'");
		return;
	}

	# add any fields from the referenced 'real' item
	# IFF they don't already exist in the vitem
	
	my $ref_id = $item->{ref_id};
	if ($ref_id)
	{
		display($dbg_vlibrary+1,0,"resolving $table ref_id=$ref_id");
		my $rec = get_record_db($dbh,"SELECT * FROM $table WHERE ID=$ref_id");
		if (!$rec)
		{
			error("Could not get $table($item->{type}) from ref_id=$ref_id");
			return;
		}
		for my $k (keys(%$rec))
		{
			$$item{$k} = $$rec{$k} if (!$$item{$k});
		}
	}

	# add fields that are needed, but not represented
	# in the VITEMS database if they werent already
	# added from a ref'd item, even if just to prevent
	# undefined variable errors.
	
	my @parts = split(/\//,$item->{FULLPATH});
	my $name = pop @parts;
	my $path = join('/',@parts);
	$item->{NAME} = $name if (!$item->{NAME});
	$item->{PATH} = $path if (!$item->{PATH});
	$item->{DIRTYPE} ||= '';
	
	# debug or not?  Prepend the prefix the folder title
	
	my $vtree = $virtual_trees{$item->{prefix}};
	my $post_fxn = $vtree->{post_fxn};
	
	&$post_fxn($dbh,$item,$as_subitems) if ($post_fxn);
	
	display($dbg_vlibrary+1,0,"resolve_item($table,%item->{ID}) returning $item->{TITLE}");
	return $item;
}



sub get_virtual_subitems
{
	my ($dbh,$table,$vid,$start,$count) = @_;
	display($dbg_vlibrary+1,0,"get_virtual_subitems($table,$vid,$start,$count)");
	my $items = get_records_db($dbh,"SELECT * FROM VITEMS WHERE PARENT_ID='$vid' ORDER BY FULLPATH");
	
	if (!$items || !@$items)
	{
		error("No virtual subitems found for $table($vid)");
		return;
	}
	
	$start ||= 0;
	$count ||= 10;
	
	my @rslt;
	for my $item (@$items)
	{
		next if ($start-- > 0);
		last if ($count-- <= 0);
		push @rslt,resolve_item($dbh,$table,$item,1);
	}

	display($dbg_vlibrary,0,"get_virtual_subitems($table,$vid,$start,$count) returning ".scalar(@rslt)." items");
	return \@rslt;
	
}



#---------------------------------------------------
# Specific virtual trees
#---------------------------------------------------

my $display_highest = '';

sub by_highest_error
	# Called on every track in the database,
	# develops a virtual tree (a) of the subfolders
	# organized by the highest error code, combining
	# folders from /albums and /singles, but ignoring
	# /unresolved.
	#
	# So, we want to map
	#
	#    /mp3s/Blues/New/Blue by Nature - Blue To The Bone/01 - Cadillac Blues.mp3
	#
	# presented as
	#
	#    /By Highest Error/ERROR_NONE/Blues/New/Blue by Nature - Blue To The Bone/01 - Cadillac Blues.mp3
	#
	# and internally developed as
	#
	#    /a/ERROR_NONE/Blues/New/Blue by Nature - Blue To The Bone/01 - Cadillac Blues.mp3
{
	my ($dbh, $prefix, $track) = @_;
	my $fullname = $track->{FULLNAME};
	return 1 if $fullname =~ /\/unresolved\//;
	return 1 if $fullname =~ /\/singles\//;
	#return 1 if $fullname ge "$mp3_dir/albums/Classical";
	
	bump_stat("vitems($prefix)_scanned($prefix)");
	display($dbg_vlibrary+2,0,"by_highest_error($prefix,$track->{ID},$track->{TITLE}) in $track->{PATH}");
	
	my $highest_error = $track->{HIGHEST_ERROR};
	my $highest_desc  = severity_to_str($highest_error);
	
	my $map_part = $fullname;
	$map_part =~ s/^($mp3_dir_RE\/(albums|singles))\///;
	my $ignore_part = $1;
	my $virtual_part = "/$prefix/$highest_desc";

	return create_virtual_path($dbh,$virtual_part,$ignore_part,$map_part);
}
	
	
sub by_genre_post
{
	my ($dbh,$item,$as_subitems) = @_;
	my @parts = split(/\//,$item->{FULLPATH});
	
	# /a/genre/album/title.mp3
	
	if (@parts == 3)
	{
		$item->{TITLE} = "Genre($item->{TITLE})";
	}
}


sub by_genre
{
	my ($dbh, $prefix, $track) = @_;
	my $fullname = $track->{FULLNAME};
	return 1 if $fullname =~ /\/unresolved\//;
	return 1 if $fullname =~ /\/singles\//;
	#return 1 if $fullname ge "$mp3_dir/albums/Classical";
	
	bump_stat("vitems($prefix)_scanned($prefix)");
	display($dbg_vlibrary+2,0,"by_genre($prefix,$track->{ID},$track->{TITLE}) in $track->{PATH}");

	# remove any slashes (path separators) from genres
	# and create the 'ignore' and 'map' portion of the
	# path so that the mapped portion is just the album
	# This will group all albums together under the genre
	# losing track of where they came from
	
	my $genre = $track->{GENRE};
	$genre =~ s/\// /g;
	$genre = CapFirst($genre);
	 
	my @parts = split(/\//,$fullname);
	my $title = pop(@parts);
	my $album = pop(@parts);
	my $ignore_part = join('/',@parts);
	my $map_part = "$album/$title";
	my $virtual_part = "/$prefix/$genre";

	my $vitem = create_virtual_path($dbh,$virtual_part,$ignore_part,$map_part);
	
	# prh - would like to map the parent here
	
	return $vitem;
}



sub by_decade
{
	my ($dbh, $prefix, $track) = @_;
	my $fullname = $track->{FULLNAME};
	return 1 if $fullname =~ /\/unresolved\//;
	return 1 if $fullname =~ /\/singles\//;
	#return 1 if $fullname ge "$mp3_dir/albums/Classical";
	
	my $year = $track->{YEAR};
	return 1 if (!$year || $year !~ /^(\d\d\d\d)/);
	$year = $1;
	return 1 if ($year gt today());
	return 1 if ($year <= 1900);
	
	
	bump_stat("vitems($prefix)_scanned($prefix)");
	display($dbg_vlibrary+2,0,"by_decade($year) $track->{PATH}/$track->{NAME}");

	# remove any slashes (path separators) from genres
	# and create the 'ignore' and 'map' portion of the
	# path so that the mapped portion is just the album
	# This will group all albums together under the genre
	# losing track of where they came from
	

	$year = substr($year,0,3);
	$year .= "0's";
	
	my @parts = split(/\//,$fullname);
	my $title = pop(@parts);
	my $album = pop(@parts);
	my $ignore_part = join('/',@parts);
	my $map_part = "$album/$title";
	my $virtual_part = "/$prefix/$year";

	my $vitem = create_virtual_path($dbh,$virtual_part,$ignore_part,$map_part);
	
	# prh - would like to map the parent here
	
	return $vitem;
}



#------------------------------------
# main-ish
#------------------------------------



sub create_virtual_trees
{
	my ($params,$rebuild) = @_;
	
	if (1 || $rebuild)
	{
		display($dbg_vlibrary,0,"deleting all vtrees");
		if (!db_do($params->{dbh},"DELETE FROM VITEMS"))
		{
			error("Could not clear database");
			return;
		}
		$params->{dbh}->commit();

	}
		
	display($dbg_vlibrary,0,"create_virtual_trees(rebuild=$rebuild)");
	for my $prefix (sort(keys(%virtual_trees)))
	{
		build_virtual_tree($params,$prefix);
	}
}



		

1;
