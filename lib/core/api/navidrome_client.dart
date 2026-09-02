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
    final session = _session;
    if (session == null) return const [];
    try {
      final auth = SubsonicAuth(
        serverUrl: session.serverUrl,
        username: session.username,
        subsonicToken: session.subsonicToken,
        subsonicSalt: session.subsonicSalt,
      );
      final res = await dio.get<Map<String, dynamic>>(
        '/rest/getSimilarSongs',
        queryParameters: {
          ...Subsonic.params(auth),
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
