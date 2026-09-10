import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/song_sorting.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/skin_tokens.dart';
import '../../shared/widgets/list_end_mark.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/motion.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/quality_badge.dart';
import '../../shared/widgets/toast.dart';
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
  bool showFileSize = false,
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
            showFileSize: showFileSize,
            selected: selectMode ? selected.contains(song.id) : null,
            onToggleSelect: selectMode && onToggle != null
                ? () => onToggle(song)
                : null,
          ),
        );
      },
    ),
    SliverToBoxAdapter(child: ListEndMark(songs: songs)),
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
    showToast(message);
  }
}

/// 统一歌曲列表页（原专辑详情 / 歌单详情 / 艺人详情三页合一）：
/// 静态头部（封面 90 + 标题/副标题 + 可选五星评分 setRating）
/// → 全部播放栏（随机播放 / 加入队列 / 顺序播放）
/// → 可收纳过滤框 → 歌曲列表（绿序号 + flac 码率 + 行菜单）→ 到底啦/加载更多。
/// 数据源四选一（优先级从高到低）：
/// - songs：直接给定（每日推荐「查看更多」）
/// - pagedSongsProvider：分页加载（艺人歌曲，含「加载更多」）
/// - songsProvider：一次性异步加载（资料库歌曲/我喜欢的/本地音乐/流派）
/// - playlistId：异步加载歌单（/api/playlist/{id}/tracks）
class SongListScreen extends ConsumerStatefulWidget {
  const SongListScreen({
    super.key,
    required this.title,
    this.songs,
    this.pagedSongsProvider,
    this.songsProvider,
    this.playlistId,
    this.coverAlbumId,
    this.date,
    this.subtitle,
    this.rating = 0,
    this.rateTargetId,
    this.onRefresh,
  }) : assert(
         songs != null ||
             pagedSongsProvider != null ||
             songsProvider != null ||
             playlistId != null,
         '必须提供 songs / pagedSongsProvider / songsProvider / playlistId 之一',
       );

  final String title;
  final List<Song>? songs;
  final AutoDisposeFamilyNotifierProvider<
    ArtistSongsController,
    ArtistSongsState,
    String
  >?
  pagedSongsProvider;
  // 同时接受普通与 autoDispose（含 family 已取参）的 provider（资料库入口/流派）
  final ProviderBase<AsyncValue<List<Song>>>? songsProvider;
  final String? playlistId;
  final String? coverAlbumId;
  final String? date;
  final String? subtitle;
  final int rating;
  final String? rateTargetId; // 非 null 且后端支持评分时显示五星评分（专辑）
  /// 下拉刷新回调（本地音乐等本地数据源启用）；null 则不启用下拉刷新
  final Future<void> Function()? onRefresh;

