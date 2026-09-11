import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../errors/app_error.dart';
import '../../lyrics/lyrics.dart';
import '../../models/models.dart';
import '../../network/http_factory.dart';
import '../../settings/streaming_prefs.dart';
import '../adapter_log.dart';
import '../server_adapter.dart';
import '../server_type.dart';

/// 飞牛 fnOS 音乐适配器。
/// 认证：POST /user/password-login（密码客户端 SHA256 小写 hex）→ userToken；
/// 后续请求经 Cookie `music-token=<32hex>` 携带（请求头形式服务端不认）。
/// API 均为 JSON，统一信封 `{code, msg, data}`：code 0 成功、99999 token 失效。
/// 分页 1-based（page/size/sort=`字段,方向`）。
class FnOsAdapter with SecretsUpdatable implements ServerAdapter {
  FnOsAdapter({
    required ServerConfig config,
    required Map<String, String> secrets,
    NetworkSettings networkSettings = const NetworkSettings(),
  }) : _config = config,
       _token = secrets['token'] ?? '',
       _deviceId = secrets['deviceId'] ?? '',
       _password = secrets['password'] ?? '' {
    _dio.options.baseUrl = _apiBase(config.serverUrl);
    NetworkRuntime.configureDio(_dio, networkSettings);
  }

  final ServerConfig _config;
  String _token;
  final String _deviceId;
  final String _password;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  /// guid → coverId 缓存（track/album/artist 的 guid）。
  /// 封面 URL 需要 coverId 而调用方只有实体 id，靠解析列表响应时顺路缓存
  final Map<String, String> _coverIds = {};

  @override
  ServerType get type => ServerType.fnos;

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities(
    ratings: false,
    similarSongs: false,
    download: true,
    transcoding: false,
    scrobbling: false,
    versionedSnapshot: false,
  );

  /// fnOS 音乐固定挂载在 /music 子路径；用户只填 host:port 时自动补上
  static String _apiBase(String serverUrl) {
    var url = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    if (!url.endsWith('/music')) url = '$url/music';
    return url;
  }

  static String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  static String _newDeviceId() {
    final rnd = Random.secure();
    return List.generate(32, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  static Future<AdapterSession> signIn(AuthRequest request) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: _apiBase(request.serverUrl),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final res = await dio.post<Map<String, dynamic>>(
        '/api/v1/user/password-login',
        data: {
          'username': request.username,
          'password': hashPassword(request.password),
          'deviceId': _newDeviceId(),
        },
      );
      final body = res.data ?? const {};
      final code = (body['code'] as num?)?.toInt() ?? -1;
      if (code != 0) {
        final msg = body['msg']?.toString() ?? '';
        throw AuthError(msg.isEmpty ? '飞牛音乐认证失败' : '飞牛音乐认证失败：$msg');
      }
      final data = body['data'] as Map<String, dynamic>? ?? const {};
      final token = data['userToken']?.toString() ?? '';
      if (token.isEmpty) throw AuthError('飞牛音乐认证失败：无凭证');
      final deviceId = data['deviceId']?.toString() ?? _newDeviceId();
      return AdapterSession(
        secrets: {
          'token': token,
          'deviceId': deviceId,
          'password': request.password,
        },
        displayName: request.username.isNotEmpty ? request.username : null,
      );
    } finally {
      dio.close();
    }
  }

