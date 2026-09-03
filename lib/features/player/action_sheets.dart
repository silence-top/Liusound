import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download_service.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../auth/auth_controller.dart';
import '../home/artist_detail_screen.dart';
import '../home/detail_screen.dart';
import '../home/home_providers.dart';
import 'player_controller.dart';
import 'widgets/star_rating.dart';

// ---------- 歌曲操作弹窗 ----------

/// 歌曲操作弹窗（对标设计图「播放页面的更多的按钮」）：
/// 头部（封面 + 标题/歌手 + 五星评分 + 收藏）→ 操作网格 → 歌手/专辑/歌曲信息行。
void showSongActionSheet(BuildContext context, Song song) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(GlassTokens.radiusSheet)),
    ),
    builder: (_) => _SongActionSheet(song: song),
  );
}

class _SongActionSheet extends ConsumerStatefulWidget {
  const _SongActionSheet({required this.song});

  final Song song;

  @override
  ConsumerState<_SongActionSheet> createState() => _SongActionSheetState();
}

class _SongActionSheetState extends ConsumerState<_SongActionSheet> {
  late Song _song = widget.song;

  /// 展示目标：当前播放曲目实时跟随乐观更新，否则用本地副本
  Song get _view {
    final current = ref.watch(currentSongProvider);
    return current?.id == widget.song.id ? current! : _song;
  }

  void _syncLocal(Song song) {
    setState(() => _song = song);
    if (ref.read(currentSongProvider)?.id == song.id) {
      ref.read(currentSongProvider.notifier).state = song;
    }
  }

  Future<void> _rate(int rating) async {
    final before = _view;
    _syncLocal(before.copyWith(rating: rating));
    final ok =
        await ref.read(serverAdapterProvider)?.setRating(before.id, rating) ?? false;
    if (!ok && mounted) {
      _syncLocal(before);
      _toast('评分提交失败');
    }
  }