  @override
  ConsumerState<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends ConsumerState<SongListScreen>
    with _BatchSelect<SongListScreen> {
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
    final target = widget.rateTargetId;
    if (target == null) return;
    final before = _rating;
    setState(() => _rating = rating);
    final ok =
        await ref.read(serverAdapterProvider)?.setRating(target, rating) ??
        false;
    if (!ok && mounted) {
      setState(() => _rating = before);
      showToast('评分提交失败', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paged = widget.pagedSongsProvider == null
        ? null
        : ref.watch(widget.pagedSongsProvider!);
    final AsyncValue<List<Song>>? async;
    if (paged != null) {
      async = null;
    } else if (widget.songs != null) {
      async = AsyncValue.data(widget.songs!);
    } else if (widget.songsProvider != null) {
      async = ref.watch(widget.songsProvider!);
    } else if (widget.playlistId != null) {
      async = ref.watch(playlistSongsProvider(widget.playlistId!));
    } else {
      async = null;
    }
    final all = paged?.songs ?? async?.value ?? const <Song>[];
    final sorted = sortSongs(all, ref.watch(songSortPrefProvider));
    final songs = _filterSongs(sorted, _search);
    final canRate =
        widget.rateTargetId != null &&
        (ref.watch(serverAdapterProvider)?.capabilities.ratings ?? false);
    final canDownload =
        ref.watch(serverAdapterProvider)?.capabilities.download ?? true;
    final selectedCount = selectionOf(songs).length;
    // 资料库歌曲入口（歌曲/我喜欢的/本地音乐）头部展示占用空间，对齐设计图
    final showFileSize = widget.songsProvider != null;
    final totalBytes = all.fold<int>(0, (sum, s) => sum + s.size);
    final subtitle =
        widget.subtitle ??
        (all.isEmpty
            ? ''
            : showFileSize && totalBytes > 0
            ? '共计占用 ${QualityBadge.fileSizeLabel(totalBytes)} 空间'
            : '共 ${all.length} 首歌曲');
    // 资料库入口没有固定封面：回退用第一首歌的专辑封面（艺人页传 artistId）
    final coverAlbumId =
        widget.coverAlbumId ?? (all.isEmpty ? null : all.first.albumId);
    // 统一背景系统：图片背景最高优先级 + 皮肤舞台（与壳层三页一致），
    // 不再使用主题联动的固定 detailBgOf 底色
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: selectMode
            ? _BatchBar(
                count: selectedCount,
                canDownload: canDownload,
                onPlayNext: () => batchPlayNext(songs),
                onAddToPlaylist: () => batchAddToPlaylist(songs),
                onDownload: () => batchDownload(songs),
              )
            : const MiniPlayer(),
        body: _bodyWithRefresh(
          CustomScrollView(
            physics: widget.onRefresh != null
                ? const AlwaysScrollableScrollPhysics()
                : null,
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
                sortActive: ref.watch(songSortPrefProvider) != null,
                onToggleSort: () => _showSortSheet(context),
                primaryColor: Theme.of(context).colorScheme.primary,
              ),
              SliverToBoxAdapter(
                child: _Header(
                  title: widget.title,
                  subtitle: widget.date ?? subtitle,
                  coverAlbumId: coverAlbumId,
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
              ..._listSlivers(paged: paged, async: async, songs: songs),
            ],
          ),
        ),
      ),
    );
  }

  /// 下拉刷新包装（仅传入 onRefresh 的数据源启用，如本地音乐）：
  /// 刷新动作完成后 invalidate 数据源，列表重读最新缓存
  Widget _bodyWithRefresh(Widget child) {
    final onRefresh = widget.onRefresh;
    if (onRefresh == null) return _pagedLoader(child: child);
    return RefreshIndicator(
      onRefresh: () async {
        await onRefresh();
        final p = widget.songsProvider;
        if (p != null) ref.invalidate(p);
      },
      child: _pagedLoader(child: child),
    );
  }

  /// 分页数据源时包一层滚动触底自动加载（LoadMoreRow 只负责状态展示）
  Widget _pagedLoader({required Widget child}) {
    if (widget.pagedSongsProvider == null) return child;
    return ScrollBottomLoader(
      onBottom: () => ref.read(widget.pagedSongsProvider!.notifier).loadMore(),
      child: child,
    );
  }

