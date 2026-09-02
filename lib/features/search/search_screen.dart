import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../shared/cover_art.dart';
import '../auth/auth_controller.dart';
import '../player/player_controller.dart';

/// 搜索关键词（300ms 防抖后由 UI 层更新，对标 1.x SEARCH_DEBOUNCE_MS）
final searchQueryProvider = StateProvider<String>((ref) => '');

/// /search 聚合结果（歌曲/专辑/歌手）
final searchResultProvider = FutureProvider<SearchResult>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const SearchResult();
  return ref.watch(navidromeClientProvider).search(query);
});

/// 搜索页（对标 1.x SearchScreen：歌曲/专辑/歌手三类结果）
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

  // 防抖搜索：停止输入 300ms 后请求（对齐 1.x）
  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      ref.read(searchQueryProvider.notifier).state = '';
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索歌曲 / 专辑 / 歌手',
            border: InputBorder.none,
            isDense: true,
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (_, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        _controller.clear();
                        ref.read(searchQueryProvider.notifier).state = '';
                      },
                    ),
            ),
          ),
        ),
      ),
      body: ref.watch(searchResultProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('搜索失败', style: TextStyle(color: Colors.white38)),
                  TextButton(
                    onPressed: () => ref.invalidate(searchResultProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
            data: (results) {
              final hasQuery = _controller.text.trim().isNotEmpty;
              if (!hasQuery || results.isEmpty) {
                return Center(
                  child: Text(
                    hasQuery ? '未找到相关内容' : '输入关键词开始搜索',
                    style: const TextStyle(color: Colors.white38),
                  ),
                );
              }
              return _ResultList(results: results);
            },
          ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.results});

  final SearchResult results;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        if (results.songs.isNotEmpty)
          _Section(header: '歌曲 (${results.songs.length})', children: [
            for (final song in results.songs)
              _SongRow(song: song),
          ]),
        if (results.albums.isNotEmpty)
          _Section(header: '专辑 (${results.albums.length})', children: [
            for (final album in results.albums) _AlbumRow(album: album),
          ]),
        if (results.artists.isNotEmpty)
          _Section(header: '歌手 (${results.artists.length})', children: [
            for (final artist in results.artists) _ArtistRow(artist: artist),
          ]),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.header, required this.children});

  final String header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            header,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// 歌曲行：点击直接播放（对标 1.x SongRow）
class _SongRow extends ConsumerWidget {
  const _SongRow({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      leading: CoverArt(albumId: song.albumId, size: 48, radius: 8),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '${song.artist} - ${song.album}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white38),
      ),
      trailing: const Icon(Icons.play_circle_outline, size: 26),
      onTap: () => ref.read(playerActionsProvider).play(song),
    );
  }
}

/// 专辑行（对标 1.x AlbumRow，纯展示）
class _AlbumRow extends StatelessWidget {
  const _AlbumRow({required this.album});

  final Album album;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: CoverArt(albumId: album.id, size: 48, radius: 8),
      title: Text(
        album.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        album.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white38),
      ),
    );
  }
}

/// 歌手行（对标 1.x ArtistRow，纯展示）
class _ArtistRow extends StatelessWidget {
  const _ArtistRow({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: CoverArt(albumId: artist.id, size: 48, radius: 24),
      title: Text(
        artist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        '${artist.albumCount} 张专辑 · ${artist.songCount} 首',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white38),
      ),
    );
  }
}
