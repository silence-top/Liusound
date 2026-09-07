import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/motion.dart';
import '../player/mini_player.dart';
import 'detail_screen.dart';
import 'home_providers.dart';

/// 艺人详情页：圆形头像 + 歌手名/歌曲统计 → 热门歌曲列表（复用 SongRow）。
/// 数据：GET /api/song?artist_id=（热门优先）。
class ArtistDetailScreen extends ConsumerWidget {
  const ArtistDetailScreen({
    super.key,
    required this.artistId,
    required this.artistName,
  });

  final String artistId;
  final String artistName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songsState = ref.watch(artistSongsProvider(artistId));

    return Scaffold(
      backgroundColor: AppTheme.detailBgOf(context),
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
                    AppTheme.detailBgOf(context),
                    AppTheme.detailBgOf(context).withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
            leading: const BackButton(),
            title: Text(
              artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SliverToBoxAdapter(
            child: _Header(
              name: artistName,
              artistId: artistId,
              songCount: songsState.songs.length,
            ),
          ),
          ..._songSlivers(context, ref, songsState),
        ],
      ),
    );
  }

  /// 歌曲分区块：首屏 loading / 失败重试 / 空态 / 列表 + 「加载更多」行
  List<Widget> _songSlivers(
    BuildContext context,
    WidgetRef ref,
    ArtistSongsState state,
  ) {
    final controller = ref.read(artistSongsProvider(artistId).notifier);
    if (state.songs.isEmpty) {
      if (state.loading) {
        return const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ];
      }
      if (state.error) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: TextButton(
                  onPressed: controller.retry,
                  child: const Text('加载失败，点击重试'),
                ),
              ),
            ),
          ),
        ];
      }
      return [SliverToBoxAdapter(child: glassEmptyState(text: '暂无歌曲'))];
    }
    return [
      SliverList.builder(
        itemCount: state.songs.length,
        itemBuilder: (context, index) => FadeSlideIn(
          child: SongRow(
            song: state.songs[index],
            index: index,
            songs: state.songs,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: LoadMoreRow(
          loading: state.loading,
          failed: state.error,
          noMore: state.noMore,
          onLoadMore: () =>
              ref.read(artistSongsProvider(artistId).notifier).loadMore(),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 64)),
    ];
  }
}

/// 头部：大圆头像 + 歌手名 + 「N 首歌曲」（对齐搜索页艺人行格式）
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.artistId,
    required this.songCount,
  });

  final String name;
  final String artistId;
  final int songCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: [
          EntityCover(entityId: artistId, size: 96, radius: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$songCount 首歌曲',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
