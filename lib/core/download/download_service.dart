import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../api/server_adapter.dart';
import '../models/models.dart';
import '../network/http_factory.dart';
import '../settings/streaming_prefs.dart';
import '../storage/app_db.dart';

/// 歌曲离线下载：通过 adapter.resolveDownload 获取的 PlaybackSource 下载
/// 到应用文档目录 Music/ 下保存。
///
/// 约束（P0）：
/// - 下载写入 .tmp 临时文件，完整 + 校验后原子 rename，最终路径不会出现半截文件；
/// - 下载成功必须登记 download_index（SQLite），反查走索引而非每次遍历目录；
/// - 索引记录与实际文件最终一致：文件丢失时懒修复（删失效记录 + 回退目录扫描）。
Future<String> downloadSongFile({
  required PlaybackSource source,
  required Song song,
  String serverId = '',
  NetworkSettings networkSettings = const NetworkSettings(),
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
  // 代理/自签证书/hosts 映射对下载同样生效（否则网络设置形同虚设）
  NetworkRuntime.configureDio(dio, networkSettings);
  final fingerprint = _songFingerprint(song.id);
  // 按源文件真实容器命名（FLAC/M4A 等），无 suffix 时回退 mp3
  final suffix = song.suffix?.trim().toLowerCase() ?? '';
  final ext = suffix.isEmpty ? 'mp3' : suffix;
  final fileName =
      '${_safeName('${song.artist} - ${song.title}')}--$fingerprint.$ext';
  final path = '${musicDir.path}${Platform.pathSeparator}$fileName';
  final tmpPath = '$path.tmp';

  // 临时文件下载（中途失败保留 .tmp 供续传场景，但最终路径不被认为有效）
  try {
    await dio.download(source.url, tmpPath, onReceiveProgress: onProgress);
  } finally {
    dio.close();
  }

  // 校验：文件存在且非空，否则视为下载失败
  final tmp = File(tmpPath);
  if (!tmp.existsSync() || tmp.lengthSync() == 0) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    throw const FileSystemException('下载内容为空');
  }

  // 原子提交：rename 覆盖旧文件（Windows 上 rename 不能覆盖已存在目标）
  final target = File(path);
  if (target.existsSync()) {
    try {
      target.deleteSync();
    } catch (_) {}
  }
  tmp.renameSync(path);

  // 登记/更新 download_index（索引失败不影响文件本身，下次反查会走目录兜底回填）
  try {
    final db = await AppDb.instance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('download_index', {
      'server_id': serverId,
      'song_id': song.id,
      'fingerprint': fingerprint,
      'path': path,
      'size': target.lengthSync(),
      'created_at': now,
      'last_accessed_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  } catch (_) {}
  return path;
}

/// Windows / Android 文件名非法字符替换为下划线
String _safeName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

/// 反查歌曲的本地离线文件，未下载返回 null。
///
/// 优先走 download_index 索引（O(1) 查询）；索引命中但文件已丢失时
/// 懒修复（删除失效记录）；索引未命中回退目录指纹扫描一次并回填索引
/// （覆盖本版本之前下载的历史文件）。
Future<String?> findDownloadedSong(Song song) async {
  final fingerprint = _songFingerprint(song.id);
  try {
    final db = await AppDb.instance();
    final rows = await db.query(
      'download_index',
      where: 'fingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final path = rows.first['path'] as String;
      if (File(path).existsSync()) {
        try {
          await db.update(
            'download_index',
            {'last_accessed_at': DateTime.now().millisecondsSinceEpoch},
            where: 'fingerprint = ?',
            whereArgs: [fingerprint],
          );
        } catch (_) {}
        return path;
      }
      // 索引有记录但文件不存在：懒修复，删除失效记录
      await db.delete(
        'download_index',
        where: 'fingerprint = ?',
        whereArgs: [fingerprint],
      );
    }
  } catch (_) {
    // 索引查询异常继续走目录兜底
  }

  // 兜底：历史下载无索引记录，按指纹扫描 Music 目录并回填索引
  try {
    final docs = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${docs.path}${Platform.pathSeparator}Music');
    if (!musicDir.existsSync()) return null;
    final marker = '--$fingerprint.';
    for (final entry in musicDir.listSync()) {
      if (entry is! File) continue;
      if (entry.uri.pathSegments.last.contains(marker)) {
        try {
          final db = await AppDb.instance();
          final now = DateTime.now().millisecondsSinceEpoch;
          await db.insert('download_index', {
            'server_id': '',
            'song_id': song.id,
            'fingerprint': fingerprint,
            'path': entry.path,
            'size': entry.lengthSync(),
            'created_at': now,
            'last_accessed_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } catch (_) {}
        return entry.path;
      }
    }
  } catch (_) {
    // 目录不可读等情况按「未下载」处理
  }
  return null;
}

String _songFingerprint(String songId) =>
    sha256.convert(utf8.encode(songId)).toString().substring(0, 16);
