import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/glass.dart';
import 'stats_providers.dart';

/// 听歌统计：概览四项 + 最常听歌曲 + 最爱歌手（本地播放历史，
/// 与当前服务器绑定）。规范推入页形态，随皮肤/主题联动
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(statsSummaryProvider);
    ref.invalidate(statsTopSongsProvider);
    ref.invalidate(statsTopArtistsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dim = AppTheme.textDimOf(context);
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                toolbarHeight: 56,
                backgroundColor: Colors.transparent,
                foregroundColor: AppTheme.textPrimaryOf(context),
                title: const Text('听歌统计'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const _SummaryGrid(),
                    const SizedBox(height: 28),
                    Text(
                      '最常听的歌曲',
                      style: TextStyle(
                        color: AppTheme.textPrimaryOf(context),
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const _TopSongs(),
                    const SizedBox(height: 28),
                    Text(
                      '最爱歌手',
                      style: TextStyle(
                        color: AppTheme.textPrimaryOf(context),
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const _TopArtists(),
                    const SizedBox(height: 12),
                    Text(
                      '统计来自本机播放记录，仅计当前服务器',
                      style: TextStyle(color: dim, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 概览四项（2×2 裸排）：总播放 / 总时长 / 听过歌曲 / 近30天
class _SummaryGrid extends ConsumerWidget {
  const _SummaryGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(statsSummaryProvider);
    return summary.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) =>
          errorRetryBox(onRetry: () => ref.invalidate(statsSummaryProvider)),
      data: (s) {
        if (s == null) {
          return glassEmptyState(text: '未连接服务器', icon: Icons.insights);
        }
        if (s.totalPlays == 0) {
          return glassEmptyState(
            text: '还没有播放记录\n去听几首歌再来吧',
            icon: Icons.insights,
          );
        }
        const labels = ['总播放', '收听时长', '听过歌曲', '近30天播放'];
        final minutes = s.totalDurationMs ~/ 60000;
        final values = [
          '${s.totalPlays}',
          minutes >= 60 ? '${minutes ~/ 60} 时 ${minutes % 60} 分' : '$minutes 分',
          '${s.uniqueSongs}',
          '${s.plays30d}',
        ];
        final cells = <Widget>[];
        for (var i = 0; i < 4; i++) {
          cells.add(
            Column(
              children: [
                Text(
                  values[i],
                  style: TextStyle(
                    color: AppTheme.textPrimaryOf(context),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: TextStyle(
                    color: AppTheme.textFaintOf(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  for (var i = 0; i < 2; i++) Expanded(child: cells[i]),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  for (var i = 2; i < 4; i++) Expanded(child: cells[i]),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 最常听歌曲列表：序号 + 封面 + 标题/歌手 + 播放次数
class _TopSongs extends ConsumerWidget {
  const _TopSongs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(statsTopSongsProvider);
    return rows.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) =>
          errorRetryBox(onRetry: () => ref.invalidate(statsTopSongsProvider)),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (var i = 0; i < list.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: i < 3
                              ? Theme.of(context).colorScheme.primary
                              : AppTheme.textFaintOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CoverArt(albumId: list[i].albumId, size: 44, radius: 6),
                  ],
                ),
                title: Text(
                  list[i].title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimaryOf(context),
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  list[i].artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textDimOf(context),
                    fontSize: 13,
                  ),
                ),
                trailing: Text(
                  '${list[i].plays} 次',
                  style: TextStyle(
                    color: AppTheme.textFaintOf(context),
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 最爱歌手：名称 + 播放次数
class _TopArtists extends ConsumerWidget {
  const _TopArtists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(statsTopArtistsProvider);
    return rows.when(
      loading: () => const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) =>
          errorRetryBox(onRetry: () => ref.invalidate(statsTopArtistsProvider)),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final r in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.18),
                  child: Icon(
                    Icons.person,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                title: Text(
                  r.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimaryOf(context),
                    fontSize: 15,
                  ),
                ),
                trailing: Text(
                  '${r.plays} 次',
                  style: TextStyle(
                    color: AppTheme.textFaintOf(context),
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
