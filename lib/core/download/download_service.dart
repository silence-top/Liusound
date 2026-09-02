import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../subsonic/subsonic.dart';

/// 歌曲离线下载：Subsonic download 端点 → 应用文档目录 Music/ 下保存。
/// 文件名优先取响应 Content-Disposition（服务端原始文件名），
/// 回退「歌手 - 标题.mp3」；返回保存的完整路径。
Future<String> downloadSongFile({
  required SubsonicAuth auth,
  required Song song,
  void Function(int received, int total)? onProgress,
}) async {
  final docs = await getApplicationDocumentsDirectory();
  final musicDir = Directory('${docs.path}${Platform.pathSeparator}Music');
  if (!musicDir.existsSync()) musicDir.createSync(recursive: true);

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    // 下载完整音质原始文件，接收超时放宽（大文件/慢网络）
    receiveTimeout: const Duration(minutes: 5),
  ));
  final fallback = '${_safeName('${song.artist} - ${song.title}')}.mp3';
  final path = '${musicDir.path}${Platform.pathSeparator}$fallback';
  final res = await dio.download(
    Subsonic.downloadUrl(auth, song.id),
    path,
    onReceiveProgress: onProgress,
  );
  // 服务端返回原始文件名时重命名（Content-Disposition）
  final serverName =
      _parseFilename(res.headers.value('content-disposition') ?? '');
  if (serverName != null && _safeName(serverName) != fallback) {
    final newPath = '${musicDir.path}${Platform.pathSeparator}${_safeName(serverName)}';
    try {
      return (await File(path).rename(newPath)).path;
    } catch (_) {
      return path; // 重命名失败（重名等）保留回退名
    }
  }
  return path;
}

/// Windows / Android 文件名非法字符替换为下划线
String _safeName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

/// 解析 Content-Disposition 文件名（支持 RFC 5987 filename*=UTF-8''）
String? _parseFilename(String disposition) {
  final star = RegExp(r"filename\*\s*=\s*(?:UTF-8|utf-8)''([^;]+)")
      .firstMatch(disposition)
      ?.group(1);
  if (star != null && star.isNotEmpty) return Uri.decodeComponent(star.trim());
  final plain =
      RegExp(r'filename\s*=\s*"?([^";]+)"?').firstMatch(disposition)?.group(1);
  return (plain == null || plain.isEmpty) ? null : plain.trim();
}
