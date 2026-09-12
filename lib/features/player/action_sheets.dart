import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/download/download_service.dart';
import '../../core/download/auto_download.dart';
import '../../core/local/local_library.dart' show downloadIndexVersionProvider;
import '../../core/models/models.dart';
import '../../core/settings/streaming_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../../shared/widgets/toast.dart';
import '../auth/auth_controller.dart';
import '../home/detail_screen.dart';
import '../home/home_providers.dart';
import '../home/song_info_screen.dart';
import 'album_tint.dart';
import 'player_controller.dart';
import 'widgets/star_rating.dart';

// ---------- 歌曲操作弹窗 ----------

/// 歌曲操作弹窗（对标设计图「播放页面的更多的按钮」）：
/// 头部（封面 + 标题/歌手 + 五星评分 + 收藏）→ 操作网格 → 歌手/专辑/歌曲信息行。
void showSongActionSheet(BuildContext context, Song song, {String? playlistId}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black38,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(GlassTokens.radiusSheet),
      ),
    ),
    builder: (_) => _SongActionSheet(song: song, playlistId: playlistId),
  );
}

class _SongActionSheet extends ConsumerStatefulWidget {
  const _SongActionSheet({required this.song, this.playlistId});

  final Song song;
  final String? playlistId;

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
        await ref.read(serverAdapterProvider)?.setRating(before.id, rating) ??
        false;
    if (!ok && mounted) {
      _syncLocal(before);
      _toast('评分提交失败');
    }
  }

  Future<void> _toggleStar() async {
    final before = _view;
    _syncLocal(before.copyWith(starred: !before.starred));
    final ok =
        await ref
            .read(serverAdapterProvider)
            ?.setStar(before.id, !before.starred) ??
        false;
    if (!ok && mounted) {
      _syncLocal(before);
      _toast('收藏操作失败');
      return;
    }
    // 收藏变化补跑自动下载（开关关闭时内部直接跳过）
    maybeAutoDownload(ref.read);
  }

  @override
  Widget build(BuildContext context) {
    final song = _view;
    final caps = ref.watch(serverAdapterProvider)?.capabilities;
    final canRate = caps?.ratings ?? false;
    final canDownload = caps?.download ?? true;
    // 弹层底色随封面主色（内容驱动取色）：毛玻璃但底色近实色（不要透明）；
    // 内部二级弹层（定时/速度）透传同一主色，色系连贯
    final dominant = ref
        .watch(albumDominantColorProvider(song.albumId))
        .valueOrNull;
    return AlbumFrostedPanel(
      dominant: dominant,
      opaque: true,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(GlassTokens.radiusSheet),
      ),
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
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (canRate)
                        StarRating(rating: song.rating, onRating: _rate),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    song.starred ? Icons.favorite : Icons.favorite_border,
                    color: song.starred ? AppTheme.heartRed : Colors.white70,
                  ),
                  onPressed: _toggleStar,
                ),
              ],
            ),
          ),
          // 操作卡片一：下一首播放/已播放/添加到/下载/删除文件 + 定时停止/播放速度
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                // 白 0.07 叠在实色底上的浮起卡片层，不随主题变脸
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppRadius.l),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: AppSpacing.m,
              ),
              child: GridView.count(
                crossAxisCount: 5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.72,
                mainAxisSpacing: 10,
                padding: EdgeInsets.zero,
                children: [
                  _circleItem(Icons.low_priority, '下一首播放', () {
                    ref.read(playerActionsProvider).playNextInQueue([song]);
                    Navigator.of(context).pop();
                    _toast('已设为下一首播放');
                  }),
                  if (caps?.scrobbling ?? false)
                    _circleItem(Icons.task_alt, '已播放', () async {
                      // pop 后 sheet 的 context 失效，先抓 navigator 再发请求
                      final navigator = Navigator.of(context);
                      final ok =
                          await ref
                              .read(serverAdapterProvider)
                              ?.scrobble(song.id) ??
                          false;
                      navigator.pop();
                      showToast(ok ? '已标记为已播放' : '标记失败', error: !ok);
                    }),
                  _circleItem(Icons.playlist_add, '添加到', () {
                    Navigator.of(context).pop();
                    showAddToPlaylistSheet(context, [song]);
                  }),
                  if (canDownload)
                    _circleItem(
                      Icons.download_outlined,
                      '下载',
                      () => downloadSongs(context, ref, [song]),
                    ),
                  _circleItem(
                    Icons.delete_outline,
                    '删除文件',
                    () => _toast('请到音乐服务器后台管理文件'),
                  ),
                  _circleItem(
                    Icons.alarm,
                    '定时停止',
                    () => showSleepTimerPicker(
                      context,
                      tint: albumFrostedTint(dominant),
                    ),
                  ),
                  _circleItem(
                    Icons.speed,
                    '播放速度',
                    () => showSpeedPicker(
                      context,
                      tint: albumFrostedTint(dominant),
                    ),
                  ),
                  _circleItem(Icons.share, '分享', () {
                    Navigator.of(context).pop();
                    SharePlus.instance.share(
                      ShareParams(
                        text: '♪ ${song.title} — ${song.artist}\n'
                            '专辑：${song.album}\n'
                            '— 来自流声音乐',
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          // 操作卡片二：歌手 / 专辑 / 歌曲信息（歌曲信息进完整详情页）
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                // 白 0.07 叠在实色底上的浮起卡片层，不随主题变脸
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppRadius.l),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: AppSpacing.m,
              ),
              child: GridView.count(
                crossAxisCount: 5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.72,
                padding: EdgeInsets.zero,
                children: [
                  _circleItem(
                    Icons.person,
                    '歌手',
                    () => _openArtist(context, song),
                  ),
                  _circleItem(
                    Icons.album,
                    '专辑',
                    () => _openAlbum(context, song),
                  ),
                  _circleItem(Icons.info_outline, '歌曲信息', () {
                    Navigator.of(context).pop();
                    Navigator.of(context)
                        .push(fadeRoute<void>(SongInfoScreen(song: song)));
                  }),
                  if (widget.playlistId != null)
                    _circleItem(Icons.playlist_remove, '从歌单移除', () async {
                      final navigator = Navigator.of(context);
                      final ok = await ref
                              .read(serverAdapterProvider)
                              ?.removeFromPlaylist(
                                widget.playlistId!,
                                song.id,
                              ) ??
                          false;
                      navigator.pop();
                      if (ok) {
                        ref.invalidate(
                          playlistSongsProvider(widget.playlistId!),
                        );
                        showToast('已从歌单移除');
                      } else {
                        showToast('移除失败', error: true);
                      }
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  /// 圆形操作按钮（对标设计图：圆形底 + 图标 + 下方小字标签）
  Widget _circleItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.s),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              // 中性半透明白：叠在封面取色卡片上的浮起层，不随主题变脸
              color: Colors.white.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: AppTheme.accentSoft),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ],
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
        SongListScreen(
          title: song.artist,
          pagedSongsProvider: artistSongsProvider(song.artistId),
          coverAlbumId: song.artistId,
        ),
      ),
    );
  }

  void _openAlbum(BuildContext context, Song song) {
    if (song.albumId.isEmpty) {
      _toast('缺少专辑信息');
      return;
    }
    Navigator.of(context).pop();
    Navigator.of(context).push(
      fadeRoute<void>(
        SongListScreen(
          rateTargetId: song.albumId,
          songsProvider: albumSongsProvider(song.albumId),
          title: song.album,
          subtitle: song.artist,
        ),
      ),
    );
  }

  void _toast(String message) {
    showToast(message);
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final adapter = ProviderScope.containerOf(context)
        .read(serverAdapterProvider);
    if (song.albumId.isEmpty || adapter == null) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
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
          color: AppTheme.surfaceOf(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.music_note, color: Colors.white24, size: 26),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: imageSource.url,
        httpHeaders: imageSource.headers.isNotEmpty
            ? imageSource.headers
            : null,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        memCacheWidth: 104,
        errorWidget: (_, _, _) => Container(
          width: 52,
          height: 52,
          color: AppTheme.surfaceOf(context),
          child: const Icon(Icons.music_note, color: Colors.white24, size: 26),
        ),
      ),
    );
  }
}

