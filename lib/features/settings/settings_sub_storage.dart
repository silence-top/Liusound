part of 'settings_screen.dart';

class _StorageSettingsPage extends ConsumerWidget {
  const _StorageSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheSettingsProvider);
    final cacheSize = ref.watch(audioCacheSizeProvider);

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: const MiniPlayer(),
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 56,
              foregroundColor: AppTheme.textPrimaryOf(context),
              title: const Text('存储与缓存'),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                12,
                4,
                12,
                48 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _GroupCard(
                    title: '下载',
                    children: [
                      _SwitchTile(
                        icon: Icons.save_alt,
                        title: '边听边存',
                        subtitle: '播放时缓存音频，断网可续播已缓存段落',
                        value: cache.cacheWhileListen,
                        onChanged: (v) => ref
                            .read(cacheSettingsProvider.notifier)
                            .set(cache.copyWith(cacheWhileListen: v)),
                      ),
                      _divider,
                      _SwitchTile(
                        icon: Icons.cloud_download_outlined,
                        title: '自动下载',
                        subtitle: '后台离线「我喜欢」的歌曲（最多 50 首）',
                        value: cache.autoDownload,
                        onChanged: (v) {
                          ref
                              .read(cacheSettingsProvider.notifier)
                              .set(cache.copyWith(autoDownload: v));
                          if (v) unawaited(AutoDownload.run(ref.read));
                        },
                      ),
                      _divider,
                      _ActionTile(
                        icon: Icons.storage,
                        title: '缓存限额',
                        subtitle: cache.limit.label,
                        onTap: () => _showCacheLimitPicker(context, ref),
                      ),
                      _divider,
                      const _DownloadQueueTile(),
                    ],
                  ),
                  _GroupCard(
                    title: '清理',
                    children: [
                      _ActionTile(
                        icon: Icons.cleaning_services,
                        title: '清理播放缓存',
                        subtitle: cacheSize.when(
                          data: (bytes) => '当前占用 ${_fmtBytes(bytes)}',
                          loading: () => '统计中…',
                          error: (_, _) => '统计失败',
                        ),
                        onTap: () => _clearAudioCache(context, ref),
                      ),
                      _divider,
                      _ActionTile(
                        icon: Icons.image_outlined,
                        title: '清除图片缓存',
                        subtitle: '清理磁盘上的封面图片缓存',
                        onTap: () => _clearImageCache(context),
                      ),
                      _divider,
                      _ActionTile(
                        icon: Icons.format_line_spacing,
                        title: '清理歌词偏移缓存',
                        subtitle: '删除所有歌曲保存的歌词时间偏移',
                        onTap: () => _clearLyricOffsets(context),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 下载列表入口：展示后台下载队列的进行中任务数，点击打开下载列表弹层
class _DownloadQueueTile extends ConsumerWidget {
  const _DownloadQueueTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadQueueProvider);
    final active = tasks
        .where(
          (t) =>
              t.status == DownloadTaskStatus.waiting ||
              t.status == DownloadTaskStatus.running,
        )
        .length;
    final subtitle = switch (active) {
      0 => '无进行中任务',
      1 => '1 个任务进行中',
      _ => '$active 个任务进行中',
    };
    return _ActionTile(
      icon: Icons.download_outlined,
      title: '下载列表',
      subtitle: subtitle,
      onTap: () => showDownloadQueueSheet(context),
    );
  }
}
