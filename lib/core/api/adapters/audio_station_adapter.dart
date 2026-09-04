import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../models/models.dart';
import '../../network/http_factory.dart';
import '../../settings/streaming_prefs.dart';
import '../server_adapter.dart';
import '../server_type.dart';

/// Synology Audio Station 适配器。
/// 认证：SYNO.API.Auth → SID（会话 ID）。
/// API：entry.cgi + SYNO.AudioStation.* 方法调用。
class AudioStationAdapter implements ServerAdapter {
  AudioStationAdapter({
    required ServerConfig config,
    required Map<String, String> secrets,
  }) : _config = config,
       _sid = secrets['sid'] ?? '',
       _password = secrets['password'] ?? '' {
    _dio.options.baseUrl = config.serverUrl;
    NetworkRuntime.configureDio(_dio);
  }

  final ServerConfig _config;
  String _sid;
  final String _password;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  @override
  ServerType get type => ServerType.audioStation;

  @override
  AdapterCapabilities get capabilities => const AdapterCapabilities(
    ratings: true,
    similarSongs: false,
    likedSongs: true,
    download: true,
    lyrics: true,
  );

  // Audio Station 无 Scrobble/曲库变更标记接口（能力矩阵如实降级）
  @override
  Future<bool> scrobble(String songId) async => false;

  @override
  Future<bool> nowPlaying(String songId) async => false;

  @override
  Future<String?> libraryVersion() async => null;

