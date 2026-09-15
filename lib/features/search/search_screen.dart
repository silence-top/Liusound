import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/settings_prefs.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../auth/auth_controller.dart';
import '../home/detail_screen.dart';
import '../home/home_providers.dart';

/// 搜索关键词（300ms 防抖后由 UI 层更新，对标 1.x SEARCH_DEBOUNCE_MS）。
/// 页面级 autoDispose：离开搜索页即销毁，重进时输入框与结果一致。
final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// /search 聚合结果（歌曲/专辑/歌手）
final searchResultProvider = FutureProvider.autoDispose<SearchResult>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const SearchResult();
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return const SearchResult();
  return adapter.search(query);
});

/// 搜索历史（应用级存活 + SharedPreferences 持久化，最多 15 条，去重置顶）。
/// 只记录两类真实意图：键盘提交搜索、点击结果条目；防抖过程中的中间词不入史
class SearchHistoryController extends Notifier<List<String>> {
  static const _key = 'search.history.v1';
  static const _max = 15;

  @override
  List<String> build() {
    // 持久化读取推迟到 build 完成后（build 期同步改 state 会被 Riverpod 拒绝）；
    // Notifier 与 App 同生命周期，异步回来直接赋值安全（对齐 SongSortController）
    Future.microtask(() async {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      try {
        final list = (jsonDecode(raw) as List).whereType<String>().toList();
        state = list;
      } catch (_) {
        // 历史损坏视为无历史，不影响搜索
      }
    });
    return const [];
  }

  void add(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    final next = [q, ...state.where((e) => e != q)];
    if (next.length > _max) next.removeRange(_max, next.length);
    state = next;
    unawaited(_persist(next));
  }

  void remove(String query) {
    state = state.where((e) => e != query).toList();
    unawaited(_persist(state));
  }

  void clear() {
    state = const [];
    unawaited(_persist(state));
  }

  Future<void> _persist(List<String> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (list.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, jsonEncode(list));
      }
    } catch (_) {
      // 持久化失败静默：内存历史已生效，下次成功写入再补
    }
  }
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryController, List<String>>(
      SearchHistoryController.new,
    );

/// 搜索页（对标 1.x SearchScreen）：
/// 搜索框（可清除）→ 结果分区：艺人（前 3）→ 专辑（前 5）→ 歌曲。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

/// 搜索分类 Tab：纯前端过滤（ServerAdapter.search 是单次聚合调用），
/// 切 Tab 零网络零闪烁
enum _SearchTab { all, songs, albums, artists }

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  _SearchTab _tab = _SearchTab.all;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 300ms 防抖后触发搜索（避免逐字符请求）
  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = text;
    });
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  /// 键盘提交：跳过防抖立即生效并记入历史（真实搜索意图）
  void _submit(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) return;
    ref.read(searchQueryProvider.notifier).state = q;
    ref.read(searchHistoryProvider.notifier).add(q);
  }

  /// 点搜索历史 chip：回填输入框 + 立即搜索 + 置顶该条历史
  void _searchFromHistory(String q) {
    _debounce?.cancel();
    _controller.text = q;
    ref.read(searchQueryProvider.notifier).state = q;
    ref.read(searchHistoryProvider.notifier).add(q);
  }

  @override
  Widget build(BuildContext context) {
    // query 不在整页 watch：结果区与清除按钮各自订阅，
    // 输入防抖触发时不再重建搜索框胶囊与分段 Tab
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GlassSurface(
              radius: GlassTokens.radiusPill,
              blur: 0,
              tint: GlassTokens.tint(context),
              gradientBorder: true,
              shadow: false,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: 24,
                    color: AppTheme.textDimOf(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: _onChanged,
                      onSubmitted: _submit,
                      autocorrect: false,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(
                        color: AppTheme.textPrimaryOf(context),
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: '搜索音乐、专辑、艺人',
                        hintStyle: TextStyle(
                          color: AppTheme.textDimOf(context),
                          fontSize: 16,
                        ),
                        // 玻璃胶囊自带描边：主题 enabledBorder/focusedBorder 会在
                        // 空位自动补描边（applyDefaults），必须三层显式全 none，
                        // 否则胶囊里再套一层输入框边框
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  _ClearButton(onClear: _clear),
                ],
              ),
            ),
            _SegmentTabs(
              current: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
            Expanded(
              child: _Results(tab: _tab, onSearch: _searchFromHistory),
            ),
          ],
        ),
      ),
    );
  }
}

