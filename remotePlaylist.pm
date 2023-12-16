#!/usr/bin/perl
#---------------------------------------
# remotePlaylist.pm
#---------------------------------------
# Builds the master playlists.db for a remote library
# Playlists are not built until they are accessed
# via call to remoteLibrary::getPlaylist(), which in
# turn calls initPlaylist() to actually build the
# playlist.  For a playlist of 1000 records this
# can take several minutes.

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


my $WMP_PLAYLIST_KLUDGE = 1;
	# This kludge will merely do a fake request
	# to the remoteLibrary contentServer to Search
	# for playlists, which *seems* to fix the WMP
	# weirdness.


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
	display($dbg_rpl,1,"playlist_db = $playlist_db exists = ".((-f $playlist_db) ? 1 : 0));

	display($dbg_rpl,1,"after unlink exists = ".((-f $playlist_db) ? 1 : 0));

	# if the playlists.db file does not exists
	# create it from the database or a didl request

	my $playlists;
	if (!-f $playlist_db)
	{
		$playlists = createPlaylistsDB($library,$playlist_db);
		return if !$playlists;
		display($dbg_rpl,1,"got ".scalar(@$playlists)." playlists from new playlists.db");
	}

	# otherwise, do a 'fake' request just to satisfy WMP

	elsif ($WMP_PLAYLIST_KLUDGE)
	{
		display($dbg_rpl,1,"DOING FAKE SEARCH PLAYLISTS");
		my $fake_name = 'FakeSearch(playlists)';
		my $params = $library->getParseParams($dbg_rpl,$fake_name);
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
		$library->serviceRequest($params);
	}

	return 1;
}


sub initPlaylist
{
	my ($library,$id) = @_;
	my $playlist_db = playlistDbName($library);
	display($dbg_rpl,0,"initPlaylist($library->{name},$id)");

	my $playlist_dbh = db_connect($playlist_db);
	return if !$playlist_dbh;

	my $playlist = get_record_db($playlist_dbh,"SELECT * FROM playlists WHERE id = '$id'");

	my $retval = 0;
	if ($playlist)
	{
		display($dbg_rpl,1,"got playlist($id) $playlist->{name}");

		# my $playlist_ts = getTimestamp($playlist_db);
		my $playlist_dir = $library->dataDir()."/playlists";
		my_mkdir $playlist_dir if !-d $playlist_dir;

		my $name = $playlist->{name};
		my $named_db = "$playlist_dir/$name.db";
		# my $named_ts = getTimestamp($named_db);

		# display($dbg_rpl,1,"Timestamps playlists.db($playlist_ts) $playlist->{name}($named_ts)");

		if (!-f $named_db)	# $playlist_ts gt $named_ts)
		{
			display($dbg_rpl,1,"creating new $name.db");
			# unlink $named_db;

			my $tracks = $library->getSubitems('tracks',$playlist->{id});
			display($dbg_rpl,1,"found ".scalar(@$tracks)." tracks");

			my $named_dbh = db_connect($named_db);
			return if !$named_dbh;
			create_table($named_dbh,"tracks");

			my $position = 1;
			my $first_track = '';
			for my $track (sort {$a->{position} <=> $b->{position}} @$tracks)
			{
				$first_track ||= $track;
				$track->{pl_idx} = $position;
				$track->{position} = $position++;
				if (!insert_record_db($named_dbh,'tracks',$track))
				{
					error("Could not insert track($track->{title},$track->{id} in $named_db");
					return;
				}
			}

			db_disconnect($named_dbh);

			# reset the initial track_index and track_id

			if (@$tracks)
			{
				$playlist->{track_index} = 1;
				$playlist->{track_id} = $first_track->{id};
			}

			if (update_record_db($playlist_dbh,'playlists',$playlist,'id'))
			{
				$retval = 1;
			}
			else
			{
				error("Could not update playlist($playlist->{id},$playlist->{name}) in $playlist_db");
			}

		}
		else
		{
			display($dbg_rpl,1,"playlist($id) $playlist->{name} is up to date");
			$retval = 1;
		}
	}
	else
	{
		error("Could not get playlist($library->{name},$id)");
	}

	db_disconnect($playlist_dbh);
	display($dbg_rpl,0,"initPlaylists($library->{name}) returning $retval");
	return $retval;
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
