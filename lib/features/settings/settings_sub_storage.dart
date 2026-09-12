part of 'settings_screen.dart';

class _StorageSettingsPage extends ConsumerWidget {
  const _StorageSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheSettingsProvider);
    final cacheSize = ref.watch(audioCacheSizeProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppTheme.textPrimaryOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          4,
          12,
          48 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
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
        ],
      ),
    );
  }
}
