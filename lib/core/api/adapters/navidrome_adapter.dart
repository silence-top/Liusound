import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/models.dart';
import '../../network/http_factory.dart';
import '../../settings/streaming_prefs.dart';
import '../../storage/auth_store.dart';
import '../../subsonic/subsonic.dart';
import '../navidrome_client.dart';
import '../server_adapter.dart';
import '../server_type.dart';

class NavidromeAdapter implements ServerAdapter {
  NavidromeAdapter({
    required ServerConfig config,
    required Map<String, String> secrets,
  }) : _config = config,
       _secrets = secrets {
    _client = NavidromeClient();
    NetworkRuntime.configureDio(_client.dio);
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
  ServerType get type => ServerType.navidrome;

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities(
    ratings: true,
    similarSongs: true,
    likedSongs: true,
    download: true,
    lyrics: true,
    artistBio: true,
    transcoding: true,
    scrobbling: true,
    incrementalSync: true,
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
    if (query.artistId != null) params['artist_id'] = query.artistId;
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

  @override
  Future<String?> libraryVersion() async {
    try {
      final res = await _client.dio.get<Map<String, dynamic>>(
        '/rest/getMusicFolders',
        queryParameters: Subsonic.params(_subsonicAuth),
      );
      final resp = res.data?['subsonic-response'] as Map<String, dynamic>?;
      if (resp == null || resp['status']?.toString() != 'ok') return null;
      return Subsonic.musicFoldersVersion(resp);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _subsonicAction(Map<String, String> extra) async {
    try {
      final res = await _client.dio.get<Map<String, dynamic>>(
        '/rest/scrobble',
        queryParameters: Subsonic.params(_subsonicAuth, extra),
      );
      final resp = res.data?['subsonic-response'] as Map<String, dynamic>?;
      return resp?['status']?.toString() == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Navidrome 全量兼容 Subsonic API；返回解包后的 subsonic-response
  Future<Map<String, dynamic>?> _subsonicGet(
    String endpoint,
    Map<String, String> extra,
  ) async {
    try {
      final res = await _client.dio.get<Map<String, dynamic>>(
        '/rest/$endpoint',
        queryParameters: Subsonic.params(_subsonicAuth, extra),
      );
      final resp = res.data?['subsonic-response'] as Map<String, dynamic>?;
      if (resp == null || resp['status']?.toString() != 'ok') return null;
      return resp;
    } catch (_) {
      return null;
    }
  }

  // ---------- 资料库扩展 ----------

  @override
  Future<List<Artist>?> fetchArtists() async {
    final data = await _subsonicGet('getIndexes', const {});
    final indexes = data?['indexes']?['index'] as List<dynamic>?;
    if (indexes == null) return null;
    return [for (final index in indexes) ..._artistsOfIndex(index)];
  }

  @override
  Future<List<Artist>?> fetchAlbumArtists() async {
    final data = await _subsonicGet('getArtists', const {});
    final indexes = data?['artists']?['index'] as List<dynamic>?;
    if (indexes == null) return null;
    return [for (final index in indexes) ..._artistsOfIndex(index)];
  }

  List<Artist> _artistsOfIndex(dynamic index) {
    if (index is! Map<String, dynamic>) return const [];
    final artists = index['artist'] as List<dynamic>? ?? const [];
    return [
      for (final a in artists)
        if (a is Map<String, dynamic>)
          Artist(
            id: a['id']?.toString() ?? '',
            name: a['name']?.toString() ?? '未知歌手',
            albumCount: (a['albumCount'] as num?)?.toInt() ?? 0,
            songCount: (a['songCount'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  @override
  Future<List<Genre>?> fetchGenres() async {
    final data = await _subsonicGet('getGenres', const {});
    final genres = data?['genres']?['genre'] as List<dynamic>?;
    if (genres == null) return null;
    return [
      for (final g in genres)
        if (g is Map<String, dynamic>)
          Genre(
            value: (g['value'] ?? g['name'] ?? g['genre'] ?? '').toString(),
            songCount: (g['count'] as num?)?.toInt() ?? 0,
            albumCount: (g['albumCount'] as num?)?.toInt() ?? 0,
          ),
    ].where((g) => g.value.isNotEmpty).toList();
  }

  @override
  Future<List<RadioStation>?> fetchRadioStations() async {
    final data = await _subsonicGet('getInternetRadioStations', const {});
    final stations =
        data?['internetRadioStations']?['station'] as List<dynamic>?;
    if (stations == null) return null;
    return [
      for (final s in stations)
        if (s is Map<String, dynamic>)
          RadioStation(
            id: s['id']?.toString() ?? '',
            name: s['name']?.toString() ?? '未命名电台',
            streamUrl: s['streamUrl']?.toString() ?? '',
            homePageUrl: s['homePageUrl']?.toString(),
          ),
    ];
  }

  @override
  Future<List<Song>?> fetchGenreSongs(String genre, {int limit = 100}) async {
    final data = await _subsonicGet('getSongsByGenre', {
      'genre': genre,
      'count': '$limit',
    });
    final songs = data?['songsByGenre']?['song'] as List<dynamic>?;
    if (songs == null) return null;
    return songs.whereType<Map<String, dynamic>>().map(Song.fromJson).toList();
  }

  @override
  Future<PlaybackSource> resolveStream(
    Song song, {
    QualityHint? quality,
  }) async {
    final auth = _subsonicAuth;
    final transcode = quality?.transcode == true;
    return PlaybackSource(
      url: Subsonic.streamUrl(
        auth,
        song.id,
        maxBitRate: transcode ? quality!.quality.bitRate : null,
        format: transcode ? quality!.format.name : null,
      ),
    );
  }

  bool? _transcodeProbe;

  @override
  Future<bool> supportsTranscode() async {
    final cached = _transcodeProbe;
    if (cached != null) return cached;
    // 先读持久化结果，避免每次冷启动首播前重探（探测要发 2 个网络请求）
    final persisted = await TranscodeProbeCache.get(
      _config.serverUrl,
      _config.username,
    );
    if (persisted != null) {
      _transcodeProbe = persisted;
      return persisted;
    }
    final result = await _probeTranscode();
    _transcodeProbe = result;
    unawaited(
      TranscodeProbeCache.set(_config.serverUrl, _config.username, result),
    );
    return result;
  }

  /// 静默探测转码能力：Navidrome 转码依赖服务器装有 ffmpeg，
  /// 声明支持不代表真能转。取一首歌请求 64kbps 转码流，只读响应头。
  /// 探测异常放行，交由播放侧回退兜底
  Future<bool> _probeTranscode() async {
    try {
      final songs = await fetchSongs(
        const SongQuery(sort: SongSort.random, limit: 1),
      );
      if (songs.isEmpty) return true;
      final resp = await _client.dio.get<ResponseBody>(
        Subsonic.streamUrl(
          _subsonicAuth,
          songs.first.id,
          maxBitRate: 64,
          format: 'mp3',
        ),
        options: Options(
          responseType: ResponseType.stream,
          // 非 200 也要拿到响应体类型用于判别，不进异常路径
          validateStatus: (_) => true,
        ),
      );
      // 取消订阅关闭底层连接，避免服务端转码流不支持 Range 时整首下载
      final sub = resp.data!.stream.listen((_) {});
      await sub.cancel();
      final type = resp.headers.value('content-type') ?? '';
      return resp.statusCode == 200 && type.startsWith('audio/');
    } catch (_) {
      return true;
    }
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