  /// 列表分区块：分页源走 loading/重试/空态 + 加载更多；
  /// 非分页源走 sliverAsyncGuard（错误重试 + 空态 + 过滤无匹配）。
  List<Widget> _listSlivers({
    required ArtistSongsState? paged,
    required AsyncValue<List<Song>>? async,
    required List<Song> songs,
  }) {
    List<Widget> rows() => _songSlivers(
      songs,
      selectMode: selectMode,
      showFileSize: widget.songsProvider != null,
      selected: selectedIds,
      onToggle: toggleSelected,
    );
    if (paged != null) {
      final controller = ref.read(widget.pagedSongsProvider!.notifier);
      if (songs.isNotEmpty) {
        return [
          ...rows(),
          SliverToBoxAdapter(
            child: LoadMoreRow(
              loading: paged.loading,
              failed: paged.error,
              noMore: paged.noMore,
              onLoadMore: controller.loadMore,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 64)),
        ];
      }
      if (paged.loading) {
        return const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ];
      }
      if (paged.error) {
        return [
          SliverToBoxAdapter(
            child: errorRetryBox(
              padding: const EdgeInsets.all(48),
              onRetry: controller.retry,
            ),
          ),
        ];
      }
      return [SliverToBoxAdapter(child: glassEmptyState(text: '暂无歌曲'))];
    }
    return sliverAsyncGuard<Song>(
      async: async ?? AsyncValue.data(const []),
      emptyText: widget.playlistId != null ? '歌单暂无歌曲' : '${widget.title}暂无歌曲',
      onRetry: () {
        final p = widget.songsProvider;
        if (p != null) {
          ref.invalidate(p);
          return;
        }
        final id = widget.playlistId;
        if (id != null) ref.invalidate(playlistSongsProvider(id));
      },
      onData: (_) => rows(),
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
    showToast('已将 ${songs.length} 首歌曲加入队列');
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
                  style: TextStyle(
                    color: AppTheme.textPrimaryOf(context),
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
                    style: TextStyle(
                      color: AppTheme.textDimOf(context),
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
        color: SkinTokens.of(context).surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.album, color: AppTheme.textFaintOf(context), size: 36),
    );
  }
}

/// 列表顶部：全部播放栏（右三图标功能化）+ 可收纳过滤框，_bar 圆角容器
class _ListTop extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // 列表头面板白玻璃微透明：乘全局「卡片透明度」系数联动
    final panel = Colors.white.withValues(alpha: 0.08);
    final panelFaint = Colors.white.withValues(alpha: 0.03);
    final panelBorder = withGlassTintOpacity(
      ref,
      Colors.white.withValues(alpha: 0.12),
    );
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            withGlassTintOpacity(ref, panel),
            withGlassTintOpacity(ref, panelFaint),
          ],
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(GlassTokens.radiusCard),
        ),
        border: Border(top: BorderSide(color: panelBorder, width: 0.5)),
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
                      Divider(height: 1, color: SkinTokens.of(context).divider),
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
  required BuildContext context,
  required bool expanded,
  required VoidCallback onPressed,
  required Color primaryColor,
}) {
  return IconButton(
    onPressed: onPressed,
    tooltip: expanded ? '收起筛选' : '筛选歌曲',
    icon: Icon(
      Icons.search,
      color: expanded ? primaryColor : AppTheme.textDimOf(context),
    ),
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
  required bool sortActive,
  required VoidCallback onToggleSort,
  required Color primaryColor,
}) {
  // 空列表没得选，入口直接禁用并置灰，省得点进去是一个空的选择态
  final canSelect = totalCount > 0;
  final allSelected = canSelect && selectedCount == totalCount;
  return SliverAppBar(
    pinned: true,
    toolbarHeight: 56,
    backgroundColor: Colors.transparent,
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
                color: AppTheme.textDimOf(context),
              ),
            ),
            IconButton(
              onPressed: onToggleSelectMode,
              tooltip: '退出批量选择',
              icon: Icon(Icons.close, color: AppTheme.textDimOf(context)),
            ),
          ]
        : [
            IconButton(
              onPressed: totalCount > 0 ? onToggleSort : null,
              tooltip: '排序',
              icon: Icon(
                Icons.swap_vert,
                color: sortActive
                    ? primaryColor
                    : totalCount > 0
                    ? AppTheme.textDimOf(context)
                    : AppTheme.textFaintOf(context),
              ),
            ),
            IconButton(
              onPressed: canSelect ? onToggleSelectMode : null,
              tooltip: '批量选择',
              icon: Icon(
                Icons.checklist,
                color: canSelect
                    ? AppTheme.textDimOf(context)
                    : AppTheme.textFaintOf(context),
              ),
            ),
            _filterAction(
              context: context,
              expanded: filterExpanded,
              onPressed: onToggleFilter,
              primaryColor: primaryColor,
            ),
          ],
  );
}

