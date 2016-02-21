#--------------------------------------------------
# Database
#--------------------------------------------------

package Database;
use strict;
use warnings;
use DBI;
use Utils;
use SQLite;


# Re-exports SQLite db_do, get_records_db, and get_record_db
BEGIN
{
 	use Exporter qw( import );
	our @EXPORT = qw (
	
        db_initialize
        db_connect
        db_disconnect
        get_table_fields
		insert_record_db
		update_record_db
		db_init_track
		db_init_folder
		db_init_rec

        get_records_db
        get_record_db
        db_do
    );
};


my $db_name = "$cache_dir/artisan.db";



#------------------------------------
# DATABASE DEFINITION
#------------------------------------

		
my %field_defs = (

    TRACKS => [
        'ID         VARCHAR(40)',	# 2016-02-11 Start using STREAM_MD5 as ID
		'PARENT_ID  INTEGER',
			# id of parent folder
		
		# raw file information
		
        'FULLNAME	VARCHAR(2048)',
        'TIMESTAMP	BIGINT',
        'SIZE		BIGINT',
        
		# parsed and/or determined from fullname
		
        'MIME_TYPE	VARCHAR(128)',
			# audio/mpeg, etc
        'PATH		VARCHAR(2048)',
        'NAME	    VARCHAR(2048)',
        'FILEEXT	VARCHAR(4)',

		# from MediaFile

        'TYPE		VARCHAR(12)',
			# synonymous with FILEEXT
			
		'FILE_MD5 VARCHAR(40)',
			# Used to detect unused fpCalc_info files
			
		
        'DURATION   INTEGER DEFAULT 0',
			# currently in seconds
        'YEAR		VARCHAR(4)',
			# the only pure 'tag' meta data at this time
			# is the year.  This could be a DATE or a DATETIME
			
		'HAS_ART  INTEGER',
			# for the TRACK the count of APICs tags
			# Note that there is no ART_URI for tracks
			
		# MediaFile things that can return defaults from filename
		
        'TRACKNUM  	  VARCHAR(6)',
        'TITLE		  VARCHAR(128)',
        'ARTIST		  VARCHAR(128)',

		# MediaFile things that can return defaults from path

        'ALBUM_ARTIST VARCHAR(128)',
        'ALBUM		  VARCHAR(128)',
        'GENRE		  VARCHAR(128)',

		# A list of the error codes found during the
		# last media scan of this item (upto 40 or so)
		
		'ERROR_CODES VARCHAR(128)',
		
		
		# The error level of the highest error found during
		# the llibrary scan of this item

		'HIGHEST_ERROR   INTEGER',

		# The bitwise 'stations' that this track is a member of.
		# Changes to this bit must propogate to parent folders.
		
		'STATIONS      INTEGER',
		
	],	# TRACK DEFINITION


    #------------------------------------
    # FOLDERS
    #------------------------------------
    # current directory types:
    #     album
	#     root
	#     section
	#     class
	# future directory types
	#     virtual?
	
    FOLDERS => [
        'ID			 	INTEGER PRIMARY KEY AUTOINCREMENT',
		'PARENT_ID      INTEGER',
        'DIRTYPE	 	VARCHAR(16)',

		# the class is null except on albums
		
		'CLASS          VARCHAR(128)',
		
		# may not be used for virtual folders
		
        'FULLPATH	 	VARCHAR(2048)',
        'NAME		 	VARCHAR(2048)',
        'PATH		 	VARCHAR(2048)',
        'HAS_ART     	INTEGER',   # set to 1 if folder.jpg exists

		# presented via DNLA ... 
		# mostly specific to albums
		# Note that the database stores the ART_URI for folders
		
		'NUM_ELEMENTS   INTEGER',
        'TITLE		    VARCHAR(128)',
		#'ART_URI	    VARCHAR(128)',
		'ARTIST		    VARCHAR(128)',
        'GENRE		    VARCHAR(128)',
        'YEAR		    VARCHAR(4)',

		# The error level of this folder, separate children tracks
		# is passed up the tree to HIGHEST_FOLDER_ERROR, and there
		# is a "mode" which displays HIGHEST_ERROR, HIGHEST_FOLDER_ERROR
		# or the highest of the two.
		
		'FOLDER_ERROR   INTEGER',
		'HIGHEST_FOLDER_ERROR  INTEGER',

		# The highest error of this and any child track is
		# passed up the folder tree.
		
		'HIGHEST_ERROR  INTEGER',
		
		# STATIONS - the bitwise stations this folder is a member of.
		#
		# A folder is a member of a station if any of it's leaf children
		# tracks is a member.  The bit on the folder object is used
		# as a UI artifice, to facilitate turning on and off large
		# numbers of tracks at a time.
		#
		# If set on the folder, toggling it means to turn off the bit
		# in all children folders and tracks.  If not set on the folder
		# toggling it means to turn it on in all children and tracks.
		# Otherwise, it may inherit a mixed 'on' state from it's children.
		
		'STATIONS      INTEGER',

        ],

		
		
    );	# %field_defs








#--------------------------------------------------------
# Database API
#--------------------------------------------------------

sub db_initialize
{
    LOG(0,"db_initialize($db_name)");

    # my @tables = select_db_tables($dbh);
    # if (!grep(/^METADATA$/, @tables))

    if (!(-f $db_name))
    {
        LOG(1,"creating new database");

	   	my $dbh = db_connect();

		$dbh->do('CREATE TABLE TRACKS ('.
            join(',',@{$field_defs{TRACKS}}).')');

		$dbh->do('CREATE TABLE FOLDERS ('.
            join(',',@{$field_defs{FOLDERS}}).')');

    	db_disconnect($dbh);
		
	}
}


sub db_connect
{
    display($dbg_db,0,"db_connect");
	my $dbh = sqlite_connect($db_name,'artisan','');
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
	for my $def (@{$field_defs{$table}})
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
	#
	# kludge for FOLDERS which has an auto-increment
	# primary ID field. Dont add the value for a field
	# named ID, unless it is explicitly passed as key_field,
	# so DO pass $key_field == "ID" for the TRACKS file.
{
	my ($dbh,$table,$rec,$key_field) = @_;
	$key_field ||= 'NAME';
	
    display($dbg_db,0,"insert_record_db($table,$key_field,$rec->{$key_field})");
	my $fields = get_table_fields($dbh,$table);
	
	my @values;
	my $query = '';
	my $vstring = '';
	for my $field (@$fields)
	{
		next if ($field eq 'ID' && $key_field ne 'ID');
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
	$id_field ||= 'ID';

	my $fields = get_table_fields($dbh,$table);
	my $id = $$rec{$id_field};
	
	my $dbg_extra = ($id_field ne 'NAME' && $rec->{NAME}) ? " $rec->{NAME}" : '';
    display($dbg_db,0,"update_record_db($table,$id)$dbg_extra");
	
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
	my $track = db_init_rec('TRACKS');
    return $track;
}

sub db_init_folder
{
	my $folder = db_init_rec('FOLDERS');
	return $folder;
}



sub db_init_rec
{
	my ($table) = @_;
	my $rec = {};
    for my $def (@{$field_defs{$table}})
	{
		my ($field,$type) = split(/\s+/,$def);
		my $value = '';
		$value = 0 if $type =~ /^(INTEGER|BIGINT)$/;
		$$rec{$field} = $value;
	}
	return $rec;
}
		




1;
