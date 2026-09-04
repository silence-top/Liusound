import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../models/models.dart';
import '../../network/http_factory.dart';
import '../../settings/streaming_prefs.dart';
import '../../subsonic/subsonic.dart';
import '../server_adapter.dart';
import '../server_type.dart';

/// 纯 Subsonic 协议适配器（兼容 Subsonic、AirSonic、Navidrome Subsonic 层等）。
/// 认证：md5(password + salt)；媒体直链复用 [Subsonic] URL 构建。
class SubsonicAdapter implements ServerAdapter {
  SubsonicAdapter({
    required ServerConfig config,
    required Map<String, String> secrets,
  }) : _config = config,
       _secrets = secrets {
    _dio.options.baseUrl = config.serverUrl;
    NetworkRuntime.configureDio(_dio);
  }

  final ServerConfig _config;
  final Map<String, String> _secrets;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  SubsonicAuth get _auth => SubsonicAuth(
    serverUrl: _config.serverUrl,
    username: _config.username,
    subsonicToken: _secrets['subsonicToken'] ?? '',
    subsonicSalt: _secrets['subsonicSalt'] ?? '',
  );

  @override
  ServerType get type => ServerType.subsonic;

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
    final salt = _randomHex(8);
    final token = md5.convert('${request.password}$salt'.codeUnits).toString();
    final dio = Dio(
      BaseOptions(
        baseUrl: request.serverUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final res = await dio.get<Map<String, dynamic>>(
        '/rest/ping',
        queryParameters: {
          'u': request.username,
          't': token,
          's': salt,
          'f': 'json',
          'v': Subsonic.apiVersion,
          'c': Subsonic.client,
        },
      );
      final status =
          res.data?['subsonic-response']?['status']?.toString() ?? '';
      if (status != 'ok') throw Exception('Subsonic 认证失败');
      return AdapterSession(
        secrets: {'subsonicToken': token, 'subsonicSalt': salt},
        displayName: request.username.isNotEmpty ? request.username : null,
      );
    } finally {
      dio.close();
    }
  }

  // ---------- 专辑 ----------

  @override
  Future<List<Album>> fetchAlbums(AlbumQuery query) async {
    final type = switch (query.sort) {
      AlbumSort.recentlyAdded => 'newest',
      AlbumSort.recentlyPlayed => 'recent',
      AlbumSort.mostPlayed => 'frequent',
      AlbumSort.random => 'random',
      AlbumSort.name => 'alphabeticalByName',
      AlbumSort.year => 'byYear',
    };
    final params = <String, String>{
      'type': type,
      'size': '${query.limit}',
      'offset': '${query.start}',
    };
    if (query.seed != null && query.sort == AlbumSort.random) {
      params['seed'] = query.seed!;
    }
    final data = await _api('getAlbumList2', params);
    final list = data['albumList2']?['album'] as List<dynamic>?;
    return (list ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toAlbum)
        .toList();
  }

  @override
  Future<List<Album>> fetchArtistAlbums(String artistId) async {
    final data = await _api('getArtist', {'id': artistId});
    final artist = data['artist'] as Map<String, dynamic>?;
    final albums = artist?['album'] as List<dynamic>?;
    return (albums ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toAlbum)
        .toList();
  }

  // ---------- 歌曲 ----------

