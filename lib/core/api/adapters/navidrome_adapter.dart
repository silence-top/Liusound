import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/models.dart';
import '../../storage/auth_store.dart';
import '../../subsonic/subsonic.dart';
import '../navidrome_client.dart';
import '../server_adapter.dart';
import '../server_type.dart';

class NavidromeAdapter implements ServerAdapter {
  NavidromeAdapter({required ServerConfig config, required Map<String, String> secrets})
      : _config = config,
        _secrets = secrets {
    _client = NavidromeClient();
    _client.setSession(StoredSession(
      serverUrl: config.serverUrl,
      username: config.username,
      token: secrets['token'] ?? '',
      subsonicToken: secrets['subsonicToken'] ?? '',
      subsonicSalt: secrets['subsonicSalt'] ?? '',
    ));
  }

  final ServerConfig _config;
  final Map<String, String> _secrets;
  late final NavidromeClient _client;

  SubsonicAuth get _subsonicAuth => SubsonicAuth(
        serverUrl: _config.serverUrl,
        username: _config.username,
        subsonicToken: _secrets['subsonicToken'] ?? '',
        subsonicSalt: _secrets['subsonicSalt'] ?? '',
      );

  @override
  ServerType get type => ServerType.navidrome;

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities(
        ratings: true,
        similarSongs: true,
        likedSongs: true,
        download: true,
        lyrics: true,
      );

  static Future<AdapterSession> signIn(AuthRequest request) async {
    final client = NavidromeClient();
    final result = await client.login(
      request.serverUrl,
      request.username,
      request.password,
    );
    return AdapterSession(
      secrets: {
        'token': result.token,
        'subsonicToken': result.subsonicToken,
        'subsonicSalt': result.subsonicSalt,
      },
      displayName: result.username.isNotEmpty ? result.username : null,
    );
  }

  @override
  Future<List<Album>> fetchAlbums(AlbumQuery query) async {
    final sort = switch (query.sort) {
      AlbumSort.recentlyAdded => 'recently_added',
      AlbumSort.recentlyPlayed => 'play_date',
      AlbumSort.mostPlayed => 'play_count',
      AlbumSort.random => 'random',
      AlbumSort.name => 'name',
      AlbumSort.year => 'max_year',
    };
    return _client.getAlbums({
      '_sort': sort,
      '_order': query.descending ? 'DESC' : 'ASC',
      '_start': query.start,
      '_end': query.start + query.limit,
      if (query.seed != null && query.sort == AlbumSort.random)
        '_seed': query.seed!,
    });
  }

  @override
  Future<List<Song>> fetchSongs(SongQuery query) async {
    final params = <String, Object?>{
      '_start': query.start,
      '_end': query.start + query.limit,
    };
    if (query.sort != null) {
      final sort = switch (query.sort!) {
        SongSort.title => 'title',
        SongSort.random => 'random',
        SongSort.rating => 'rating',
        SongSort.recentlyAdded => 'recently_added',
        SongSort.track => 'track',
      };
      params['_sort'] = sort;
    }
    if (query.albumId != null) params['album_id'] = query.albumId;
    if (query.artistId != null) params['artist_id'] = query.artistId;
    if (query.starredOnly) params['starred'] = true;
    return _client.getSongs(params);
  }

  @override
  Future<List<Song>> fetchAlbumSongs(String albumId) =>
      _client.getAlbumSongs(albumId);

  @override
  Future<List<Album>> fetchArtistAlbums(String artistId) =>
      _client.getAlbums({
        'artist_id': artistId,
        '_sort': 'max_year',
        '_order': 'DESC',
      });

  @override
  Future<List<Song>> fetchArtistSongs(String artistId, {int limit = 30}) =>
      _client.getSongs({
        'artist_id': artistId,
        '_end': limit,
        '_order': 'DESC',
        '_sort': 'rating',
        '_start': 0,
      });

  @override
  Future<List<Playlist>> fetchPlaylists() => _client.getPlaylists();

  @override
  Future<List<Song>> fetchPlaylistSongs(String playlistId) =>
      _client.getPlaylistSongs(playlistId);

  @override
  Future<List<Song>> fetchLikedSongs({int limit = 100}) =>
      _client.getLikedSongs();

  @override
  Future<List<Song>> fetchSimilarSongs(String songId, {int count = 20}) =>
      _client.getSimilarSongs(songId, count: count);

  @override
  Future<SearchResult> search(String query) => _client.search(query);

  @override
  Future<int> fetchSongCount() => _client.getSongTotal();

  @override
  Future<bool> setStar(String id, bool starred) => _client.setStar(id, starred);

  @override
  Future<bool> setRating(String id, int rating) =>
      _client.setRating(id, rating);

  @override
  Future<bool> addToPlaylist(String playlistId, String songId) =>
      _client.addToPlaylist(playlistId, songId);

  @override
  Future<PlaybackSource> resolveStream(Song song) async {
    final auth = _subsonicAuth;
    return PlaybackSource(url: Subsonic.streamUrl(auth, song.id));
  }

  @override
  Future<PlaybackSource> resolveDownload(Song song) async {
    final auth = _subsonicAuth;
    return PlaybackSource(url: Subsonic.downloadUrl(auth, song.id));
  }

  @override
  ImageSource? coverImage(String albumId, {int size = 300}) {
    final auth = _subsonicAuth;
    if (!auth.isValid || albumId.isEmpty) return null;
    return ImageSource(url: Subsonic.coverArtUrl(auth, albumId));
  }

  @override
  Future<Uint8List?> fetchCoverBytes(String albumId, {int size = 64}) async {
    final auth = _subsonicAuth;
    if (!auth.isValid || albumId.isEmpty) return null;
    try {
      final url = Subsonic.coverArtUrl(auth, albumId);
      final resp = await Dio().get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      return resp.data;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> validateSession() async {
    try {
      await _client.getSongTotal();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {}
}