// ---------- 定时停止选择 ----------

/// 定时停止播放选择弹窗（歌曲操作弹窗 / 设置页共用）：
/// 选择后倒计时展示在设置页；到点自动暂停。
/// 从歌曲操作弹窗进入时传封面取色 tint，与弹窗连成同一色系；设置页不传走主题玻璃
Future<void> showSleepTimerPicker(BuildContext context, {Color? tint}) {
  return glassBottomSheet<void>(
    context,
    const _SleepTimerContent(),
    tint: tint,
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
          child: Text(
            '定时停止播放',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final m in _minutes)
          ListTile(
            title: Text(
              '$m 分钟',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            onTap: () {
              ref.read(sleepTimerProvider.notifier).start(Duration(minutes: m));
              Navigator.of(context).pop();
              showToast('将在 $m 分钟后停止播放');
            },
          ),
        if (remain != null)
          ListTile(
            title: Text(
              '取消定时（剩余 ${remain.inMinutes}:${(remain.inSeconds % 60).toString().padLeft(2, '0')}）',
              style: const TextStyle(color: AppTheme.heartRed, fontSize: 16),
            ),
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
/// tint 语义同 [showSleepTimerPicker]。
Future<void> showSpeedPicker(BuildContext context, {Color? tint}) {
  return glassBottomSheet<void>(context, const _SpeedContent(), tint: tint);
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
          child: Text(
            '播放速度',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final s in _speeds)
          ListTile(
            leading: s == speed
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const SizedBox(width: 24),
            title: Text(
              s == 1.0 ? '1.0x（正常）' : '${s.toStringAsFixed(2)}x',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
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

// ---------- 交叉淡入淡出 ----------

/// 交叉淡化时长选择弹窗（设置页），0 表示关闭，选择后立即生效并持久化。
Future<void> showCrossfadePicker(BuildContext context) {
  return glassBottomSheet<void>(context, const _CrossfadeContent());
}

class _CrossfadeContent extends ConsumerWidget {
  const _CrossfadeContent();

  static const _options = [0, 1, 2, 3, 5, 8, 10];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(crossfadeSecondsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '交叉淡入淡出',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final s in _options)
          ListTile(
            leading: s == current
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const SizedBox(width: 24),
            title: Text(
              s == 0 ? '关闭' : '$s 秒',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            onTap: () {
              ref.read(crossfadeSecondsProvider.notifier).set(s);
              Navigator.of(context).pop();
            },
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}

// ---------- 离线下载（§3.2 支持批量） ----------

/// 把一批歌曲下载到应用文档目录 Music/：全程一个进度对话框，结束后汇总提示。
/// 单曲入口传 `[song]`，文案与批量前的单曲下载完全一致。
/// 单曲失败不该中断整批，所以逐条计数、跑完再报结果。
Future<void> downloadSongs(
  BuildContext context,
  WidgetRef ref,
  List<Song> songs,
) async {
  if (songs.isEmpty) return;
  final adapter = ref.read(serverAdapterProvider);
  if (adapter == null) {
    showToast('未登录，无法下载', error: true);
    return;
  }

  // 蜂窝禁传门禁：与播放、自动下载共用同一开关，避免设置项形同虚设
  final quality = await resolveCurrentQuality(
    ref.read(streamingSettingsProvider),
  );
  if (quality == null) {
    showToast('当前为移动网络，「移动网络传输」已关闭，无法下载', error: true);
    return;
  }
  if (!context.mounted) return;

  final total = songs.length;
  // (歌名, 批量进度段, 整体进度)：ValueNotifier 按结构相等判定，任一变化都会重建
  final state = ValueNotifier<(String, String, double?)>((
    songs.first.title,
    '',
    null,
  ));
  var dialogOpen = true;
  unawaited(
    glassDialog<void>(
      context,
      barrierDismissible: false,
      title: '正在下载',
      content: ValueListenableBuilder<(String, String, double?)>(
        valueListenable: state,
        builder: (dialogCtx, v, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              v.$1,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(dialogCtx),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (v.$2.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                v.$2,
                style: TextStyle(
                  color: AppTheme.textFaintOf(dialogCtx),
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: v.$3,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
              backgroundColor: AppTheme.textPrimaryOf(dialogCtx)
                  .withValues(alpha: 0.12),
              color: Theme.of(dialogCtx).colorScheme.primary,
            ),
            if (v.$3 != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${((v.$3! * 100).round()).clamp(0, 100)}%',
                  style: TextStyle(
                    color: AppTheme.textFaintOf(dialogCtx),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ).then((_) => dialogOpen = false),
  );

  var done = 0;
  var failed = 0;
  var networkFail = false;
  var lastName = '';
  for (var i = 0; i < total; i++) {
    final song = songs[i];
    state.value = (
      song.title,
      total == 1 ? '' : '${i + 1}/$total',
      total == 1 ? null : i / total,
    );
    try {
      final source = await adapter.resolveDownload(song);
      final path = await downloadSongFile(
        source: source,
        song: song,
        networkSettings: ref.read(networkSettingsProvider),
        onProgress: (received, size) {
          if (size <= 0) return;
          state.value = (
            state.value.$1,
            state.value.$2,
            total == 1 ? received / size : (i + received / size) / total,
          );
        },
      );
      done++;
      // 下载完成即时刷新「本地音乐」合并展示（downloadIndexVersionProvider）
      ref.read(downloadIndexVersionProvider.notifier).state++;
      lastName = Uri.file(path).pathSegments.last;
    } on DioException {
      failed++;
      networkFail = true;
    } catch (_) {
      failed++;
    }
  }
  state.dispose();
  if (dialogOpen && context.mounted) Navigator.of(context).pop();

  final message = failed == 0
      ? (total == 1 ? '已下载到：$lastName' : '已下载 $done 首歌曲')
      : (done == 0
            ? (networkFail ? '下载失败，请检查网络' : '下载失败')
            : '已下载 $done 首，$failed 首失败');
  showToast(message, error: failed > 0);
}

// ---------- 添加到歌单 ----------

/// 添加到歌单弹层（§3.2 支持批量）：选一个歌单，把 [songs] 全部加进去。
/// 单曲入口传 `[song]` 即可，两条路径共用同一份结果提示。
Future<void> showAddToPlaylistSheet(BuildContext context, List<Song> songs) {
  if (songs.isEmpty) return Future.value();
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
    builder: (_) => _PlaylistPickerSheet(songs: songs),
  );
}

class _PlaylistPickerSheet extends ConsumerWidget {
  const _PlaylistPickerSheet({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    // 弹层底色随封面主色（内容驱动取色）：批量时取第一首的专辑；完全实色不透明
    return AlbumFrostedPanel(
      dominant: songs.isEmpty
          ? null
          : ref
                .watch(albumDominantColorProvider(songs.first.albumId))
                .valueOrNull,
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
          maxHeight: MediaQuery.of(context).size.height * 0.55,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                songs.length == 1 ? '添加到歌单' : '添加 ${songs.length} 首到歌单',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: playlists.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '加载失败: $e',
                    style: const TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        '还没有歌单',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(
                        Icons.queue_music,
                        color: Colors.white54,
                      ),
                      title: Text(
                        list[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        '${list[i].songCount} 首歌曲',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () async {
                        final navigator = Navigator.of(context);
                        final adapter = ref.read(serverAdapterProvider);
                        final playlist = list[i];
                        var added = 0;
                        for (final s in songs) {
                          final ok =
                              await adapter?.addToPlaylist(playlist.id, s.id) ??
                              false;
                          if (ok) added++;
                        }
                        showToast(
                          songs.length == 1
                              ? (added == 1 ? '已添加到「${playlist.name}」' : '添加失败')
                              : '已添加 $added/${songs.length} 首到'
                                    '「${playlist.name}」',
                          error: songs.length == 1 && added == 0,
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
