import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../auth/auth_controller.dart';
import '../player/mini_player.dart';
import '../player/player_controller.dart';
import 'detail_screen.dart';
import 'home_providers.dart';

/// 负一屏音乐库（设计图「负一屏」）：
/// 服务器卡片（Navidrome / 主线路 / 歌曲总数）
/// → 四入口（歌曲 / 我喜欢的 / 本地音乐 / 专辑）
/// → 我的歌单列表（点击进歌单详情，三点菜单支持播放/加入队列）。
class MusicLibraryScreen extends ConsumerWidget {
  const MusicLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(songTotalProvider);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 96),
        children: [
          _ServerCard(total: total.value ?? 0),
          _EntryGrid(
            onSongs: () => _openSongs(
                context, '歌曲', librarySongsProvider),
            onLiked: () => _openSongs(
                context, '我喜欢的', likedSongsProvider),
            onLocal: () => _openSongs(
                context, '本地音乐', librarySongsProvider),
            onAlbums: () => _openAlbums(context),
          ),
          const SizedBox(height: 20),
          const _PlaylistSection(),
        ],
      ),
    );
  }

  void _openSongs(
      BuildContext context, String title, FutureProvider<List<Song>> provider) {
    Navigator.of(context).push(
      fadeRoute<void>(
        SongListPage(title: title, provider: provider),
      ),
    );
  }

  void _openAlbums(BuildContext context) {
    Navigator.of(context).push(
      fadeRoute<void>(
        AlbumListPage(title: '专辑', provider: libraryAlbumsProvider),
      ),
    );
  }
}