  static Future<AdapterSession> signIn(AuthRequest request) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: request.serverUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final res = await dio.get<Map<String, dynamic>>(
        '/webapi/auth.cgi',
        queryParameters: {
          'api': 'SYNO.API.Auth',
          'version': '3',
          'method': 'login',
          'account': request.username,
          'passwd': request.password,
          'session': 'AudioStation',
          'format': 'sid',
        },
      );
      final data = res.data ?? const {};
      if (data['success'] != true) {
        throw Exception('Audio Station 认证失败');
      }
      final sid = data['data']?['sid']?.toString() ?? '';
      if (sid.isEmpty) throw Exception('Audio Station 认证失败：无 SID');
      return AdapterSession(
        secrets: {'sid': sid, 'password': request.password},
        displayName: request.username.isNotEmpty ? request.username : null,
      );
    } finally {
      dio.close();
    }
  }

  // ---------- 专辑 ----------

  @override
  Future<List<Album>> fetchAlbums(AlbumQuery query) async {
    final sort = switch (query.sort) {
      AlbumSort.recentlyAdded => 'createtime',
      AlbumSort.recentlyPlayed => 'lastplayed',
      AlbumSort.mostPlayed => 'playcount',
      AlbumSort.random => 'random',
      AlbumSort.name => 'name',
      AlbumSort.year => 'year',
    };
    final order = query.descending ? 'desc' : 'asc';
    final data = await _api('SYNO.AudioStation.Album', 'list', {
      'album_type': 'album',
      'sort_by': sort,
      'sort_order': order,
      'limit': '${query.limit}',
      'offset': '${query.start}',
    });
    return _parseAlbums(data);
  }

  @override
  Future<List<Album>> fetchArtistAlbums(String artistId) async {
    final data = await _api('SYNO.AudioStation.Album', 'list', {
      'album_type': 'album',
      'artist': artistId,
      'limit': '100',
      'offset': '0',
    });
    return _parseAlbums(data);
  }

  // ---------- 歌曲 ----------

  @override
  Future<List<Song>> fetchSongs(SongQuery query) async {
    if (query.albumId != null) return fetchAlbumSongs(query.albumId!);
    if (query.starredOnly) return fetchLikedSongs(limit: query.limit);
    if (query.artistId != null) {
      return fetchArtistSongs(query.artistId!, limit: query.limit);
    }
    final sortBy = switch (query.sort ?? SongSort.title) {
      SongSort.title => 'title',
      SongSort.random => 'random',
      SongSort.rating => 'rating',
      SongSort.recentlyAdded => 'createtime',
      SongSort.recentlyPlayed => 'lastplayed',
      SongSort.mostPlayed => 'playcount',
      SongSort.track => 'track',
    };
    // 时间/热度类排序需要倒序（Audio Station 默认升序）
    const descSorts = {
      SongSort.rating,
      SongSort.recentlyAdded,
      SongSort.recentlyPlayed,
      SongSort.mostPlayed,
    };
    final data = await _api('SYNO.AudioStation.Song', 'list', {
      'sort_by': sortBy,
      'sort_order': descSorts.contains(query.sort) ? 'desc' : 'asc',
      'limit': '${query.limit}',
      'offset': '${query.start}',
    });
    return _parseSongs(data);
  }

  @override
  Future<List<Song>> fetchAlbumSongs(String albumId) async {
    final data = await _api('SYNO.AudioStation.Song', 'list', {
      'album': albumId,
      'sort_by': 'track',
      'sort_order': 'asc',
      'limit': '500',
      'offset': '0',
    });
    return _parseSongs(data);
  }

  @override
  Future<List<Song>> fetchArtistSongs(String artistId, {int limit = 30}) async {
    final data = await _api('SYNO.AudioStation.Song', 'list', {
      'artist': artistId,
      'sort_by': 'playcount',
      'sort_order': 'desc',
      'limit': '$limit',
      'offset': '0',
    });
    return _parseSongs(data);
  }

  // ---------- 歌单 / 喜欢 / 总数 ----------

  @override
  Future<List<Playlist>> fetchPlaylists() async {
    final data = await _api('SYNO.AudioStation.Playlist', 'list', {
      'limit': '200',
      'offset': '0',
    });
    final items = _dataList(data);
    return items.whereType<Map<String, dynamic>>().map((e) {
      return Playlist(
        id: _s(e, 'id'),
        name: _s(e, 'name', '未命名歌单'),
        songCount: _i(e, 'song_count'),
      );
    }).toList();
  }

  @override
  Future<List<Song>> fetchPlaylistSongs(String playlistId) async {
    final data = await _api('SYNO.AudioStation.Playlist', 'getinfo', {
      'id': playlistId,
    });
    final songs = data['data']?['songs'] as List<dynamic>?;
    return (songs ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  @override
  Future<List<Song>> fetchLikedSongs({int limit = 100}) async {
    final data = await _api('SYNO.AudioStation.Song', 'list', {
      'sort_by': 'title',
      'sort_order': 'asc',
      'limit': '$limit',
      'offset': '0',
      'filter': 'starred',
    });
    return _parseSongs(data);
  }

  @override
  Future<List<Song>> fetchSimilarSongs(String songId, {int count = 20}) async =>
      const [];

  /// Audio Station 没有歌手简介接口，能力位 artistBio 保持 false
  @override
  Future<String?> fetchArtistBio(String artistId) async => null;

  @override
  Future<int> fetchSongCount() async {
    final data = await _api('SYNO.AudioStation.Song', 'list', {
      'limit': '0',
      'offset': '0',
    });
    final total = data['data']?['total'] as num?;
    return total?.toInt() ?? 0;
  }

  // ---------- 搜索 ----------

  @override
  Future<SearchResult> search(String query) async {
    final data = await _api('SYNO.AudioStation.Search', 'search', {
      'title': query,
      'limit': '20',
      'offset': '0',
    });
    final songs = <Song>[];
    final albums = <Album>[];
    final artists = <Artist>[];

    final songItems = data['data']?['song'] as List<dynamic>?;
    for (final e in (songItems ?? const [])) {
      if (e is Map<String, dynamic>) songs.add(_toSong(e));
    }
    final albumItems = data['data']?['album'] as List<dynamic>?;
    for (final e in (albumItems ?? const [])) {
      if (e is Map<String, dynamic>) albums.add(_toAlbum(e));
    }
    final artistItems = data['data']?['artist'] as List<dynamic>?;
    for (final e in (artistItems ?? const [])) {
      if (e is Map<String, dynamic>) {
        artists.add(
          Artist(
            id: _s(e, 'id'),
            name: _s(e, 'name', '未知歌手'),
            albumCount: _i(e, 'album_count'),
            songCount: _i(e, 'song_count'),
          ),
        );
      }
    }
    return SearchResult(songs: songs, albums: albums, artists: artists);
  }

  // ---------- 动作 ----------

  @override
  Future<bool> setStar(String id, bool starred) async {
    try {
      await _api('SYNO.AudioStation.Song', starred ? 'star' : 'unstar', {
        'id': id,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setRating(String id, int rating) async {
    try {
      await _api('SYNO.AudioStation.Song', 'set_rating', {
        'id': id,
        'rating': '$rating',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> addToPlaylist(String playlistId, String songId) async {
    try {
      await _api('SYNO.AudioStation.Playlist', 'add', {
        'id': playlistId,
        'song_id': songId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> createPlaylist(String name) async {
    try {
      await _api('SYNO.AudioStation.Playlist', 'create', {'name': name});
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- 媒体 ----------

  @override
  Future<PlaybackSource> resolveStream(
    Song song, {
    QualityHint? quality,
  }) async {
    await _ensureSid();
    return PlaybackSource(
      url:
          '${_config.serverUrl}/webapi/entry.cgi?api=SYNO.AudioStation.Stream&version=1&method=stream&song_id=${Uri.encodeComponent(song.id)}&_sid=$_sid',
    );
  }

  @override
  Future<bool> supportsTranscode() async => capabilities.transcoding;

  @override
  Future<PlaybackSource> resolveDownload(Song song) async {
    await _ensureSid();
    return PlaybackSource(
      url:
          '${_config.serverUrl}/webapi/entry.cgi?api=SYNO.AudioStation.Download&version=1&method=download&song_id=${Uri.encodeComponent(song.id)}&_sid=$_sid',
    );
  }

  @override
  ImageSource? coverImage(String albumId, {int size = 300}) {
    if (albumId.isEmpty || _sid.isEmpty) return null;
    return ImageSource(
      url:
          '${_config.serverUrl}/webapi/entry.cgi?api=SYNO.AudioStation.CoverArt&version=1&method=getcover&album_id=${Uri.encodeComponent(albumId)}&size=$size&_sid=$_sid',
    );
  }

  @override
  Future<Uint8List?> fetchCoverBytes(String albumId, {int size = 64}) async {
    if (albumId.isEmpty) return null;
    await _ensureSid();
    try {
      final url =
          '${_config.serverUrl}/webapi/entry.cgi?api=SYNO.AudioStation.CoverArt&version=1&method=getcover&album_id=${Uri.encodeComponent(albumId)}&size=$size&_sid=$_sid';
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
      await _api('SYNO.AudioStation.Info', 'getinfo', {});
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() => _dio.close();

  // ========== 内部工具 ==========

  Future<Map<String, dynamic>> _api(
    String api,
    String method,
    Map<String, String> extra,
  ) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/webapi/entry.cgi',
      queryParameters: {
        'api': api,
        'version': '1',
        'method': method,
        '_sid': _sid,
        ...extra,
      },
    );
    final data = res.data ?? const {};
    if (data['success'] != true) {
      final errorCode = data['error']?['code']?.toString() ?? '';
      if (errorCode == '105' || errorCode == '106' || errorCode == '107') {
        await _relogin();
        final retry = await _dio.get<Map<String, dynamic>>(
          '/webapi/entry.cgi',
          queryParameters: {
            'api': api,
            'version': '1',
            'method': method,
            '_sid': _sid,
            ...extra,
          },
        );
        final retryData = retry.data ?? const {};
        if (retryData['success'] != true) {
          throw Exception('Audio Station 请求失败');
        }
        return retryData;
      }
      throw Exception('Audio Station 请求失败');
    }
    return data;
  }

  Future<void> _ensureSid() async {
    if (_sid.isNotEmpty) return;
    await _relogin();
  }

  Future<void> _relogin() async {
    if (_password.isEmpty) throw Exception('无密码，无法重新登录');
    final res = await _dio.get<Map<String, dynamic>>(
      '/webapi/auth.cgi',
      queryParameters: {
        'api': 'SYNO.API.Auth',
        'version': '3',
        'method': 'login',
        'account': _config.username,
        'passwd': _password,
        'session': 'AudioStation',
        'format': 'sid',
      },
    );
    final data = res.data ?? const {};
    if (data['success'] != true) throw Exception('Audio Station 重新登录失败');
    _sid = data['data']?['sid']?.toString() ?? '';
    if (_sid.isEmpty) throw Exception('Audio Station 重新登录失败：无 SID');
  }

  List<dynamic> _dataList(Map<String, dynamic> data) {
    final items = data['data']?['items'] as List<dynamic>?;
    return items ?? const [];
  }

  List<Album> _parseAlbums(Map<String, dynamic> data) {
    return _dataList(data)
        .whereType<Map<String, dynamic>>()
        .map(_toAlbum)
        .toList();
  }

  List<Song> _parseSongs(Map<String, dynamic> data) {
    return _dataList(data)
        .whereType<Map<String, dynamic>>()
        .map(_toSong)
        .toList();
  }

  Song _toSong(Map<String, dynamic> j) {
    final additional = j['additional'] as Map<String, dynamic>? ?? const {};
    final audio = additional['song_audio'] as Map<String, dynamic>? ?? const {};
    final tag = additional['song_tag'] as Map<String, dynamic>? ?? const {};
    final id = _s(j, 'id');
    return Song(
      id: id,
      title: _s(j, 'title', '未知歌曲'),
      artist: _s(j, 'artist', '未知歌手'),
      album: _s(j, 'album'),
      albumId: _s(j, 'album_id'),
      artistId: _s(j, 'artist_id'),
      duration: (audio['duration'] as num?)?.toDouble() ?? (_n(j, 'duration')),
      playCount: _i(j, 'play_count'),
      starred: tag['starred'] == true || j['starred'] == true,
      size: (audio['size'] as num?)?.toInt() ?? _i(j, 'size'),
      rating: _i(j, 'rating'),
      // Song.list 默认不返回 song_audio，此时退回从 id 的文件扩展名取容器
      suffix: _firstStr(audio, const ['container', 'codec']) ?? _extOf(id),
      codec: _firstStr(audio, const ['codec']),
      bitRate: _bpsToKbps(_n(audio, 'bitrate')),
      sampleRate: _hzOrNull(
        _firstNum(audio, const ['sample_rate', 'frequency']),
      ),
    );
  }

  static String? _firstStr(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      final v = j[k]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  static double? _firstNum(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      final v = j[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final p = double.tryParse(v);
        if (p != null) return p;
      }
    }
    return null;
  }

  /// Audio Station 的 bitrate 单位是 bps（320000），归一到 kbps
  static int? _bpsToKbps(double bps) => bps <= 0 ? null : (bps / 1000).round();

  static int? _hzOrNull(double? hz) =>
      hz == null || hz <= 0 ? null : hz.round();

  /// AudioStation 的歌曲 id 就是音乐库相对路径，扩展名即容器格式
  static String? _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    final ext = path.substring(dot + 1).toLowerCase();
    // 路径里的「.」可能出现在目录名上，限定长度过滤掉误判
    return ext.length <= 5 ? ext : null;
  }

  Album _toAlbum(Map<String, dynamic> j) {
    final additional = j['additional'] as Map<String, dynamic>? ?? const {};
    final audio =
        additional['album_audio'] as Map<String, dynamic>? ?? const {};
    return Album(
      id: _s(j, 'id'),
      name: _s(j, 'name', '未知专辑'),
      artist: _s(j, 'artist', '未知歌手'),
      artistId: _s(j, 'artist_id'),
      songCount: _i(j, 'song_count'),
      duration: (audio['duration'] as num?)?.toDouble() ?? _n(j, 'duration'),
      playCount: _i(j, 'play_count'),
      starred: false,
      rating: 0,
      year: _iOrNull(j, 'year'),
    );
  }

  static String _s(Map<String, dynamic> j, String key, [String d = '']) =>
      j[key]?.toString() ?? d;
  static int _i(Map<String, dynamic> j, String key) =>
      (j[key] as num?)?.toInt() ?? 0;
  static int? _iOrNull(Map<String, dynamic> j, String key) =>
      (j[key] as num?)?.toInt();
  static double _n(Map<String, dynamic> j, String key) =>
      (j[key] as num?)?.toDouble() ?? 0;
}
