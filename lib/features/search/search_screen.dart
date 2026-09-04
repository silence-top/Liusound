import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../auth/auth_controller.dart';
import '../home/artist_detail_screen.dart';
import '../player/full_screen_player.dart';
import '../player/player_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
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
                      autocorrect: false,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: '搜索音乐、专辑、艺人',
                        hintStyle: TextStyle(
                          color: AppTheme.textDimOf(context),
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  if (query.isNotEmpty)
                    IconButton(
                      onPressed: _clear,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.cancel,
                        size: 20,
                        color: AppTheme.textDimOf(context),
                      ),
                    ),
                ],
              ),
            ),
            _SegmentTabs(
              current: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
            Expanded(
              child: _Results(query: query, tab: _tab),
            ),
          ],
        ),
      ),
    );
  }
}

/// 结果区：区分「未输入」/「无结果」/「有结果」三种状态
class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.tab});

  final String query;
  final _SearchTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(searchResultProvider)
        .when(
          // 新关键词请求期间保留上次结果，避免结果区闪烁 loading
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text('$e', style: const TextStyle(color: Colors.white38)),
          ),
          data: (results) {
            if (query.trim().isEmpty) return const SizedBox.shrink();
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
            return _ResultList(results: results, tab: tab);
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
  const _ResultList({required this.results, required this.tab});

  final SearchResult results;
  final _SearchTab tab;

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

    return CustomScrollView(
      slivers: [
        if (artists.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _SectionTitle('艺人')),
          SliverList.builder(
            itemCount: artists.length,
            itemBuilder: (context, i) => _ArtistRow(artist: artists[i]),
          ),
        ],
        if (albums.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _SectionTitle('专辑')),
          SliverList.builder(
            itemCount: albums.length,
            itemBuilder: (context, i) => _AlbumRowCard(album: albums[i]),
          ),
        ],
        if (results.songs.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _SectionTitle('歌曲')),
          SliverList.builder(
            itemCount: results.songs.length,
            itemBuilder: (context, i) => _SongRow(song: results.songs[i]),
          ),
        ],
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 艺人行：圆形封面 + 名称 + 「N 张专辑 · N 首」
class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        fadeRoute<void>(
          ArtistDetailScreen(artistId: artist.id, artistName: artist.name),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CoverArt(albumId: artist.id, size: 48, radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
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
  const _AlbumRowCard({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                  style: const TextStyle(color: Colors.white, fontSize: 16),
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
    );
  }
}

/// 歌曲行：48 封面 + 标题/副标题 + 播放按钮（点击即播放）
class _SongRow extends ConsumerWidget {
  const _SongRow({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () {
        ref.read(playerActionsProvider).play(song);
        if (ref.read(autoOpenPlayerProvider)) openFullScreenPlayer(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CoverArt(albumId: song.albumId, size: 48, radius: 6),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${song.artist} - ${song.album}',
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
            const SizedBox(width: 8),
            const Icon(
              Icons.play_circle_outline,
              size: 28,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
