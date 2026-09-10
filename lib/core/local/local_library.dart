import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../models/models.dart';
import '../platform/isolate_runner.dart';
import '../storage/app_db.dart';

import 'local_library_web.dart' if (dart.library.io) 'local_library_io.dart';
export 'local_library_web.dart' if (dart.library.io) 'local_library_io.dart';

/// 本地歌曲 id 前缀：与服务器歌曲 id 天然不冲突。
/// id 格式为 local:{fingerprint}——fingerprint 由文件大小 + mtime + 头部 16KB +
/// 元数据派生，移动/重命名文件不改变歌曲身份（路径变化仍记录在 Song.path）
const localSongIdPrefix = 'local:';

/// 从本地歌曲 id 解出 fingerprint（非本地歌曲返回 null）
String? localSongFingerprint(Song song) => song.id.startsWith(localSongIdPrefix)
    ? song.id.substring(localSongIdPrefix.length)
    : null;

/// 本地歌曲的磁盘路径（非本地歌曲返回 null）
String? localSongPath(Song song) =>
    song.id.startsWith(localSongIdPrefix) ? song.path : null;

/// 下载产物命名标记（download_service：`歌手 - 标题--<16位指纹>.<ext>`，
/// 指纹为 sha256(songId) 前 16 位十六进制）：下载落盘目录（Android 公共
/// Music/流声、Windows 音乐库\流声）与本地扫描目录重叠，按文件名标记排除，
/// 避免同一首歌既作为服务器歌曲离线副本、又以 local: 身份重复入库。
/// 用户自放文件几乎不会匹配该模式，误伤概率可忽略。
final RegExp _downloadArtifactPattern = RegExp(
  r'--[0-9a-f]{16}\.[A-Za-z0-9]+$',
);

/// 是否应用自身下载产物（扫描排除用；公开以便测试与排查）
bool isDownloadedArtifact(String path) =>
    _downloadArtifactPattern.hasMatch(p.basename(path));

// ---------- 快照缓存：进页面先读 SQLite 秒开，后台限流重扫 ----------

/// 后台重扫发现文件变化时 bump，驱动 localSongsProvider 重读快照
final localScanVersionProvider = StateProvider<int>((ref) => 0);

/// 下载完成信号：downloadSongFile 落盘并登记索引后由调用方 bump，
/// 驱动 localSongsProvider 的「已下载」段实时进入列表（与本地音乐合并展示）
final downloadIndexVersionProvider = StateProvider<int>((ref) => 0);

DateTime? _lastScanFinishedAt;

/// 已下载的服务器歌曲（download_index.payload 快照反序列化）：
/// 身份保持服务器 id——列表点播经 player_source_resolver 自动命中离线文件，
/// 收藏/评分/歌词等继续命中服务器歌曲，与扫描的 local: 歌曲天然不重。
/// payload 为空的历史下载（旧版本所下）无法还原元数据，跳过。
Future<List<Song>> loadDownloadedSongs() async {
  try {
    final db = await AppDb.instance();
    final rows = await db.query(
      'download_index',
      columns: ['payload'],
      orderBy: 'created_at DESC',
    );
    final songs = <Song>[];
    for (final row in rows) {
      final raw = row['payload'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        songs.add(Song.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // 单条快照损坏跳过，不影响其余
      }
    }
    return songs;
  } catch (_) {
    return const [];
  }
}

/// 本地音乐列表（资料库「本地音乐」入口）：
/// 扫描的本地歌曲 + 已下载的服务器歌曲合并展示；
/// 首次进页面同步扫描；之后读 SQLite 快照秒开，后台限流重扫（5 分钟内不重复），
/// 文件有增删时 bump 版本自动刷新列表；下载完成由调用方 bump
/// downloadIndexVersionProvider 实时补入已下载段。
final localSongsProvider = FutureProvider<List<Song>>((ref) async {
  ref.watch(localScanVersionProvider);
  ref.watch(downloadIndexVersionProvider);
  final cached = await loadLocalSongsCache();
  final List<Song> local;
  if (cached != null && cached.isNotEmpty) {
    _rescanInBackground(ref, cached);
    local = cached;
  } else {
    local = await scanLocalLibrary();
    _lastScanFinishedAt = DateTime.now();
  }
  final downloaded = await loadDownloadedSongs();
  return [...local, ...downloaded];
});

/// 强制重扫磁盘（本地音乐下拉刷新）：绕过 5 分钟限流直扫文件系统，
/// 结果直接覆盖 SQLite 快照；调用方随后 invalidate localSongsProvider
/// 重读缓存即可拿到最新数据。
Future<void> forceLocalRescan() async {
  await scanLocalLibrary();
  _lastScanFinishedAt = DateTime.now();
}

void _rescanInBackground(Ref ref, List<Song> served) {
  final last = _lastScanFinishedAt;
  if (last != null &&
      DateTime.now().difference(last) < const Duration(minutes: 5)) {
    return;
  }
  _lastScanFinishedAt = DateTime.now();
  Future<void> run() async {
    try {
      final fresh = await scanLocalLibrary();
      if (!_sameSongs(fresh, served)) {
        ref.read(localScanVersionProvider.notifier).state++;
      }
    } catch (_) {
      // 权限被回收等场景静默保留快照
    }
  }

  unawaited(run());
}

/// 快照对比只看关键元数据：数量或任一文件的大小/时长/标签变了才算变化
bool _sameSongs(List<Song> a, List<Song> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x.id != y.id ||
        x.size != y.size ||
        x.duration != y.duration ||
        x.title != y.title ||
        x.artist != y.artist) {
      return false;
    }
  }
  return true;
}

Future<List<Song>?> loadLocalSongsCache() async {
  try {
    final db = await AppDb.instance();
    final rows = await db.query(
      'library_snapshot',
      where: "server_key = 'local' AND kind = 'local_songs_v2'",
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['payload'] as String;
    return await _decodeSongsPayload(raw);
  } catch (_) {
    return null;
  }
}

/// 大 JSON 快照编解码阈值（超过则强制后台 isolate，避免主 isolate 卡顿）
const _snapshotIsolateThreshold = 256 * 1024;

/// payload 解码：大于阈值时在 isolate 中执行（web 无 isolate，直接算）
Future<List<Song>> _decodeSongsPayload(String raw) async {
  if (raw.length > _snapshotIsolateThreshold) {
    return runInIsolate(() => _decodeSongs(raw));
  }
  return _decodeSongs(raw);
}

List<Song> _decodeSongs(String raw) => [
  for (final j in jsonDecode(raw) as List)
    Song.fromJson(j as Map<String, dynamic>),
];

/// 扫描结果落 SQLite 快照（供平台扫描实现调用；缓存失败只影响下次秒开）
Future<void> saveLocalScanCache(List<Song> songs) async {
  try {
    final db = await AppDb.instance();
    final payload = songs.length > 1000
        ? await runInIsolate(
            () => jsonEncode(songs.map((s) => s.toJson()).toList()),
          )
        : jsonEncode(songs.map((s) => s.toJson()).toList());
    await db.insert('library_snapshot', {
      'server_key': 'local',
      'kind': 'local_songs_v2',
      'version': DateTime.now().toIso8601String(),
      'payload': payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // 旧格式（路径 id）缓存行清理——纯可再生缓存，无用户数据
    await db.delete(
      'library_snapshot',
      where: "server_key = 'local' AND kind = 'local_songs'",
    );
  } catch (_) {
    // 缓存失败只影响下次秒开，不影响本次结果
  }
}
