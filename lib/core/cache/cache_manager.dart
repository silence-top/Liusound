import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/prefs.dart';

import 'cache_manager_web.dart' if (dart.library.io) 'cache_manager_io.dart';
export 'cache_manager_web.dart' if (dart.library.io) 'cache_manager_io.dart';

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
    this.cacheWhileListen = false,
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