  @override
  Future<List<Song>> fetchSongs(SongQuery query) async {
    if (query.albumId != null) return fetchAlbumSongs(query.albumId!);
    if (query.starredOnly) return fetchLikedSongs(limit: query.limit);
    if (query.artistId != null) {
      return fetchArtistSongs(query.artistId!, limit: query.limit);
    }
    // Subsonic 协议没有歌曲级最近/最常播放接口（getAlbumList2 仅专辑级）
    if (query.sort == SongSort.recentlyPlayed ||
        query.sort == SongSort.mostPlayed) {
      return const [];
    }
    final data = await _api('getRandomSongs', {'size': '${query.limit}'});
    final list = data['randomSongs']?['song'] as List<dynamic>?;
    return (list ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  @override
  Future<List<Song>> fetchAlbumSongs(String albumId) async {
    final data = await _api('getAlbum', {'id': albumId});
    final album = data['album'] as Map<String, dynamic>?;
    final songs = album?['song'] as List<dynamic>?;
    return (songs ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  @override
  Future<List<Song>> fetchArtistSongs(String artistId, {int limit = 30}) async {
    final name = await _artistName(artistId);
    if (name == null) return const [];
    final data = await _api('getTopSongs', {'artist': name, 'count': '$limit'});
    final list = data['topSongs']?['song'] as List<dynamic>?;
    return (list ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  // ---------- 歌单 / 喜欢 / 总数 ----------

  @override
  Future<List<Playlist>> fetchPlaylists() async {
    final data = await _api('getPlaylists', {});
    final list = data['playlists']?['playlist'] as List<dynamic>?;
    return (list ?? const []).whereType<Map<String, dynamic>>().map((e) {
      return Playlist(
        id: _str(e, 'id'),
        name: _str(e, 'name', '未命名歌单'),
        songCount: _int(e, 'songCount'),
      );
    }).toList();
  }

  @override
  Future<List<Song>> fetchPlaylistSongs(String playlistId) async {
    final data = await _api('getPlaylist', {'id': playlistId});
    final playlist = data['playlist'] as Map<String, dynamic>?;
    final songs = playlist?['entry'] as List<dynamic>?;
    return (songs ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  @override
  Future<List<Song>> fetchLikedSongs({int limit = 100}) async {
    final data = await _api('getStarred2', {});
    final songs = data['starred2']?['song'] as List<dynamic>?;
    return (songs ?? const [])
        .whereType<Map<String, dynamic>>()
        .take(limit)
        .map(_toSong)
        .toList();
  }

  @override
  Future<List<Song>> fetchSimilarSongs(String songId, {int count = 20}) async {
    final data = await _api('getSimilarSongs2', {
      'id': songId,
      'count': '$count',
    });
    final list = data['similarSongs2']?['song'] as List<dynamic>?;
    return (list ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  @override
  Future<String?> fetchArtistBio(String artistId) async {
    try {
      final data = await _api('getArtistInfo', {'id': artistId});
      final info =
          (data['artistInfo'] ?? data['artistInfo2'])
              as Map<String, dynamic>? ??
          const {};
      final bio = info['biography']?.toString().trim() ?? '';
      return bio.isEmpty ? null : bio;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> fetchSongCount() async {
    final data = await _api('getAlbumList2', {'type': 'newest', 'size': '1'});
    final list = data['albumList2']?['album'] as List<dynamic>?;
    return list?.length ?? 0;
  }

  // ---------- 搜索 ----------

  @override
  Future<SearchResult> search(String query) async {
    final data = await _api('search3', {
      'query': query,
      'songCount': '20',
      'albumCount': '20',
      'artistCount': '20',
    });
    final s3 = data['searchResult3'] as Map<String, dynamic>? ?? const {};
    return SearchResult(
      songs: ((s3['song'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_toSong)
          .toList(),
      albums: ((s3['album'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_toAlbum)
          .toList(),
      artists: ((s3['artist'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (e) => Artist(
              id: _str(e, 'id'),
              name: _str(e, 'name', '未知歌手'),
              albumCount: _int(e, 'albumCount'),
              songCount: _int(e, 'songCount'),
            ),
          )
          .toList(),
    );
  }

  // ---------- 动作 ----------

  @override
  Future<bool> setStar(String id, bool starred) =>
      _action(starred ? 'star' : 'unstar', {'id': id});

  @override
  Future<bool> setRating(String id, int rating) =>
      _action('setRating', {'id': id, 'rating': '$rating'});

  @override
  Future<bool> addToPlaylist(String playlistId, String songId) =>
      _action('createPlaylist', {'playlistId': playlistId, 'songId': songId});

  /// Subsonic 的 createPlaylist 只传 name（不带 playlistId）即为新建
  @override
  Future<bool> createPlaylist(String name) =>
      _action('createPlaylist', {'name': name});

  /// submission=true 为完成上报（scrobble）；false 为「正在播放」
  @override
  Future<bool> scrobble(String songId) =>
      _action('scrobble', {'id': songId, 'submission': 'true'});

  @override
  Future<bool> nowPlaying(String songId) =>
      _action('scrobble', {'id': songId, 'submission': 'false'});

  @override
  Future<String?> libraryVersion() async {
    try {
      final data = await _api('getMusicFolders', {});
      return Subsonic.musicFoldersVersion(data);
    } catch (_) {
      return null;
    }
  }

  // ---------- 媒体 ----------

  @override
  Future<PlaybackSource> resolveStream(
    Song song, {
    QualityHint? quality,
  }) async {
    final hint = quality;
    return PlaybackSource(
      url: Subsonic.streamUrl(
        _auth,
        song.id,
        maxBitRate: hint?.transcode == true ? hint!.quality.bitRate : null,
        format: hint?.transcode == true ? hint!.format.name : null,
      ),
    );
  }

  bool? _transcodeProbe;

  @override
  Future<bool> supportsTranscode() async {
    final cached = _transcodeProbe;
    if (cached != null) return cached;
    final result = await _probeTranscode();
    _transcodeProbe = result;
    return result;
  }

  /// 静默探测转码能力：取一首歌请求 64kbps 转码流，只读响应头不下载内容。
  /// 响应是音频流 → 支持；返回 JSON 错误/HTTP 错误 → 服务端缺转码器。
  /// 探测异常（网络抖动/曲库为空）放行，交由播放侧回退兜底
  Future<bool> _probeTranscode() async {
    try {
      final songs = await fetchSongs(
        const SongQuery(sort: SongSort.random, limit: 1),
      );
      if (songs.isEmpty) return true;
      final resp = await _dio.get<ResponseBody>(
        Subsonic.streamUrl(
          _auth,
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
  Future<PlaybackSource> resolveDownload(Song song) async =>
      PlaybackSource(url: Subsonic.downloadUrl(_auth, song.id));

  @override
  ImageSource? coverImage(String albumId, {int size = 300}) {
    if (!_auth.isValid || albumId.isEmpty) return null;
    return ImageSource(url: Subsonic.coverArtUrl(_auth, albumId));
  }

  @override
  Future<Uint8List?> fetchCoverBytes(String albumId, {int size = 64}) async {
    if (!_auth.isValid || albumId.isEmpty) return null;
    try {
      final url = Subsonic.coverArtUrl(_auth, albumId);
      final resp = await _dio.get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      return resp.data;
    } catch (_) {
      return null;
    }
  }

  // ---------- 生命周期 ----------

  @override
  Future<bool> validateSession() async {
    try {
      await _api('ping', {});
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() => _dio.close();

  // ========== 内部工具 ==========

  Map<String, String> get _baseParams => Subsonic.params(_auth);

  Future<Map<String, dynamic>> _api(
    String endpoint,
    Map<String, String> extra,
  ) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/rest/$endpoint',
      queryParameters: {..._baseParams, ...extra},
    );
    return _unwrap(res.data);
  }

  Future<bool> _action(String endpoint, Map<String, String> extra) async {
    try {
      final data = await _api(endpoint, extra);
      return data['status']?.toString() == 'ok';
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic>? raw) {
    if (raw == null) throw Exception('空响应');
    final resp = raw['subsonic-response'] as Map<String, dynamic>?;
    if (resp == null || resp['status'] != 'ok') {
      throw Exception('Subsonic 请求失败');
    }
    return resp;
  }

  Future<String?> _artistName(String artistId) async {
    try {
      final data = await _api('getArtist', {'id': artistId});
      return _str(data['artist'] as Map<String, dynamic>? ?? const {}, 'name');
    } catch (_) {
      return null;
    }
  }

  // ---------- JSON 映射 ----------

  Song _toSong(Map<String, dynamic> j) => Song(
    id: _str(j, 'id'),
    title: _str(j, 'title', '未知歌曲'),
    artist: _str(j, 'artist', '未知歌手'),
    album: _str(j, 'album'),
    albumId: _str(j, 'albumId'),
    artistId: _str(j, 'artistId'),
    duration: _num(j, 'duration'),
    playCount: _int(j, 'playCount'),
    starred: j['starred'] != null,
    size: _int(j, 'size'),
    rating: _int(j, 'rating'),
    suffix: _firstStr(j, const ['suffix', 'transcodedSuffix']),
    codec: _firstStr(j, const ['contentType', 'transcodedContentType']),
    bitRate: _intOrNull(j, 'bitRate'),
    sampleRate: _khzToHz(_num(j, 'samplingRate')),
    albumArtist: _firstStr(j, const ['albumArtist', 'displayAlbumArtist']),
    year: _intOrNull(j, 'year'),
    discNumber: _intOrNull(j, 'discNumber'),
    trackNumber: _intOrNull(j, 'track'),
    path: _firstStr(j, const ['path']),
    lastPlayed: j['played']?.toString(),
    created: j['created']?.toString(),
    replayGain: _replayGain(j),
  );

  /// OpenSubsonic 扩展：child 里的 replayGain 对象（albumGain/albumPeak/trackGain/trackPeak）
  static ReplayGain? _replayGain(Map<String, dynamic> j) {
    final rg = j['replayGain'];
    if (rg is! Map<String, dynamic>) return null;
    return ReplayGain(
      albumGain: _doubleOrNull(rg, 'albumGain'),
      albumPeak: _doubleOrNull(rg, 'albumPeak'),
      trackGain: _doubleOrNull(rg, 'trackGain'),
      trackPeak: _doubleOrNull(rg, 'trackPeak'),
    );
  }

  static double? _doubleOrNull(Map<String, dynamic> j, String k) {
    final v = j[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  Album _toAlbum(Map<String, dynamic> j) => Album(
    id: _str(j, 'id'),
    name: _str(j, 'name', '未知专辑'),
    artist: _str(j, 'artist', '未知歌手'),
    artistId: _str(j, 'artistId'),
    songCount: _int(j, 'songCount'),
    duration: _num(j, 'duration'),
    playCount: _int(j, 'playCount'),
    starred: j['starred'] != null,
    rating: _int(j, 'rating'),
    year: _intOrNull(j, 'year'),
  );

  static String _str(Map<String, dynamic> j, String k, [String d = '']) =>
      j[k]?.toString() ?? d;
  static int _int(Map<String, dynamic> j, String k) =>
      (j[k] as num?)?.toInt() ?? 0;
  static int? _intOrNull(Map<String, dynamic> j, String k) =>
      (j[k] as num?)?.toInt();
  static double _num(Map<String, dynamic> j, String k) =>
      (j[k] as num?)?.toDouble() ?? 0;

  /// 按候选键顺序取第一个非空字符串；用于「原始格式 → 转码格式」回退
  static String? _firstStr(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      final v = j[k]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  /// Subsonic 协议的 samplingRate 单位是 kHz（44.1），统一归一为 Hz
  static int? _khzToHz(double khz) => khz <= 0 ? null : (khz * 1000).round();

  static String _randomHex(int bytes) {
    final r = Random.secure();
    return List.generate(
      bytes,
      (_) => r.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
