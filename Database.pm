#--------------------------------------------------
# Database
#--------------------------------------------------

package Database;
use strict;
use warnings;
use threads;
use threads::shared;
use DBI;
use artisanUtils;
use SQLite;

my $dbg_db = 1;

our $HAS_FOLDER_ART = 1;
our $HAS_TRACK_ART  = 2;
	# bitwise constants for track has_art



# Re-exports SQLite db_do, get_records_db, and get_record_db
BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (

		$HAS_TRACK_ART
		$HAS_FOLDER_ART

        db_initialize
        db_connect
        db_disconnect

        get_records_db
        get_record_db
        db_do

		insert_record_db
		update_record_db

        get_table_fields
		db_init_track
		db_init_folder
		db_init_rec
		create_table

		%artisan_field_defs



    );
};


my $db_name = "$data_dir/artisan.db";



#------------------------------------
# DATABASE DEFINITION
#------------------------------------


our %artisan_field_defs = (

	# The ID fields VARCHARS need to be large enough to accept
	# ANY library's IDs (i.e. WMP)

	#------------------------------------
	# Playlists
	#------------------------------------

	playlists => [
		'id		 	   VARCHAR(128)',
		'uuid          VARCHAR(128)',
		'name		   VARCHAR(128)',
		'num_tracks    INTEGER',
		'shuffle	   INTEGER',
		'track_index   INTEGER',
		'track_id	   VARCHAR(128)',
		'version	   INTEGER',
		'data_version  INTEGER',
	],

    #------------------------------------
    # TRACKS
    #------------------------------------

    tracks => [

		'position 		INTEGER',
			# the position within the playlist
			# or in a fresh library scan. Need
			# a query that returns MAX at the
			# beginning of the scan ...

		'is_local       INTEGER',
			# indicates whether this is a file
			# on the local machine, in which case
			# the id will be used to develop the
			# public uri, and the path itself
			# contains the mp3s_dir relative path
			# to the file.
			#
			# The local database ONLY consists of
			# these items, and it can be ASSUMED in
			# some code (i.e. the perl Library scan)

		'id             VARCHAR(128)',
			# stream_md5 from fpcalc

		'parent_id    	VARCHAR(128)',		#
			# id of parent folder

		'has_art        INTEGER',
			# for local items (art_uri="")
			# 1=folder.jpg exists
			# 2=there's an image in the mp3 file

		'path			VARCHAR(1024)',
			# the public_uri for non-local files

		'art_uri		VARCHAR(1024)',
			# the http://uri and art_uri for external files
			# uri will be the relative path to the file
			# and art_uri will blank for local items

		# metadata from our database for local items
		# or from the didl of an external http:// track

		'duration     	BIGINT',			# milliseconds
		'size         	BIGINT',
		'type         	VARCHAR(8)',		# MP3, WMA, M4A, etc
        'title		  	VARCHAR(128)',
        'artist		  	VARCHAR(128)',
        'album_title  	VARCHAR(128)',
        'album_artist 	VARCHAR(128)',
        'tracknum  	  	VARCHAR(6)',
        'genre		  	VARCHAR(128)',
		'year_str     	VARCHAR(4)',

		# concessions to Perl Library scanner

		'timestamp      BIGINT',
		'file_md5       VARCHAR(40)',
			# for change detection

		'error_codes VARCHAR(128)',
			# A list of the error codes found during the
			# last media scan of this item (upto 40 or so)

		'highest_error   INTEGER',
			# The error level of the highest error found during
			# the llibrary scan of this item

		'pl_idx			INTEGER',
			# the sorted position when the track is
			# in a playlist

	],	# tracks


    #------------------------------------
    # FOLDERS
    #------------------------------------
    # current directory types:
	#     root
	#     section
	#     class
	# future directory types
	#     virtual?

    folders => [

		'is_local       INTEGER',
			# indicates whether this is a directory
			# on the local machine, in which case
			# the id will be used to develop the
			# public art uri, and the local art uri
			# will be of the form file://
			#
			# The local database ONLY consists of
			# these items, and it can be ASSUMED in
			# some code (i.e. the perl Library scan)

        'id			 	VARCHAR(128)',
			# md5 checksum of the path

		'parent_id      VARCHAR(128)',
        'dirtype	 	VARCHAR(16)',
		    # album, root, section, class, virtual, etc
        'has_art     	INTEGER',
			# set to 1 if local folder.jpg exists

        'path	 		VARCHAR(1024)',
		'art_uri		VARCHAR(1024)',
			# empty on local Folders

		# presented via DNLA ...
		# mostly specific to albums

		'num_elements   INTEGER',
        'title			VARCHAR(128)',
		'artist   		VARCHAR(128)',
        'genre		    VARCHAR(128)',
        'year_str       VARCHAR(4)',

		# The error level of this folder, separate children tracks
		# is passed up the tree to HIGHEST_FOLDER_ERROR, and there
		# is a "mode" which displays HIGHEST_ERROR, HIGHEST_FOLDER_ERROR
		# or the highest of the two.

		'folder_error          INTEGER',
		'highest_folder_error  INTEGER',

		# The highest error of this and any child track is
		# passed up the folder tree.

		'highest_track_error  INTEGER'

	],	# folder

);	# %field_defs








