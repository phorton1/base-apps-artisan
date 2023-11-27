#!/usr/bin/perl
#---------------------------------------
# remotePlaylist.pm
#---------------------------------------
# Builds the master playlists.db for a remote library

package remotePlaylist;
use strict;
use warnings;
use threads;
use threads::shared;
use artisanUtils;
use Database;
use Track;
use Folder;
use artisanUtils;
use Playlist;


my $dbg_rpl = 0;


sub playlistDbName
{
	my ($library) = @_;
	return $library->dataDir()."/playlists.db";
}

sub onlyFirstByTitle
{
	my ($first_by_title,$rec) = @_;
	my $title = $rec->{title};
	my $exists = $first_by_title->{$title} ? 1 : 0;
	$first_by_title->{$title} = 1;
	display($dbg_rpl,0,"onlyFirstByTitle($title) exists=$exists");
	return !$exists;
}


sub initPlaylists
{
	my ($library) = @_;
	my $playlist_db = playlistDbName($library);
	display($dbg_rpl,0,"initPlaylists($library->{name})");
	display($dbg_rpl,1,"playlist_db = $playlist_db");

	# if the playlists.db file does not exists
	# create it from the database or a didl request

	my $playlists;
	if (!-f $playlist_db)
	{
		$playlists = createPlaylistsDB($library,$playlist_db);
		return if !$playlists;
		display($dbg_rpl,1,"got ".scalar(@$playlists)." playlists from new playlists.db");
	}
	else
	{
		my $playlist_dbh = db_connect($playlist_db);
		return if !$playlist_dbh;

		$playlists = get_records_db($playlist_dbh,"SELECT * FROM playlists ORDER BY id");
		display($dbg_rpl,1,"got ".scalar(@$playlists)." playlists from existing playlists.db");

		db_disconnect($playlist_dbh);
	}

	# create the named.db files in the playlists subfolder
	# wiping out the old one if the playlists.db is newer than the named.db,
	# which will usually be all-or-none (unlsess a named_db file is deleted)

	display($dbg_rpl,1,"updating ".scalar(@$playlists)." named.db files");

	my $playlist_ts = getTimestamp($playlist_db);
	display($dbg_rpl,2,"ts=$playlist_db for PLAYLISTS.DB");
	my $playlist_dir = $library->dataDir()."/playlists";
	my_mkdir $playlist_dir if !-d $playlist_dir;

	# Could bump version number of playlists here
	# again if they changed relative to the master
	# but right now it's all or nothing ...

	# re-open the $playlist_dbh for writing 1st track_id and index==1

	my $playlist_dbh = db_connect($playlist_db);
	return if !$playlist_dbh;

	for my $playlist (@$playlists)
	{
		my $name = $playlist->{name};
		my $named_db = "$playlist_dir/$name.db";
		my $named_ts = getTimestamp($named_db);
		display($dbg_rpl,2,"ts=$named_ts for $name");
		if ($playlist_ts gt $named_ts)
		{
			display($dbg_rpl,2,"creating new $name.db");
			unlink $named_db;
			my $tracks = $library->getSubitems('tracks',$playlist->{id});
			display($dbg_rpl,3,"found ".scalar(@$tracks)." tracks");

			my $named_dbh = db_connect($named_db);
			return if !$named_dbh;
			create_table($named_dbh,"pl_tracks");

			my $position = 1;
			my $first_track_id = '';
			for my $track (sort {$a->{position} <=> $b->{position}} @$tracks)
			{
				$first_track_id = $track->{id} if $position == 1;
				my $pl_track = {
					id => $track->{id},
					album_id => $track->{album_title},
					position => $position,
					idx => $position };
				$position++;
				return !error("Could not insert pl_track($track->{title},$track->{id} in $named_db")
					if !insert_record_db($named_dbh,'pl_tracks',$pl_track);
			}

			db_disconnect($named_dbh);

			# reset the initial track_index and track_id

			if (@$tracks)
			{
				$playlist->{track_index} = 1;
				$playlist->{track_id} = $first_track_id;
			}

			return !error("Could not update playlist($playlist->{id},$playlist->{name}) in $playlist_db")
				if !update_record_db($playlist_dbh,'playlists',$playlist,'id');
		}
	}

	db_disconnect($playlist_dbh);

	display($dbg_rpl,0,"initPlaylists($library->{name}) finished");
}



sub createPlaylistsDB
{
	my ($library,$playlist_db) = @_;
	display($dbg_rpl,0,"createPlaylistsDB($playlist_db)");

	my $dbh = db_connect($library->dbPath());
	return if !$dbh;

	my $folders = [];
	my $from_database = 0;
	my $dbg_name = 'Search(playlists)';
	my $cache_dir = $library->subDir('cache');
	my $cache_file = "$cache_dir/$dbg_name.didl.txt";

	# if the cache_file exists, get records from the database

	if (-f $cache_file)
	{
		$from_database = 1;
		my $recs = get_records_db($dbh,"SELECT * FROM folders WHERE dirtype = 'playlist'");
		if ($recs && @$recs)
		{
			for my $rec (@$recs)
			{
				push @$folders, Folder->newFromHash($rec);
			}
		}
	}
	else
	{
		my $params = $library->getParseParams($dbg_rpl,$dbg_name);
		$params->{dbh} = $dbh;
		$params->{dbg} = $dbg_rpl;
		$params->{service} = 'ContentDirectory';
		$params->{action} = 'Search';
		$params->{args} = [
			ContainerID => 0,
			SearchCriteria =>  'upnp:class derivedfrom "object.container.playlistContainer"',
			Filter => '*',
			StartingIndex => 0,
			RequestedCount => 9999,
			SortCriteria => '', ];

		my $first_by_title = {};
		$folders = $library->getAndParseDidl($params,'folders',\&onlyFirstByTitle,$first_by_title);
	}

	db_disconnect($dbh);
	display($dbg_rpl,1,"createPlaylistsDB() found ".scalar(@$folders)." playlist 'folders' ".($from_database?'from database':''));

	# create the new playlist.db

	unlink $playlist_db;
	my $playlist_dbh = db_connect($playlist_db);
	return if !$playlist_dbh;
	create_table($playlist_dbh,"playlists");

	my $playlists = [];
	for my $folder (@$folders)
	{
		display($dbg_rpl,2,"adding playlist($folder->{id},$folder->{title})");
		my $playlist = {
			id => $folder->{id},
			uuid => $library->{uuid},
			name => $folder->{title},
			query => '',
			num_tracks => $folder->{num_elements},
			shuffle => 0,
			track_index => 0,
			track_id => '',
			version => 0 };

		return !error("Could not insert playlist($playlist->{id},$playlist->{name}) in $playlist_db")
			if !insert_record_db($playlist_dbh,'playlists',$playlist);

		push @$playlists,$playlist;
	}

	db_disconnect($playlist_dbh);
	display($dbg_rpl,0,"createPlaylistsDB() returning ".scalar(@$playlists)." playlists");
	return $playlists;
}




1;