/// 清除按钮：独立订阅 query，输入变化只重建此按钮
class _ClearButton extends ConsumerWidget {
  const _ClearButton({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(searchQueryProvider).isEmpty) return const SizedBox.shrink();
    return IconButton(
      onPressed: onClear,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        Icons.cancel,
        size: 20,
        color: AppTheme.textDimOf(context),
      ),
    );
  }
}

/// 结果区：区分「未输入（历史）」/「无结果」/「有结果」三种状态
class _Results extends ConsumerWidget {
  const _Results({required this.tab, required this.onSearch});

  final _SearchTab tab;

  /// 空态点历史 chip 回填搜索（回调持有输入框控制器）
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider);
    return ref
        .watch(searchResultProvider)
        .when(
          // 新关键词请求期间保留上次结果，避免结果区闪烁 loading
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Builder(
              builder: (context) => Text(
                '$e',
                style: TextStyle(color: AppTheme.textFaintOf(context)),
              ),
            ),
          ),
          data: (results) {
            if (query.trim().isEmpty) {
              return _HistoryView(onSearch: onSearch);
            }
            if (results.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.music_off,
                      size: 48,
                      color: AppTheme.textFaintOf(context),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '未找到与"$query"相关的内容',
                      style: TextStyle(
                        color: AppTheme.textDimOf(context),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            }
            return _ResultList(
              results: results,
              tab: tab,
              onRecord: () =>
                  ref.read(searchHistoryProvider.notifier).add(query),
            );
          },
        );
  }
}

/// 搜索分段条（对齐 app_shell Tab 语言）：4 等分 pill，激活项 primary 18% 底
class _SegmentTabs extends StatelessWidget {
  const _SegmentTabs({required this.current, required this.onChanged});

  final _SearchTab current;
  final ValueChanged<_SearchTab> onChanged;