/// 服务器卡片：后端图标 + 服务器名 + 类型/账号 + 歌曲总数
/// 标题与副标题读自当前激活服务器，六种后端各自正确显示（不再硬编码 Navidrome）
class _ServerCard extends ConsumerWidget {
  const _ServerCard({required this.total});

  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(authControllerProvider).activeConfig;
    final type = config?.type;
    return GlassContainer(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.s),
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadius.m),
            ),
            child: Icon(type?.fallbackIcon ?? Icons.album,
                color: AppTheme.primary, size: 26),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(config?.name ?? '未连接服务器',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                    type == null
                        ? '点击设置添加服务器'
                        : '${type.displayName} · ${config!.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('歌曲总数',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 2),
              Text('$total',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 19,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 四入口：歌曲 / 我喜欢的 / 本地音乐 / 专辑
class _EntryGrid extends StatelessWidget {
  const _EntryGrid({
    required this.onSongs,
    required this.onLiked,
    required this.onLocal,
    required this.onAlbums,
  });

  final VoidCallback onSongs;
  final VoidCallback onLiked;
  final VoidCallback onLocal;
  final VoidCallback onAlbums;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _Entry(Icons.music_note, '歌曲', onSongs),
          _Entry(Icons.favorite, '我喜欢的', onLiked),
          _Entry(Icons.smartphone, '本地音乐', onLocal),
          _Entry(Icons.album, '专辑', onAlbums),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassCard(
        onTap: onTap,
        radius: AppRadius.m,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
        child: Column(
          children: [
            Icon(icon, size: 24, color: AppTheme.primary),
            const SizedBox(height: AppSpacing.xs),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// 我的歌单：标题 + 歌单列表（封面 + 名称 + N 首歌曲 + 三点菜单）
class _PlaylistSection extends ConsumerWidget {
  const _PlaylistSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('我的歌单',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
        ),
        playlists.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: TextButton(
                onPressed: () => ref.invalidate(playlistsProvider),
                child: const Text('加载失败，点击重试',
                    style: TextStyle(color: Colors.white38)),
              ),
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return glassEmptyState(
                text: '还没有歌单\n在服务端创建或重新同步后会显示在这里',
                icon: Icons.queue_music_outlined,
                padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xl, horizontal: AppSpacing.l),
                actions: [
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(playlistsProvider),
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('重新同步'),
                  ),
                ],
              );
            }
            return GlassCard(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children:
                    list.map((p) => _PlaylistRow(playlist: p, ref: ref)).toList(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, required this.ref});

  final Playlist playlist;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final adapter = ProviderScope.containerOf(context).read(serverAdapterProvider);
    final hasCover =
        playlist.coverArt != null && playlist.coverArt!.isNotEmpty && adapter != null;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        fadeRoute<void>(
          PlaylistDetailScreen(
            playlistId: playlist.id,
            title: playlist.name,
            coverAlbumId: playlist.coverArt,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            hasCover
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CoverArt(
                      albumId: playlist.coverArt!,
                      size: 52,
                      radius: 8,
                    ),
                  )
                : Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.queue_music,
                        color: Colors.white24, size: 26),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('${playlist.songCount} 首歌曲',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onSelected: (action) =>
                  _onMenuAction(context, action),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'play', child: Text('播放')),
                PopupMenuItem(value: 'queue', child: Text('加入队列')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenuAction(BuildContext context, String action) async {
    final navigator = ScaffoldMessenger.of(context);
    final adapter = ref.read(serverAdapterProvider);
    if (adapter == null) return;
    final songs = await adapter.fetchPlaylistSongs(playlist.id);
    if (songs.isEmpty) {
      navigator.showSnackBar(const SnackBar(content: Text('歌单暂无歌曲')));
      return;
    }
    final actions = ref.read(playerActionsProvider);
    if (action == 'play') {
      actions.replaceQueue(songs);
      await actions.play(songs.first);
    } else {
      actions.addToQueue(songs);
      navigator.showSnackBar(
        SnackBar(content: Text('已将 ${songs.length} 首歌曲加入队列')),
      );
    }
  }
}

// ---------- 二级页 ----------

/// 通用歌曲列表二级页（歌曲 / 我喜欢的 / 本地音乐入口共用）。
/// 行为与详情页一致：点击播放整表替换队列，三点打开歌曲操作弹窗。
class SongListPage extends ConsumerWidget {
  const SongListPage({super.key, required this.title, required this.provider});

  final String title;
  final FutureProvider<List<Song>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return Scaffold(
      backgroundColor: AppTheme.detailBg,
      appBar: AppBar(title: Text(title)), // 样式走主题 titleTextStyle
      bottomNavigationBar: const MiniPlayer(),
      body: _SongListBody(async: async, provider: provider),
    );
  }
}

class _SongListBody extends ConsumerWidget {
  const _SongListBody({required this.async, required this.provider});

  final AsyncValue<List<Song>> async;
  final FutureProvider<List<Song>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncStateBox<Song>(
      async: async,
      emptyText: '暂无歌曲',
      onRetry: () => ref.invalidate(provider),
      onData: (songs) => ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) => FadeSlideIn(
          child: SongRow(song: songs[index], index: index, songs: songs),
        ),
      ),
    );
  }
}

/// 专辑列表二级页（2 列网格封面）
class AlbumListPage extends ConsumerWidget {
  const AlbumListPage({super.key, required this.title, required this.provider});

  final String title;
  final FutureProvider<List<Album>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return Scaffold(
      backgroundColor: AppTheme.detailBg,
      appBar: AppBar(title: Text(title)), // 样式走主题 titleTextStyle
      body: _AlbumGridBody(async: async, provider: provider),
    );
  }
}

class _AlbumGridBody extends ConsumerWidget {
  const _AlbumGridBody({required this.async, required this.provider});

  final AsyncValue<List<Album>> async;
  final FutureProvider<List<Album>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return asyncStateBox<Album>(
      async: async,
      emptyText: '暂无专辑',
      onRetry: () => ref.invalidate(provider),
      onData: (albums) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.92,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return FadeSlideIn(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CoverArt(albumId: album.id, size: 170, radius: 10),
                  const SizedBox(height: 6),
                  Text(album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