  Future<void> _toggleStar() async {
    final before = _view;
    _syncLocal(before.copyWith(starred: !before.starred));
    final ok = await ref
        .read(serverAdapterProvider)
        ?.setStar(before.id, !before.starred) ?? false;
    if (!ok && mounted) {
      _syncLocal(before);
      _toast('收藏操作失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = _view;
    final caps = ref.watch(serverAdapterProvider)?.capabilities;
    final canRate = caps?.ratings ?? false;
    final canDownload = caps?.download ?? true;
    return GlassSurface(
      radius: GlassTokens.radiusSheet,
      blur: GlassTokens.blurHeavy,
      tint: Colors.black.withValues(alpha: 0.35),
      gradientBorder: true,
      shadow: false,
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 10,
        left: 0,
        right: 0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部：封面 + 标题/歌手 + 收藏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 4),
            child: Row(
              children: [
                _Cover(song: song),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 14)),
                      const SizedBox(height: 4),
                      if (canRate)
                        StarRating(rating: song.rating, onRating: _rate),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    song.starred ? Icons.favorite : Icons.favorite_border,
                    color: song.starred
                        ? AppTheme.heartRed
                        : Colors.white70,
                  ),
                  onPressed: _toggleStar,
                ),
              ],
            ),
          ),
          // 操作网格（2 行 × 3 列）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.15,
              padding: EdgeInsets.zero,
              children: [
                _gridItem(Icons.low_priority, '下一首播放', () {
                  ref.read(playerActionsProvider).playNextInQueue([song]);
                  Navigator.of(context).pop();
                  _toast('已设为下一首播放');
                }),
                _gridItem(Icons.playlist_add, '添加到', () =>
                    _addToPlaylist(context, song)),
                if (canDownload)
                  _gridItem(Icons.download_outlined, '下载', () =>
                      _downloadSong(context, song)),
                _gridItem(Icons.delete_outline, '删除文件', () =>
                    _toast('请到 Navidrome 网页端管理文件')),
                _gridItem(Icons.timer_outlined, '定时停止', () =>
                    showSleepTimerPicker(context)),
                _gridItem(Icons.speed, '播放速度', () =>
                    showSpeedPicker(context)),
              ],
            ),
          ),
          const Divider(height: 1), // 颜色走 dividerTheme
          // 底部信息行：歌手 / 专辑 / 歌曲信息
          _infoRow('歌手', song.artist, () => _openArtist(context, song)),
          _infoRow('专辑', song.album, () => _openAlbum(context, song)),
          _infoRow(
              '歌曲信息',
              '${_fmtDuration(song.duration)}'
              '${song.size > 0 ? ' · ${_fmtSize(song.size)} MB' : ''}',
              () => _showSongInfo(context, song)),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _gridItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: AppTheme.accentSoft),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  void _openArtist(BuildContext context, Song song) {
    if (song.artistId.isEmpty) {
      _toast('缺少歌手信息');
      return;
    }
    Navigator.of(context).pop();
    Navigator.of(context).push(
      fadeRoute<void>(
        ArtistDetailScreen(
          artistId: song.artistId,
          artistName: song.artist,
        ),
      ),
    );
  }

  /// 离线下载：进度对话框 → 保存到应用文档目录 Music/ → 提示结果
  Future<void> _downloadSong(BuildContext context, Song song) async {
    final adapter = ref.read(serverAdapterProvider);
    if (adapter == null) {
      _toast('未登录，无法下载');
      return;
    }
    final progress = ValueNotifier<double?>(null); // null = 未知总量
    var dialogOpen = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (_, value, _) => AlertDialog(
          backgroundColor: AppTheme.queuePanel,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('正在下载「${song.title}」',
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white12,
                color: AppTheme.primary,
              ),
            ],
          ),
        ),
      ),
    ).then((_) => dialogOpen = false));
    try {
      final source = await adapter.resolveDownload(song);
      final path = await downloadSongFile(
        source: source,
        song: song,
        onProgress: (received, total) {
          if (total > 0) progress.value = received / total;
        },
      );
      progress.dispose();
      if (dialogOpen && context.mounted) Navigator.of(context).pop();
      _toast('已下载到：${Uri.file(path).pathSegments.last}');
    } on DioException {
      progress.dispose();
      if (dialogOpen && context.mounted) Navigator.of(context).pop();
      _toast('下载失败，请检查网络');
    } catch (_) {
      progress.dispose();
      if (dialogOpen && context.mounted) Navigator.of(context).pop();
      _toast('下载失败');
    }
  }

  void _openAlbum(BuildContext context, Song song) {
    if (song.albumId.isEmpty) {
      _toast('缺少专辑信息');
      return;
    }
    Navigator.of(context).pop();
    Navigator.of(context).push(
      fadeRoute<void>(
        AlbumDetailScreen(
          albumId: song.albumId,
          title: song.album,
          subtitle: song.artist,
        ),
      ),
    );
  }

  Future<void> _addToPlaylist(BuildContext context, Song song) async {
    Navigator.of(context).pop();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(GlassTokens.radiusSheet)),
      ),
      builder: (_) => _PlaylistPickerSheet(song: song),
    );
  }

  void _showSongInfo(BuildContext context, Song song) {
    final canRate =
        ref.read(serverAdapterProvider)?.capabilities.ratings ?? false;
    Navigator.of(context).pop();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.queuePanel,
        title: const Text('歌曲信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoLine('标题', song.title),
            _infoLine('歌手', song.artist),
            _infoLine('专辑', song.album),
            _infoLine('时长', _fmtDuration(song.duration)),
            if (song.size > 0) _infoLine('大小', '${_fmtSize(song.size)} MB'),
            if (song.size > 0 && song.duration > 0)
              _infoLine('码率',
                  '${((song.size * 8) / song.duration / 1000).round()} Kbps'),
            _infoLine('播放次数', '${song.playCount}'),
            _infoLine('收藏', song.starred ? '是' : '否'),
            if (canRate) _infoLine('评分', '${song.rating} / 5'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(label,
                  style: const TextStyle(color: Colors.white38, fontSize: 14)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ],
        ),
      );

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final adapter = ProviderScope.containerOf(context).read(serverAdapterProvider);
    if (song.albumId.isEmpty || adapter == null) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.music_note, color: Colors.white24, size: 26),
      );
    }
    final imageSource = adapter.coverImage(song.albumId, size: 104);
    if (imageSource == null) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.music_note, color: Colors.white24, size: 26),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: imageSource.url,
        httpHeaders: imageSource.headers.isNotEmpty ? imageSource.headers : null,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        memCacheWidth: 104,
        errorWidget: (_, _, _) => Container(
          width: 52,
          height: 52,
          color: AppTheme.surface,
          child: const Icon(Icons.music_note, color: Colors.white24, size: 26),
        ),
      ),
    );
  }
}