  static const _labels = {
    _SearchTab.all: '全部',
    _SearchTab.songs: '歌曲',
    _SearchTab.albums: '专辑',
    _SearchTab.artists: '歌手',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GlassSurface(
        radius: GlassTokens.radiusPill,
        blur: 0,
        tint: GlassTokens.tint(context),
        gradientBorder: true,
        shadow: false,
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final tab in _SearchTab.values)
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    onTap: () => onChanged(tab),
                    child: Container(
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tab == current
                            ? Theme.of(context).colorScheme.primary
                                  .withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(999),
                        ),
                      ),
                      child: Text(
                        _labels[tab]!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: tab == current
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: tab == current
                              ? Theme.of(context).colorScheme.primary
                              : AppTheme.textDimOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 结果列表：Tab 纯前端过滤 —— 全部视图艺人前 3 / 专辑前 5 / 歌曲全部，
/// 单类 Tab 放开截断渲染对应组
class _ResultList extends ConsumerWidget {
  const _ResultList({
    required this.results,
    required this.tab,
    required this.onRecord,
  });

  final SearchResult results;
  final _SearchTab tab;

  /// 点击结果条目时记录搜索历史（在行内跳转/播放前执行）
  final VoidCallback onRecord;

  static const _emptyText = {
    _SearchTab.all: '未找到相关内容',
    _SearchTab.songs: '未找到相关歌曲',
    _SearchTab.albums: '未找到相关专辑',
    _SearchTab.artists: '未找到相关歌手',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAll = tab == _SearchTab.all;
    final artists = (isAll || tab == _SearchTab.artists)
        ? (isAll ? results.artists.take(3).toList() : results.artists.toList())
        : const <Artist>[];
    final albums = (isAll || tab == _SearchTab.albums)
        ? (isAll ? results.albums.take(5).toList() : results.albums.toList())
        : const <Album>[];
    final songs = (isAll || tab == _SearchTab.songs)
        ? results.songs
        : const <Song>[];

    if (artists.isEmpty && albums.isEmpty && songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_off,
              size: 48,
              color: AppTheme.textFaintOf(context),
            ),
            const SizedBox(height: 12),
            Text(
              _emptyText[tab]!,
              style: TextStyle(
                color: AppTheme.textDimOf(context),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final cardsOn = ref.watch(cardDisplayProvider);
    Widget group(Widget rows) => cardsOn
        ? GlassContainer(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: rows,
          )
        : rows;

    // 分区标题独立成 sliver；裸排模式（默认）行级 SliverList.builder 虚拟化，
    // 一次只 build/layout 可视行——否则全部结果一次性塞进 SliverToBoxAdapter，
    // 大结果集时整段 build+layout 阻塞；卡片模式保留单卡包裹的整体形态
    List<Widget> section(String title, int count, Widget Function(int) row) {
      final titleSliver = SliverToBoxAdapter(child: _SectionTitle(title));
      if (cardsOn) {
        return [
          titleSliver,
          SliverToBoxAdapter(
            child: group(
              Column(
                children: [for (var i = 0; i < count; i++) row(i)],
              ),
            ),
          ),
        ];
      }
      return [
        titleSliver,
        SliverList.builder(itemCount: count, itemBuilder: (_, i) => row(i)),
      ];
    }

    return CustomScrollView(
      slivers: [
        if (artists.isNotEmpty)
          ...section(
            '艺人',
            artists.length,
            (i) => _ArtistRow(artist: artists[i], onRecord: onRecord),
          ),
        if (albums.isNotEmpty)
          ...section(
            '专辑',
            albums.length,
            (i) => _AlbumRowCard(album: albums[i], onRecord: onRecord),
          ),
        if (results.songs.isNotEmpty)
          ...section(
            '歌曲',
            results.songs.length,
            (i) => FadeSlideIn(
              child: SongRow(
                song: results.songs[i],
                index: i,
                songs: results.songs,
                onResultTap: onRecord,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: AppTheme.textPrimaryOf(context),
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 艺人行：圆形封面 + 名称 + 「N 张专辑 · N 首」
class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artist, required this.onRecord});

  final Artist artist;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        onRecord();
        Navigator.of(context).push(
          fadeRoute<void>(
            SongListScreen(
              title: artist.name,
              pagedSongsProvider: artistSongsProvider(artist.id),
              coverAlbumId: artist.id,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            EntityCover(entityId: artist.id, size: 48, radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textPrimaryOf(context),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${artist.albumCount} 张专辑 · ${artist.songCount} 首',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textDimOf(context),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 专辑行：48 封面 + 名称 + 歌手
class _AlbumRowCard extends StatelessWidget {
  const _AlbumRowCard({required this.album, required this.onRecord});

  final Album album;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        onRecord();
        Navigator.of(context).push(
          fadeRoute<void>(
            SongListScreen(
              rateTargetId: album.id,
              songsProvider: albumSongsProvider(album.id),
              title: album.name,
              subtitle: '${album.year ?? ''} ${album.artist}'.trim(),
              rating: album.rating,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CoverArt(albumId: album.id, size: 48, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textPrimaryOf(context),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textDimOf(context),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空态：搜索历史 chips（点按回填搜索 / 单条删除 / 一键清空），无历史给引导文案
class _HistoryView extends ConsumerWidget {
  const _HistoryView({required this.onSearch});

  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider);
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: AppTheme.textFaintOf(context)),
            const SizedBox(height: 12),
            Text(
              '搜索音乐、专辑、艺人',
              style: TextStyle(
                color: AppTheme.textDimOf(context),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 4, 0),
            child: Row(
              children: [
                Text(
                  '搜索历史',
                  style: TextStyle(
                    color: AppTheme.textPrimaryOf(context),
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () =>
                      ref.read(searchHistoryProvider.notifier).clear(),
                  tooltip: '清空搜索历史',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 22,
                    color: AppTheme.textFaintOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in history)
                  _HistoryChip(query: q, onSearch: onSearch),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

/// 历史词条：胶囊 chip，点按重新搜索；尾部 × 单条删除（命中区 32×32）
class _HistoryChip extends ConsumerWidget {
  const _HistoryChip({required this.query, required this.onSearch});

  final String query;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      onTap: () => onSearch(query),
      child: Container(
        height: 36,
        padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
        decoration: BoxDecoration(
          color: GlassTokens.tint(context),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              query,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => ref.read(searchHistoryProvider.notifier).remove(query),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: AppTheme.textFaintOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
