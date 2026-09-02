import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'player_controller.dart';

/// 打开播放队列弹窗（对标 1.x QueueModal：底部滑出 + 下拉关闭）。
void showQueueModal(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.queuePanel,
    barrierColor: Colors.black45,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: 320,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部拖动条
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题 + 播放模式切换
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              child: Row(
                children: [
                  Text('播放列表(${queue.length})',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
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
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text('队列为空',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: queue.length,
                  itemBuilder: (_, i) {
                    final song = queue[i];
                    final isCurrent = current?.id == song.id;
                    return Container(
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? const Color(0x141EB4FF) // rgba(30,180,255,0.08)
                            : Colors.transparent,
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFF333333), width: 0.5),
                        ),
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          ref.read(playerActionsProvider).play(song);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
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
                                            fontSize: 13, color: Colors.white54)),
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
      ),
    );
  }
}
