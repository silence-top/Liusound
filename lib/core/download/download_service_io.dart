import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../api/server_adapter.dart';
import '../models/models.dart';
import '../network/http_factory.dart';
import '../platform/media_store.dart';
import '../settings/streaming_prefs.dart';
import '../storage/app_db.dart';

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
  final musicDir = Directory(p.join(docs.path, 'Music'));
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
  // 指纹含 serverId：不同服务器的同名数字 id（fnOS/Plex）不得共用一个文件
  final fingerprint = _songFingerprint(serverId, song.id);
  // 按源文件真实容器命名（FLAC/M4A 等），无 suffix 时回退 mp3
  final suffix = song.suffix?.trim().toLowerCase() ?? '';
  final ext = suffix.isEmpty ? 'mp3' : suffix;
  final fileName =
      '${_safeName('${song.artist} - ${song.title}')}--$fingerprint.$ext';
  final path = p.join(musicDir.path, fileName);
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
  final saved = await mediaStore.saveToPublicMusic(
    sourcePath: tmpPath,
    fileName: fileName,
    title: song.title,
    artist: song.artist,
    album: song.album,
    durationMs: song.duration.toInt(),
  );
  if (saved != null) {
    finalPath = saved;
    // Android MediaStore 实现是 copy 而非 move：成功后删除私有目录残缺副本，
    // 否则同一首歌存两份（桌面/iOS 实现为 move，delete 不命中、无副作用）
    try {
      await tmp.delete();
    } catch (_) {}
  } else {
    // 公共目录不可用/失败，原子提交到私有目录：rename 覆盖旧文件
    // （Windows 上 rename 不能覆盖已存在目标）
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
/// 优先走 download_index 索引（O(1) 查询）：先查本服务器新指纹，未命中
/// 再查旧版指纹（升级前的历史下载），命中且归属可确认时把旧记录迁移到
/// 新指纹（文件名不变，无需重下）。索引命中但文件已丢失时懒修复（删除
/// 失效记录）；索引未命中回退目录指纹扫描一次并回填索引。
Future<String?> findDownloadedSong(Song song, String serverId) async {
  final fingerprint = _songFingerprint(serverId, song.id);
  final legacy = _legacySongFingerprint(song.id);
  Database? db;
  try {
    db = await AppDb.instance();
  } catch (_) {}
  if (db != null) {
    try {
      for (final fp in [fingerprint, legacy]) {
        final rows = await db.query(
          'download_index',
          where: 'fingerprint = ?',
          whereArgs: [fp],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final row = rows.first;
        final path = row['path'] as String;
        // 旧记录须归属本服务器（或无归属）才可复用：另一服务器的同名 id
        // 记录不能跨服共用，保持未下载语义（目录扫描兜底会再校验一次）
        final rowServer = (row['server_id'] as String?) ?? '';
        if (fp == legacy && rowServer.isNotEmpty && rowServer != serverId) {
          break;
        }
        if (await File(path).exists()) {
          try {
            await db.update(
              'download_index',
              {
                // 旧记录迁移：指纹改写为新值并补归属
                if (fp == legacy) 'fingerprint': fingerprint,
                if (fp == legacy) 'server_id': serverId,
                'last_accessed_at': DateTime.now().millisecondsSinceEpoch,
              },
              where: 'fingerprint = ?',
              whereArgs: [fp],
            );
          } catch (_) {}
          return path;
        }
        // 索引有记录但文件不存在：懒修复，删除失效记录
        await db.delete(
          'download_index',
          where: 'fingerprint = ?',
          whereArgs: [fp],
        );
      }
    } catch (_) {
      // 索引查询异常继续走目录兜底
    }
  }

  // 兜底：历史下载无索引记录，按指纹扫描 Music 目录并回填索引
  try {
    final docs = await getApplicationDocumentsDirectory();
    final musicDir = Directory(p.join(docs.path, 'Music'));
    if (!await musicDir.exists()) return null;
    final marker = '--$fingerprint.';
    final legacyMarker = '--$legacy.';
    await for (final entry in musicDir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      // .tmp 是中断残留的半截文件，绝不能当作有效下载回填索引
      if (name.endsWith('.tmp')) continue;
      final isLegacy = !name.contains(marker) && name.contains(legacyMarker);
      if (!name.contains(marker) && !isLegacy) continue;
      // 旧文件认领须过归属校验：已有记录且归属其他服务器时不得跨服共用
      // （索引不可用时保持旧行为：认领）
      if (isLegacy &&
          db != null &&
          !await _legacyAdoptable(db, song.id, serverId)) {
        continue;
      }
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        final data = {
          'server_id': serverId,
          'song_id': song.id,
          'fingerprint': fingerprint,
          'path': entry.path,
          'size': await entry.length(),
          'created_at': now,
          'last_accessed_at': now,
        };
        // 旧文件认领：若存在归属合法的旧记录则就地迁移，否则新登记
        final existing = (isLegacy && db != null)
            ? await db.query(
                'download_index',
                where: 'fingerprint = ?',
                whereArgs: [legacy],
                limit: 1,
              )
            : const <Map<String, Object?>>[];
        if (db != null) {
          if (existing.isNotEmpty) {
            await db.update(
              'download_index',
              data,
              where: 'fingerprint = ?',
              whereArgs: [legacy],
            );
          } else {
            await db.insert(
              'download_index',
              data,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      } catch (_) {}
      return entry.path;
    }
  } catch (_) {
    // 目录不可读等情况按「未下载」处理
  }
  return null;
}

/// 旧版指纹文件可否认领：无记录（最早期下载）或记录归属本服务器/无归属
/// 才可认领；已归属其他服务器（同数字 id 不同服）的文件不可跨服共用。
/// 索引不可用时保持旧行为（认领）
Future<bool> _legacyAdoptable(
  Database db,
  String songId,
  String serverId,
) async {
  try {
    final rows = await db.query(
      'download_index',
      where: 'fingerprint = ?',
      whereArgs: [_legacySongFingerprint(songId)],
      limit: 1,
    );
    if (rows.isEmpty) return true;
    final server = (rows.first['server_id'] as String?) ?? '';
    return server.isEmpty || server == serverId;
  } catch (_) {
    return true;
  }
}

String _songFingerprint(String serverId, String songId) => sha256
    .convert(utf8.encode('$serverId|$songId'))
    .toString()
    .substring(0, 16);

/// 旧版指纹（仅 songId，不含服务器）：用于升级前历史下载/记录的迁移识别
String _legacySongFingerprint(String songId) =>
    sha256.convert(utf8.encode(songId)).toString().substring(0, 16);

/// 清理下载中断残留的 .tmp 半截文件（进程被杀/断电时 dio 来不及删除）。
/// 残留文件的指纹标记会被目录兜底扫描和本地音乐扫描误匹配，启动时统一清掉
Future<void> cleanupOrphanTmpFiles() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final musicDir = Directory(p.join(docs.path, 'Music'));
    if (!await musicDir.exists()) return;
    await for (final entry in musicDir.list()) {
      if (entry is! File) continue;
      if (!entry.uri.pathSegments.last.endsWith('.tmp')) continue;
      try {
        // 只清超过 1 小时的残留：正在进行的下载不会误伤
        final mtime = (await entry.stat()).modified;
        if (DateTime.now().difference(mtime) > const Duration(hours: 1)) {
          await entry.delete();
        }
      } catch (_) {}
    }
  } catch (_) {
    // 清理失败不影响主流程
  }
}
