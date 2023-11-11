#!/usr/bin/perl
#-------------------------------------------------
# localPLSource.pm - Local Playlist Source
#-------------------------------------------------
# I was thinking that a playlist source would be completely generic,
# and not require any sub-objects.  Now I notice that Playlist.pm
# is a class which would be better called a localPlaylist, and that
# we would then need another derivation hierarchy with Playlist,
# localPlaylist and remotePlaylist.
#
# I think, for starters, I'm gonna create a localPlaylist without
# the hierarchy, at least until I get things sort of working.

package localPLSource;
use strict;
use warnings;
use threads;
use threads::shared;
use SQLite;
use artisanUtils;
use Database;
use PLSource;
use localPlaylist;
use base qw(PLSource);

my $dbg_lpls = 0;


sub new
{
	my ($class) = @_;
	display($dbg_lpls,0,"localPLSource::new()");
	my $this = $class->SUPER::new(
		1,
		$this_uuid,
		$program_name);


	$this->{playlists} = shared_clone([]);
	$this->{playlists_by_name} = shared_clone({});

	bless $this,$class;
	return $this;
}





#----------------------------------------------
# public API called by WebUI
#----------------------------------------------

sub getPlaylist
{
	my ($this,$name) = @_;
	my $playlist = $this->{playlists_by_name}->{$name};
	$playlist->{uuid} = $this_uuid if $playlist;
	return $playlist;
}


sub getPlaylistNames()
	# returns a list of the names of the Playlists within this PLSource
{
	my ($this) = @_;
	my $retval = [];
	display($dbg_lpls,0,"getPlaylistNames(".scalar(@{$this->{playlists}}).")");

	for my $playlist (@{$this->{playlists}})
	{
		display($dbg_lpls+1,0,"adding $playlist->{name}");
		push @$retval,$playlist->{name};
	}
	return $retval;
}


sub setPlaylistInfo
	# shuffle = 0,1, or 2 or
	# track_index = 1..num_tracks
	# Returns the json for the playlist on success,
	# or {error=>msg} json on a failure
{
	my ($this,$name,$field,$value) = @_;
}


# Other methods will be needed by the Renderer



#---------------------------
# DEFAULT PLAYLISTS
#---------------------------

my %default_playlists = (

	# playlist names may have spaces
	# but since they get sent along as parts of
	# urls, etc, they cannot have any special characters
	# except maybe dash and dot (certainly not ampersand)
	# which does not work unencoded in xml

	test => {
		num => 1,
		query =>
			"albums/Productions/Originals/Forgotten Space" },
	work => {
		num => 2,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Work" },
	dead => {
		num => 3,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Dead\t".
			"singles/Dead" },
    favorite => {
		num => 4,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Favorite\t".
			"singles/Favorite" },
    jazz => {
		num => 5,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Jazz/Old\t".
			"albums/Jazz/Soft\t".
			"albums/Jazz/Swing\t".
			"singles/Jazz" },
    blues => {
		num => 6,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Blues\t".
			"singles/Blues" },
	station7 => { num => 7, query => "" },
	station8 => { num => 8, query => "" },
    world => {
		num => 9,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/World minus /Tipico\t".
			"singles/World" },
	orleans => {
		num => 10,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/NewOrleans\t".
			"albums/Zydeco" },
    reggae => {
		num => 11,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Reggae\t".
			"singles/Reggae" },
	rock => {
		num => 12,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Rock\t".
			"albums/SanDiegoLocals\t".
			"singles/Rock" },
    RandB => {
		num  => 13,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/R&B\t".
			"singles/R&B" },
    country => {
		num  => 14,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Country\t".
			"singles/Country" },
    classical => {
		num  => 15,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Classical minus /Baroque\t".
			"singles/Classical minus /Baroque" },
    xmas => {
		num  => 16,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Christmas\t".
			"singles/Christmas" },
    friends => {
		num  => 17,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Productions minus Sweardha Buddha\t".
			"albums/Friends" },
    folk => {
		num  => 18,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Folk\t".
			"singles/Folk" },
    compilations => {
		num  => 19,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Compilations\t".
			"singles/Compilations" },
    soundtrack => {
		num  => 20,
		shuffle => $SHUFFLE_ALBUMS,
		query =>
			"albums/Soundtracks" },
    other => {
		num  => 21,
		shuffle => $SHUFFLE_TRACKS,
		query =>
			"albums/Other\t".
			"singles/Other" },
	station22 => { num => 22, query => "" },
	station23 => { num => 23, query => "" },
	station24 => { num => 24, query => "" },
	station25 => { num => 25, query => "" },
	station26 => { num => 26, query => "" },
	station27 => { num => 27, query => "" },
	station28 => { num => 28, query => "" },
	station29 => { num => 29, query => "" },
	station30 => { num => 30, query => "" },
	station31 => { num => 31, query => "" },
	station32 => { num => 32, query => "" },


);	# %default_playlists


#-----------------------------------------
# initPlaylists
#-----------------------------------------


sub initPlaylists
{
	my ($this) = @_;
	display($dbg_lpls,0,"initPlaylists() started ...");

	my $main_db_name = "$data_dir/playlists.db";
	my $new_database = !-f $main_db_name;
	my $dbh = sqlite_connect($main_db_name,'playlists','');
	create_table($dbh,"playlists") if $new_database;

	# create any missing default playlists
	# or update the track databases if not found
	# the default playlists are assumed to be in the correct order.

	for my $name (sort {$default_playlists{$a}->{num} <=> $default_playlists{$b}->{num}} keys(%default_playlists))
	{
		my $exists = -f "$playlist_dir/$name.db" ? 1 : 0;
		my $rec = get_record_db($dbh,
			"SELECT * FROM playlists WHERE name='$name'");

		display($dbg_lpls,1,"got($name) exists=$exists rec="._def($rec));

		# if record does not exist, we recreate the playlist from scratch
		# if the table doesnt exist, then we create it from the query
		# otherwise, we assume it is correct

		my $playlist;
		if (!$rec)
		{
			display($dbg_lpls,2,"creating new playlist($name) from default");
			$playlist = localPlaylist->newFromDefault(
				$name,
				$default_playlists{$name});
			next if !$playlist;
			if (!insert_record_db($dbh,'playlists',$playlist))
			{
				error("Could not insert playlist($name) into database");
				next;
			}

		}
		elsif (!$exists)
		{
			display($dbg_lpls,2,"updating playlist($name) from its table");
			$playlist = localPlaylist->newFromQuery($rec);
			next if !$playlist;
		}
		else
		{
			display($dbg_lpls,2,"using existing playlist ".pad($name,20)." num_tracks=$rec->{num_tracks}");
			$playlist = localPlaylist->newFromRecAndTable($rec);
				# cannot fail
		}

		$this->{playlists_by_name}->{$name} = $playlist;
		push @{$this->{playlists}},$playlist;
	}

	# finished

	display($dbg_lpls,0,"static_init_playlists finished");
}





1;