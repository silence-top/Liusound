import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/cover_art.dart';
import 'full_screen_player.dart';
import 'player_controller.dart';

/// 底部迷你播放条。
///
/// 性能红线示范：本组件只 watch [currentSongProvider]（仅切歌时重建）；
/// 播放按钮与进度条拆分为独立子组件各自局部订阅高频流 ——
/// 播放期间仅这两个小组件重建，页面其余部分零参与。
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: CoverArt(albumId: song.albumId, size: 44, radius: 8),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
              trailing: const _MiniPlayButton(),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => FullScreenPlayer(
                      onClose: () => Navigator.of(context).pop(),
                    ),
                  ),
                );
              },
            ),
            const _MiniProgressBar(),
          ],
        ),
      ),
    );
  }
}

/// 播放/暂停按钮（仅订阅 isPlaying 布尔流，distinct 后仅在翻转时重建）
class _MiniPlayButton extends ConsumerWidget {
  const _MiniPlayButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying =
        ref.watch(isPlayingProvider).valueOrNull ?? false;
    return IconButton(
      iconSize: 34,
      color: Colors.white,
      icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
      onPressed: () => ref.read(playerActionsProvider).toggle(),
    );
  }
}

/// 细线进度条（仅订阅进度/时长流，内部已事件驱动节流）
class _MiniProgressBar extends ConsumerWidget {
  const _MiniProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration =
        ref.watch(durationProvider).valueOrNull ?? Duration.zero;
    final progress =
        duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0.0;
    return LinearProgressIndicator(
      value: progress.clamp(0.0, 1.0),
      minHeight: 2,
      backgroundColor: Colors.white12,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}
