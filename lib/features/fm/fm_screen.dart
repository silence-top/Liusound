import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/toast.dart';
import '../player/player_controller.dart';
import 'fm_providers.dart';

/// 私人 FM：随曲库随机漫游。
/// 入口在首页横幅；队列由全局 queueProvider 承载，本页只做
/// 开始 / 不喜欢跳过 / 收藏 / 播放暂停 / 补充下一批。
class FmScreen extends ConsumerWidget {
  const FmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    final loading = ref.watch(fmLoadingProvider);
    // 切歌后检查队列余量，将尽自动补一批
    ref.listen(currentSongProvider, (_, _) {
      unawaited(ref.read(fmControllerProvider).refillIfNeeded());
    });
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: AppTheme.textPrimaryOf(context),
          title: const Text('私人 FM'),
          actions: [
            IconButton(
              tooltip: '换一批',
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onPressed: loading ? null : () => _start(ref),
            ),
          ],
        ),
        body: song == null ? _StartHero(loading: loading) : _NowRoaming(),
      ),
    );
  }

  Future<void> _start(WidgetRef ref) async {
    final ok = await ref.read(fmControllerProvider).start();
    if (!ok) showToast('没有拿到新歌，稍后再试', error: true);
  }
}

/// 未开始：引导页
class _StartHero extends ConsumerWidget {
  const _StartHero({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.radio, size: 88, color: AppTheme.textFaintOf(context)),
          const SizedBox(height: 16),
          Text(
            '从你的曲库里随机漫游',
            style: TextStyle(color: AppTheme.textDimOf(context), fontSize: 15),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: loading
                ? null
                : () async {
                    final ok = await ref.read(fmControllerProvider).start();
                    if (!ok && context.mounted) {
                      showToast('没有拿到新歌，稍后再试', error: true);
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: primary.withValues(alpha: 0.9),
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始漫游'),
          ),
        ],
      ),
    );
  }
}

/// 漫游中：大封面 + 曲目信息 + 操作行（不喜欢 / 收藏 / 播放暂停 / 下一首）
class _NowRoaming extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    final isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CoverArt(
              albumId: song.albumId,
              size: MediaQuery.sizeOf(context).width - 64 > 320
                  ? 320
                  : MediaQuery.sizeOf(context).width - 64,
              radius: 16,
            ),
            const SizedBox(height: 28),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${song.artist} · ${song.album}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textDimOf(context),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 36),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: '不喜欢，换一首',
                  iconSize: 30,
                  color: AppTheme.textDimOf(context),
                  icon: const Icon(Icons.thumb_down_off_alt),
                  onPressed: () => ref.read(fmControllerProvider).skipDislike(),
                ),
                IconButton(
                  tooltip: song.starred ? '取消收藏' : '收藏',
                  iconSize: 30,
                  color: song.starred
                      ? Theme.of(context).colorScheme.primary
                      : AppTheme.textDimOf(context),
                  icon: Icon(
                    song.starred ? Icons.favorite : Icons.favorite_border,
                  ),
                  onPressed: () => ref.read(fmControllerProvider).likeCurrent(),
                ),
                _PlayPauseButton(isPlaying: isPlaying),
                IconButton(
                  tooltip: '下一首',
                  iconSize: 30,
                  color: AppTheme.textDimOf(context),
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => ref.read(playerActionsProvider).playNext(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 播放/暂停大按钮（68 圆形，主题色描边）
class _PlayPauseButton extends ConsumerWidget {
  const _PlayPauseButton({required this.isPlaying});

  final bool isPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => ref.read(playerActionsProvider).toggle(),
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: primary, width: 2),
          color: primary.withValues(alpha: 0.12),
        ),
        child: Icon(
          isPlaying ? Icons.pause : Icons.play_arrow,
          size: 34,
          color: AppTheme.textPrimaryOf(context),
        ),
      ),
    );
  }
}
