import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/local/local_library.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/album_card.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/list_end_mark.dart';
import '../../shared/widgets/motion.dart';
import '../auth/auth_controller.dart';
import '../player/mini_player.dart';
import '../player/player_controller.dart';
import '../search/search_screen.dart';
import 'detail_screen.dart';
import 'home_providers.dart';
import 'library_entries_screen.dart';
import 'server_detail_screen.dart';

/// 负一屏音乐库（对齐设计图「资料库」）：
/// 搜索栏 → 服务器大卡片（类型名 + 别名/歌曲数，内嵌八入口可折叠，点头像进服务器详情）
/// → 歌单列表（我的/全部切换，点击进歌单详情，三点菜单支持播放/加入队列）。
class MusicLibraryScreen extends ConsumerWidget {
  const MusicLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(songTotalProvider);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        children: [
          const _SearchBar(),
          _ServerPanel(total: total.value ?? 0),
          const SizedBox(height: 20),
          const _PlaylistSection(),
        ],
      ),
    );
  }
}

/// 顶部搜索栏：圆角半透明条 + 扫码图标，点击进搜索页
class _SearchBar extends ConsumerWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () =>
          Navigator.of(context).push(fadeRoute<void>(const SearchScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 22, color: Colors.white54),
            const SizedBox(width: 10),
            const Text(
              '搜索',
              style: TextStyle(color: Colors.white38, fontSize: 15),
            ),
            const Spacer(),
            Icon(
              Icons.qr_code_scanner,
              size: 22,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// 服务器大卡片（设计图）：头部（后端 Logo + 类型名 + 「别名 · 歌曲数」副行，
/// 点击进服务器详情页）→ 分隔线 → 内嵌八入口网格（可折叠）→ 底部折叠箭头。
class _ServerPanel extends ConsumerStatefulWidget {
  const _ServerPanel({required this.total});

  final int total;

  @override
  ConsumerState<_ServerPanel> createState() => _ServerPanelState();
}

class _ServerPanelState extends ConsumerState<_ServerPanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(authControllerProvider).activeConfig;
    final type = config?.type;
    final primary = Theme.of(context).colorScheme.primary;
    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: config == null
                ? null
                : () =>
                      Navigator.of(context)
                          .push(fadeRoute<void>(ServerDetailScreen())),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.l),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  if (type != null && type.hasLogoAsset)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.m),
                      child: Image.asset(type.iconAsset, width: 44, height: 44),
                    )
                  else
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(AppRadius.m),
                      ),
                      child: Icon(
                        type?.fallbackIcon ?? Icons.album,
                        color: primary,
                        size: 26,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type?.displayName ?? '未连接服务器',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.alt_route,
                              size: 13,
                              color: Colors.white38,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                config?.name ?? '点击设置添加服务器',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.music_note,
                              size: 13,
                              color: Colors.white38,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.total}',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          // 入口网格可折叠：收起时高度压缩为 0，箭头随状态翻转
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              heightFactor: _expanded ? 1 : 0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: const _EntryGrid(),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: SizedBox(
              height: 30,
              width: double.infinity,
              child: Icon(
                _expanded
                    ? Icons.keyboard_double_arrow_up
                    : Icons.keyboard_double_arrow_down,
                size: 20,
                color: Colors.white38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 八入口：歌曲 / 我喜欢的 / 本地音乐 / 专辑 + 专辑艺术家 / 歌手 / 流派 / 电台。
/// 后四项按后端能力显隐：provider 返回 null（不支持）时入口隐藏；
/// 加载中先隐藏避免闪烁，加载完成支持则出现。
class _EntryGrid extends ConsumerWidget {
  const _EntryGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    final albumArtists = ref.watch(albumArtistsProvider);
    final genres = ref.watch(genresProvider);
    final radios = ref.watch(radioStationsProvider);
    final extras = <Widget>[
      if (albumArtists.valueOrNull != null)
        _Entry(
          Icons.theaters,
          '专辑艺术家',
          () => _openArtists(context, '专辑艺术家', albumArtistsProvider),
        ),
      if (artists.valueOrNull != null)
        _Entry(
          Icons.person,
          '歌手',
          () => _openArtists(context, '歌手', artistsProvider),
        ),
      if (genres.valueOrNull != null)
        _Entry(
          Icons.piano,
          '流派',
          () => Navigator.of(context).push(fadeRoute<void>(const GenrePage())),
        ),
      if (radios.valueOrNull != null)
        _Entry(
          Icons.radio,
          '电台',
          () => Navigator.of(context).push(fadeRoute<void>(const RadioPage())),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              _Entry(
                Icons.music_note,
                '歌曲',
                () => _openSongs(context, '歌曲', librarySongsProvider),
              ),
              _Entry(
                Icons.favorite,
                '我喜欢的',
                () => _openSongs(context, '我喜欢的', likedSongsProvider),
              ),
              _Entry(
                Icons.smartphone,
                '本地音乐',
                () => _openSongs(context, '本地音乐', localSongsProvider),
              ),
              _Entry(Icons.album, '专辑', () => _openAlbums(context)),
            ],
          ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(children: [for (final e in extras) Expanded(child: e)]),
          ],
        ],
      ),
    );
  }

  void _openSongs(
    BuildContext context,
    String title,
    FutureProvider<List<Song>> provider,
  ) {
    Navigator.of(context)
        .push(fadeRoute<void>(SongListPage(title: title, provider: provider)));
  }

  void _openArtists(
    BuildContext context,
    String title,
    FutureProvider<List<Artist>?> provider,
  ) {
    Navigator.of(
      context,
    ).push(fadeRoute<void>(ArtistListPage(title: title, provider: provider)));
  }

  void _openAlbums(BuildContext context) {
    Navigator.of(context).push(
      fadeRoute<void>(
        AlbumListPage(title: '专辑', provider: libraryAlbumsProvider),
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
            Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌单区：标题旁三角图标切换「我的歌单 / 全部歌单」（owner 匹配当前用户名）；
/// 后端不提供 owner（全部为空）时两份列表一致，切换图标隐藏。
class _PlaylistSection extends ConsumerStatefulWidget {
  const _PlaylistSection();

  @override
  ConsumerState<_PlaylistSection> createState() => _PlaylistSectionState();
}

class _PlaylistSectionState extends ConsumerState<_PlaylistSection> {
  bool _all = false; // false = 我的歌单，true = 全部歌单

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    final username = ref
        .watch(authControllerProvider)
        .activeConfig
        ?.username
        .toLowerCase();
    return playlists.when(
      loading: () => _header(context, null, const [], username),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: TextButton(
            onPressed: () => ref.invalidate(playlistsProvider),
            child: const Text(
              '加载失败，点击重试',
              style: TextStyle(color: Colors.white38),
            ),
          ),
        ),
      ),
      data: (list) => _header(context, list, list, username),
    );
  }

  Widget _header(
    BuildContext context,
    List<Playlist>? asyncList,
    List<Playlist> all,
    String? username,
  ) {
    final hasOwnerInfo = all.any((p) => p.owner?.isNotEmpty == true);
    // 后端没返回 owner（或未登录）时无法区分归属，「我的歌单」回退为全部，
    // 避免过滤出空列表导致整个歌单区看起来消失
    final mine = username == null || !hasOwnerInfo
        ? all
        : all
              .where(
                (p) => p.owner != null && p.owner!.toLowerCase() == username,
              )
              .toList();
    // 只有 owner 信息能区分两份列表时才显示切换
    final canToggle = hasOwnerInfo && mine.length != all.length;
    final list = _all ? all : mine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
          child: Row(
            children: [
              Text(
                _all ? '全部歌单' : '我的歌单',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (canToggle)
                GestureDetector(
                  onTap: () => setState(() => _all = !_all),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
                    child: Icon(
                      _all ? Icons.arrow_right : Icons.arrow_left,
                      size: 22,
                      color: Colors.white54,
                    ),
                  ),
                ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, color: Colors.white54),
                onSelected: (action) {
                  if (action == 'create') {
                    glassDialog<void>(
                      context,
                      title: '新建歌单',
                      content: const _CreatePlaylistForm(),
                    );
                  } else if (action == 'sync') {
                    ref.invalidate(playlistsProvider);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'create',
                    child: Row(
                      children: [
                        Icon(Icons.playlist_add, size: 18),
                        SizedBox(width: 8),
                        Text('新建歌单'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'sync',
                    child: Row(
                      children: [
                        Icon(Icons.sync, size: 18),
                        SizedBox(width: 8),
                        Text('重新同步'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (asyncList == null)
          const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          )
        else
          _buildList(context, list, mine),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    List<Playlist> list,
    List<Playlist> mine,
  ) {
    if (list.isEmpty) {
      // 我的歌单为空但服务器有歌单 → 引导切换查看；否则走新建/同步引导
      final guideSwitch = !_all && mine.isEmpty;
      return glassEmptyState(
        text: guideSwitch ? '没有你的歌单\n点击标题旁箭头查看全部歌单' : '还没有歌单\n新建一个，或从服务器重新同步',
        icon: Icons.queue_music_outlined,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xl,
          horizontal: AppSpacing.l,
        ),
        actions: guideSwitch
            ? const <Widget>[]
            : <Widget>[
                FilledButton.icon(
                  onPressed: () => glassDialog<void>(
                    context,
                    title: '新建歌单',
                    content: const _CreatePlaylistForm(),
                  ),
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: const Text('新建歌单'),
                ),
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
        children: list.map((p) => _PlaylistRow(playlist: p, ref: ref)).toList(),
      ),
    );
  }
}

/// 新建歌单表单（§7.2 空态引导），作为 glassDialog 的 content 使用。
///
/// 做成 StatefulWidget 是为了自己持有并释放 TextEditingController：
/// 弹窗 pop 之后路由还要放退场动画，控制器若在外部提前 dispose，
/// 会和 EditableText 的焦点回调撞在一起，退场途中直接报错。
class _CreatePlaylistForm extends ConsumerStatefulWidget {
  const _CreatePlaylistForm();

  @override
  ConsumerState<_CreatePlaylistForm> createState() =>
      _CreatePlaylistFormState();
}

class _CreatePlaylistFormState extends ConsumerState<_CreatePlaylistForm> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _busy) return;
    final adapter = ref.read(serverAdapterProvider);
    // 成功路径要先 pop 再提示，Messenger 必须在 pop 之前取到
    final messenger = ScaffoldMessenger.of(context);
    if (adapter == null) {
      setState(() => _error = '未登录，无法新建歌单');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await adapter.createPlaylist(name);
    if (!mounted) return;
    if (!ok) {
      // 失败留在弹窗内用行内文字提示：SnackBar 挂在 Scaffold 上，
      // 会被弹窗遮罩压住，用户看不见
      setState(() {
        _busy = false;
        _error = '创建失败，请确认服务器允许写入';
      });
      return;
    }
    ref.invalidate(playlistsProvider);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('已创建歌单「$name」'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: const InputDecoration(hintText: '歌单名称'),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            _error!,
            style: const TextStyle(color: AppTheme.heartRed, fontSize: 13),
          ),
        ],
        const SizedBox(height: AppSpacing.m),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: AppSpacing.s),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '创建中…' : '创建'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 歌单封面：优先用前 4 首歌的去重专辑封面拼 2×2（对齐设计图）；
/// 不足 2 张时回退歌单自带封面 / 占位图标。
class _PlaylistCover extends ConsumerWidget {
  const _PlaylistCover({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final covers = ref.watch(playlistCoverIdsProvider(playlist.id));
    return covers.when(
      loading: () => _fallback(context),
      error: (_, _) => _fallback(context),
      data: (ids) {
        if (ids.length >= 2) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Column(
                children: [
                  for (var r = 0; r < 2; r++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var c = 0; c < 2; c++)
                            Expanded(
                              // 不足 4 张时循环复用已有封面补位
                              child: CoverArt(
                                albumId: ids[(r * 2 + c) % ids.length],
                                size: 26,
                                radius: 0,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        if (ids.length == 1) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CoverArt(albumId: ids.first, size: 52, radius: 8),
          );
        }
        return _fallback(context);
      },
    );
  }

  Widget _fallback(BuildContext context) {
    final adapter = ProviderScope.containerOf(context)
        .read(serverAdapterProvider);
    final hasCover =
        playlist.coverArt != null &&
        playlist.coverArt!.isNotEmpty &&
        adapter != null;
    if (hasCover) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CoverArt(albumId: playlist.coverArt!, size: 52, radius: 8),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.queue_music, color: Colors.white24, size: 26),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, required this.ref});

  final Playlist playlist;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
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
            _PlaylistCover(playlist: playlist),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlist.songCount} 首歌曲',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onSelected: (action) => _onMenuAction(context, action),
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
      backgroundColor: AppTheme.detailBgOf(context),
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
        itemCount: songs.length + 1,
        itemBuilder: (context, index) {
          if (index == songs.length) return ListEndMark(songs: songs);
          return FadeSlideIn(
            child: SongRow(song: songs[index], index: index, songs: songs),
          );
        },
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
      backgroundColor: AppTheme.detailBgOf(context),
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
            child: AlbumCard(
              album: album,
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
            ),
          );
        },
      ),
    );
  }
}
