part of 'full_screen_player.dart';

// ---------- Tab 1：推荐（相似歌曲 + 热门歌曲） ----------

class _RecommendTab extends ConsumerStatefulWidget {
  const _RecommendTab();

  @override
  ConsumerState<_RecommendTab> createState() => _RecommendTabState();
}

class _RecommendTabState extends ConsumerState<_RecommendTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    final caps = ref.watch(serverAdapterProvider)?.capabilities;
    final canSimilar = caps?.similarSongs ?? false;
    final canBio = (caps?.artistBio ?? false) && song.artistId.isNotEmpty;
    final similar = canSimilar
        ? ref.watch(similarSongsProvider(song.id))
        : null;
    final hot = song.artistId.isEmpty
        ? null
        : ref.watch(hotSongsProvider(song.artistId));
    final bio = canBio ? ref.watch(artistBioProvider(song.artistId)) : null;
    // 歌手简介卡片随封面主色毛玻璃底（底色近实色不透底）
    final bioDominant = ref
        .watch(albumDominantColorProvider(song.albumId))
        .valueOrNull;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (canSimilar) _SongSection(title: '相似歌曲', async: similar),
        if (canBio) _BioSection(async: bio, dominant: bioDominant),
        _SongSection(title: '热门歌曲', async: hot),
      ],
    );
  }
}

/// 歌手简介分区：玻璃卡片承载长文本，默认折叠 3 行，可展开全文。
/// 后端没给简介时整个分区不渲染（§4.1 要求避免空洞的「暂无数据」）。
class _BioSection extends StatefulWidget {
  const _BioSection({required this.async, this.dominant});

  final AsyncValue<String?>? async;

  /// 封面主色（毛玻璃底，与播放页弹层同款）；null 时回落主题表面色
  final Color? dominant;

  @override
  State<_BioSection> createState() => _BioSectionState();
}

class _BioSectionState extends State<_BioSection> {
  bool _expanded = false;

  /// 折叠 3 行的容量上限，超出才给「展开」按钮；按 14sp 中文约 22 字/行估算
  static const _collapsedLimit = 66;

  @override
  Widget build(BuildContext context) {
    final bio = widget.async?.valueOrNull?.trim() ?? '';
    if (bio.isEmpty) return const SizedBox.shrink();
    final overflowed = bio.length > _collapsedLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(30, 8, 0, 12),
          child: Text(
            '歌手简介',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 18, 24),
          child: AlbumFrostedPanel(
            dominant: widget.dominant,
            borderRadius: BorderRadius.circular(AppRadius.m),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.m,
              AppSpacing.m,
              AppSpacing.m,
              AppSpacing.s,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bio,
                  maxLines: _expanded ? null : 3,
                  overflow: _expanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Colors.white70,
                  ),
                ),
                if (overflowed)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(44, 36),
                      ),
                      child: Text(_expanded ? '收起' : '展开全文'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 推荐分区：标题 + 歌曲行列表（对标 1.x recommendSection）
class _SongSection extends StatelessWidget {
  const _SongSection({required this.title, required this.async});

  final String title;
  final AsyncValue<List<Song>>? async;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 8, 0, 12),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        ...switch (async) {
          null => [const SizedBox.shrink()],
          AsyncValue(:final valueOrNull?) =>
            valueOrNull.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.only(left: 30, bottom: 24),
                      child: Text(
                        '暂无数据',
                        style: TextStyle(fontSize: 14, color: Colors.white38),
                      ),
                    ),
                  ]
                : [for (final s in valueOrNull) _SongRow(song: s)],
          _ => const [
            SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ],
        },
      ],
    );
  }
}

/// 歌曲行：封面 44 + 标题/副标题 + playlist-add（对标 1.x songRow）
class _SongRow extends ConsumerWidget {
  const _SongRow({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(playerActionsProvider).play(song),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 0, 18, 14),
        child: Row(
          children: [
            CoverArt(
              albumId: song.albumId,
              size: 44,
              radius: 4,
              localCover: song.localCoverPath,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${song.artist} - ${song.album}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: Colors.white38),
                  ),
                ],
              ),
            ),
            // 下一首播放（设计图行尾 ☰+ 按钮）
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.playlist_add,
                size: 22,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              tooltip: '下一首播放',
              onPressed: () {
                ref.read(playerActionsProvider).playNextInQueue([song]);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已设为下一首播放'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
