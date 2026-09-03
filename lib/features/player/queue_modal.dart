import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(GlassTokens.radiusSheet)),
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
                  Text('播放列表(${queue.length})',
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  // 清空队列（现代播放器标配）
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      ref.read(playerActionsProvider).clearQueue();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('已清空播放队列'),
                            duration: Duration(seconds: 1)),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('清空',
                          style:
                              TextStyle(fontSize: 14, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        ref.read(playerActionsProvider).cyclePlayMode(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(modeIcon, size: 22, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(_modeText[mode] ?? '',
                              style: const TextStyle(
                                  fontSize: 14, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (queue.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Text('队列为空',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
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
                  onReorderItem: (oldIndex, newIndex) =>
                      ref.read(playerActionsProvider).reorderQueue(
                          oldIndex, newIndex),
                  proxyDecorator: (child, index, animation) => AnimatedBuilder(
                    animation: animation,
                    builder: (_, child) => Material(
                      color: const Color(0x2E1EB4FF),
                      borderRadius:
                          const BorderRadius.all(Radius.circular(AppRadius.s)),
                      elevation: animation.value * 6,
                      child: child,
                    ),
                    child: child,
                  ),
                  itemCount: queue.length,
                  itemBuilder: (_, i) {
                    final song = queue[i];
                    final isCurrent = current?.id == song.id;
                    return Container(
                      key: ValueKey(song.id),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppTheme.queueActive.withValues(alpha: 0.08)
                            : Colors.transparent,
                        border: const Border(
                          bottom: BorderSide(color: Color(0x14FFFFFF), width: 0.5),
                        ),
                      ),
                      child: InkWell(
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
                                  index: i,
                                  child: const Icon(Icons.drag_indicator,
                                      size: 22, color: Colors.white38),
                                ),
                              ),
                              // 序号：当前行 queueActive 高亮
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '${i + 1}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                    color: isCurrent
                                        ? AppTheme.queueActive
                                        : Colors.white38,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              CoverArt(
                                  albumId: song.albumId,
                                  size: 48,
                                  radius: AppRadius.s),
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
                                        color: isCurrent
                                            ? AppTheme.queueActive
                                            : Colors.white,
                                        fontWeight: isCurrent
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white54)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    size: 22, color: Colors.white),
                                onPressed: () => ref
                                    .read(playerActionsProvider)
                                    .removeFromQueue(song.id),
                              ),
                            ],
                          ),
                        ),
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
}
