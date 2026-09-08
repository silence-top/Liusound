import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lpinyin/lpinyin.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/motion.dart';
import 'detail_screen.dart';
import 'home_providers.dart';
import 'music_library_screen.dart';

// ---------- 歌手 / 专辑艺术家（A-Z 分组 + 右侧索引条） ----------

/// 歌手列表二级页（资料库「歌手」/「专辑艺术家」共用）。
/// provider 返回 null 表示后端不支持该能力（入口已被隐藏，兜底空态）。
/// openAlbums 为 true 时（专辑艺术家）行点击进该歌手的专辑列表页，
/// 否则进歌手歌曲列表（歌手）。
class ArtistListPage extends ConsumerWidget {
  const ArtistListPage({
    super.key,
    required this.title,
    required this.provider,
    this.openAlbums = false,
  });

  final String title;
  final FutureProvider<List<Artist>?> provider;
  final bool openAlbums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return Scaffold(
      backgroundColor: AppTheme.detailBgOf(context),
      appBar: AppBar(title: Text(title)),
      body: _ArtistListBody(
        async: async,
        provider: provider,
        openAlbums: openAlbums,
      ),
    );
  }
}

class _ArtistListBody extends ConsumerWidget {
  const _ArtistListBody({
    required this.async,
    required this.provider,
    required this.openAlbums,
  });

  final AsyncValue<List<Artist>?> async;
  final FutureProvider<List<Artist>?> provider;
  final bool openAlbums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = async.value;
    if (artists == null) {
      if (async.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (async.hasError) {
        return errorRetryBox(
          padding: EdgeInsets.zero,
          onRetry: () => ref.invalidate(provider),
        );
      }
      return glassEmptyState(text: '当前服务器不支持该内容', icon: Icons.person_outline);
    }
    if (artists.isEmpty) {
      return glassEmptyState(text: '暂无歌手', icon: Icons.person_outline);
    }
    return _GroupedArtistList(artists: artists, openAlbums: openAlbums);
  }
}

class _LetterGroup {
  const _LetterGroup(this.letter, this.artists);
  final String letter;
  final List<Artist> artists;
}

/// 名称的拼音键（无音调小写；罕见字转换失败时回退原名），
/// 用于分组与排序——中文名按拼音归入 A-Z，而非 Unicode 码点。
String _pinyinKey(String name) {
  if (name.isEmpty) return '';
  try {
    return PinyinHelper.getPinyin(name, separator: ' ').toLowerCase();
  } catch (_) {
    return name.toLowerCase();
  }
}

String _letterOf(String pinyinKey) {
  if (pinyinKey.isEmpty) return '#';
  final f = pinyinKey[0].toUpperCase();
  return RegExp(r'[A-Z]').hasMatch(f) ? f : '#';
}

