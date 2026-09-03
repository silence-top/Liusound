import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../player/player_controller.dart';
import '../search/search_screen.dart';
import 'detail_screen.dart';
import 'home_providers.dart';

/// 首页（对标 1.x HomeScreen）：
/// 装饰搜索栏 + 分区顺序：最新专辑 / 每日推荐 / 最近播放 / 最常播放 / 随机专辑。
/// 每日推荐展示 3 行，点「查看更多」进入全屏列表（PlaylistDetailScreen）。
///
/// 性能设计：本页不订阅任何播放进度 provider → 播放期间零重建；
/// 横向分区使用 ListView.builder 惰性构建 + 固定 itemExtent。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// 下拉刷新：更换随机 seed 并重取全部分区
  Future<void> _refresh(WidgetRef ref) async {
    ref.read(randomSeedProvider.notifier).state = makeSeed();
    ref.invalidate(latestAlbumsProvider);
    ref.invalidate(recentlyPlayedProvider);
    ref.invalidate(mostPlayedProvider);
    ref.invalidate(randomAlbumsProvider);
    ref.invalidate(dailySongsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: _SearchBar()),
            SliverToBoxAdapter(
              child: _Section(
                title: '最新专辑',
                child: _AlbumRow(latestAlbumsProvider),
              ),
            ),
            const SliverToBoxAdapter(child: _DailySection()),
            SliverToBoxAdapter(
              child: _Section(
                title: '最近播放',
                child: _AlbumRow(recentlyPlayedProvider),
              ),
            ),
            SliverToBoxAdapter(
              child: _Section(
                title: '最常播放',
                child: _AlbumRow(mostPlayedProvider),
              ),
            ),
            SliverToBoxAdapter(
              child: _Section(
                title: '随机专辑',
                child: _AlbumRow(randomAlbumsProvider),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

/// 装饰搜索栏（点击进入全屏搜索页，对齐设计图首屏）
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        fadeRoute<void>(const SearchScreen()),
      ),
      child: GlassSurface(
        radius: GlassTokens.radiusPill,
        blur: 0,
        tint: Colors.white.withValues(alpha: 0.06),
        gradientBorder: true,
        shadow: false,
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 38,
          child: const Row(
            children: [
              SizedBox(width: 4),
              Icon(Icons.search, size: 20, color: AppTheme.textDim),
              SizedBox(width: 8),
              Expanded(
                child: Text('搜索',
                    style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 16)),
              ),
              Icon(Icons.qr_code, size: 20, color: AppTheme.textDim),
              SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分区容器：标题（20 加粗）+ 可选尾部动作 + 内容
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                ?trailing,
              ],
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 横向专辑行（四个专辑分区共用）
class _AlbumRow extends ConsumerWidget {
  const _AlbumRow(this.provider);

  final FutureProvider<List<Album>> provider;

  static const _cardWidth = 140.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(provider);
    return albums.when(
      loading: () => const SizedBox(
        height: 190,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) =>
          _ErrorRetry(message: '$e', onRetry: () => ref.invalidate(provider)),
      data: (list) {
        if (list.isEmpty) {
          return const SizedBox(
            height: 150,
            child: Center(
                child: Text('暂无内容',
                    style: TextStyle(color: Colors.white38))),
          );
        }
        return SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: list.length,
            itemExtent: _cardWidth + 8, // 卡片宽 + 左右 margin 4
            itemBuilder: (context, index) => _AlbumCard(album: list[index]),
          ),
        );
      },
    );
  }
}

/// 专辑卡（140 封面 + 名称 + 歌手，点击进入专辑详情）
class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: PressableScale(
        onTap: () => Navigator.of(context).push(
          fadeRoute<void>(
            AlbumDetailScreen(
              albumId: album.id,
              title: album.name,
              subtitle: '${album.year ?? ''} ${album.artist}'.trim(),
              rating: album.rating,
            ),
          ),
        ),
        child: SizedBox(
          width: _AlbumRow._cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverArt(albumId: album.id, size: _AlbumRow._cardWidth, radius: 8),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 每日推荐分区：3 行歌曲 + 「查看更多」进入全屏列表
class _DailySection extends ConsumerWidget {
  const _DailySection();

  void _openDetail(BuildContext context, List<Song> songs) {
    Navigator.of(context).push(
      fadeRoute<void>(
        PlaylistDetailScreen(
          title: '每日推荐',
          songs: songs,
          coverAlbumId: songs.first.albumId,
          date: DateTime.now().toIso8601String().substring(0, 10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(dailySongsProvider);
    return songs.when(
      loading: () => const _Section(
        title: '每日推荐',
        child: SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => _Section(
        title: '每日推荐',
        child: _ErrorRetry(
            message: '$e', onRetry: () => ref.invalidate(dailySongsProvider)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const _Section(
            title: '每日推荐',
            child: SizedBox(
              height: 60,
              child: Center(
                  child: Text('暂无内容',
                      style: TextStyle(color: Colors.white38))),
            ),
          );
        }
        return _Section(
          title: '每日推荐',
          trailing: GestureDetector(
            onTap: () => _openDetail(context, list),
            child: const Text('查看更多',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ),
          child: GlassCard(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              children:
                  list.take(3).map((song) => _DailyRow(song: song)).toList(),
            ),
          ),
        );
      },
    );
  }
}

/// 每日推荐歌曲行：56 封面 + 标题/副标题 + 播放按钮
class _DailyRow extends ConsumerWidget {
  const _DailyRow({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 18),
      child: Row(
        children: [
          CoverArt(albumId: song.albumId, size: 56, radius: 8),
          const SizedBox(width: 14),
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
                      fontSize: 17,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${song.artist} - ${song.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Color(0xFFB0B0B0), fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => ref.read(playerActionsProvider).play(song),
            icon: const Icon(Icons.play_circle_outline,
                size: 32, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('加载失败',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 4),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
