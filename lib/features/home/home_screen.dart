import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/settings_prefs.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/album_card.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/marquee_text.dart';
import '../../shared/widgets/motion.dart';
import '../../shared/widgets/search_entry.dart';
import '../player/action_sheets.dart';
import '../player/full_screen_player.dart';
import '../player/player_controller.dart';
import '../search/search_screen.dart';
import 'detail_screen.dart';
import 'home_providers.dart';
import 'library_entries_screen.dart';
import 'music_library_screen.dart';

/// 首页（2.0 改版，参考网易云 / QQ 音乐布局）：
/// 搜索栏 → 快捷导航宫格(2×4) → 推荐歌单(3列) → 最新专辑(横滑) →
/// 每日推荐 / 最近播放 / 最常播放（带排名序号）。
///
/// 性能设计：本页不订阅任何播放进度 provider → 播放期间零重建；
/// 横向分区使用 ListView.builder 惰性构建 + 固定 itemExtent。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.read(randomSeedProvider.notifier).state = makeSeed();
    ref.invalidate(latestAlbumsProvider);
    ref.invalidate(recentlyPlayedSongsProvider);
    ref.invalidate(mostPlayedSongsProvider);
    ref.invalidate(randomAlbumsProvider);
    ref.invalidate(dailySongsProvider);
    ref.invalidate(playlistsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SearchEntryBar(
                onTap: () => Navigator.of(context).push(
                  fadeRoute<void>(const SearchScreen()),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _quickNavGrid(context, ref)),
            _playlistSection(context, ref),
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
                subtitle: DateTime.now().toIso8601String().substring(0, 10),
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
                numbered: true,
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 96 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 快捷导航宫格：2 行 × 4 列，圆形图标 + 标签
  Widget _quickNavGrid(BuildContext context, WidgetRef ref) {
    final items = _quickNavItems(context, ref);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        runSpacing: 8,
        children: [
          for (final item in items) _QuickNavItem(icon: item.icon, label: item.label, onTap: item.onTap),
        ],
      ),
    );
  }

  List<({IconData icon, String label, VoidCallback onTap})> _quickNavItems(
    BuildContext context,
    WidgetRef ref,
  ) {
    return [
      (
        icon: Icons.calendar_today,
        label: '每日推荐',
        onTap: () => Navigator.of(context).push(
          fadeRoute<void>(
            SongListScreen(
              title: '每日推荐',
              songsProvider: dailySongsProvider,
              date: DateTime.now().toIso8601String().substring(0, 10),
            ),
          ),
        ),
      ),
      (
        icon: Icons.queue_music,
        label: '歌单',
        onTap: () => Navigator.of(context).push(
          fadeRoute<void>(const MusicLibraryScreen()),
        ),
      ),
      (
        icon: Icons.person,
        label: '歌手',
        onTap: () => Navigator.of(context).push(
          fadeRoute<void>(
            ArtistListPage(title: '歌手', provider: artistsProvider),
          ),
        ),
      ),
      (
        icon: Icons.album,
        label: '专辑',
        onTap: () => Navigator.of(context).push(
          fadeRoute<void>(
            AlbumListPage(title: '专辑', provider: libraryAlbumsProvider),
          ),
        ),
      ),
      (
        icon: Icons.history,
        label: '最近播放',
        onTap: () => Navigator.of(context).push(
          fadeRoute<void>(
            SongListScreen(
              title: '最近播放',
              songsProvider: recentlyPlayedSongsProvider,
            ),
          ),
        ),
      ),
      (
        icon: Icons.favorite,
        label: '我喜欢',
        onTap: () => Navigator.of(context).push(
          fadeRoute<void>(
            SongListScreen(
              title: '我喜欢的',
              songsProvider: likedSongsProvider,
            ),
          ),
        ),
      ),
      (
        icon: Icons.grid_view,
        label: '流派',
        onTap: () => Navigator.of(context).push(
          fadeRoute<void>(const GenrePage()),
        ),
      ),
      (
        icon: Icons.apps,
        label: '更多',
        onTap: () => Navigator.of(context).push(
          fadeRoute<void>(const MusicLibraryScreen()),
        ),
      ),
    ];
  }

  /// 推荐歌单分区：3 列网格，展示前 6 个歌单
  Widget _playlistSection(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return playlists.when(
      loading: () => const SliverToBoxAdapter(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, _) => const SliverToBoxAdapter(
        child: SizedBox(
          height: 120,
          child: Center(
            child: Text('加载歌单失败', style: TextStyle(color: Colors.grey)),
          ),
        ),
      ),
      data: (list) {
        if (list.isEmpty) return const SliverToBoxAdapter();
        final visible = list.take(6).toList();
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        '推荐歌单',
                        style: TextStyle(
                          color: AppTheme.textPrimaryOf(context),
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          fadeRoute<void>(const MusicLibraryScreen()),
                        ),
                        child: Text(
                          '查看更多',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: [
                      for (var i = 0; i < visible.length; i++)
                        _PlaylistCard(
                          playlist: visible[i],
                          onTap: () => Navigator.of(context).push(
                            fadeRoute<void>(
                              SongListScreen(
                                title: visible[i].name,
                                playlistId: visible[i].id,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── 快捷导航项 ─────────────────────────────────────────

class _QuickNavItem extends ConsumerWidget {
  const _QuickNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 72,
      child: PressableScale(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: withGlassTintOpacity(
                  ref,
                  AppTheme.surfaceOf(context).withValues(alpha: 0.6),
                ),
                border: Border.all(
                  color: AppTheme.textFaintOf(context).withValues(alpha: 0.12),
                ),
              ),
              child: Icon(
                icon,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 歌单网格 ────────────────────────────────────────────

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.onTap});

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final coverSize = (screenWidth - 24 - 16) / 3;
    return PressableScale(
      onTap: onTap,
      child: SizedBox(
        width: coverSize,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: AppTheme.surfaceOf(context).withValues(alpha: 0.3),
                      ),
                    ),
                    Center(
                      child: Icon(
                        Icons.queue_music,
                        size: 32,
                        color: AppTheme.textFaintOf(context),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.play_arrow,
                              size: 10,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 1),
                            Text(
                              '${playlist.songCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            MarqueeText(
              playlist.name,
              maxLines: 2,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 分区容器 ────────────────────────────────────────────

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
                  style: TextStyle(
                    color: AppTheme.textPrimaryOf(context),
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

// ─── 横向专辑行 ──────────────────────────────────────────

class _AlbumRow extends ConsumerWidget {
  const _AlbumRow(this.provider);

  final FutureProvider<List<Album>> provider;

  static const _cardWidth = 140.0;
  static const _rowHeight = 208.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(provider);
    return albums.when(
      loading: () => const SizedBox(
        height: _rowHeight,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => errorRetryBox(onRetry: () => ref.invalidate(provider)),
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
            itemExtent: _cardWidth + 8,
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
            SongListScreen(
              rateTargetId: album.id,
              songsProvider: albumSongsProvider(album.id),
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
              Stack(
                children: [
                  CoverArt(albumId: album.id, size: _AlbumRow._cardWidth, radius: 8),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: SongCountBadge(count: album.songCount),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              MarqueeText(
                album.name,
                maxLines: 2,
                style: TextStyle(
                  color: AppTheme.textPrimaryOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              MarqueeText(
                album.artist,
                style: TextStyle(
                  color: AppTheme.textFaintOf(context),
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

// ─── 歌曲列表分区 ────────────────────────────────────────

/// 歌曲列表分区：3 行歌曲 + 「查看更多」进入全屏列表。
/// [numbered] = true 时左侧显示排名序号（最常播放 / 热歌榜风格）。
class _SongListSection extends ConsumerWidget {
  const _SongListSection({
    required this.title,
    required this.provider,
    this.withDate = false,
    this.subtitle,
    this.numbered = false,
  });

  final String title;
  final FutureProvider<List<Song>> provider;
  final bool withDate;
  final String? subtitle;
  final bool numbered;

  void _openDetail(BuildContext context, List<Song> songs) {
    Navigator.of(context).push(
      fadeRoute<void>(
        SongListScreen(
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
        child: errorRetryBox(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
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
          child: ref.watch(cardDisplayProvider)
              ? GlassContainer(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: list
                        .take(3)
                        .map(
                          (song) => _SongCardRow(
                            song: song,
                            queue: list,
                            rank: numbered
                                ? list.indexOf(song) + 1
                                : null,
                          ),
                        )
                        .toList(),
                  ),
                )
              : Column(
                  children: list
                      .take(3)
                      .map(
                        (song) => _SongCardRow(
                          song: song,
                          queue: list,
                          rank: numbered ? list.indexOf(song) + 1 : null,
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }
}

/// 歌曲行：可选排名序号 + 封面 + 标题/副标题 + 播放按钮。
/// [rank] 非空时左侧显示排名数字（前 3 名高亮主题色），隐藏封面。
class _SongCardRow extends ConsumerWidget {
  const _SongCardRow({required this.song, required this.queue, this.rank});

  final Song song;
  final List<Song> queue;
  final int? rank;

  void _play(BuildContext context, WidgetRef ref) {
    final actions = ref.read(playerActionsProvider);
    actions.replaceQueue(queue);
    actions.play(song);
    if (ref.read(autoOpenPlayerProvider)) openFullScreenPlayer(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () => _play(context, ref),
      onLongPress: () => showSongActionSheet(context, song),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            if (rank != null) ...[
              SizedBox(
                width: 28,
                child: Text(
                  '${rank!}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: rank! <= 3 ? primary : AppTheme.textDimOf(context),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              CoverArt(albumId: song.albumId, size: 56, radius: 8),
              const SizedBox(width: 14),
            ],
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
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
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
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => _play(context, ref),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(
                Icons.play_circle_outline,
                size: 34,
                color: AppTheme.textPrimaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
