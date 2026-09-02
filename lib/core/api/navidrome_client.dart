import 'package:dio/dio.dart';

import '../models/models.dart';
import '../storage/auth_store.dart';
import '../subsonic/subsonic.dart';

/// 登录接口响应（实际包含 token + Subsonic 双要素）
class LoginResult {
  const LoginResult({
    required this.token,
    required this.subsonicToken,
    required this.subsonicSalt,
    required this.username,
  });

  final String token;
  final String subsonicToken;
  final String subsonicSalt;
  final String username;

  factory LoginResult.fromJson(Map<String, dynamic> j) => LoginResult(
        token: j['token']?.toString() ?? '',
        subsonicToken: j['subsonicToken']?.toString() ?? '',
        subsonicSalt: j['subsonicSalt']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
      );
}

/// Navidrome REST 客户端（对标 1.x services/navidromeApi.ts）
///
/// 凭证由 [setSession] 注入后缓存在内存，请求拦截器零异步 IO 附加认证头。
class NavidromeClient {
  NavidromeClient() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_session != null) {
            final token = _session!.token;
            options.headers['Authorization'] = 'Bearer $token';
            options.headers['x-nd-authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  StoredSession? _session;

  /// 登录后 / 会话恢复后调用：切换 baseUrl 并启用认证头
  void setSession(StoredSession session) {
    _session = session;
    dio.options.baseUrl = session.serverUrl;
  }

  /// 登出时调用：清除内存凭证与 baseUrl
  void clearSession() {
    _session = null;
    dio.options.baseUrl = '';
  }

  StoredSession? get session => _session;

  /// 内部工具：当前会话的 Subsonic 认证要素（未登录抛异常）
  SubsonicAuth get _subsonicAuth {
    final session = _session;
    if (session == null) throw Exception('未登录');
    return SubsonicAuth(
      serverUrl: session.serverUrl,
      username: session.username,
      subsonicToken: session.subsonicToken,
      subsonicSalt: session.subsonicSalt,
    );
  }

  /// 登录（临时将 baseUrl 指向目标服务器，成功后由调用方保存会话）
  Future<LoginResult> login(String serverUrl, String username, String password) async {
    final saved = dio.options.baseUrl;
    dio.options.baseUrl = serverUrl;
    try {
      final res = await dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'username': username, 'password': password},
      );
      final map = res.data ?? const {};
      final result = LoginResult.fromJson(map);
      if (result.token.isEmpty || result.subsonicToken.isEmpty || result.subsonicSalt.isEmpty) {
        throw Exception('登录响应缺少必要的认证信息');
      }
      return result;
    } finally {
      dio.options.baseUrl = saved;
    }
  }

  // ---------- 专辑 ----------
  Future<List<Album>> getAlbums(Map<String, Object?> query) async {
    final res = await dio.get<List<dynamic>>('/api/album', queryParameters: query);
    return (res.data ?? const [])
        .map((e) => Album.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------- 歌曲 ----------
  Future<List<Song>> getSongs(Map<String, Object?> query) async {
    final res = await dio.get<List<dynamic>>('/api/song', queryParameters: query);
    return (res.data ?? const [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------- 相似歌曲推荐 ----------

  /// 相似歌曲（Subsonic getSimilarSongs，对标 1.x songApi.getSimilarSongs）。
  /// 兼容 similarSongs2 / similarSongs 两种响应包装，异常时返回空列表。
  Future<List<Song>> getSimilarSongs(String songId, {int count = 20}) async {
    if (_session == null) return const [];
    try {
      final res = await dio.get<Map<String, dynamic>>(
        '/rest/getSimilarSongs',
        queryParameters: {
          ...Subsonic.params(_subsonicAuth),
          'id': songId,
          'count': count,
        },
      );
      final response = res.data?['subsonic-response'] as Map<String, dynamic>?;
      if (response == null || response['status'] != 'ok') return const [];
      final container =
          (response['similarSongs2'] ?? response['similarSongs']) as Map<String, dynamic>?;
      final songs = container?['song'] as List<dynamic>?;
      return (songs ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Song.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ---------- 专辑歌曲 / 歌单 / 喜欢 / 总数 / 收藏 / 评分 ----------

  /// 专辑内歌曲（按曲目号排序，对标 1.x 详情页 GET /api/song?album_id=）
  Future<List<Song>> getAlbumSongs(String albumId) =>
      getSongs({'album_id': albumId, '_sort': 'track'});

  /// 歌单列表（对标 1.x GET /api/playlist）
  Future<List<Playlist>> getPlaylists() async {
    final res = await dio.get<List<dynamic>>('/api/playlist');
    return (res.data ?? const [])
        .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 歌单内歌曲（对标 1.x GET /api/playlist/{id}/tracks）
  Future<List<Song>> getPlaylistSongs(String playlistId) async {
    final res =
        await dio.get<List<dynamic>>('/api/playlist/$playlistId/tracks');
    return (res.data ?? const [])
        .map((e) => Song.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 我喜欢的歌曲（Navidrome starred 过滤）
  Future<List<Song>> getLikedSongs() =>
      getSongs({'starred': true, '_end': 100});

  /// 曲库歌曲总数（读 X-Total-Count 响应头，负一屏服务器卡片展示）
  Future<int> getSongTotal() async {
    try {
      final res =
          await dio.get<dynamic>('/api/song', queryParameters: {'_end': 1});
      return int.tryParse(res.headers.value('x-total-count') ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Subsonic 简单动作（star/unstar/setRating），未登录或失败返回 false
  Future<bool> _subsonicAction(
      String endpoint, Map<String, String> extra) async {
    if (_session == null) return false;
    try {
      final res = await dio.get<Map<String, dynamic>>(
        '/rest/$endpoint',
        queryParameters: {...Subsonic.params(_subsonicAuth, extra)},
      );
      return res.data?['subsonic-response']?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// 收藏 / 取消收藏（Subsonic star/unstar）
  Future<bool> setStar(String id, bool starred) =>
      _subsonicAction(starred ? 'star' : 'unstar', {'id': id});

  /// 评分 0-5（Subsonic setRating）
  Future<bool> setRating(String id, int rating) =>
      _subsonicAction('setRating', {'id': id, 'rating': '$rating'});

  /// 添加歌曲到歌单（Navidrome POST /api/playlist/{id}/tracks）
  Future<bool> addToPlaylist(String playlistId, String songId) async {
    try {
      final res = await dio.post<dynamic>(
        '/api/playlist/$playlistId/tracks',
        data: {'ids': [songId]},
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---------- 搜索 ----------
  Future<SearchResult> search(String query) async {
    final res = await dio.get<Map<String, dynamic>>('/search', queryParameters: {'q': query});
    final data = res.data ?? const {};
    return SearchResult(
      songs: Song.listFromJson(data['songs'] ?? const []),
      albums: Album.listFromJson(data['albums'] ?? const []),
      artists: Artist.listFromJson(data['artists'] ?? const []),
    );
  }
}