#--------------------------------------------------------
# Database API
#--------------------------------------------------------

sub db_initialize
{
	my ($use_name) = @_;
	$use_name ||= $db_name;

    LOG(0,"db_initialize($use_name)");

    # my @tables = select_db_tables($dbh);
    # if (!grep(/^METADATA$/, @tables))

    if (!(-f $use_name))
    {
        LOG(1,"creating new database");

	   	my $dbh = db_connect($use_name);

		$dbh->do('CREATE TABLE tracks ('.
            join(',',@{$artisan_field_defs{tracks}}).')');

		$dbh->do('CREATE TABLE folders ('.
            join(',',@{$artisan_field_defs{folders}}).')');

    	db_disconnect($dbh);

	}
}


sub db_connect
{
	my ($use_name) = @_;
	$use_name ||= $db_name;

    display($dbg_db,0,"db_connect($use_name)");
	my $dbh = sqlite_connect($use_name,'artisan','');
	error("Could not connect to database($use_name)") if !$dbh;
	return $dbh;
}


sub db_disconnect
{
	my ($dbh) = @_;
    display($dbg_db,0,"db_disconnect");
	sqlite_disconnect($dbh);
}




sub get_table_fields
{
    my ($dbh,$table) = @_;
    display($dbg_db+1,0,"get_table_fields($table)");
    my @rslt;
	for my $def (@{$artisan_field_defs{$table}})
	{
		my $copy_def = $def;
		$copy_def =~ s/\s.*$//;
		display($dbg_db+2,1,"field=$copy_def");
		push @rslt,$copy_def;
	}
	return \@rslt;
}


sub insert_record_db
	# inserts ALL table fields for a record
	# and ignores other fields that may be in rec.
	# best to call init_rec before this.
{
	my ($dbh,$table,$rec) = @_;

    display($dbg_db,0,"insert_record_db($table)");
	my $fields = get_table_fields($dbh,$table);

	my @values;
	my $query = '';
	my $vstring = '';
	for my $field (@$fields)
	{
		$query .= ',' if $query;
		$query .= $field;
		$vstring .= ',' if $vstring;
		$vstring .= '?';
		push @values,$$rec{$field};
	}
	return db_do($dbh,"INSERT INTO $table ($query) VALUES ($vstring)",\@values);
}


sub update_record_db

{
	my ($dbh,$table,$rec,$id_field) = @_;
	$id_field ||= 'id';

	my $fields = get_table_fields($dbh,$table);
	my $id = $$rec{$id_field};

    display($dbg_db,0,"update_record_db($table) id_field=$id_field id_value=$id");

	my @values;
	my $query = '';
	for my $field (@$fields)
	{
		next if (!$field);
		next if ($field eq $id_field);
		$query .= ',' if ($query);
		$query .= "$field=?";
		push @values,$$rec{$field};
	}
	push @values,$id;

	return db_do($dbh,"UPDATE $table SET $query WHERE $id_field=?",
		\@values);
}




sub db_init_track
{
	my $track = db_init_rec('tracks');
    return $track;
}

sub db_init_folder
{
	my $folder = db_init_rec('folders');
	return $folder;
}



sub db_init_rec
{
	my ($table) = @_;
	my $rec = shared_clone({});
    for my $def (@{$artisan_field_defs{$table}})
	{
		my ($field,$type) = split(/\s+/,$def);
		my $value = '';
		$value = 0 if $type =~ /^(INTEGER|BIGINT)$/i;
		$$rec{$field} = $value;
	}
	return $rec;
}



sub create_table
{
	my ($dbh,$table) = @_;
	display($dbg_db,0,"create_table($table)");
	my $def = join(',',@{$artisan_field_defs{$table}});
	$def =~ s/\s+/ /g;
	$dbh->do("CREATE TABLE $table ($def)");
}




1;
