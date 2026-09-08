import 'package:dio/dio.dart';

import '../../errors/app_error.dart';
import '../../models/models.dart';
import '../../network/http_factory.dart';
import '../../settings/streaming_prefs.dart';
import '../../storage/auth_store.dart';
import '../../subsonic/subsonic.dart';
import '../navidrome_client.dart';
import '../adapter_log.dart';
import '../server_adapter.dart';
import '../server_type.dart';
import 'subsonic_protocol.dart';

/// Navidrome 适配器：REST API 为主，Subsonic 兼容层（媒体直链/资料库扩展/
/// 转码探测）与纯 Subsonic 适配器共用 [SubsonicProtocolAdapter]。
class NavidromeAdapter extends SubsonicProtocolAdapter {
  NavidromeAdapter({
    required ServerConfig config,
    required Map<String, String> secrets,
    NetworkSettings networkSettings = const NetworkSettings(),
  }) : _config = config,
       _secrets = secrets {
    _client = NavidromeClient();
    NetworkRuntime.configureDio(_client.dio, networkSettings);
    _client.setSession(
      StoredSession(
        serverUrl: config.serverUrl,
        username: config.username,
        token: secrets['token'] ?? '',
        subsonicToken: secrets['subsonicToken'] ?? '',
        subsonicSalt: secrets['subsonicSalt'] ?? '',
      ),
    );
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
  SubsonicAuth get auth => _subsonicAuth;

  @override
  Dio get dio => _client.dio;

  /// Subsonic 兼容层入口：失败抛异常（与纯 Subsonic 适配器的 _api 语义一致）
  @override
  Future<Map<String, dynamic>> api(
    String endpoint,
    Map<String, String> extra,
  ) async {
    final res = await _client.dio.get<Map<String, dynamic>>(
      '/rest/$endpoint',
      queryParameters: Subsonic.params(_subsonicAuth, extra),
    );
    final resp = res.data?['subsonic-response'] as Map<String, dynamic>?;
    if (resp == null || resp['status']?.toString() != 'ok') {
      throw ServerError('Subsonic 请求失败');
    }
    return resp;
  }

  @override
  Song parseSong(Map<String, dynamic> json) => Song.fromJson(json);

  @override
  ServerType get type => ServerType.navidrome;

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities(
    ratings: true,
    similarSongs: true,
    artistBio: true,
    transcoding: true,
    scrobbling: true,
    versionedSnapshot: true,
  );

  static Future<AdapterSession> signIn(AuthRequest request) async {
    final client = NavidromeClient();
    try {
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
    } finally {
      client.dio.close();
    }
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
        SongSort.recentlyPlayed => 'play_date',
        SongSort.mostPlayed => 'play_count',
        SongSort.track => 'track',
      };
      params['_sort'] = sort;
      // 最近添加/最近播放/最常播放需要倒序（Navidrome REST 默认 ASC）
      const descSorts = {
        SongSort.recentlyAdded,
        SongSort.recentlyPlayed,
        SongSort.mostPlayed,
      };
      if (descSorts.contains(query.sort)) params['_order'] = 'DESC';
    }
    if (query.albumId != null) params['album_id'] = query.albumId;
    // /api/song 按参与者过滤（专辑艺人+艺人），artist_id 不是合法过滤器
    if (query.artistId != null) params['artists_id'] = query.artistId;
    if (query.starredOnly) params['starred'] = true;
    return _client.getSongs(params);
  }

  @override
  Future<List<Song>> fetchAlbumSongs(String albumId) =>
      _client.getAlbumSongs(albumId);

  @override
  Future<List<Album>> fetchArtistAlbums(String artistId) => _client.getAlbums({
    'artist_id': artistId,
    '_sort': 'max_year',
    '_order': 'DESC',
  });

  @override
  Future<List<Song>> fetchArtistSongs(String artistId, {int limit = 30}) =>
      _client.getSongs({
        // artists_id：参与者过滤（覆盖专辑艺人+艺人角色），Navidrome ≥0.55；
        // artist_id 不是 /api/song 的合法过滤器，传了会被忽略导致返回全库歌曲
        'artists_id': artistId,
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
  Future<String?> fetchArtistBio(String artistId) =>
      _client.getArtistBio(artistId);

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
  Future<bool> createPlaylist(String name) => _client.createPlaylist(name);

  /// Navidrome 同时兼容 Subsonic API，scrobble 走 /rest/scrobble
  @override
  Future<bool> scrobble(String songId) =>
      _subsonicAction({'id': songId, 'submission': 'true'});

  @override
  Future<bool> nowPlaying(String songId) =>
      _subsonicAction({'id': songId, 'submission': 'false'});

  Future<bool> _subsonicAction(Map<String, String> extra) async {
    try {
      final res = await _client.dio.get<Map<String, dynamic>>(
        '/rest/scrobble',
        queryParameters: Subsonic.params(_subsonicAuth, extra),
      );
      final resp = res.data?['subsonic-response'] as Map<String, dynamic>?;
      return resp?['status']?.toString() == 'ok';
    } catch (err, st) {
      adapterSwallowLog('Navidrome', err, st);
      return false;
    }
  }

  // 媒体直链/资料库扩展/转码探测与纯 Subsonic 适配器共用 SubsonicProtocolAdapter

  // ---------- 生命周期 ----------

  @override
  Future<bool> validateSession() async {
    try {
      await _client.getSongTotal();
      return true;
    } catch (err, st) {
      adapterSwallowLog('Navidrome', err, st);
      return false;
    }
  }

  @override
  void dispose() => _client.dio.close();
}
