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
	my $pldb_name = playlistDbName($library);
	display($dbg_rpl,0,"initPlaylists($library->{name})");
	display($dbg_rpl,1,"pldb_name = $pldb_name");

	# if the playlists.db file does not exists
	# create it from the database or a didl request

	my $playlists;
	if (!-f $pldb_name)
	{
		$playlists = createPlaylistsDB($library,$pldb_name);
		return if !$playlists;
		display($dbg_rpl,1,"got ".scalar(@$playlists)." playlists from new playlists.db");
	}
	else
	{
		my $dbh = db_connect($pldb_name);
		return if !$dbh;

		$playlists = get_records_db($dbh,"SELECT * FROM playlists ORDER BY id");
		display($dbg_rpl,1,"got ".scalar(@$playlists)." playlists from existing playlists.db");

		db_disconnect($dbh);
	}

	# create the named.db files in the playlists subfolder
	# wiping out the old one if the playlists.db is newer than the named.db,
	# which will usually be all-or-none (unlsess a named_db file is deleted)

	display($dbg_rpl,1,"updating ".scalar(@$playlists)." named.db files");

	my $pldb_ts = getTimestamp($pldb_name);
	display($dbg_rpl,2,"ts=$pldb_ts for PLAYLISTS.DB");
	my $playlist_dir = $library->dataDir()."/playlists";
	my_mkdir $playlist_dir if !-d $playlist_dir;

	for my $playlist (@$playlists)
	{
		my $name = $playlist->{name};
		my $db_name = "$playlist_dir/$name.db";
		my $pl_ts = getTimestamp($db_name);
		display($dbg_rpl,2,"ts=$pl_ts for $name");
		if ($pldb_ts gt $pl_ts)
		{
			display($dbg_rpl,2,"creating new $name.db");
			unlink $db_name;
			my $tracks = $library->getSubitems('tracks',$playlist->{id});
			display($dbg_rpl,3,"found ".scalar(@$tracks)." tracks");

			my $dbh = db_connect($db_name);
			return if !$dbh;
			create_table($dbh,"pl_tracks");

			my $position = 1;

			# At this time there is not a meaningful album_id on
			# remoteTracks.  The path is an arbitrary http;// for the media,
			# and the only 'parent' of the track is the playlist.
			# It is not even clear if this could be accomplished.
			# For WMP it could *perhaps* be accomplished by relating the
			# final -xxxxx part of the id back into the 'folders' tree.
			# for now, the sort by albums is meaningless.
			# I'll have another look at the 'dumps' and see if anything
			# good comes to mind

			for my $track (sort {$a->{position} <=> $b->{position}} @$tracks)
			{
				my $pl_track = {
					id => $track->{id},
					album_id => $track->{album_title},
					position => $position,
					idx => $position };
				$position++;
				return !error("Could not insert pl_track($track->{title},$track->{id} in $db_name")
					if !insert_record_db($dbh,'pl_tracks',$pl_track);
			}
		}
	}

	display($dbg_rpl,0,"initPlaylists($library->{name}) finished");
}



sub createPlaylistsDB
{
	my ($library,$pldb_name) = @_;
	display($dbg_rpl,0,"createPlaylistsDB($pldb_name)");

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

	unlink $pldb_name;
	my $pl_dbh = db_connect($pldb_name);
	return if !$pl_dbh;
	create_table($pl_dbh,"playlists");

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
			track_index => 1, };

		$playlist->{track_index} = 0 if !$playlist->{num_tracks};
		$playlist->{track_index} = 1 if !$playlist->{track_index} && $playlist->{num_tracks};

		return !error("Could not insert playlist($playlist->{id},$playlist->{name}) in $pldb_name")
			if !insert_record_db($pl_dbh,'playlists',$playlist);

		push @$playlists,$playlist;
	}

	db_disconnect($pl_dbh);
	display($dbg_rpl,0,"createPlaylistsDB() returning ".scalar(@$playlists)." playlists");
	return $playlists;
}




1;
