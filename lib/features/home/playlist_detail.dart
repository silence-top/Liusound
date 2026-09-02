import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/subsonic/subsonic.dart';
import '../auth/auth_controller.dart';
import '../player/mini_player.dart';
import '../player/player_controller.dart';

// 配色（逐项对齐 1.x PlaylistDetail 样式表）
const _bg = Color(0xFF0A1A2A);
const _bar = Color(0xFF222B3A);
const _indexGreen = Color(0xFF3EC06C);
const _formatBorder = Color(0xFF7ECFFF);
const _formatBg = Color(0x593C5078); // rgba(60,80,120,0.35)
const _formatText = Color(0xFFE0F6FF);
const _actionBlue = Color(0xFFB2D7F7);

/// 全屏播放列表详情页（对标 1.x PlaylistDetail，首页「每日推荐 · 查看更多」进入）：
/// 折叠头部（模糊封面背景 + 封面/标题/日期）→ 全部播放栏 → 站内过滤搜索框 → 歌曲列表，
/// 底部保留 MiniPlayer。
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.title,
    required this.songs,
    this.coverAlbumId,
    this.date,
  });

  final String title;
  final List<Song> songs;
  final String? coverAlbumId; // 头部封面（模糊背景与小图共用）
  final String? date; // 头部日期（如每日推荐日期）

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  String _search = '';

  List<Song> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return widget.songs;
    return widget.songs
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            s.artist.toLowerCase().contains(q) ||
            s.album.toLowerCase().contains(q))
        .toList();
  }

  /// 全部播放（对齐 1.x handlePlayAll：清队列 → 入队 → 从第一首开始）
  void _playAll() {
    if (widget.songs.isEmpty) return;
    final actions = ref.read(playerActionsProvider);
    actions.replaceQueue(widget.songs);
    actions.play(widget.songs.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: const MiniPlayer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 260,
            collapsedHeight: 64,
            toolbarHeight: 64,
            backgroundColor: _bg,
            leading: const BackButton(),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              title: Text(
                widget.title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              background: _HeaderBackground(
                auth: ref.watch(subsonicAuthProvider),
                coverAlbumId: widget.coverAlbumId,
                title: widget.title,
                date: widget.date,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: _bar,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Column(
                children: [
                  _PlayAllBar(count: _filtered.length, onPlayAll: _playAll),
                  const Divider(height: 1, color: Color(0x0DFFFFFF)),
                  _FilterBar(onChanged: (v) => setState(() => _search = v)),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: _filtered.length,
            itemBuilder: (context, index) =>
                _SongRow(song: _filtered[index], index: index),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/// 折叠头部背景：模糊封面 + 暗色遮罩 + 居中封面/标题/日期
class _HeaderBackground extends StatelessWidget {
  const _HeaderBackground({
    required this.auth,
    required this.coverAlbumId,
    required this.title,
    required this.date,
  });

  final SubsonicAuth auth;
  final String? coverAlbumId;
  final String title;
  final String? date;

  @override
  Widget build(BuildContext context) {
    final hasCover =
        coverAlbumId != null && coverAlbumId!.isNotEmpty && auth.isValid;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasCover)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: CachedNetworkImage(
              imageUrl: Subsonic.coverArtUrl(auth, coverAlbumId!),
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const ColoredBox(color: _bar),
            ),
          )
        else
          const ColoredBox(color: Color(0xFF10233A)),
        const ColoredBox(color: Color(0xBF0A1428)), // rgba(10,20,40,0.75)
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              if (hasCover)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: Subsonic.coverArtUrl(auth, coverAlbumId!),
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    memCacheWidth: 180,
                    errorWidget: (_, _, _) => const _CoverPlaceholder(),
                  ),
                )
              else
                const _CoverPlaceholder(),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              if (date != null && date!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(date!,
                    style: const TextStyle(
                        color: Color(0xFFBBBBBB), fontSize: 14)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFF1A2C3A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.album, color: Colors.white24, size: 36),
    );
  }
}

/// 全部播放栏（右侧三个功能图标为 1.x 原版装饰位，保留占位）
class _PlayAllBar extends StatelessWidget {
  const _PlayAllBar({required this.count, required this.onPlayAll});

  final int count;
  final VoidCallback onPlayAll;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 18),
          GestureDetector(
            onTap: onPlayAll,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0x2E78B4FF), // rgba(120,180,255,0.18)
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_circle_fill,
                  size: 28, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPlayAll,
            child: Row(
              children: [
                const Text('全部播放',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('（共$count首）',
                    style: const TextStyle(
                        color: Color(0xFFBBBBBB), fontSize: 13)),
              ],
            ),
          ),
          const Spacer(),
          const Icon(Icons.radio_button_checked, size: 22, color: _actionBlue),
          const SizedBox(width: 16),
          const Icon(Icons.queue_music, size: 22, color: _actionBlue),
          const SizedBox(width: 16),
          const Icon(Icons.play_arrow, size: 22, color: _actionBlue),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}

/// 站内过滤搜索框（过滤当前列表，非全局搜索）
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 18),
          const Icon(Icons.search, size: 20, color: Color(0xFF888888)),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: const InputDecoration(
                hintText: '搜索歌曲/专辑/歌手',
                hintStyle: TextStyle(color: Color(0xFFAAAAAA), fontSize: 15),
                border: InputBorder.none,
                filled: false,
                isDense: true,
              ),
            ),
          ),
          const Icon(Icons.filter_list, size: 22, color: Color(0xFF888888)),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}

/// 歌曲行：绿色序号 + 标题 + 码率标签 + 歌手 - 专辑
class _SongRow extends ConsumerWidget {
  const _SongRow({required this.song, required this.index});

  final Song song;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 码率（对齐 1.x：Math.round(size * 8 / duration / 1000)，flac 标签）
    final kbps = song.size > 0 && song.duration > 0
        ? ((song.size * 8) / song.duration / 1000).round()
        : 0;
    return InkWell(
      onTap: () => ref.read(playerActionsProvider).play(song),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _indexGreen,
                    fontSize: 17,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (kbps > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _formatBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _formatBorder),
                          ),
                          child: Text('flac ${kbps}K',
                              style: const TextStyle(
                                  color: _formatText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          '${song.artist} - ${song.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFFB0BAC6), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.more_vert, size: 22, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
