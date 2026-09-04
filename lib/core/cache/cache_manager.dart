import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/prefs.dart';

/// 缓存限额档位（附录·四）：2GB / 5GB / 10GB / 无限制
enum CacheLimit {
  g2('2 GB', 2 * 1024 * 1024 * 1024),
  g5('5 GB', 5 * 1024 * 1024 * 1024),
  g10('10 GB', 10 * 1024 * 1024 * 1024),
  unlimited('无限制', null);

  const CacheLimit(this.label, this.bytes);
  final String label;
  final int? bytes;
}

/// 缓存设置：边听边存 / 自动下载 / 限额
class CacheSettings {
  const CacheSettings({
    this.cacheWhileListen = true,
    this.autoDownload = false,
    this.limit = CacheLimit.g2,
  });

  /// 播放时走本地缓存源（LockCachingAudioSource），断网可续播已缓存段落
  final bool cacheWhileListen;
  final bool autoDownload;
  final CacheLimit limit;

  CacheSettings copyWith({
    bool? cacheWhileListen,
    bool? autoDownload,
    CacheLimit? limit,
  }) => CacheSettings(
    cacheWhileListen: cacheWhileListen ?? this.cacheWhileListen,
    autoDownload: autoDownload ?? this.autoDownload,
    limit: limit ?? this.limit,
  );
}

class CacheSettingsController extends Notifier<CacheSettings> {
  static const _listenKey = 'cache_while_listen';
  static const _autoDownloadKey = 'cache_auto_download';
  static const _limitKey = 'cache_limit';

  @override
  CacheSettings build() {
    final prefs = ref.watch(sharedPrefsProvider);
    const fallback = CacheSettings();
    return CacheSettings(
      cacheWhileListen: prefs.getBool(_listenKey) ?? fallback.cacheWhileListen,
      autoDownload: prefs.getBool(_autoDownloadKey) ?? fallback.autoDownload,
      limit: CacheLimit.values.firstWhere(
        (l) => l.name == prefs.getString(_limitKey),
        orElse: () => fallback.limit,
      ),
    );
  }

  Future<void> set(CacheSettings s) async {
    state = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_listenKey, s.cacheWhileListen);
    await prefs.setBool(_autoDownloadKey, s.autoDownload);
    await prefs.setString(_limitKey, s.limit.name);
  }
}

final cacheSettingsProvider =
    NotifierProvider<CacheSettingsController, CacheSettings>(
      CacheSettingsController.new,
    );

/// 缓存占用统计（清理后调用方 invalidate 刷新）
final audioCacheSizeProvider = FutureProvider<int>(
  (_) => AudioCache.sizeBytes(),
);

/// 音频边听边存缓存目录管理（just_audio LockCachingAudioSource 的默认落盘位置）
abstract final class AudioCache {
  static Future<Directory> dir() async {
    final tmp = await getTemporaryDirectory();
    return Directory('${tmp.path}${Platform.pathSeparator}just_audio_cache');
  }

  /// 缓存占用字节数；目录不存在或不可读返回 0
  static Future<int> sizeBytes() async {
    try {
      final cacheDir = await dir();
      if (!cacheDir.existsSync()) return 0;
      var total = 0;
      await for (final entity in cacheDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) total += entity.lengthSync();
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

  /// 超限 LRU 清理：按最后修改时间从旧到新删除文件直到低于限额
  static Future<void> enforceLimit(CacheLimit limit) async {
    final maxBytes = limit.bytes;
    if (maxBytes == null) return;
    try {
      final cacheDir = await dir();
      if (!cacheDir.existsSync()) return;
      final files = <File>[];
      var total = 0;
      await for (final entity in cacheDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        files.add(entity);
        total += entity.lengthSync();
      }
      if (total <= maxBytes) return;
      files.sort(
        (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
      );
      for (final f in files) {
        if (total <= maxBytes) break;
        final size = f.lengthSync();
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
