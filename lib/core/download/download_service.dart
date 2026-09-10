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
import 'public_music.dart';

/// 歌曲离线下载：通过 adapter.resolveDownload 获取的 PlaybackSource 下载落盘。
///
/// 落盘目标（P0-公共音乐目录）：优先公共音乐目录——Android 10+ 经 MediaStore
/// 写入 /sdcard/Music/流声/（文件管理器/其他播放器可见），Windows 写入
/// 用户音乐库\流声\；iOS / Android 9- / 公共目录失败时回退应用私有
/// Documents/Music（旧行为）。download_index 登记最终真实路径，播放反查不变。
/// 本地音乐扫描按文件名指纹标记排除下载产物，避免同一首歌重复入库。
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
  if (!await musicDir.exists()) await musicDir.create(recursive: true);

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
  if (!await tmp.exists() || await tmp.length() == 0) {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    throw const FileSystemException('下载内容为空');
  }
  final bytes = await tmp.length();

  // 落盘目标：优先公共音乐目录（对用户可见），失败回退私有 Documents/Music
  // finalPath 兜底初值即私有路径，公共分支成功时才覆盖
  var finalPath = path;
  var placed = false;
  if (Platform.isAndroid) {
    final saved = await PublicMusicStore.saveToPublicMusic(
      sourcePath: tmpPath,
      fileName: fileName,
      title: song.title,
      artist: song.artist,
      album: song.album,
      durationMs: song.duration.toInt(),
    );
    if (saved != null) {
      finalPath = saved;
      placed = true;
      // MediaStore 已复制内容，临时文件就地清理
      try {
        await tmp.delete();
      } catch (_) {}
    }
  } else if (Platform.isWindows) {
    final publicDir = PublicMusicStore.windowsPublicMusicDir();
    if (publicDir != null) {
      try {
        if (!await publicDir.exists()) {
          await publicDir.create(recursive: true);
        }
        final target = File(
          '${publicDir.path}${Platform.pathSeparator}$fileName',
        );
        if (await target.exists()) {
          try {
            await target.delete();
          } catch (_) {}
        }
        await tmp.rename(target.path);
        finalPath = target.path;
        placed = true;
      } catch (_) {
        // 公共目录不可写等场景回退私有目录
      }
    }
  }
  if (!placed) {
    // 原子提交：rename 覆盖旧文件（Windows 上 rename 不能覆盖已存在目标）
    final target = File(path);
    if (await target.exists()) {
      try {
        await target.delete();
      } catch (_) {}
    }
    await tmp.rename(path);
  }

  // 登记/更新 download_index（索引失败不影响文件本身，下次反查会走目录兑底回填）
  try {
    final db = await AppDb.instance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('download_index', {
      'server_id': serverId,
      'song_id': song.id,
      'fingerprint': fingerprint,
      'path': finalPath,
      'size': bytes,
      'created_at': now,
      'last_accessed_at': now,
      // Song 元数据快照：本地音乐列表合并展示已下载歌曲用（身份保持服务器 id）
      'payload': jsonEncode(song.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  } catch (_) {}
  return finalPath;
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
      if (await File(path).exists()) {
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
    if (!await musicDir.exists()) return null;
    final marker = '--$fingerprint.';
    await for (final entry in musicDir.list()) {
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
            'size': await entry.length(),
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
