import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/marquee_text.dart';
import '../../shared/widgets/motion.dart';
import '../player/action_sheets.dart';
import '../player/full_screen_player.dart';
import '../player/player_controller.dart';
import '../search/search_screen.dart';
import 'detail_screen.dart';
import 'home_providers.dart';

/// 首页（对标 1.x HomeScreen）：
/// 装饰搜索栏 + 分区顺序：最新专辑 / 每日推荐 / 最近播放 / 最常播放 / 随机专辑。
/// 歌曲分区（每日推荐 / 最近播放 / 最常播放）展示 3 行歌曲，
/// 点「查看更多」进入全屏列表（PlaylistDetailScreen）。
///
/// 性能设计：本页不订阅任何播放进度 provider → 播放期间零重建；
/// 横向分区使用 ListView.builder 惰性构建 + 固定 itemExtent。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// 下拉刷新：更换随机 seed 并重取全部分区
  Future<void> _refresh(WidgetRef ref) async {
    ref.read(randomSeedProvider.notifier).state = makeSeed();
    ref.invalidate(latestAlbumsProvider);
    ref.invalidate(recentlyPlayedSongsProvider);
    ref.invalidate(mostPlayedSongsProvider);
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
            const SliverToBoxAdapter(child: _Greeting()),
            const SliverToBoxAdapter(child: _SearchBar()),
            SliverToBoxAdapter(
              child: _Section(
                title: '最新专辑',
                child: _AlbumRow(latestAlbumsProvider),
              ),
            ),
            SliverToBoxAdapter(
              child: _SongListSection(
                title: '每日推荐',
                provider: dailySongsProvider,
                withDate: true,
              ),
            ),
            SliverToBoxAdapter(
              child: _SongListSection(
                title: '最近播放',
                provider: recentlyPlayedSongsProvider,
              ),
            ),
            SliverToBoxAdapter(
              child: _SongListSection(
                title: '最常播放',
                provider: mostPlayedSongsProvider,
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

/// 时段问候语（对齐设计图「Good Morning」）：
/// build 内一次性求值，无 Timer / 无 provider 订阅，保持本页零重建
String _greetingForNow() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 11) return '早上好';
  if (hour >= 11 && hour < 13) return '中午好';
  if (hour >= 13 && hour < 18) return '下午好';
  if (hour >= 18 && hour < 23) return '晚上好';
  return '夜深了';
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.l,
          AppSpacing.xl,
          AppSpacing.l,
          0,
        ),
        child: Text(_greetingForNow(), style: AppText.h1),
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
      onTap: () =>
          Navigator.of(context).push(fadeRoute<void>(const SearchScreen())),
      child: GlassSurface(
        radius: GlassTokens.radiusPill,
        blur: 0,
        tint: GlassTokens.tint,
        gradientBorder: true,
        shadow: false,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 38,
          child: const Row(
            children: [
              SizedBox(width: 4),
              Icon(Icons.search, size: 20, color: AppTheme.textDim),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '搜索',
                  style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 16),
                ),
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
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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

/// 横向专辑行（最新专辑 / 随机专辑分区共用），点击进入专辑详情页
class _AlbumRow extends ConsumerWidget {
  const _AlbumRow(this.provider);

  final FutureProvider<List<Album>> provider;

  static const _cardWidth = 140.0;

  /// 封面 140 + 间距 8 + 双行标题 ~34 + 间距 4 + 歌手 ~17
  static const _rowHeight = 208.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(provider);
    return albums.when(
      loading: () => const SizedBox(
        height: _rowHeight,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) =>
          _ErrorRetry(message: '$e', onRetry: () => ref.invalidate(provider)),
      data: (list) {
        if (list.isEmpty) {
          return glassEmptyState(
            text: '暂无专辑',
            icon: Icons.album_outlined,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.xl,
              horizontal: AppSpacing.l,
            ),
            actions: [
              FilledButton.icon(
                onPressed: () => ref.invalidate(provider),
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('重新同步'),
              ),
            ],
          );
        }
        return SizedBox(
          height: _rowHeight,
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

/// 专辑卡（140 封面 + 名称 + 歌手，点击进入专辑详情页）
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
              CoverArt(
                albumId: album.id,
                size: _AlbumRow._cardWidth,
                radius: 8,
              ),
              const SizedBox(height: AppSpacing.s),
              // 双行 12sp：避免「我的楼兰（2026新…」这类粗暴截断；
              // 两行仍放不下时长按可跑马灯读全名
              MarqueeText(
                album.name,
                maxLines: 2,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              MarqueeText(
                album.artist,
                style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 歌曲列表分区（每日推荐 / 最近播放 / 最常播放共用）：
/// GlassCard 内 3 行歌曲 + 「查看更多」进入全屏列表
class _SongListSection extends ConsumerWidget {
  const _SongListSection({
    required this.title,
    required this.provider,
    this.withDate = false,
  });

  final String title;
  final FutureProvider<List<Song>> provider;

  /// 「查看更多」页头是否展示今日日期（每日推荐）
  final bool withDate;

  void _openDetail(BuildContext context, List<Song> songs) {
    Navigator.of(context).push(
      fadeRoute<void>(
        PlaylistDetailScreen(
          title: title,
          songs: songs,
          coverAlbumId: songs.first.albumId,
          date: withDate
              ? DateTime.now().toIso8601String().substring(0, 10)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(provider);
    return songs.when(
      loading: () => _Section(
        title: title,
        child: const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => _Section(
        title: title,
        child: _ErrorRetry(
          message: '$e',
          onRetry: () => ref.invalidate(provider),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return _Section(
            title: title,
            child: glassEmptyState(
              text: '$title暂无内容',
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.l,
                horizontal: AppSpacing.l,
              ),
            ),
          );
        }
        return _Section(
          title: title,
          trailing: GestureDetector(
            onTap: () => _openDetail(context, list),
            child: Text(
              '查看更多',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          child: GlassContainer(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: list
                  .take(3)
                  .map((song) => _SongCardRow(song: song, queue: list))
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

/// 歌曲列表分区行：56 封面 + 标题/副标题 + 播放按钮，
/// 点击直接播放（整卡队列）并弹出全屏播放器
class _SongCardRow extends ConsumerWidget {
  const _SongCardRow({required this.song, required this.queue});

  final Song song;
  final List<Song> queue;

  void _play(BuildContext context, WidgetRef ref) {
    final actions = ref.read(playerActionsProvider);
    actions.replaceQueue(queue);
    actions.play(song);
    openFullScreenPlayer(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _play(context, ref),
      // 长按唤出上下文菜单（与详情页 SongRow 行为一致）
      onLongPress: () => showSongActionSheet(context, song),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${song.artist} - ${song.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB0B0B0),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // 命中区 44×44dp：圆圈图标本身偏小，靠 constraints 兜住可点范围
            IconButton(
              onPressed: () => _play(context, ref),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const Icon(
                Icons.play_circle_outline,
                size: 34,
                color: Colors.white,
              ),
            ),
          ],
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
            const Text(
              '加载失败',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
