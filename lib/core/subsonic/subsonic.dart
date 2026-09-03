/// Subsonic 兼容接口直链构建（对标 1.x src/utils/subsonic.ts）
abstract final class Subsonic {
  static const client = 'NavidromeUI';
  static const apiVersion = '1.8.0';

  /// Subsonic 公共认证参数（u/t/s/f/v/c）
  static Map<String, String> params(
    SubsonicAuth auth, [
    Map<String, String> extra = const {},
  ]) => {
    'u': auth.username,
    't': auth.subsonicToken,
    's': auth.subsonicSalt,
    'f': 'json',
    'v': apiVersion,
    'c': client,
    ...extra,
  };

  /// 专辑/歌曲封面直链（服务端裁剪到 300px，配合客户端限制解码尺寸）
  static String coverArtUrl(SubsonicAuth auth, String id) =>
      '${auth.serverUrl}/rest/getCoverArt?${_query(params(auth, {'id': id, 'size': '300', 'square': 'true'}))}';

  /// 歌曲流媒体直链
  static String streamUrl(SubsonicAuth auth, String songId) =>
      '${auth.serverUrl}/rest/stream?${_query(params(auth, {'id': songId}))}';

  /// 歌曲原始文件下载直链（Subsonic download，返回无损原始音质）
  static String downloadUrl(SubsonicAuth auth, String songId) =>
      '${auth.serverUrl}/rest/download?${_query(params(auth, {'id': songId}))}';

  static String _query(Map<String, String> p) => p.entries
      .map(
        (e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
      )
      .join('&');
}

class SubsonicAuth {
  const SubsonicAuth({
    required this.serverUrl,
    required this.username,
    required this.subsonicToken,
    required this.subsonicSalt,
  });

  final String serverUrl;
  final String username;
  final String subsonicToken;
  final String subsonicSalt;

  static const empty = SubsonicAuth(
    serverUrl: '',
    username: '',
    subsonicToken: '',
    subsonicSalt: '',
  );

  bool get isValid =>
      serverUrl.isNotEmpty &&
      subsonicToken.isNotEmpty &&
      subsonicSalt.isNotEmpty;
}
