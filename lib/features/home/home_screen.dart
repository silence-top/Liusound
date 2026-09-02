import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../shared/cover_art.dart';
import '../player/player_controller.dart';
import 'home_providers.dart';

/// 首页五分区：最新专辑 / 最近播放 / 最常播放 / 随机专辑 / 每日推荐
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
            const SliverToBoxAdapter(child: _Header()),
            SliverToBoxAdapter(
              child: _Section(
                title: '最新专辑',
                child: _AlbumRow(latestAlbumsProvider),
              ),
            ),
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
            SliverToBoxAdapter(
              child: _Section(
                title: '每日推荐',
                child: _DailySongRow(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Image.asset('assets/app/logo.png', width: 36, height: 36),
          const SizedBox(width: 10),
          Text('流声', style: Theme.of(context).textTheme.headlineMedium),
        ],
      ),
    );
  }
}

/// 分区容器：标题 + 内容
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
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

  static const _cardWidth = 128.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(provider);
    return albums.when(
      loading: () => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _ErrorRetry(message: '$e', onRetry: () => ref.invalidate(provider)),
      data: (list) {
        if (list.isEmpty) {
          return const SizedBox(
            height: 150,
            child: Center(child: Text('暂无内容', style: TextStyle(color: Colors.white38))),
          );
        }
        return SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: list.length,
            itemExtent: _cardWidth + 12, // 固定宽度 + 间距，帮助滑动布局
            itemBuilder: (context, index) {
              final album = list[index];
              return _AlbumCard(album: album);
            },
          ),
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        // TODO(Phase 2)：进入专辑详情（曲目列表）
        onTap: () {},
        child: SizedBox(
          width: _AlbumRow._cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverArt(albumId: album.id, size: _AlbumRow._cardWidth),
              const SizedBox(height: 6),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 每日推荐：横向歌曲卡，点击即播放
class _DailySongRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(dailySongsProvider);
    return songs.when(
      loading: () => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) =>
          _ErrorRetry(message: '$e', onRetry: () => ref.invalidate(dailySongsProvider)),
      data: (list) {
        if (list.isEmpty) {
          return const SizedBox(
            height: 150,
            child: Center(child: Text('暂无内容', style: TextStyle(color: Colors.white38))),
          );
        }
        return SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: list.length,
            itemExtent: 140,
            itemBuilder: (context, index) {
              final song = list[index];
              return _DailySongCard(song: song);
            },
          ),
        );
      },
    );
  }
}

class _DailySongCard extends ConsumerWidget {
  const _DailySongCard({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ref.read(playerActionsProvider).play(song),
        child: SizedBox(
          width: 128,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  CoverArt(albumId: song.albumId, size: 128),
                  const Positioned(
                    right: 6,
                    bottom: 6,
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white70,
                      size: 30,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
        ),
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
            const Text('加载失败', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 4),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
