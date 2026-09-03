import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/motion.dart';
import '../../shared/widgets/glass.dart';
import '../auth/auth_controller.dart';
import '../player/action_sheets.dart';
import '../player/mini_player.dart';
import '../player/player_controller.dart';
import '../player/widgets/star_rating.dart';
import 'home_providers.dart';

// 配色统一收敛到 AppTheme（对齐设计图「歌单和专辑点击后进入的页面」与 1.x 样式表）

/// 数据态列表（过滤空态 + 歌曲行入场动画 + 到底标记），两个详情页共用。
List<Widget> _songSlivers(List<Song> songs) {
  if (songs.isEmpty) {
    return [SliverToBoxAdapter(child: noMatchBox())];
  }
  return [
    SliverList.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) =>
          FadeSlideIn(child: SongRow(song: songs[index], index: index, songs: songs)),
    ),
    const SliverToBoxAdapter(child: _EndMark()),
  ];
}

/// 专辑详情页（设计图「歌单和专辑点击后进入的页面」）：
/// 静态头部（封面 90 + 标题 + 年份/歌手 + 五星评分 setRating）
/// → 全部播放栏（随机播放 / 加入队列 / 顺序播放，全部功能可用）
/// → 过滤框 → 歌曲列表（绿序号 + flac 码率 + 行菜单）→ 到底啦。
class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({
    super.key,
    required this.albumId,
    required this.title,
    this.subtitle,
    this.rating = 0,
    this.coverAlbumId,
  });

  final String albumId;
  final String title;
  final String? subtitle; // 如 "2011 SARA"
  final int rating; // 专辑初始评分
  final String? coverAlbumId; // 默认用 albumId

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  late int _rating = widget.rating;
  String _search = '';

  Future<void> _rate(int rating) async {
    final before = _rating;
    setState(() => _rating = rating);
    final ok =
        await ref.read(serverAdapterProvider)?.setRating(widget.albumId, rating) ?? false;
    if (!ok && mounted) {
      setState(() => _rating = before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('评分提交失败'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final songsAsync = ref.watch(albumSongsProvider(widget.albumId));
    final all = songsAsync.value ?? const <Song>[];
    final songs = _filterSongs(all, _search);
    final canRate =
        ref.watch(serverAdapterProvider)?.capabilities.ratings ?? false;
    return Scaffold(
      backgroundColor: AppTheme.detailBg,
      bottomNavigationBar: const MiniPlayer(),
      body: CustomScrollView(
        slivers: [
          _appBar(),
          SliverToBoxAdapter(
            child: _Header(
              title: widget.title,
              subtitle: widget.subtitle,
              coverAlbumId: widget.coverAlbumId ?? widget.albumId,
              rating: canRate ? _rating : null,
              onRating: canRate ? _rate : null,
            ),
          ),
          SliverToBoxAdapter(
            child: _ListTop(
              count: songs.length,
              onPlayAll: () => _playAll(songs),
              onShuffle: () => _playShuffle(songs),
              onQueue: () => _enqueue(songs),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          ...sliverAsyncGuard<Song>(
            async: songsAsync,
            emptyText: '专辑暂无歌曲',
            onRetry: () => ref.invalidate(albumSongsProvider(widget.albumId)),
            onData: (_) => _songSlivers(songs),
          ),
        ],
      ),
    );
  }

  SliverAppBar _appBar() {
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 56,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.detailBg,
              AppTheme.detailBg.withValues(alpha: 0.85),
            ],
          ),
        ),
      ),
      leading: const BackButton(),
      title: Text(widget.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  void _playAll(List<Song> songs) {
    if (songs.isEmpty) return;
    final actions = ref.read(playerActionsProvider);
    actions.replaceQueue(songs);
    actions.play(songs.first);
  }

  void _playShuffle(List<Song> songs) {
    if (songs.isEmpty) return;
    final actions = ref.read(playerActionsProvider);
    actions.replaceQueue(songs);
    ref.read(playModeProvider.notifier).state = PlayMode.shuffle;
    actions.play(songs[DateTime.now().millisecond % songs.length]);
  }

  void _enqueue(List<Song> songs) {
    if (songs.isEmpty) return;
    ref.read(playerActionsProvider).addToQueue(songs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('已将 ${songs.length} 首歌曲加入队列'),
          duration: const Duration(seconds: 2)),
    );
  }
}

/// 歌单 / 每日推荐详情页：
/// - 每日推荐：直接传入 songs（首页「查看更多」）
/// - 我的歌单：传 playlistId 异步加载（/api/playlist/{id}/tracks）
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    this.title = '歌单',
    this.songs,
    this.playlistId,
    this.coverAlbumId,
    this.date,
    this.subtitle,
  })  : assert(songs != null || playlistId != null,
            '必须提供 songs 或 playlistId 之一');

  final String title;
  final List<Song>? songs; // 直接给定（每日推荐）
  final String? playlistId; // 异步加载（我的歌单）
  final String? coverAlbumId;
  final String? date;
  final String? subtitle;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final async = widget.playlistId == null
        ? null
        : ref.watch(playlistSongsProvider(widget.playlistId!));
    final all = widget.songs ?? async?.value ?? const <Song>[];
    final songs = _filterSongs(all, _search);
    final subtitle =
        widget.subtitle ?? (all.isEmpty ? '' : '共 ${all.length} 首歌曲');
    return Scaffold(
      backgroundColor: AppTheme.detailBg,
      bottomNavigationBar: const MiniPlayer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 56,
            backgroundColor: Colors.transparent,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.detailBg,
                    AppTheme.detailBg.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
            leading: const BackButton(),
            title: Text(widget.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          SliverToBoxAdapter(
            child: _Header(
              title: widget.title,
              subtitle: widget.date ?? subtitle,
              coverAlbumId: widget.coverAlbumId,
              rating: null, // 歌单无评分
              onRating: null,
            ),
          ),
          SliverToBoxAdapter(
            child: _ListTop(
              count: songs.length,
              onPlayAll: () => _playAll(songs),
              onShuffle: () => _playShuffle(songs),
              onQueue: () => _enqueue(songs),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          ...sliverAsyncGuard<Song>(
            async: async ?? AsyncValue.data(all),
            emptyText: '歌单暂无歌曲',
            onRetry: () =>
                ref.invalidate(playlistSongsProvider(widget.playlistId!)),
            onData: (_) => _songSlivers(songs),
          ),
        ],
      ),
    );
  }

  void _playAll(List<Song> songs) {
    if (songs.isEmpty) return;
    final actions = ref.read(playerActionsProvider);
    actions.replaceQueue(songs);
    actions.play(songs.first);
  }

  void _playShuffle(List<Song> songs) {
    if (songs.isEmpty) return;
    final actions = ref.read(playerActionsProvider);
    actions.replaceQueue(songs);
    ref.read(playModeProvider.notifier).state = PlayMode.shuffle;
    actions.play(songs[DateTime.now().millisecond % songs.length]);
  }

  void _enqueue(List<Song> songs) {
    if (songs.isEmpty) return;
    ref.read(playerActionsProvider).addToQueue(songs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('已将 ${songs.length} 首歌曲加入队列'),
          duration: const Duration(seconds: 2)),
    );
  }
}