  /// 统一信封解包：code != 0 抛错；99999（token 失效）触发静默重登重试一次
  static Future<Map<String, dynamic>> _envelope(
    Response<Map<String, dynamic>?> res,
  ) async {
    final body = res.data ?? const {};
    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code == 0) {
      return body['data'] as Map<String, dynamic>? ?? const {};
    }
    throw ServerError(
      body['msg']?.toString().isEmpty ?? true
          ? '飞牛音乐请求失败'
          : body['msg'].toString(),
    );
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, dynamic> query,
  ) async {
    final res = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: query,
      options: Options(headers: _headers),
    );
    final body = res.data ?? const {};
    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code == 99999) {
      await _relogin();
      final retry = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: query,
        options: Options(headers: _headers),
      );
      return _envelope(retry);
    }
    return _envelope(res);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: Options(headers: _headers),
    );
    final envelope = res.data ?? const {};
    final code = (envelope['code'] as num?)?.toInt() ?? -1;
    if (code == 99999) {
      await _relogin();
      final retry = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(headers: _headers),
      );
      return _envelope(retry);
    }
    return _envelope(res);
  }

  Map<String, String> get _headers => {'Cookie': 'music-token=$_token'};

  Future<void> _relogin() async {
    if (_password.isEmpty) throw AuthError('无密码，无法重新登录');
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/user/password-login',
      data: {
        'username': _config.username,
        'password': hashPassword(_password),
        'deviceId': _deviceId.isEmpty ? _newDeviceId() : _deviceId,
      },
    );
    final data = await _envelope(res);
    final token = data['userToken']?.toString() ?? '';
    if (token.isEmpty) throw AuthError('飞牛音乐重新登录失败');
    _token = token;
    // 新 token 上报持久化，下次冷启动直接可用
    onSecretsUpdated?.call({
      'token': token,
      'deviceId': _deviceId.isEmpty ? _newDeviceId() : _deviceId,
      'password': _password,
    });
  }

  // ---------- 列表分页工具 ----------

  /// fnOS 分页 1-based；调用方给的是 offset
  Map<String, dynamic> _pageQuery(int start, int limit, String? sort) => {
    'page': '${start ~/ limit + 1}',
    'size': '$limit',
    'sort': ?sort,
  };

  List<Map<String, dynamic>> _listOf(Map<String, dynamic> data) =>
      (data['list'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  // ---------- 专辑 ----------

  @override
  Future<List<Album>> fetchAlbums(AlbumQuery query) async {
    final sort = switch (query.sort) {
      AlbumSort.recentlyAdded => 'newTrackAddedAt,desc',
      AlbumSort.name => 'name,asc',
      AlbumSort.recentlyPlayed || AlbumSort.mostPlayed => null,
      _ => null,
    };
    final data = await _get('/api/v1/album/list', {
      ..._pageQuery(query.start, query.limit, sort),
    });
    return _listOf(data).map(_toAlbum).toList();
  }

  @override
  Future<List<Album>> fetchArtistAlbums(String artistId) async {
    final data = await _get('/api/v1/album/artist-detail/list', {
      'artistGUID': artistId,
      'page': '1',
      'size': '500',
    });
    return _listOf(data).map(_toAlbum).toList();
  }

  // ---------- 歌曲 ----------

  @override
  Future<List<Song>> fetchSongs(SongQuery query) async {
    if (query.albumId != null) return fetchAlbumSongs(query.albumId!);
    if (query.starredOnly) return fetchLikedSongs(limit: query.limit);
    if (query.artistId != null) {
      return fetchArtistSongs(query.artistId!, limit: query.limit);
    }
    final sort = switch (query.sort) {
      SongSort.title => 'title,asc',
      SongSort.recentlyAdded => 'createdAt,desc',
      _ => null,
    };
    final data = await _get('/api/v1/track/list', {
      ..._pageQuery(query.start, query.limit, sort),
    });
    return _listOf(data).map(_toSong).toList();
  }

  @override
  Future<List<Song>> fetchAlbumSongs(String albumId) async {
    final data = await _get('/api/v1/track/album-detail/list', {
      'albumGUID': albumId,
      'page': '1',
      'size': '500',
    });
    return _listOf(data).map(_toSong).toList();
  }

  @override
  Future<List<Song>> fetchArtistSongs(String artistId, {int limit = 30}) async {
    final data = await _get('/api/v1/track/artist-detail/list', {
      'artistGUID': artistId,
      'page': '1',
      'size': '$limit',
    });
    return _listOf(data).map(_toSong).toList();
  }

  // ---------- 歌单 / 喜欢 / 流派 / 总数 ----------

  @override
  Future<List<Playlist>> fetchPlaylists() async {
    final data = await _get('/api/v1/playlist/list', {
      'page': '1',
      'size': '200',
    });
    return _listOf(data)
        .map(
          (e) => Playlist(
            id: _s(e, 'guid'),
            name: _s(e, 'name', '未命名歌单'),
            songCount: _i(e, 'trackCount'),
            coverArt: _sOrNull(e, 'coverId'),
          ),
        )
        .toList();
  }

  @override
  Future<List<Song>> fetchPlaylistSongs(String playlistId) async {
    final data = await _get('/api/v1/track/playlist-detail/list', {
      'playlistGUID': playlistId,
      'page': '1',
      'size': '500',
    });
    return _listOf(data).map(_toSong).toList();
  }

  @override
  Future<List<Song>> fetchLikedSongs({int limit = 100}) async {
    final data = await _get('/api/v1/favorite-track/list', {
      ..._pageQuery(0, limit, 'favoriteAt,desc'),
    });
    return _listOf(data).map(_toSong).toList();
  }

  @override
  Future<List<Song>> fetchSimilarSongs(String songId, {int count = 20}) async =>
      const [];

  @override
  Future<String?> fetchArtistBio(String artistId) async => null;

  @override
  Future<List<Artist>?> fetchArtists() =>
      _fetchArtistList('/api/v1/artist/list');

  /// fnOS 只有统一歌手视角（无 ID3 专辑艺术家区分），两个入口共用
  @override
  Future<List<Artist>?> fetchAlbumArtists() =>
      _fetchArtistList('/api/v1/artist/list');

  Future<List<Artist>?> _fetchArtistList(String path) async {
    try {
      final result = <Artist>[];
      var page = 1;
      while (true) {
        final data = await _get(path, {'page': '$page', 'size': '500'});
        final items = _listOf(data);
        result.addAll(items.map(_toArtist));
        final total = _i(data, 'total');
        if (result.length >= total || items.isEmpty || page >= 10) break;
        page += 1;
      }
      return result;
    } catch (err, st) {
      adapterSwallowLog('FnOS', err, st);
      return null;
    }
  }

  @override
  Future<List<Genre>?> fetchGenres() async {
    try {
      final data = await _get('/api/v1/genre/list', {
        'page': '1',
        'size': '500',
      });
      return _listOf(data)
          .map(
            (e) => Genre(value: _s(e, 'name'), songCount: _i(e, 'trackCount')),
          )
          .toList();
    } catch (err, st) {
      adapterSwallowLog('FnOS', err, st);
      return null;
    }
  }

  @override
  Future<List<RadioStation>?> fetchRadioStations() async => null;

  @override
  Future<List<Song>?> fetchGenreSongs(String genre, {int limit = 100}) async {
    try {
      final data = await _get('/api/v1/track/genre-detail/list', {
        'genreGUID': genre,
        'page': '1',
        'size': '$limit',
      });
      return _listOf(data).map(_toSong).toList();
    } catch (err, st) {
      adapterSwallowLog('FnOS', err, st);
      return null;
    }
  }

  @override
  Future<int> fetchSongCount() async {
    final data = await _get('/api/v1/track/list', {'page': '1', 'size': '1'});
    return _i(data, 'total');
  }

  // ---------- 搜索 ----------

  @override
  Future<SearchResult> search(String query) async {
    final songs = await _searchTracks(query);
    final albums = await _searchAlbums(query);
    final artists = await _searchArtists(query);
    return SearchResult(songs: songs, albums: albums, artists: artists);
  }

  Future<List<Song>> _searchTracks(String q) async {
    final data = await _get('/api/v1/search/track', {
      'q': q,
      'page': '1',
      'size': '30',
    });
    return _listOf(data).map(_toSong).toList();
  }

  Future<List<Album>> _searchAlbums(String q) async {
    final data = await _get('/api/v1/search/album', {
      'q': q,
      'page': '1',
      'size': '20',
    });
    return _listOf(data).map(_toAlbum).toList();
  }

  Future<List<Artist>> _searchArtists(String q) async {
    final data = await _get('/api/v1/search/artist', {
      'q': q,
      'page': '1',
      'size': '20',
    });
    return _listOf(data).map(_toArtist).toList();
  }

  // ---------- 动作 ----------

  @override
  Future<bool> setStar(String id, bool starred) async {
    try {
      await _post(
        starred
            ? '/api/v1/favorite-track/create'
            : '/api/v1/favorite-track/delete',
        {'trackGUID': id},
      );
      return true;
    } catch (err, st) {
      adapterSwallowLog('FnOS', err, st);
      return false;
    }
  }

  // fnOS 无评分接口（能力位如实降级）
  @override
  Future<bool> setRating(String id, int rating) async => false;

  @override
  Future<bool> addToPlaylist(String playlistId, String songId) async {
    try {
      await _post('/api/v1/playlist/add-track', {
        'guid': playlistId,
        'trackGUIDs': [songId],
      });
      return true;
    } catch (err, st) {
      adapterSwallowLog('FnOS', err, st);
      return false;
    }
  }

  @override
  Future<bool> createPlaylist(String name) async {
    try {
      await _post('/api/v1/playlist/create', {'name': name});
      return true;
    } catch (err, st) {
      adapterSwallowLog('FnOS', err, st);
      return false;
    }
  }

  /// fnOS 服务端在流播放时自动记录播放历史，无需显式上报
  @override
  Future<bool> scrobble(String songId) async => false;

  @override
  Future<bool> nowPlaying(String songId) async => false;

  @override
  Future<String?> libraryVersion() async => null;

  /// LRC 原文 → Navidrome 结构化歌词 JSON（统一解析管线入口格式）
  @override
  Future<String?> fetchLyrics(String songId) async {
    try {
      final data = await _get('/api/v1/lyric/list', {'trackGUID': songId});
      for (final e in _listOf(data)) {
        final content = e['content']?.toString() ?? '';
        if (content.trim().isEmpty) continue;
        final lines = parseLrcText(content);
        if (lines.isEmpty) continue;
        return jsonEncode([
          {
            'lang': 'und',
            'line': [
              for (final l in lines)
                {'start': (l.time * 1000).round(), 'value': l.text},
            ],
          },
        ]);
      }
      return null;
    } catch (err, st) {
      adapterSwallowLog('FnOS', err, st);
      return null;
    }
  }

  // ---------- 媒体 ----------

  @override
  Future<PlaybackSource> resolveStream(
    Song song, {
    QualityHint? quality,
  }) async {
    return PlaybackSource(
      url:
          '${_dio.options.baseUrl}/api/v1/track/stream?guid=${Uri.encodeComponent(song.id)}',
      headers: _headers,
    );
  }

  @override
  Future<bool> supportsTranscode() async => false;

  @override
  Future<PlaybackSource> resolveDownload(Song song) => resolveStream(song);

  @override
  ImageSource? coverImage(String albumId, {int size = 300}) {
    final coverId = _coverIds[albumId];
    if (coverId == null || coverId.isEmpty) {
      _prefetchCoverId(albumId);
      return null;
    }
    return _coverSource(coverId);
  }

  ImageSource _coverSource(String coverId) => ImageSource(
    url:
        '${_dio.options.baseUrl}/api/v1/static/cover?coverId=${Uri.encodeComponent(coverId)}',
    headers: _headers,
  );

  /// 缓存未命中时后台补拉（专辑详情带 coverId），下次 build 命中；
  /// coverImage 是同步接口，只能 fire-and-forget
  void _prefetchCoverId(String guid) {
    if (guid.isEmpty || _prefetching.contains(guid)) return;
    _prefetching.add(guid);
    _get('/api/v1/album/detail', {'albumGUID': guid})
        .then((data) {
          final coverId = data['coverId']?.toString();
          if (coverId != null && coverId.isNotEmpty) _coverIds[guid] = coverId;
        })
        .catchError((_) {})
        .whenComplete(() => _prefetching.remove(guid));
  }

  final Set<String> _prefetching = {};

  @override
  Future<Uint8List?> fetchCoverBytes(String albumId, {int size = 64}) async {
    var coverId = _coverIds[albumId];
    if (coverId == null || coverId.isEmpty) {
      try {
        final data = await _get('/api/v1/album/detail', {'albumGUID': albumId});
        coverId = data['coverId']?.toString();
        if (coverId != null && coverId.isNotEmpty) _coverIds[albumId] = coverId;
      } catch (err, st) {
        adapterSwallowLog('FnOS', err, st);
        return null;
      }
    }
    if (coverId == null || coverId.isEmpty) return null;
    try {
      final resp = await _dio.get<List<int>>(
        '/api/v1/static/cover',
        queryParameters: {'coverId': coverId},
        options: Options(responseType: ResponseType.bytes, headers: _headers),
      );
      return Uint8List.fromList(resp.data ?? const []);
    } catch (err, st) {
      adapterSwallowLog('FnOS', err, st);
      return null;
    }
  }

  // ---------- 生命周期 ----------

  @override
  Future<bool> validateSession() async {
    try {
      await _get('/api/v1/user/me', const {});
      return true;
    } catch (err, st) {
      adapterSwallowLog('FnOS', err, st);
      return false;
    }
  }

  @override
  void dispose() => _dio.close();

  // ========== 模型映射 ==========

  Song _toSong(Map<String, dynamic> j) {
    final album = j['album'] as Map<String, dynamic>? ?? const {};
    final artists = j['artists'] as List<dynamic>? ?? const [];
    final artistMap = artists.isNotEmpty
        ? artists.first as Map<String, dynamic>? ?? const {}
        : const <String, dynamic>{};
    final spec = j['audioSpec'] as Map<String, dynamic>? ?? const {};
    final guid = _s(j, 'guid');
    final albumGuid = _s(album, 'guid');
    final albumCover = _sOrNull(album, 'coverId');
    if (albumGuid.isNotEmpty && albumCover != null) {
      _coverIds[albumGuid] = albumCover;
    }
    final trackCover = _sOrNull(j, 'coverId');
    if (guid.isNotEmpty && trackCover != null) _coverIds[guid] = trackCover;
    final createdSec = _iOrNull(j, 'createdAt');
    return Song(
      id: guid,
      title: _s(j, 'title', '未知歌曲'),
      artist: _s(artistMap, 'name', '未知歌手'),
      album: _s(album, 'name'),
      albumId: albumGuid,
      artistId: _s(artistMap, 'guid'),
      duration: (_n(j, 'duration') / 1000),
      playCount: 0,
      starred: j['isFavorite'] == true,
      size: _i(spec, 'size'),
      rating: 0,
      suffix: _extOf(_s(spec, 'path')),
      codec: _sOrNull(spec, 'codec')?.toUpperCase(),
      bitRate: _iOrNull(spec, 'bitrate') == null
          ? null
          : (_i(spec, 'bitrate') ~/ 1000),
      sampleRate: _iOrNull(spec, 'sampleRate'),
      bitDepth: _iOrNull(spec, 'bitDepth'),
      albumArtist: artists.length > 1
          ? _s((artists.last as Map<String, dynamic>? ?? const {}), 'name')
          : null,
      year: _positiveInt(_iOrNull(j, 'year')),
      discNumber: _positiveInt(_iOrNull(j, 'discNo')),
      trackNumber: _positiveInt(_iOrNull(j, 'trackNo')),
      path: _sOrNull(spec, 'path'),
      created: createdSec == null || createdSec <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdSec * 1000)
                .toIso8601String(),
    );
  }

  Album _toAlbum(Map<String, dynamic> j) {
    final guid = _s(j, 'guid');
    final cover = _sOrNull(j, 'coverId');
    if (guid.isNotEmpty && cover != null) _coverIds[guid] = cover;
    final artists = j['artists'] as List<dynamic>? ?? const [];
    final artistMap = artists.isNotEmpty
        ? artists.first as Map<String, dynamic>? ?? const {}
        : const <String, dynamic>{};
    final release = _sOrNull(j, 'releaseDate');
    final year = release == null || release.length < 4
        ? null
        : int.tryParse(release.substring(0, 4));
    return Album(
      id: guid,
      name: _s(j, 'name', '未知专辑'),
      artist: _s(artistMap, 'name', '未知歌手'),
      artistId: _s(artistMap, 'guid'),
      songCount: _i(j, 'trackCount'),
      duration: 0,
      playCount: 0,
      starred: false,
      rating: 0,
      year: year,
    );
  }

  Artist _toArtist(Map<String, dynamic> j) {
    final guid = _s(j, 'guid');
    final cover = _sOrNull(j, 'coverId');
    if (guid.isNotEmpty && cover != null) _coverIds[guid] = cover;
    return Artist(
      id: guid,
      name: _s(j, 'name', '未知歌手'),
      albumCount: _i(j, 'albumCount'),
      songCount: _i(j, 'trackCount'),
    );
  }

  /// 从服务端文件路径取容器后缀（"…/齐秦 - 往事随风.flac" → flac）
  static String? _extOf(String path) {
    final name = path.isEmpty ? '' : Uri.file(path).pathSegments.last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    return ext.length <= 5 ? ext : null;
  }

  static String _s(Map<String, dynamic> j, String key, [String d = '']) =>
      Json.str(j, key, d);
  static String? _sOrNull(Map<String, dynamic> j, String key) {
    final v = j[key]?.toString() ?? '';
    return v.isEmpty ? null : v;
  }

  static int _i(Map<String, dynamic> j, String key) => Json.intOf(j, key);
  static int? _iOrNull(Map<String, dynamic> j, String key) =>
      Json.intOfOrNull(j, key);
  static double _n(Map<String, dynamic> j, String key) => Json.doubleOf(j, key);
  static int? _positiveInt(int? v) => v == null || v <= 0 ? null : v;
}
