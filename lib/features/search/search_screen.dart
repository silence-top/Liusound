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
import '../player/player_controller.dart';

/// 搜索关键词（300ms 防抖后由 UI 层更新，对标 1.x SEARCH_DEBOUNCE_MS）
final searchQueryProvider = StateProvider<String>((ref) => '');

/// /search 聚合结果（歌曲/专辑/歌手）
final searchResultProvider = FutureProvider<SearchResult>((ref) async {
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

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

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
              radius: GlassTokens.radiusCard,
              blur: 0,
              tint: Colors.white.withValues(alpha: 0.06),
              gradientBorder: true,
              shadow: false,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 24, color: AppTheme.textDim),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: _onChanged,
                      autocorrect: false,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: '搜索音乐、专辑、艺人',
                        hintStyle:
                            TextStyle(color: AppTheme.textDim, fontSize: 16),
                        border: InputBorder.none,
                        filled: false,
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (query.isNotEmpty)
                    IconButton(
                      onPressed: _clear,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.cancel,
                          size: 20, color: AppTheme.textDim),
                    ),
                ],
              ),
            ),
            Expanded(child: _Results(query: query)),
          ],
        ),
      ),
    );
  }
}

/// 结果区：区分「未输入」/「无结果」/「有结果」三种状态
class _Results extends ConsumerWidget {
  const _Results({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(searchResultProvider).when(
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
                    const Icon(Icons.music_off,
                        size: 48, color: AppTheme.textFaint),
                    const SizedBox(height: 12),
                    Text('未找到与"$query"相关的内容',
                        style: const TextStyle(
                            color: AppTheme.textDim, fontSize: 15)),
                  ],
                ),
              );
            }
            return _ResultList(results: results);
          },
        );
  }
}

/// 结果列表：艺人（前 3）→ 专辑（前 5）→ 歌曲（全部）
class _ResultList extends ConsumerWidget {
  const _ResultList({required this.results});

  final SearchResult results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = results.artists.take(3).toList();
    final albums = results.albums.take(5).toList();

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
      child: Text(title,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold)),
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
          ArtistDetailScreen(
            artistId: artist.id,
            artistName: artist.name,
          ),
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
                  Text(artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('${artist.albumCount} 张专辑 · ${artist.songCount} 首',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 13)),
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
                Text(album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 15)),
                const SizedBox(height: 2),
                Text(album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textDim, fontSize: 13)),
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
      onTap: () => ref.read(playerActionsProvider).play(song),
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
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('${song.artist} - ${song.album}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.textDim, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.play_circle_outline,
                size: 28, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
