/// web 端音频缓存占位：浏览器端缓存走 IndexedDB/Cache API（Phase 2）。
/// 当前：占用恒 0，清理/限额 no-op。
library;

import 'cache_manager.dart' show CacheLimit;

abstract final class AudioCache {
  static Future<int> sizeBytes() async => 0;

  static Future<void> clear() async {}

  static Future<void> enforceLimit(CacheLimit limit) async {}
}