// ---------- 共享组件 ----------

/// 静态头部：封面 90 + 标题/副标题 + 可选评分行（rating == null 隐藏）
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.coverAlbumId,
    required this.rating,
    required this.onRating,
  });

  final String title;
  final String? subtitle;
  final String? coverAlbumId;
  final int? rating;
  final ValueChanged<int>? onRating;

  @override
  Widget build(BuildContext context) {
    final adapter = ProviderScope.containerOf(context).read(serverAdapterProvider);
    final hasCover =
        coverAlbumId != null && coverAlbumId!.isNotEmpty && adapter != null;
    final imageSource = hasCover ? adapter.coverImage(coverAlbumId!, size: 180) : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          (hasCover && imageSource != null)
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: imageSource.url,
                    httpHeaders: imageSource.headers.isNotEmpty ? imageSource.headers : null,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    memCacheWidth: 180,
                    errorWidget: (_, _, _) => const _CoverPlaceholder(),
                  ),
                )
              : const _CoverPlaceholder(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Color(0xFFBBBBBB), fontSize: 13)),
                ],
                if (rating != null && onRating != null) ...[
                  const SizedBox(height: 8),
                  StarRating(rating: rating!, onRating: onRating!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFF1A2C3A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.album, color: Colors.white24, size: 36),
    );
  }
}

