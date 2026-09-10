import '../models/models.dart';
import '../api/server_adapter.dart';
import '../settings/streaming_prefs.dart';

/// web 端下载占位：Phase 2 接浏览器下载（Blob + a[download]）。
/// 反查恒 null——web 无本地离线文件。
Future<String> downloadSongFile({
  required PlaybackSource source,
  required Song song,
  String serverId = '',
  NetworkSettings networkSettings = const NetworkSettings(),
  void Function(int received, int total)? onProgress,
}) async => throw UnsupportedError('web 端下载将在后续版本支持');

Future<String?> findDownloadedSong(Song song) async => null;