// ---------- 定时停止选择 ----------

/// 定时停止播放选择弹窗（歌曲操作弹窗 / 设置页共用）：
/// 选择后倒计时展示在设置页；到点自动暂停。
Future<void> showSleepTimerPicker(BuildContext context) {
  return glassBottomSheet<void>(
    context,
    const _SleepTimerContent(),
  );
}

class _SleepTimerContent extends ConsumerWidget {
  const _SleepTimerContent();

  static const _minutes = [15, 30, 45, 60, 90];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remain = ref.watch(sleepTimerProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('定时停止播放',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
        for (final m in _minutes)
          ListTile(
            title: Text('$m 分钟',
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            onTap: () {
              ref
                  .read(sleepTimerProvider.notifier)
                  .start(Duration(minutes: m));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('将在 $m 分钟后停止播放'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        if (remain != null)
          ListTile(
            title: Text(
                '取消定时（剩余 ${remain.inMinutes}:${(remain.inSeconds % 60).toString().padLeft(2, '0')}）',
                style: const TextStyle(color: AppTheme.heartRed, fontSize: 16)),
            onTap: () {
              ref.read(sleepTimerProvider.notifier).cancel();
              Navigator.of(context).pop();
            },
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}

// ---------- 播放速度选择 ----------

/// 播放速度选择弹窗（歌曲操作弹窗 / 设置页共用），选择后立即生效并持久化。
Future<void> showSpeedPicker(BuildContext context) {
  return glassBottomSheet<void>(
    context,
    const _SpeedContent(),
  );
}

class _SpeedContent extends ConsumerWidget {
  const _SpeedContent();

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackSpeedProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('播放速度',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
        for (final s in _speeds)
          ListTile(
            leading: s == speed
                ? const Icon(Icons.check, color: AppTheme.primary)
                : const SizedBox(width: 24),
            title: Text(
                s == 1.0 ? '1.0x（正常）' : '${s.toStringAsFixed(2)}x',
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            onTap: () {
              ref.read(playbackSpeedProvider.notifier).state = s;
              Navigator.of(context).pop();
            },
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}

// ---------- 添加到歌单 ----------

class _PlaylistPickerSheet extends ConsumerWidget {
  const _PlaylistPickerSheet({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return GlassSurface(
      radius: GlassTokens.radiusSheet,
      blur: GlassTokens.blurHeavy,
      tint: Colors.black.withValues(alpha: 0.35),
      gradientBorder: true,
      shadow: false,
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.55,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('添加到歌单',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: playlists.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('加载失败: $e',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 14)),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('还没有歌单',
                          style:
                              TextStyle(color: Colors.white38, fontSize: 14)),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.queue_music,
                          color: Colors.white54),
                      title: Text(list[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16)),
                      subtitle: Text('${list[i].songCount} 首歌曲',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                      onTap: () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await ref
                            .read(serverAdapterProvider)
                            ?.addToPlaylist(list[i].id, song.id) ?? false;
                        messenger.showSnackBar(
                          SnackBar(
                            content:
                                Text(ok ? '已添加到「${list[i].name}」' : '添加失败'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        navigator.pop();
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// ---------- 工具 ----------

String _fmtDuration(double seconds) {
  final d = Duration(seconds: seconds.round());
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _fmtSize(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);
