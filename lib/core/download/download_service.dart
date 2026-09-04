import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../api/server_adapter.dart';
import '../models/models.dart';

/// 歌曲离线下载：通过 adapter.resolveDownload 获取的 PlaybackSource 下载
/// 到应用文档目录 Music/ 下保存。
/// 文件名由歌曲稳定 id 派生，避免同名歌曲互相覆盖；返回保存的完整路径。
Future<String> downloadSongFile({
  required PlaybackSource source,
  required Song song,
  void Function(int received, int total)? onProgress,
}) async {
  final docs = await getApplicationDocumentsDirectory();
  final musicDir = Directory('${docs.path}${Platform.pathSeparator}Music');
  if (!musicDir.existsSync()) musicDir.createSync(recursive: true);

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 5),
      headers: source.headers.isNotEmpty ? source.headers : null,
    ),
  );
  final fileName =
      '${_safeName('${song.artist} - ${song.title}')}--${_songFingerprint(song.id)}.mp3';
  final path = '${musicDir.path}${Platform.pathSeparator}$fileName';
  await dio.download(source.url, path, onReceiveProgress: onProgress);
  return path;
}

/// Windows / Android 文件名非法字符替换为下划线
String _safeName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

/// 反查歌曲的本地离线文件，未下载返回 null。
///
/// 按歌曲 id 指纹查找，不能被同名歌曲或服务端文件名影响。
Future<String?> findDownloadedSong(Song song) async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${docs.path}${Platform.pathSeparator}Music');
    if (!musicDir.existsSync()) return null;
    final fingerprint = '--${_songFingerprint(song.id)}.';
    for (final entry in musicDir.listSync()) {
      if (entry is! File) continue;
      if (entry.uri.pathSegments.last.contains(fingerprint)) return entry.path;
    }
  } catch (_) {
    // 目录不可读等情况按「未下载」处理，不影响信息弹窗其余内容
  }
  return null;
}

String _songFingerprint(String songId) =>
    sha256.convert(utf8.encode(songId)).toString().substring(0, 16);
