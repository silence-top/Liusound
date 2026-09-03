import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/glass.dart';
import 'player_controller.dart';

/// 打开播放队列弹窗（对标 1.x QueueModal：底部滑出 + 下拉关闭）。
void showQueueModal(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black45,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(GlassTokens.radiusSheet),
      ),
    ),
    builder: (_) => const _QueueSheet(),
  );
}

/// 队列弹窗内容：拖动条 + 标题/模式切换 + 队列列表（当前项绿色高亮）。
class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  static const _modeText = {
    PlayMode.order: '顺序播放',
    PlayMode.shuffle: '随机播放',
    PlayMode.repeatOne: '单曲循环',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    final current = ref.watch(currentSongProvider);
    final mode = ref.watch(playModeProvider);
    // 流还没吐第一个值时按「播放中」处理，避免刚打开队列电平条就僵住
    final playing = ref.watch(isPlayingProvider).value ?? true;
    final modeIcon = switch (mode) {
      PlayMode.order => Icons.repeat,
      PlayMode.shuffle => Icons.shuffle,
      PlayMode.repeatOne => Icons.repeat_one,
    };

    return GlassSurface(
      radius: GlassTokens.radiusSheet,
      blur: GlassTokens.blurHeavy,
      tint: Colors.black.withValues(alpha: 0.35),
      gradientBorder: true,
      shadow: false,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖动条
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              // 圆角豁免：弹窗顶部拖动条 4px 高，仅 2px 圆角
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题 + 播放模式切换
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Text(
                  '播放列表(${queue.length})',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // 清空队列（现代播放器标配）
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    ref.read(playerActionsProvider).clearQueue();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已清空播放队列'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '清空',
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => ref.read(playerActionsProvider).cyclePlayMode(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(modeIcon, size: 22, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          _modeText[mode] ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (queue.isEmpty)
            glassEmptyState(
              text: '队列为空\n去首页挑几首歌开始播放',
              icon: Icons.queue_music_outlined,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            )
          else
            Flexible(
              // 拖动排序（现代播放器标配）：行首把手拖动 + 拖动中浮起高亮
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                // 固定行高：惰性构建 + 滚动确定性
                itemExtent: 64,
                // onReorderItem 的 newIndex 已完成移除位修正，直接插入
                onReorderItem: (oldIndex, newIndex) => ref
                    .read(playerActionsProvider)
                    .reorderQueue(oldIndex, newIndex),
                proxyDecorator: (child, index, animation) => AnimatedBuilder(
                  animation: animation,
                  builder: (_, child) => Material(
                    color: const Color(0x2E1EB4FF),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppRadius.s),
                    ),
                    elevation: animation.value * 6,
                    child: child,
                  ),
                  child: child,
                ),
                itemCount: queue.length,
                itemBuilder: (_, i) {
                  final song = queue[i];
                  final isCurrent = current?.id == song.id;
                  final row = _row(context, ref, song, i, isCurrent, playing);
                  // key 必须留在 itemBuilder 返回的最外层，ReorderableListView 才认得
                  return Dismissible(
                    key: ValueKey(song.id),
                    direction: DismissDirection.endToStart,
                    background: _removeBackground(),
                    onDismissed: (_) => ref
                        .read(playerActionsProvider)
                        .removeFromQueue(song.id),
                    child: isCurrent
                        ? GlassSurface(
                            radius: AppRadius.m,
                            blur: 0,
                            tint: AppTheme.queueActive.withValues(alpha: 0.14),
                            shadow: false,
                            margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                            child: row,
                          )
                        : Container(
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Color(0x14FFFFFF),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: row,
                          ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 队列行本体：拖动把手 + 序号/电平条 + 封面 + 标题歌手 + 删除
  Widget _row(
    BuildContext context,
    WidgetRef ref,
    Song song,
    int index,
    bool isCurrent,
    bool playing,
  ) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        ref.read(playerActionsProvider).play(song);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // 拖动把手：热区扩为 40×48（≥36dp 触控标准）
            SizedBox(
              width: 40,
              height: 48,
              child: ReorderableDragStartListener(
                index: index,
                child: const Icon(
                  Icons.drag_indicator,
                  size: 22,
                  color: Colors.white38,
                ),
              ),
            ),
            // 当前播放行用电平条取代序号，一眼定位正在播的是哪首
            SizedBox(
              width: 28,
              child: isCurrent
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: _EqualizerBars(
                        color: AppTheme.queueActive,
                        playing: playing,
                      ),
                    )
                  : Text(
                      '${index + 1}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontFeatures: [FontFeature.tabularFigures()],
                        color: Colors.white38,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            CoverArt(albumId: song.albumId, size: 48, radius: AppRadius.s),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: isCurrent ? AppTheme.queueActive : Colors.white,
                      fontWeight: isCurrent
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 22, color: Colors.white),
              onPressed: () =>
                  ref.read(playerActionsProvider).removeFromQueue(song.id),
            ),
          ],
        ),
      ),
    );
  }

  /// 左滑删除的底衬：与当前行同样的圆角与外边距，滑动时才露出来
  Widget _removeBackground() => Container(
    alignment: Alignment.centerRight,
    margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
    padding: const EdgeInsets.only(right: 24),
    decoration: BoxDecoration(
      color: AppTheme.heartRed.withValues(alpha: 0.20),
      borderRadius: BorderRadius.circular(AppRadius.m),
    ),
    child: const Icon(Icons.delete_outline, size: 22, color: AppTheme.heartRed),
  );
}

/// 播放中电平条：三根竖条按不同相位做三角波起伏，暂停时冻结在低位。
/// 仅当前播放行使用，全场最多一个实例，动画开销可忽略。
class _EqualizerBars extends StatefulWidget {
  const _EqualizerBars({required this.color, this.playing = true});

  final Color color;
  final bool playing;

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  static const _phases = [0.0, 0.38, 0.71];
  static const _minHeight = 4.0;
  static const _maxHeight = 16.0;

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: _maxHeight,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final phase in _phases)
              _bar((_controller.value + phase) % 1.0),
          ],
        ),
      ),
    );
  }

  /// 三角波（0→1→0），避免锯齿波在循环接缝处跳变
  Widget _bar(double t) {
    final wave = t < 0.5 ? t * 2 : (1 - t) * 2;
    return Container(
      width: 3,
      height: _minHeight + (_maxHeight - _minHeight) * wave,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}
