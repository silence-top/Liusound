import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../shared/cover_art.dart';
import '../player/mini_player.dart';
import 'detail_screen.dart';
import 'home_providers.dart';

const _bg = Color(0xFF0A1A2A);

/// 艺人详情页：圆形头像 + 歌手名/统计 → 专辑横向卡片区（跳专辑页）
/// → 热门歌曲列表（复用 SongRow，整表播放）。
/// 数据：GET /api/album?artist_id=（按年降序）、GET /api/song?artist_id=（热门优先）。
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
    final albumsAsync = ref.watch(artistAlbumsProvider(artistId));
    final songsAsync = ref.watch(artistSongsProvider(artistId));
    final albums = albumsAsync.value ?? const <Album>[];
    final songs = songsAsync.value ?? const <Song>[];

    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: const MiniPlayer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            toolbarHeight: 56,
            backgroundColor: _bg,
            leading: const BackButton(),
            title: Text(artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
          SliverToBoxAdapter(
            child: _Header(
              name: artistName,
              artistId: artistId,
              albumCount: albums.length,
              songCount: songs.length,
            ),
          ),
          if (albumsAsync.isLoading && albums.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (albums.isNotEmpty)
            SliverToBoxAdapter(child: _AlbumSection(albums: albums)),
          if (songsAsync.isLoading && songs.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (songsAsync.hasError && songs.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: TextButton(
                    onPressed: () =>
                        ref.invalidate(artistSongsProvider(artistId)),
                    child: const Text('加载失败，点击重试',
                        style: TextStyle(color: Colors.white38)),
                  ),
                ),
              ),
            )
          else if (songs.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(
                  child: Text('暂无歌曲',
                      style: TextStyle(color: Colors.white38, fontSize: 14)),
                ),
              ),
            )
          else ...[
            SliverList.builder(
              itemCount: songs.length,
              itemBuilder: (context, index) =>
                  SongRow(song: songs[index], index: index, songs: songs),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ],
      ),
    );
  }
}

/// 头部：大圆头像 + 歌手名 + 「N 张专辑 · N 首歌曲」（对齐搜索页艺人行格式）
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.artistId,
    required this.albumCount,
    required this.songCount,
  });

  final String name;
  final String artistId;
  final int albumCount;
  final int songCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Row(
        children: [
          CoverArt(albumId: artistId, size: 96, radius: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('$albumCount 张专辑 · $songCount 首歌曲',
                    style:
                        const TextStyle(color: Color(0xFFBBBBBB), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 专辑横向卡片区（跳转专辑详情页，对齐首页专辑卡样式）
class _AlbumSection extends StatelessWidget {
  const _AlbumSection({required this.albums});

  final List<Album> albums;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final album = albums[i];
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AlbumDetailScreen(
                  albumId: album.id,
                  title: album.name,
                  subtitle: '${album.year ?? ''} ${album.artist}'.trim(),
                  rating: album.rating,
                ),
              ),
            ),
            child: SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CoverArt(albumId: album.id, size: 120, radius: 8),
                  const SizedBox(height: 6),
                  Text(album.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                  Text('${album.songCount} 首',
                      style: const TextStyle(
                          color: Color(0xFFB0BAC6), fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