List<_LetterGroup> _groupArtists(List<Artist> artists) {
  final sorted = [...artists]
    ..sort((a, b) {
      final pa = _pinyinKey(a.name);
      final pb = _pinyinKey(b.name);
      final cmp = pa.compareTo(pb);
      return cmp != 0
          ? cmp
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  final map = <String, List<Artist>>{};
  for (final a in sorted) {
    map.putIfAbsent(_letterOf(_pinyinKey(a.name)), () => []).add(a);
  }
  final letters = map.keys.toList()
    ..sort((a, b) {
      if (a == '#') return 1;
      if (b == '#') return -1;
      return a.compareTo(b);
    });
  return [for (final l in letters) _LetterGroup(l, map[l]!)];
}

const _kHeaderHeight = 32.0;
const _kRowHeight = 64.0;

class _GroupedArtistList extends ConsumerStatefulWidget {
  const _GroupedArtistList({required this.artists, required this.openAlbums});

  final List<Artist> artists;
  final bool openAlbums;

  @override
  ConsumerState<_GroupedArtistList> createState() => _GroupedArtistListState();
}

class _GroupedArtistListState extends ConsumerState<_GroupedArtistList> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Artist> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return widget.artists;
    return widget.artists
        .where(
          (a) =>
              a.name.toLowerCase().contains(q) ||
              _pinyinKey(a.name).contains(q),
        )
        .toList();
  }

  void _jumpTo(int groupIndex, List<_LetterGroup> groups) {
    var offset = 12.0;
    for (var i = 0; i < groupIndex && i < groups.length; i++) {
      offset += _kHeaderHeight + groups[i].artists.length * _kRowHeight;
    }
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupArtists(_filtered);
    final letters = groups.map((g) => g.letter).toList();
    return Column(
      children: [
        ListSearchBar(
          controller: _searchController,
          hint: '搜索歌手',
          onChanged: (v) => setState(() => _search = v),
        ),
        Expanded(
          child: groups.isEmpty
              ? glassEmptyState(text: '没有匹配的歌手', icon: Icons.person_outline)
              : Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(0, 12, 24, 96),
                      itemCount: groups.length,
                      itemBuilder: (context, gi) {
                        final group = groups[gi];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: _kHeaderHeight,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.l,
                              ),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                group.letter,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            for (final artist in group.artists)
                              _ArtistRow(
                                artist: artist,
                                artists: group.artists,
                                onTap: () => Navigator.of(context).push(
                                  fadeRoute<void>(
                                    widget.openAlbums
                                        ? AlbumListPage(
                                            title: artist.name,
                                            provider: artistAlbumsProvider(
                                              artist.id,
                                            ),
                                          )
                                        : SongListScreen(
                                            title: artist.name,
                                            pagedSongsProvider:
                                                artistSongsProvider(artist.id),
                                            coverAlbumId: artist.id,
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    Positioned(
                      right: 2,
                      top: 0,
                      bottom: 96,
                      child: Center(
                        child: _LetterIndexBar(
                          letters: letters,
                          onTap: (i) => _jumpTo(i, groups),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({
    required this.artist,
    required this.artists,
    required this.onTap,
  });

  final Artist artist;
  final List<Artist> artists;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = artist.songCount > 0
        ? '${artist.songCount} 首歌曲'
        : artist.albumCount > 0
        ? '${artist.albumCount} 张专辑'
        : '';
    return InkWell(
      onTap: onTap,
      child: Container(
        height: _kRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 44,
                height: 44,
                child: EntityCover(entityId: artist.id, size: 44, radius: 22),
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textPrimaryOf(context),
                      fontSize: 15,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.textFaintOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterIndexBar extends StatelessWidget {
  const _LetterIndexBar({required this.letters, required this.onTap});

  final List<String> letters;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final box = context.findRenderObject()! as RenderBox;
        final index = (d.localPosition.dy / (box.size.height / letters.length))
            .floor()
            .clamp(0, letters.length - 1);
        onTap(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < letters.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 0.5),
                child: Text(
                  letters[i],
                  style: TextStyle(
                    color: AppTheme.textDimOf(context),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------- 流派 ----------

/// 流派二级页：彩色瓷砖网格（色相由流派名哈希固定映射），点击进流派歌曲列表。
class GenrePage extends ConsumerWidget {
  const GenrePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(genresProvider);
    final genres = async.value;
    Widget body;
    if (genres == null) {
      if (async.isLoading) {
        body = const Center(child: CircularProgressIndicator());
      } else {
        body = glassEmptyState(
          text: async.hasError ? '加载失败，点击重试' : '当前服务器不支持流派',
          icon: Icons.piano_outlined,
        );
      }
    } else if (genres.isEmpty) {
      body = glassEmptyState(text: '暂无流派', icon: Icons.piano_outlined);
    } else {
      body = GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.5,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: genres.length,
        itemBuilder: (context, index) {
          final genre = genres[index];
          final hue = (genre.value.hashCode % 360).abs().toDouble();
          final color = HSLColor.fromAHSL(1, hue, 0.45, 0.42).toColor();
          return FadeSlideIn(
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                fadeRoute<void>(
                  SongListScreen(
                    title: genre.value,
                    songsProvider: genreSongsProvider(genre.value),
                  ),
                ),
              ),
              borderRadius: BorderRadius.circular(AppRadius.m),
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(AppRadius.m),
                ),
                padding: const EdgeInsets.all(AppSpacing.m),
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      genre.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (genre.songCount > 0)
                      Text(
                        '${genre.songCount} 首',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.detailBgOf(context),
      appBar: AppBar(title: const Text('流派')),
      body: body,
    );
  }
}

// ---------- 电台 ----------

/// 电台二级页：不支持 → 提示；支持但为空 → 空态；有数据 → 台站列表。
/// 电台播放需要独立流媒体管线，本期仅展示（对标截图空态）。
class RadioPage extends ConsumerWidget {
  const RadioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(radioStationsProvider);
    final stations = async.value;
    Widget body;
    if (stations == null) {
      if (async.isLoading) {
        body = const Center(child: CircularProgressIndicator());
      } else {
        body = glassEmptyState(
          text: async.hasError ? '加载失败，点击重试' : '当前服务器不支持电台',
          icon: Icons.radio_outlined,
        );
      }
    } else if (stations.isEmpty) {
      body = glassEmptyState(text: '暂无电台', icon: Icons.radio_outlined);
    } else {
      body = ListView.builder(
        itemCount: stations.length,
        itemBuilder: (context, index) {
          final s = stations[index];
          return ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.radio,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            title: Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 15,
              ),
            ),
            subtitle: s.homePageUrl == null
                ? null
                : Text(
                    s.homePageUrl!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textFaintOf(context),
                      fontSize: 12,
                    ),
                  ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.detailBgOf(context),
      appBar: AppBar(title: const Text('电台')),
      body: body,
    );
  }
}
