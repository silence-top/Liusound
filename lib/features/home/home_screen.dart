import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion_tokens.dart';
import '../../core/theme/skin_tokens.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../../shared/widgets/search_entry.dart';
import '../fm/fm_screen.dart';
import '../player/action_sheets.dart';
import '../player/full_screen_player.dart';
import '../player/player_controller.dart';
import '../search/search_screen.dart';
import 'detail_screen.dart';
import 'home_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.read(randomSeedProvider.notifier).state = makeSeed();
    await Future.wait([
      ref.read(latestAlbumsProvider.notifier).refresh(),
      ref.read(recentlyPlayedSongsProvider.notifier).refresh(),
      ref.read(mostPlayedSongsProvider.notifier).refresh(),
      ref.read(randomAlbumsProvider.notifier).refresh(),
      ref.read(dailySongsProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          key: const PageStorageKey('home-discovery'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SearchEntryBar(
                onTap: () =>
                    Navigator.of(context)
                        .push(fadeRoute<void>(const SearchScreen())),
              ),
            ),
            const SliverToBoxAdapter(child: _FmEntry()),
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
            const SliverToBoxAdapter(child: _ListeningHistory()),
            SliverToBoxAdapter(
              child: _Section(
                title: '随机专辑',
                child: _AlbumRow(randomAlbumsProvider),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: AppSpacing.huge + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FmEntry extends StatelessWidget {
  const _FmEntry();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SkinTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: FadeSlideIn(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.s),
          onTap: () =>
              Navigator.of(context).push(fadeRoute<void>(const FmScreen())),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.xxxl),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.xxl,
                  height: AppSpacing.xxl,
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(
                      AppRadius.s * tokens.radiusScale,
                    ),
                  ),
                  child: Icon(
                    Icons.radio_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Text('私人 FM', style: theme.textTheme.titleSmall),
                ),
                Icon(Icons.chevron_right, color: AppTheme.textDimOf(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.heading,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final Widget? heading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSpacing.xxxl),
              child: Row(
                children: [
                  Expanded(
                    child:
                        heading ??
                        Wrap(
                          spacing: AppSpacing.m,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(title, style: text.titleMedium),
                            ),
                            if (subtitle != null)
                              Text(subtitle!, style: text.bodySmall),
                          ],
                        ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          child,
        ],
      ),
    );
  }
}

class _AlbumRow extends ConsumerWidget {
  const _AlbumRow(this.provider);

  final HomeSectionProvider<Album> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(provider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = (constraints.maxWidth * 0.32).clamp(104.0, 148.0);
        final scaler = MediaQuery.textScalerOf(context);
        final text = Theme.of(context).textTheme;
        final height =
            size +
            (scaler.scale(text.labelLarge!.fontSize!) * 2.8).ceilToDouble() +
            (scaler.scale(text.bodySmall!.fontSize!) * 1.4).ceilToDouble() +
            AppSpacing.m;
        return albums.when(
          loading: () => SizedBox(
            height: height,
            child: const Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              errorRetryBox(onRetry: () => ref.invalidate(provider)),
          data: (list) {
            if (list.isEmpty) {
              return glassEmptyState(
                text: '暂无专辑',
                icon: Icons.album_outlined,
                actions: [
                  TextButton.icon(
                    onPressed: () => ref.invalidate(provider),
                    icon: const Icon(Icons.sync),
                    label: const Text('重新同步'),
                  ),
                ],
              );
            }
            return SizedBox(
              height: height,
              child: ListView.builder(
                key: PageStorageKey(provider),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                itemCount: list.length,
                itemExtent: size + AppSpacing.l,
                itemBuilder: (context, index) => FadeSlideIn(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.l),
                    child: _HomeCoverCard(
                      albumId: list[index].id,
                      title: list[index].name,
                      subtitle: list[index].artist,
                      size: size,
                      onTap: () {
                        final album = list[index];
                        Navigator.of(context).push(
                          fadeRoute<void>(
                            SongListScreen(
                              rateTargetId: album.id,
                              songsProvider: albumSongsProvider(album.id),
                              title: album.name,
                              subtitle: '${album.year ?? ''} ${album.artist}'
                                  .trim(),
                              rating: album.rating,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _HomeCoverCard extends StatelessWidget {
  const _HomeCoverCard({
    required this.albumId,
    required this.title,
    required this.subtitle,
    required this.size,
    required this.onTap,
    this.onLongPress,
    this.localCover,
  });

  final String albumId;
  final String title;
  final String subtitle;
  final double size;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    final tokens = SkinTokens.of(context);
    final text = Theme.of(context).textTheme;
    return PressableScale(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                AppRadius.m * tokens.radiusScale,
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.shadowColor,
                  blurRadius: AppSpacing.l,
                  offset: const Offset(0, AppSpacing.xs),
                ),
              ],
            ),
            child: CoverArt(
              albumId: albumId,
              localCover: localCover,
              size: size,
              radius: AppRadius.m * tokens.radiusScale,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            height:
                (MediaQuery.textScalerOf(context)
                            .scale(text.labelLarge!.fontSize!) *
                        2.8)
                    .ceilToDouble(),
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge?.copyWith(height: 1.4),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ListeningHistory extends StatefulWidget {
  const _ListeningHistory();

  @override
  State<_ListeningHistory> createState() => _ListeningHistoryState();
}

class _ListeningHistoryState extends State<_ListeningHistory> {
  bool _mostPlayed = false;

  @override
  Widget build(BuildContext context) {
    final titles = ['最近播放', '最常播放'];
    return _SongListSection(
      title: titles[_mostPlayed ? 1 : 0],
      horizontalCovers: true,
      provider: _mostPlayed
          ? mostPlayedSongsProvider
          : recentlyPlayedSongsProvider,
      heading: Wrap(
        spacing: AppSpacing.m,
        children: [
          for (var i = 0; i < titles.length; i++)
            Semantics(
              selected: _mostPlayed == (i == 1),
              child: InkWell(
                onTap: () => setState(() => _mostPlayed = i == 1),
                borderRadius: BorderRadius.circular(AppRadius.s),
                child: AnimatedContainer(
                  duration: AppMotion.duration(
                    context,
                    MotionTokens.durationSnappy,
                  ),
                  constraints: const BoxConstraints(minHeight: AppSpacing.xxxl),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 2,
                        color: _mostPlayed == (i == 1)
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    titles[i],
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _mostPlayed == (i == 1)
                          ? AppTheme.textPrimaryOf(context)
                          : AppTheme.textDimOf(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SongListSection extends ConsumerWidget {
  const _SongListSection({
    required this.title,
    required this.provider,
    this.withDate = false,
    this.horizontalCovers = false,
    this.heading,
  });

  final String title;
  final HomeSectionProvider<Song> provider;
  final bool withDate;
  final bool horizontalCovers;
  final Widget? heading;

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
    final list = songs.valueOrNull;
    final today = DateTime.now();
    return _Section(
      title: title,
      heading: heading,
      subtitle: withDate ? '${today.month} 月 ${today.day} 日' : null,
      trailing: IconButton(
        tooltip: '查看全部$title',
        onPressed: list == null || list.isEmpty
            ? null
            : () => _openDetail(context, list),
        icon: Icon(
          Icons.arrow_forward_rounded,
          color: AppTheme.textDimOf(context),
        ),
      ),
      child: songs.when(
        loading: () => const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => errorRetryBox(onRetry: () => ref.invalidate(provider)),
        data: (items) {
          if (items.isEmpty) {
            return glassEmptyState(text: '$title暂无内容');
          }
          if (horizontalCovers) {
            return _SongCoverRow(provider: provider, songs: items);
          }
          return GlassCard(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < items.length && i < 3; i++)
                  _SongCardRow(song: items[i], queue: items),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SongCoverRow extends ConsumerWidget {
  const _SongCoverRow({required this.provider, required this.songs});

  final HomeSectionProvider<Song> provider;
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = (constraints.maxWidth * 0.32).clamp(104.0, 148.0);
        final scaler = MediaQuery.textScalerOf(context);
        final text = Theme.of(context).textTheme;
        final height =
            size +
            (scaler.scale(text.labelLarge!.fontSize!) * 2.8).ceilToDouble() +
            (scaler.scale(text.bodySmall!.fontSize!) * 1.4).ceilToDouble() +
            AppSpacing.m;
        return SizedBox(
          height: height,
          child: ListView.builder(
            key: PageStorageKey(provider),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            itemCount: songs.length,
            itemExtent: size + AppSpacing.l,
            itemBuilder: (context, index) {
              final song = songs[index];
              return FadeSlideIn(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.l),
                  child: _HomeCoverCard(
                    albumId: song.albumId,
                    localCover: song.localCoverPath,
                    title: song.title,
                    subtitle: song.artist,
                    size: size,
                    onTap: () {
                      final actions = ref.read(playerActionsProvider);
                      actions.replaceQueue(songs);
                      actions.play(song);
                      if (ref.read(autoOpenPlayerProvider)) {
                        openFullScreenPlayer(context);
                      }
                    },
                    onLongPress: () => showSongActionSheet(context, song),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SongCardRow extends ConsumerWidget {
  const _SongCardRow({required this.song, required this.queue});

  final Song song;
  final List<Song> queue;

  void _play(BuildContext context, WidgetRef ref) {
    final actions = ref.read(playerActionsProvider);
    actions.replaceQueue(queue);
    actions.play(song);
    if (ref.read(autoOpenPlayerProvider)) openFullScreenPlayer(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.m),
      onTap: () => _play(context, ref),
      onLongPress: () => showSongActionSheet(context, song),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s),
        child: Row(
          children: [
            CoverArt(albumId: song.albumId, size: 52, radius: AppRadius.s),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${song.artist} · ${song.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
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
