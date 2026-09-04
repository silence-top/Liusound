import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/settings_prefs.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/motion.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/quality_badge.dart';
import '../auth/auth_controller.dart';
import '../player/action_sheets.dart';
import '../player/full_screen_player.dart';
import '../player/mini_player.dart';
import '../player/player_controller.dart';
import '../player/widgets/star_rating.dart';
import 'home_providers.dart';

// 配色统一收敛到 AppTheme（对齐设计图「歌单和专辑点击后进入的页面」与 1.x 样式表）

/// 数据态列表（过滤空态 + 歌曲行入场动画 + 到底标记），两个详情页共用。
/// [selectMode] 为真时行首序号换成勾选框、点击变成勾选（§3.2 批量选择）。
List<Widget> _songSlivers(
  List<Song> songs, {
  bool selectMode = false,
  Set<String> selected = const {},
  ValueChanged<Song>? onToggle,
}) {
  if (songs.isEmpty) {
    return [SliverToBoxAdapter(child: noMatchBox())];
  }
  return [
    SliverList.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return FadeSlideIn(
          child: SongRow(
            song: song,
            index: index,
            songs: songs,
            selected: selectMode ? selected.contains(song.id) : null,
            onToggleSelect: selectMode && onToggle != null
                ? () => onToggle(song)
                : null,
          ),
        );
      },
    ),
    const SliverToBoxAdapter(child: _EndMark()),
  ];
}

