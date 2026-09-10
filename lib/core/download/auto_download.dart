import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/adapter_provider.dart'
    show activeServerIdProvider, serverAdapterProvider;
import '../cache/cache_manager.dart' show cacheSettingsProvider;
import '../local/local_library.dart' show downloadIndexVersionProvider;
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
      final serverId = read(activeServerIdProvider);
      for (final song in liked) {
        // 循环中重读当前服务器：切换服务器后旧流程必须中止，
        // 否则会把旧服务器的歌曲下到新服务器的归属里
        if (read(activeServerIdProvider) != serverId) {
          return;
        }
        if (!read(cacheSettingsProvider).autoDownload) return;
        if (await findDownloadedSong(song) != null) continue;
        try {
          final source = await adapter.resolveDownload(song);
          await downloadSongFile(
            source: source,
            song: song,
            serverId: serverId,
            networkSettings: read(networkSettingsProvider),
          );
          // 下载完成即时刷新「本地音乐」合并展示
          read(downloadIndexVersionProvider.notifier).state++;
        } catch (_) {
          continue; // 单曲失败继续下一首
        }
      }
      // 下载库（Music/）不参与播放缓存 LRU：Cache 与 Download 完全分离，
      // 容量治理由设置页下载管理负责，这里不再触发 AudioCache.enforceLimit
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