/// 排序弹层：字段单选 + 升降序切换，实时生效（列表在弹层后即时更新）。
/// 「默认」= 恢复各列表原始顺序（歌单的服务端编排、曲库的加入时间倒序等）
Future<void> _showSortSheet(BuildContext context) {
  return glassBottomSheet<void>(
    context,
    Consumer(
      builder: (context, ref, _) {
        final pref = ref.watch(songSortPrefProvider);
        final controller = ref.read(songSortPrefProvider.notifier);
        final primary = Theme.of(context).colorScheme.primary;
        Widget row({
          required String label,
          required bool selected,
          required VoidCallback onTap,
        }) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? primary
                          : AppTheme.textPrimaryOf(context),
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 20, color: primary),
              ],
            ),
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                '排序方式',
                style: TextStyle(
                  color: AppTheme.textPrimaryOf(context),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            row(
              label: '默认（原始顺序）',
              selected: pref == null,
              onTap: () => controller.set(null),
            ),
            for (final field in kSortableSongFields)
              row(
                label: songSortLabel(field),
                selected: pref?.field == field,
                onTap: () => controller.set(
                  pref?.field == field
                      ? pref
                      : SongSortPref(
                          field: field,
                          ascending:
                              field == SongSort.title ||
                              field == SongSort.artist ||
                              field == SongSort.album,
                        ),
                ),
              ),
            if (pref != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Text(
                      '方向',
                      style: TextStyle(
                        color: AppTheme.textDimOf(context),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text('升序'),
                            icon: Icon(Icons.arrow_upward, size: 16),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text('降序'),
                            icon: Icon(Icons.arrow_downward, size: 16),
                          ),
                        ],
                        selected: {pref.ascending},
                        onSelectionChanged: (v) => controller.set(
                          SongSortPref(field: pref.field, ascending: v.first),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    ),
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
      gradientBorder: false,
      shadow: false,
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: [
          _action(context, Icons.low_priority, '下一首播放', onPlayNext),
          _action(context, Icons.playlist_add, '添加到歌单', onAddToPlaylist),
          if (canDownload)
            _action(context, Icons.download_outlined, '下载', onDownload),
        ],
      ),
    );
  }

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
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
                color: enabled
                    ? AppTheme.actionBlue
                    : AppTheme.textFaintOf(context),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: enabled
                      ? AppTheme.textPrimaryOf(context)
                      : AppTheme.textFaintOf(context),
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
          Icon(Icons.search, size: 20, color: AppTheme.textFaintOf(context)),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              // 由 AppBar 搜索图标展开时立即获得焦点，省去二次点击
              autofocus: true,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: '搜索歌曲/专辑/歌手',
                hintStyle: TextStyle(
                  color: AppTheme.textFaintOf(context),
                  fontSize: 16,
                ),
                // 玻璃 AppBar 内输入框：三层显式全 none，防止主题描边套进来
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
              ),
            ),
          ),
          Icon(
            Icons.filter_list,
            size: 22,
            color: AppTheme.textFaintOf(context),
          ),
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
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_circle_fill,
                size: 28,
                color: AppTheme.textPrimaryOf(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPlayAll,
            child: Row(
              children: [
                Text(
                  '全部播放',
                  style: TextStyle(
                    color: AppTheme.textPrimaryOf(context),
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '（共$count首）',
                  style: TextStyle(
                    color: AppTheme.textDimOf(context),
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
    this.showFileSize = false,
    this.selected,
    this.onToggleSelect,
  });

  final Song song;
  final int index;
  final List<Song> songs;

  /// 为真时徽标显示文件大小（flac 61 MB）而非码率（本地音乐列表）
  final bool showFileSize;

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
                          : AppTheme.textFaintOf(context),
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
                    style: TextStyle(
                      color: AppTheme.textPrimaryOf(context),
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      QualityBadge(
                        song: song,
                        trailingGap: 8,
                        showFileSize: showFileSize,
                      ),
                      Expanded(
                        child: Text(
                          '${song.artist} - ${song.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.textDimOf(context),
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
                icon: Icon(
                  Icons.more_vert,
                  size: 22,
                  color: AppTheme.textPrimaryOf(context),
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
