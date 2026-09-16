import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download_queue.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/glass_theme.dart';
import 'album_tint.dart';

/// 下载列表弹层：后台下载队列总览（排队 / 进行中 / 完成 / 失败）。
/// 失败可重试，非运行中的任务可移除，可一键清理已完成。
Future<void> showDownloadQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black38,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(GlassTokens.radiusSheet),
      ),
    ),
    builder: (_) => const _DownloadQueueSheet(),
  );
}

class _DownloadQueueSheet extends ConsumerWidget {
  const _DownloadQueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadQueueProvider);
    final hasFinished = tasks.any(
      (t) =>
          t.status == DownloadTaskStatus.completed ||
          t.status == DownloadTaskStatus.failed,
    );
    return AlbumFrostedPanel(
      dominant: null,
      opaque: true,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(GlassTokens.radiusSheet),
      ),
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '下载列表',
                    style: TextStyle(
                      color: AppTheme.textPrimaryOf(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (hasFinished)
                  TextButton(
                    onPressed: () => ref
                        .read(downloadQueueProvider.notifier)
                        .clearFinished(),
                    child: const Text('清已完成'),
                  ),
                const SizedBox(width: 8),
              ],
            ),
            Divider(
              height: 1,
              color: AppTheme.textPrimaryOf(context).withValues(alpha: 0.08),
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  '暂无下载任务',
                  style: TextStyle(
                    color: AppTheme.textFaintOf(context),
                    fontSize: 14,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  itemBuilder: (context, i) => _TaskTile(task: tasks[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;
    final errorColor = Theme.of(context).colorScheme.error;
    final faint = AppTheme.textFaintOf(context);
    final (icon, iconColor, statusText) = switch (task.status) {
      DownloadTaskStatus.waiting => (Icons.schedule, faint, '排队中'),
      DownloadTaskStatus.running => (
        Icons.downloading,
        primary,
        task.total > 0 ? '${(task.progress! * 100).round()}%' : '连接中…',
      ),
      DownloadTaskStatus.completed => (Icons.check_circle, primary, '已完成'),
      DownloadTaskStatus.failed => (
        Icons.error_outline,
        errorColor,
        task.error ?? '下载失败',
      ),
    };
    return ListTile(
      leading: switch (task.status) {
        DownloadTaskStatus.running => SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            value: task.progress,
            color: primary,
          ),
        ),
        _ => Icon(icon, size: 22, color: iconColor),
      },
      title: Text(
        task.song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppTheme.textPrimaryOf(context),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            '${task.song.artist} · $statusText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: faint, fontSize: 12),
          ),
          if (task.status == DownloadTaskStatus.running && task.total > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 3,
                backgroundColor: AppTheme.textPrimaryOf(context)
                    .withValues(alpha: 0.12),
                color: primary,
              ),
            ),
          ],
        ],
      ),
      trailing: switch (task.status) {
        DownloadTaskStatus.running => null,
        DownloadTaskStatus.failed => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              color: primary,
              tooltip: '重试',
              onPressed: () =>
                  ref.read(downloadQueueProvider.notifier).retry(task.id),
            ),
            _removeButton(context, ref),
          ],
        ),
        _ => _removeButton(context, ref),
      },
    );
  }

  Widget _removeButton(BuildContext context, WidgetRef ref) => IconButton(
    icon: const Icon(Icons.close, size: 20),
    color: AppTheme.textFaintOf(context),
    tooltip: '移除',
    onPressed: () => ref.read(downloadQueueProvider.notifier).remove(task.id),
  );
}