/// 详情页批量选择态（§3.2）：专辑页与歌单页共用，
/// 免得两边各写一遍勾选集合与三个批处理动作。
mixin _BatchSelect<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool _selectMode = false;
  final Set<String> _selected = {};

  bool get selectMode => _selectMode;
  Set<String> get selectedIds => _selected;

  /// 勾选集合与当前可见列表取交集：筛选隐藏掉的行不参与批量动作，
  /// 保证 AppBar 上的「已选 N 首」和实际处理的歌曲数永远一致
  List<Song> selectionOf(List<Song> songs) =>
      songs.where((s) => _selected.contains(s.id)).toList();

  void toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selected.clear();
    });
  }

  void toggleSelected(Song song) {
    setState(() {
      if (!_selected.remove(song.id)) _selected.add(song.id);
    });
  }

  /// 全选 / 再点一次取消全选（只作用于当前筛选结果）
  void toggleSelectAll(List<Song> songs) {
    setState(() {
      if (_selected.length == songs.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(songs.map((s) => s.id));
      }
    });
  }

  void _exitSelect() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  /// 批量插入下一首播放
  void batchPlayNext(List<Song> songs) {
    final picked = selectionOf(songs);
    if (picked.isEmpty) return;
    ref.read(playerActionsProvider).playNextInQueue(picked);
    _exitSelect();
    _toast('已将 ${picked.length} 首设为下一首播放');
  }

  /// 批量下载（进度与结果提示由 downloadSongs 统一负责）
  Future<void> batchDownload(List<Song> songs) async {
    final picked = selectionOf(songs);
    if (picked.isEmpty) return;
    await downloadSongs(context, ref, picked);
    if (mounted) _exitSelect();
  }

  /// 批量添加到歌单：先退出选择态，免得弹层压在底部操作栏上
  Future<void> batchAddToPlaylist(List<Song> songs) async {
    final picked = selectionOf(songs);
    if (picked.isEmpty) return;
    _exitSelect();
    await showAddToPlaylistSheet(context, picked);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
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

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen>
    with _BatchSelect<AlbumDetailScreen> {
  late int _rating = widget.rating;
  String _search = '';
  bool _filterExpanded = false;
  final TextEditingController _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  /// 收起时一并清空关键词，避免「看不见但仍在过滤」
  void _toggleFilter() {
    setState(() {
      _filterExpanded = !_filterExpanded;
      if (!_filterExpanded) {
        _filterController.clear();
        _search = '';
      }
    });
  }

  Future<void> _rate(int rating) async {
    final before = _rating;
    setState(() => _rating = rating);
    final ok =
        await ref
            .read(serverAdapterProvider)
            ?.setRating(widget.albumId, rating) ??
        false;
    if (!ok && mounted) {
      setState(() => _rating = before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评分提交失败'), duration: Duration(seconds: 2)),
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
    final canDownload =
        ref.watch(serverAdapterProvider)?.capabilities.download ?? true;
    final selectedCount = selectionOf(songs).length;
    return Scaffold(
      backgroundColor: AppTheme.detailBgOf(context),
      bottomNavigationBar: selectMode
          ? _BatchBar(
              count: selectedCount,
              canDownload: canDownload,
              onPlayNext: () => batchPlayNext(songs),
              onAddToPlaylist: () => batchAddToPlaylist(songs),
              onDownload: () => batchDownload(songs),
            )
          : const MiniPlayer(),
      body: CustomScrollView(
        slivers: [
          _detailAppBar(
            context: context,
            title: widget.title,
            selectMode: selectMode,
            selectedCount: selectedCount,
            totalCount: songs.length,
            onToggleSelectMode: toggleSelectMode,
            onSelectAll: () => toggleSelectAll(songs),
            filterExpanded: _filterExpanded,
            onToggleFilter: _toggleFilter,
            primaryColor: Theme.of(context).colorScheme.primary,
          ),
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
              controller: _filterController,
              expanded: _filterExpanded,
            ),
          ),
          ...sliverAsyncGuard<Song>(
            async: songsAsync,
            emptyText: '专辑暂无歌曲',
            onRetry: () => ref.invalidate(albumSongsProvider(widget.albumId)),
            onData: (_) => _songSlivers(
              songs,
              selectMode: selectMode,
              selected: selectedIds,
              onToggle: toggleSelected,
            ),
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
        duration: const Duration(seconds: 2),
      ),
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
  }) : assert(
         songs != null || playlistId != null,
         '必须提供 songs 或 playlistId 之一',
       );

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

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen>
    with _BatchSelect<PlaylistDetailScreen> {
  String _search = '';
  bool _filterExpanded = false;
  final TextEditingController _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  /// 收起时一并清空关键词，避免「看不见但仍在过滤」
  void _toggleFilter() {
    setState(() {
      _filterExpanded = !_filterExpanded;
      if (!_filterExpanded) {
        _filterController.clear();
        _search = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = widget.playlistId == null
        ? null
        : ref.watch(playlistSongsProvider(widget.playlistId!));
    final all = widget.songs ?? async?.value ?? const <Song>[];
    final songs = _filterSongs(all, _search);
    final subtitle =
        widget.subtitle ?? (all.isEmpty ? '' : '共 ${all.length} 首歌曲');
    final canDownload =
        ref.watch(serverAdapterProvider)?.capabilities.download ?? true;
    final selectedCount = selectionOf(songs).length;
    return Scaffold(
      backgroundColor: AppTheme.detailBgOf(context),
      bottomNavigationBar: selectMode
          ? _BatchBar(
              count: selectedCount,
              canDownload: canDownload,
              onPlayNext: () => batchPlayNext(songs),
              onAddToPlaylist: () => batchAddToPlaylist(songs),
              onDownload: () => batchDownload(songs),
            )
          : const MiniPlayer(),
      body: CustomScrollView(
        slivers: [
          _detailAppBar(
            context: context,
            title: widget.title,
            selectMode: selectMode,
            selectedCount: selectedCount,
            totalCount: songs.length,
            onToggleSelectMode: toggleSelectMode,
            onSelectAll: () => toggleSelectAll(songs),
            filterExpanded: _filterExpanded,
            onToggleFilter: _toggleFilter,
            primaryColor: Theme.of(context).colorScheme.primary,
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
              controller: _filterController,
              expanded: _filterExpanded,
            ),
          ),
          ...sliverAsyncGuard<Song>(
            async: async ?? AsyncValue.data(all),
            emptyText: '歌单暂无歌曲',
            onRetry: () =>
                ref.invalidate(playlistSongsProvider(widget.playlistId!)),
            onData: (_) => _songSlivers(
              songs,
              selectMode: selectMode,
              selected: selectedIds,
              onToggle: toggleSelected,
            ),
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
        duration: const Duration(seconds: 2),
      ),
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
    final adapter = ProviderScope.containerOf(context)
        .read(serverAdapterProvider);
    final hasCover =
        coverAlbumId != null && coverAlbumId!.isNotEmpty && adapter != null;
    final imageSource = hasCover
        ? adapter.coverImage(coverAlbumId!, size: 180)
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          (hasCover && imageSource != null)
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: imageSource.url,
                    httpHeaders: imageSource.headers.isNotEmpty
                        ? imageSource.headers
                        : null,
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
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFBBBBBB),
                      fontSize: 14,
                    ),
                  ),
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

/// 列表顶部：全部播放栏（右三图标功能化）+ 可收纳过滤框，_bar 圆角容器
class _ListTop extends StatelessWidget {
  const _ListTop({
    required this.count,
    required this.onPlayAll,
    required this.onShuffle,
    required this.onQueue,
    required this.onChanged,
    required this.controller,
    required this.expanded,
  });

  final int count;
  final VoidCallback onPlayAll;
  final VoidCallback onShuffle;
  final VoidCallback onQueue;
  final ValueChanged<String> onChanged;
  final TextEditingController controller;
  final bool expanded;

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
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(GlassTokens.radiusCard),
        ),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 0.5,
          ),
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
          // 收起时高度归零，把 44dp 纵向空间还给歌曲列表
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    children: [
                      const Divider(height: 1, color: Color(0x0DFFFFFF)),
                      _FilterBar(controller: controller, onChanged: onChanged),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
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
      .where(
        (s) =>
            s.title.toLowerCase().contains(q) ||
            s.artist.toLowerCase().contains(q) ||
            s.album.toLowerCase().contains(q),
      )
      .toList();
}

/// AppBar 过滤入口：点击展开/收起列表内过滤框，展开态染主色
/// （专辑详情页与歌单详情页共用）
Widget _filterAction({
  required bool expanded,
  required VoidCallback onPressed,
  required Color primaryColor,
}) {
  return IconButton(
    onPressed: onPressed,
    tooltip: expanded ? '收起筛选' : '筛选歌曲',
    icon: Icon(Icons.search, color: expanded ? primaryColor : Colors.white70),
  );
}

/// 详情页顶栏（专辑页与歌单页共用）：
/// 常态「标题 + 批量选择 + 筛选」，选择态换成「已选 N 首 + 全选 + 退出」
SliverAppBar _detailAppBar({
  required BuildContext context,
  required String title,
  required bool selectMode,
  required int selectedCount,
  required int totalCount,
  required VoidCallback onToggleSelectMode,
  required VoidCallback onSelectAll,
  required bool filterExpanded,
  required VoidCallback onToggleFilter,
  required Color primaryColor,
}) {
  // 空列表没得选，入口直接禁用并置灰，省得点进去是一个空的选择态
  final canSelect = totalCount > 0;
  final allSelected = canSelect && selectedCount == totalCount;
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
            AppTheme.detailBgOf(context),
            AppTheme.detailBgOf(context).withValues(alpha: 0.85),
          ],
        ),
      ),
    ),
    leading: const BackButton(),
    title: Text(
      selectMode ? '已选 $selectedCount 首' : title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    actions: selectMode
        ? [
            IconButton(
              onPressed: canSelect ? onSelectAll : null,
              tooltip: allSelected ? '取消全选' : '全选',
              icon: Icon(
                allSelected ? Icons.deselect : Icons.select_all,
                color: Colors.white70,
              ),
            ),
            IconButton(
              onPressed: onToggleSelectMode,
              tooltip: '退出批量选择',
              icon: const Icon(Icons.close, color: Colors.white70),
            ),
          ]
        : [
            IconButton(
              onPressed: canSelect ? onToggleSelectMode : null,
              tooltip: '批量选择',
              icon: Icon(
                Icons.checklist,
                color: canSelect ? Colors.white70 : Colors.white24,
              ),
            ),
            _filterAction(
              expanded: filterExpanded,
              onPressed: onToggleFilter,
              primaryColor: primaryColor,
            ),
          ],
  );
}

/// 批量操作栏（§3.2）：选择态顶掉 MiniPlayer。
/// 未勾选任何歌曲时整排置灰不可点，下载在后端不支持取文件时直接不出现。
class _BatchBar extends StatelessWidget {
  const _BatchBar({
    required this.count,
    required this.canDownload,
    required this.onPlayNext,
    required this.onAddToPlaylist,
    required this.onDownload,
  });

  final int count;
  final bool canDownload;
  final VoidCallback onPlayNext;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 0,
      blur: GlassTokens.blurMedium,
      tint: Colors.black.withValues(alpha: 0.45),
      gradientBorder: false,
      shadow: false,
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: [
          _action(Icons.low_priority, '下一首播放', onPlayNext),
          _action(Icons.playlist_add, '添加到歌单', onAddToPlaylist),
          if (canDownload) _action(Icons.download_outlined, '下载', onDownload),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    final enabled = count > 0;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: enabled ? AppTheme.actionBlue : Colors.white24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white24,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 站内过滤搜索框（过滤当前列表，非全局搜索）
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.onChanged, required this.controller});

  final ValueChanged<String> onChanged;
  final TextEditingController controller;

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
              controller: controller,
              onChanged: onChanged,
              // 由 AppBar 搜索图标展开时立即获得焦点，省去二次点击
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: const InputDecoration(
                hintText: '搜索歌曲/专辑/歌手',
                hintStyle: TextStyle(color: Color(0xFFAAAAAA), fontSize: 16),
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
              child: const Icon(
                Icons.play_circle_fill,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPlayAll,
            child: Row(
              children: [
                const Text(
                  '全部播放',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '（共$count首）',
                  style: const TextStyle(
                    color: Color(0xFFBBBBBB),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.shuffle,
              size: 22,
              color: AppTheme.actionBlue,
            ),
            tooltip: '随机播放',
            onPressed: onShuffle,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.playlist_add,
              size: 22,
              color: AppTheme.actionBlue,
            ),
            tooltip: '加入队列',
            onPressed: onQueue,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.play_circle_outline,
              size: 22,
              color: AppTheme.actionBlue,
            ),
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
/// 批量选择态（§3.2）下序号换成勾选框、点击变成勾选、行菜单隐藏。
class SongRow extends ConsumerWidget {
  const SongRow({
    super.key,
    required this.song,
    required this.index,
    required this.songs,
    this.selected,
    this.onToggleSelect,
  });

  final Song song;
  final int index;
  final List<Song> songs;

  /// 非 null 即处于批量选择态，值为该行是否已勾选
  final bool? selected;
  final VoidCallback? onToggleSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selecting = onToggleSelect != null;
    final checked = selected ?? false;
    return InkWell(
      onTap: selecting
          ? onToggleSelect
          : () {
              final actions = ref.read(playerActionsProvider);
              if (identical(songs, const [])) return;
              actions.replaceQueue(songs);
              actions.play(song);
              if (ref.read(autoOpenPlayerProvider)) {
                openFullScreenPlayer(context);
              }
            },
      onLongPress: selecting ? null : () => showSongActionSheet(context, song),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 勾选框占用与序号同宽的列，进出选择态行内容不会横向跳动
            SizedBox(
              width: 24,
              child: selecting
                  ? Icon(
                      checked
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 22,
                      color: checked
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white24,
                    )
                  : Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.indexGreen,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      QualityBadge(song: song, trailingGap: 8),
                      Expanded(
                        child: Text(
                          '${song.artist} - ${song.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB0BAC6),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!selecting) ...[
              const SizedBox(width: 10),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.more_vert,
                  size: 22,
                  color: Colors.white,
                ),
                onPressed: () => showSongActionSheet(context, song),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 列表底部触底标记（§8.4 支持自定义文案 + {nTitle}/{nArtist}/{nAlbum} 占位符）
class _EndMark extends ConsumerWidget {
  const _EndMark();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final template = ref.watch(listEndTextProvider);
    final next = ref.watch(nextSongProvider);
    final text = template
        .replaceAll('{nTitle}', next?.title ?? '？')
        .replaceAll('{nArtist}', next?.artist ?? '？')
        .replaceAll('{nAlbum}', next?.album ?? '？');
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 48),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: Colors.white24, fontSize: 14),
        ),
      ),
    );
  }
}
