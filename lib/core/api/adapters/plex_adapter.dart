import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/models.dart';
import '../server_adapter.dart';
import '../server_type.dart';

/// Plex 适配器。
/// 认证：POST https://plex.tv/users/sign_in.json（Basic Auth）→ X-Plex-Token。
/// 需发现音乐分区（/library/sections type=music）。
class PlexAdapter implements ServerAdapter {
  PlexAdapter({
    required ServerConfig config,
    required Map<String, String> secrets,
  })  : _config = config,
        _token = secrets['plexToken'] ?? '',
        _machineId = secrets['machineId'] ?? '',
        _musicSectionKey = secrets['musicSectionKey'] ?? '' {
    _dio.options.baseUrl = config.serverUrl;
  }

  final ServerConfig _config;
  final String _token;
  final String _machineId;
  final String _musicSectionKey;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  @override
  ServerType get type => ServerType.plex;

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities(
        ratings: true,
        similarSongs: false,
        likedSongs: true,
        download: true,
        lyrics: true,
      );

  static Future<AdapterSession> signIn(AuthRequest request) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    try {
      final credentials =
          base64Encode(utf8.encode('${request.username}:${request.password}'));
      final res = await dio.post<Map<String, dynamic>>(
        'https://plex.tv/users/sign_in.json',
        options: Options(headers: {
          'Authorization': 'Basic $credentials',
          'X-Plex-Client-Identifier': 'liusound-${DateTime.now().millisecondsSinceEpoch}',
          'X-Plex-Product': 'LiuSound',
          'X-Plex-Device': 'Flutter',
        }),
      );
      final data = res.data ?? const {};
      final user = data['user'] as Map<String, dynamic>?;
      final token = user?['authToken']?.toString() ?? '';
      if (token.isEmpty) throw Exception('Plex 认证失败');

      final plexDio = Dio(BaseOptions(
        baseUrl: request.serverUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ));
      try {
        final serverRes = await plexDio.get<Map<String, dynamic>>(
          '/identity',
          queryParameters: {'X-Plex-Token': token},
        );
        final machineId =
            serverRes.data?['MediaContainer']?['machineIdentifier']?.toString() ?? '';

        final sectionsRes = await plexDio.get<Map<String, dynamic>>(
          '/library/sections',
          queryParameters: {'X-Plex-Token': token},
        );
        final dirs = (sectionsRes.data?['MediaContainer']?['Directory']
                as List<dynamic>?) ??
            const [];
        String musicKey = '';
        for (final d in dirs) {
          if (d is Map<String, dynamic> && d['type'] == 'artist') {
            musicKey = d['key']?.toString() ?? '';
            break;
          }
        }

        return AdapterSession(
          secrets: {
            'plexToken': token,
            'machineId': machineId,
            'musicSectionKey': musicKey,
          },
          displayName: user?['username']?.toString() ??
              user?['title']?.toString(),
        );
      } finally {
        plexDio.close();
      }
    } finally {
      dio.close();
    }
  }

  // ---------- 专辑 ----------

  @override
  Future<List<Album>> fetchAlbums(AlbumQuery query) async {
    final sort = switch (query.sort) {
      AlbumSort.recentlyAdded => 'addedAt:desc',
      AlbumSort.recentlyPlayed => 'lastViewedAt:desc',
      AlbumSort.mostPlayed => 'viewCount:desc',
      AlbumSort.random => 'random',
      AlbumSort.name => 'titleSort:asc',
      AlbumSort.year => 'year:desc',
    };
    final data = await _api('/library/sections/$_musicSectionKey/albums', {
      'sort': sort,
      'X-Plex-Container-Start': '${query.start}',
      'X-Plex-Container-Size': '${query.limit}',
    });
    return _parseAlbums(data);
  }

  @override
  Future<List<Album>> fetchArtistAlbums(String artistId) async {
    final data = await _api('/library/metadata/$artistId/children', {});
    return _parseAlbums(data);
  }

  // ---------- 歌曲 ----------

  @override
  Future<List<Song>> fetchSongs(SongQuery query) async {
    if (query.albumId != null) return fetchAlbumSongs(query.albumId!);
    final params = <String, String>{
      'X-Plex-Container-Start': '${query.start}',
      'X-Plex-Container-Size': '${query.limit}',
    };
    if (query.sort != null) {
      params['sort'] = switch (query.sort!) {
        SongSort.title => 'titleSort:asc',
        SongSort.random => 'random',
        SongSort.rating => 'rating:desc',
        SongSort.recentlyAdded => 'addedAt:desc',
        SongSort.recentlyPlayed => 'lastViewedAt:desc',
        SongSort.mostPlayed => 'viewCount:desc',
        SongSort.track => 'index:asc',
      };
    }
    if (query.starredOnly) {
      final data = await _api('/library/sections/$_musicSectionKey/stars', params);
      return _parseSongs(data);
    }
    final data = await _api('/library/sections/$_musicSectionKey/all', {
      ...params,
      'type': '9',
    });
    return _parseSongs(data);
  }

  @override
  Future<List<Song>> fetchAlbumSongs(String albumId) async {
    final data = await _api('/library/metadata/$albumId/children', {});
    return _parseSongs(data);
  }

  @override
  Future<List<Song>> fetchArtistSongs(String artistId, {int limit = 30}) async {
    final data = await _api('/library/sections/$_musicSectionKey/all', {
      'artist.id': artistId,
      'type': '9',
      'sort': 'rating:desc',
      'X-Plex-Container-Size': '$limit',
    });
    return _parseSongs(data);
  }

  // ---------- 歌单 / 喜欢 / 总数 ----------

  @override
  Future<List<Playlist>> fetchPlaylists() async {
    final data = await _api('/playlists', {});
    final items = _containerItems(data);
    return items.map((e) {
      return Playlist(
        id: _s(e, 'ratingKey'),
        name: _s(e, 'title', '未命名歌单'),
        songCount: _i(e, 'leafCount'),
      );
    }).toList();
  }

  @override
  Future<List<Song>> fetchPlaylistSongs(String playlistId) async {
    final data = await _api('/playlists/$playlistId/items', {});
    return _parseSongs(data);
  }

  @override
  Future<List<Song>> fetchLikedSongs({int limit = 100}) async {
    final data = await _api('/library/sections/$_musicSectionKey/stars', {
      'X-Plex-Container-Size': '$limit',
    });
    return _parseSongs(data);
  }

  @override
  Future<List<Song>> fetchSimilarSongs(String songId, {int count = 20}) async =>
      const [];

  @override
  Future<int> fetchSongCount() async {
    final data = await _api('/library/sections/$_musicSectionKey/all', {
      'type': '9',
      'X-Plex-Container-Size': '0',
    });
    final mc = data['MediaContainer'] as Map<String, dynamic>?;
    return _i(mc ?? const {}, 'totalSize');
  }

  // ---------- 搜索 ----------

  @override
  Future<SearchResult> search(String query) async {
    final data = await _api('/search', {
      'query': query,
      'sectionId': _musicSectionKey,
    });
    final items = _containerItems(data);
    final songs = <Song>[];
    final albums = <Album>[];
    final artists = <Artist>[];
    for (final e in items) {
      switch (_s(e, 'type')) {
        case 'track':
          songs.add(_toSong(e));
        case 'album':
          albums.add(_toAlbum(e));
        case 'artist':
          artists.add(Artist(
            id: _s(e, 'ratingKey'),
            name: _s(e, 'title', '未知歌手'),
            albumCount: _i(e, 'albumCount'),
            songCount: 0,
          ));
      }
    }
    return SearchResult(songs: songs, albums: albums, artists: artists);
  }

  // ---------- 动作 ----------

  @override
  Future<bool> setStar(String id, bool rating) async {
    try {
      if (rating) {
        await _api('/:/rate', {'key': id, 'rating': '10', 'identifier': 'com.plexapp.plugins.library'});
      } else {
        await _api('/:/rate', {'key': id, 'rating': '0', 'identifier': 'com.plexapp.plugins.library'});
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setRating(String id, int rating) async {
    try {
      final plexRating = (rating * 2).toString();
      await _api('/:/rate', {'key': id, 'rating': plexRating, 'identifier': 'com.plexapp.plugins.library'});
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> addToPlaylist(String playlistId, String songId) async {
    try {
      await _api('/playlists/$playlistId/items', {
        'uri': 'server://$_machineId/com.plexapp.plugins.library/library/metadata/$songId',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- 媒体 ----------

  @override
  Future<PlaybackSource> resolveStream(Song song) async {
    return PlaybackSource(
      url: '${_config.serverUrl}/library/metadata/${song.id}?X-Plex-Token=$_token',
    );
  }

  @override
  Future<PlaybackSource> resolveDownload(Song song) async {
    return PlaybackSource(
      url: '${_config.serverUrl}/library/metadata/${song.id}?download=1&X-Plex-Token=$_token',
    );
  }

  @override
  ImageSource? coverImage(String albumId, {int size = 300}) {
    if (albumId.isEmpty) return null;
    return ImageSource(
      url: '${_config.serverUrl}/library/metadata/$albumId/thumb?X-Plex-Token=$_token&width=$size',
    );
  }

  @override
  Future<Uint8List?> fetchCoverBytes(String albumId, {int size = 64}) async {
    if (albumId.isEmpty) return null;
    try {
      final url =
          '${_config.serverUrl}/library/metadata/$albumId/thumb?X-Plex-Token=$_token&width=$size';
      final resp = await _dio.get<Uint8List>(url,
          options: Options(responseType: ResponseType.bytes));
      return resp.data;
    } catch (_) {
      return null;
    }
  }

  // ---------- 生命周期 ----------

  @override
  Future<bool> validateSession() async {
    try {
      await _api('/identity', {});
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() => _dio.close();

  // ========== 内部工具 ==========

  Future<Map<String, dynamic>> _api(
      String path, Map<String, String> params) async {
    final res = await _dio.get<Map<String, dynamic>>(path,
        queryParameters: {...params, 'X-Plex-Token': _token});
    return res.data ?? const {};
  }

  List<dynamic> _containerItems(Map<String, dynamic> data) {
    final mc = data['MediaContainer'] as Map<String, dynamic>?;
    if (mc == null) return const [];
    return (mc['Metadata'] ?? mc['Server'] ?? const []) as List<dynamic>;
  }

  List<Album> _parseAlbums(Map<String, dynamic> data) {
    return _containerItems(data)
        .whereType<Map<String, dynamic>>()
        .map(_toAlbum)
        .toList();
  }

  List<Song> _parseSongs(Map<String, dynamic> data) {
    return _containerItems(data)
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  Song _toSong(Map<String, dynamic> j) {
    final durationMs = _i(j, 'duration');
    return Song(
      id: _s(j, 'ratingKey'),
      title: _s(j, 'title', '未知歌曲'),
      artist: _s(j, 'grandparentTitle', '未知歌手'),
      album: _s(j, 'parentTitle'),
      albumId: _s(j, 'parentRatingKey'),
      artistId: _s(j, 'grandparentRatingKey'),
      duration: durationMs / 1000,
      playCount: _i(j, 'viewCount'),
      starred: j['userRating'] != null,
      size: _i(j, 'size'),
      rating: ((_i(j, 'userRating')) / 2).round(),
    );
  }

  Album _toAlbum(Map<String, dynamic> j) {
    return Album(
      id: _s(j, 'ratingKey'),
      name: _s(j, 'title', '未知专辑'),
      artist: _s(j, 'parentTitle', '未知歌手'),
      artistId: _s(j, 'parentRatingKey'),
      songCount: _i(j, 'leafCount'),
      duration: (_i(j, 'duration')) / 1000,
      playCount: _i(j, 'viewCount'),
      starred: j['userRating'] != null,
      rating: ((_i(j, 'userRating')) / 2).round(),
      year: _iOrNull(j, 'year'),
    );
  }

  static String _s(Map<String, dynamic> j, String k, [String d = '']) =>
      j[k]?.toString() ?? d;
  static int _i(Map<String, dynamic> j, String k) =>
      (j[k] as num?)?.toInt() ?? 0;
  static int? _iOrNull(Map<String, dynamic> j, String k) =>
      (j[k] as num?)?.toInt();
}