/// 列表顶部：全部播放栏（右三图标功能化）+ 过滤框，_bar 圆角容器
class _ListTop extends StatelessWidget {
  const _ListTop({
    required this.count,
    required this.onPlayAll,
    required this.onShuffle,
    required this.onQueue,
    required this.onChanged,
  });

  final int count;
  final VoidCallback onPlayAll;
  final VoidCallback onShuffle;
  final VoidCallback onQueue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(GlassTokens.radiusCard)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 0.5),
        ),
      ),
      child: Column(
        children: [
          _PlayAllBar(
            count: count,
            onPlayAll: onPlayAll,
            onShuffle: onShuffle,
            onQueue: onQueue,
          ),
          const Divider(height: 1, color: Color(0x0DFFFFFF)),
          _FilterBar(onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 站内过滤（标题/歌手/专辑包含匹配）
List<Song> _filterSongs(List<Song> songs, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return songs;
  return songs
      .where((s) =>
          s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q) ||
          s.album.toLowerCase().contains(q))
      .toList();
}

/// 站内过滤搜索框（过滤当前列表，非全局搜索）
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 18),
          const Icon(Icons.search, size: 20, color: Color(0xFF888888)),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: const InputDecoration(
                hintText: '搜索歌曲/专辑/歌手',
                hintStyle: TextStyle(color: Color(0xFFAAAAAA), fontSize: 15),
                border: InputBorder.none,
                filled: false,
                isDense: true,
              ),
            ),
          ),
          const Icon(Icons.filter_list, size: 22, color: Color(0xFF888888)),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}

/// 全部播放栏：▶ 全部播放（共N首）+ 随机播放 / 加入队列 / 顺序播放
class _PlayAllBar extends StatelessWidget {
  const _PlayAllBar({
    required this.count,
    required this.onPlayAll,
    required this.onShuffle,
    required this.onQueue,
  });

  final int count;
  final VoidCallback onPlayAll;
  final VoidCallback onShuffle;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 18),
          GestureDetector(
            onTap: onPlayAll,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0x2E78B4FF), // rgba(120,180,255,0.18)
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_circle_fill,
                  size: 28, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPlayAll,
            child: Row(
              children: [
                const Text('全部播放',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('（共$count首）',
                    style: const TextStyle(
                        color: Color(0xFFBBBBBB), fontSize: 13)),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.shuffle, size: 22, color: AppTheme.actionBlue),
            tooltip: '随机播放',
            onPressed: onShuffle,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon:
                const Icon(Icons.playlist_add, size: 22, color: AppTheme.actionBlue),
            tooltip: '加入队列',
            onPressed: onQueue,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.play_circle_outline,
                size: 22, color: AppTheme.actionBlue),
            tooltip: '顺序播放',
            onPressed: onPlayAll,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// 歌曲行：绿色序号 + 标题 + 码率标签 + 歌手 - 专辑 + 行菜单
/// 点击播放（整表替换队列），三点打开歌曲操作弹窗。
class SongRow extends ConsumerWidget {
  const SongRow({super.key,
    required this.song,
    required this.index,
    required this.songs,
  });

  final Song song;
  final int index;
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 码率（对齐 1.x：Math.round(size * 8 / duration / 1000)，flac 标签）
    final kbps = song.size > 0 && song.duration > 0
        ? ((song.size * 8) / song.duration / 1000).round()
        : 0;
    return InkWell(
      onTap: () {
        final actions = ref.read(playerActionsProvider);
        if (identical(songs, const [])) return;
        actions.replaceQueue(songs);
        actions.play(song);
      },
      onLongPress: () => showSongActionSheet(context, song),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.indexGreen,
                    fontSize: 17,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (kbps > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.formatBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.formatBorder),
                          ),
                          child: Text('flac ${kbps}K',
                              style: const TextStyle(
                                  color: AppTheme.formatText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          '${song.artist} - ${song.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFFB0BAC6), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_vert, size: 22, color: Colors.white),
              onPressed: () => showSongActionSheet(context, song),
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表底部「到底啦」标记
class _EndMark extends StatelessWidget {
  const _EndMark();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          '- 到底啦 -',
          style: TextStyle(color: Colors.white24, fontSize: 13),
        ),
      ),
    );
  }
}
