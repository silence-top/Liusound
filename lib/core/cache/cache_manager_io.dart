import 'dart:io';

import 'cache_manager.dart' show CacheLimit;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 音频边听边存缓存目录管理（just_audio LockCachingAudioSource 的默认落盘位置）
abstract final class AudioCache {
  static Future<Directory> dir() async {
    final tmp = await getTemporaryDirectory();
    return Directory(p.join(tmp.path, 'just_audio_cache'));
  }

  /// 缓存占用字节数；目录不存在或不可读返回 0
  static Future<int> sizeBytes() async {
    try {
      final cacheDir = await dir();
      if (!await cacheDir.exists()) return 0;
      var total = 0;
      await for (final entity in cacheDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 一键清理：删除整个缓存目录后重建
  static Future<void> clear() async {
    try {
      final cacheDir = await dir();
      if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
    } catch (_) {
      // 清理失败静默（下次冷启动目录重建）
    }
  }

  static DateTime? _lastEnforceAt;
  static int? _lastEnforceLimitBytes;

  /// 超限 LRU 清理：按最后修改时间从旧到新删除文件直到低于限额。
  /// 每次切歌都会被播放器调用（一次播放两连调），全目录递归 + 逐文件
  /// stat 开销大——同限额 5 分钟内只跑一轮，限额变化立即生效
  static Future<void> enforceLimit(CacheLimit limit) async {
    final maxBytes = limit.bytes;
    if (maxBytes == null) return;
    final now = DateTime.now();
    if (maxBytes == _lastEnforceLimitBytes &&
        _lastEnforceAt != null &&
        now.difference(_lastEnforceAt!) < const Duration(minutes: 5)) {
      return;
    }
    _lastEnforceAt = now;
    _lastEnforceLimitBytes = maxBytes;
    try {
      final cacheDir = await dir();
      if (!await cacheDir.exists()) return;
      // (file, size, mtime)：mtime 异步取，避免排序前主 isolate 逐个同步 stat
      final entries = <(File, int, DateTime)>[];
      var total = 0;
      await for (final entity in cacheDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final length = await entity.length();
        final modified = await entity.lastModified();
        entries.add((entity, length, modified));
        total += length;
      }
      if (total <= maxBytes) return;
      entries.sort((a, b) => a.$3.compareTo(b.$3));
      for (final (f, size, _) in entries) {
        if (total <= maxBytes) break;
        try {
          await f.delete();
          total -= size;
        } catch (_) {
          // 单个文件删除失败不影响整体
        }
      }
    } catch (_) {
      // 目录异常时放弃本轮清理
    }
  }
}
