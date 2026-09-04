import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart' show serverAdapterProvider;
import '../cache/cache_manager.dart';
import '../models/models.dart';
import '../settings/streaming_prefs.dart';
import 'download_service.dart';

/// 兼容 Ref 与 WidgetRef 的最小读取接口（两者 .read tear-off 同签名）
typedef RefReader = T Function<T>(ProviderListenable<T> provider);

/// 自动下载（附录·四）：开启后台预取「我喜欢」歌曲（最多 50 首）到离线目录。
/// 蜂窝下关闭传输开关时跳过；已离线的歌曲按回退命名规则去重。
class AutoDownload {
  static bool _running = false;

  static Future<void> run(RefReader read) async {
    if (_running) return;
    final adapter = read(serverAdapterProvider);
    if (adapter == null) return;
    final settings = read(streamingSettingsProvider);
    final quality = await resolveCurrentQuality(settings);
    if (quality == null) return; // 蜂窝禁传
    _running = true;
    try {
      final List<Song> liked;
      try {
        liked = await adapter.fetchLikedSongs(limit: 50);
      } catch (_) {
        return;
      }
      for (final song in liked) {
        if (!read(cacheSettingsProvider).autoDownload) return;
        if (await findDownloadedSong(song) != null) continue;
        try {
          final source = await adapter.resolveDownload(song);
          await downloadSongFile(source: source, song: song);
        } catch (_) {
          continue; // 单曲失败继续下一首
        }
      }
      unawaited(AudioCache.enforceLimit(read(cacheSettingsProvider).limit));
    } finally {
      _running = false;
    }
  }
}

/// 供启动时调用（自动下载开关开启则补跑一轮）
void maybeAutoDownload(RefReader read) {
  if (!read(cacheSettingsProvider).autoDownload) return;
  unawaited(AutoDownload.run(read));
}
