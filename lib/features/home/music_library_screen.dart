import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/local/local_library.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/settings_prefs.dart';
import '../../core/theme/skin_tokens.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/album_card.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/marquee_text.dart';
import '../../shared/widgets/motion.dart';
import '../../shared/widgets/search_entry.dart';
import '../../shared/widgets/toast.dart';
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
      // 嵌套在壳层 AmbientBackground 之内：透明底让自定义背景图/皮肤舞台透出
      backgroundColor: Colors.transparent,
      body: ListView(
        // 底部：96 设计留白 + 悬浮迷你条占位（壳层经 MediaQuery 注入）
        padding: EdgeInsets.only(
          top: 4,
          bottom: 96 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          SearchEntryBar(
            onTap: () =>
                Navigator.of(context)
                    .push(fadeRoute<void>(const SearchScreen())),
          ),
          _ServerPanel(total: total.value ?? 0),
          const SizedBox(height: 20),
          const _PlaylistSection(),
        ],
      ),
    );
  }
}

/// 服务器区（裸排）：头部（后端 Logo + 类型名 + 「别名 · 歌曲数」副行，
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
    final cardsOn = ref.watch(cardDisplayProvider);
    final content = Column(
      children: [
        InkWell(
          onTap: config == null
              ? null
              : () =>
                    Navigator.of(context)
                        .push(fadeRoute<void>(ServerDetailScreen())),
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
                        style: TextStyle(
                          color: AppTheme.textPrimaryOf(context),
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
                            color: AppTheme.textFaintOf(context),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              config?.name ?? '点击设置添加服务器',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textFaintOf(context),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.music_note,
                            size: 13,
                            color: AppTheme.textFaintOf(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.total}',
                            style: TextStyle(
                              color: AppTheme.textFaintOf(context),
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
        Divider(height: 1, color: SkinTokens.of(context).divider),
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
              color: AppTheme.textFaintOf(context),
            ),
          ),
        ),
      ],
    );
    return cardsOn
        ? GlassContainer(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: EdgeInsets.zero,
            child: content,
          )
        : content;
  }
}

/// 入口网格：Wrap 布局 + 圆形玻璃按钮，视觉对齐首页快捷导航。
/// 后四项按后端能力显隐：provider 返回 null（不支持）时入口隐藏。
class _EntryGrid extends ConsumerWidget {
  const _EntryGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider);
    final albumArtists = ref.watch(albumArtistsProvider);
    final genres = ref.watch(genresProvider);
    final radios = ref.watch(radioStationsProvider);
    final entries = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.music_note,
        label: '歌曲',
        onTap: () => _openSongs(context, '歌曲', librarySongsProvider),
      ),
      (
        icon: Icons.favorite,
        label: '我喜欢的',
        onTap: () => _openSongs(context, '我喜欢的', likedSongsProvider),
      ),
      (
        icon: Icons.smartphone,
        label: '本地音乐',
        onTap: () => _openSongs(
          context,
          '本地音乐',
          localSongsProvider,
          onRefresh: forceLocalRescan,
        ),
      ),
      (icon: Icons.album, label: '专辑', onTap: () => _openAlbums(context)),
      if (albumArtists.valueOrNull != null)
        (
          icon: Icons.theaters,
          label: '专辑艺术家',
          onTap: () => _openArtists(
            context,
            '专辑艺术家',
            albumArtistsProvider,
            openAlbums: true,
          ),
        ),
      if (artists.valueOrNull != null)
        (
          icon: Icons.person,
          label: '歌手',
          onTap: () => _openArtists(context, '歌手', artistsProvider),
        ),
      if (genres.valueOrNull != null)
        (
          icon: Icons.piano,
          label: '流派',
          onTap: () =>
              Navigator.of(context).push(fadeRoute<void>(const GenrePage())),
        ),
      if (radios.valueOrNull != null)
        (
          icon: Icons.radio,
          label: '电台',
          onTap: () =>
              Navigator.of(context).push(fadeRoute<void>(const RadioPage())),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        runSpacing: 8,
        children: [
          for (final e in entries)
            _RoundEntry(icon: e.icon, label: e.label, onTap: e.onTap),
        ],
      ),
    );
  }

  void _openSongs(
    BuildContext context,
    String title,
    FutureProvider<List<Song>> provider, {
    Future<void> Function()? onRefresh,
  }) {
    Navigator.of(context).push(
      fadeRoute<void>(
        SongListScreen(
          title: title,
          songsProvider: provider,
          onRefresh: onRefresh,
        ),
      ),
    );
  }

  void _openArtists(
    BuildContext context,
    String title,
    FutureProvider<List<Artist>?> provider, {
    bool openAlbums = false,
  }) {
    Navigator.of(context).push(
      fadeRoute<void>(
        ArtistListPage(
          title: title,
          provider: provider,
          openAlbums: openAlbums,
        ),
      ),
    );
  }

  void _openAlbums(BuildContext context) {
    Navigator.of(context).push(
      fadeRoute<void>(
        AlbumListPage(title: '专辑', paged: libraryAlbumsPagedProvider),
      ),
    );
  }
}

/// 圆形玻璃入口按钮（对齐首页 _QuickNavItem 风格）
class _RoundEntry extends ConsumerWidget {
  const _RoundEntry({
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 12,
              ),
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
      error: (e, _) => errorRetryBox(
        padding: const EdgeInsets.all(16),
        onRetry: () => ref.invalidate(playlistsProvider),
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
    final matched = username == null || !hasOwnerInfo
        ? all
        : all
              .where(
                (p) => p.owner != null && p.owner!.toLowerCase() == username,
              )
              .toList();
    final mine = matched.isEmpty ? all : matched;
    final canToggle = all.isNotEmpty;
    final list = _all ? all : mine;
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
          child: Row(
            children: [
              if (canToggle) ...[
                GestureDetector(
                  onTap: () => setState(() => _all = false),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '我的',
                              style: TextStyle(
                                color: !_all
                                    ? primary
                                    : AppTheme.textFaintOf(context),
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${mine.length}',
                              style: TextStyle(
                                color: !_all
                                    ? primary
                                    : AppTheme.textFaintOf(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 2.5,
                          width: 28,
                          decoration: BoxDecoration(
                            color: !_all ? primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _all = true),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '全部',
                              style: TextStyle(
                                color: _all
                                    ? primary
                                    : AppTheme.textFaintOf(context),
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${all.length}',
                              style: TextStyle(
                                color: _all
                                    ? primary
                                    : AppTheme.textFaintOf(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 2.5,
                          width: 28,
                          decoration: BoxDecoration(
                            color: _all ? primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                Text(
                  '歌单',
                  style: TextStyle(
                    color: AppTheme.textPrimaryOf(context),
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const Spacer(),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_horiz,
                  color: AppTheme.textFaintOf(context),
                ),
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
      final guideSwitch = !_all && mine.isEmpty;
      return glassEmptyState(
        text: guideSwitch ? '没有你的歌单\n点击上方「全部」标签查看全部' : '还没有歌单\n新建一个，或从服务器重新同步',
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
    final coverSize = (MediaQuery.sizeOf(context).width - 24 - 16) / 3;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 12,
        children: [
          for (final p in list)
            _PlaylistCard(
              playlist: p,
              size: coverSize,
              onTap: () => Navigator.of(context).push(
                fadeRoute<void>(
                  SongListScreen(
                    playlistId: p.id,
                    title: p.name,
                    coverAlbumId: p.coverArt,
                  ),
                ),
              ),
              onLongPress: () => _showPlaylistMenu(context, p),
            ),
        ],
      ),
    );
  }

  void _showPlaylistMenu(BuildContext context, Playlist playlist) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlaylistActionSheet(playlist: playlist, ref: ref),
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
    showToast('已创建歌单「$name」');
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

/// 重命名歌单表单：预填当前名称，提交后 pop 返回新名称。
class _RenamePlaylistForm extends StatefulWidget {
  const _RenamePlaylistForm({required this.controller});

  final TextEditingController controller;

  @override
  State<_RenamePlaylistForm> createState() => _RenamePlaylistFormState();
}

class _RenamePlaylistFormState extends State<_RenamePlaylistForm> {
  bool _dirty = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(hintText: '新歌单名称'),
        ),
        const SizedBox(height: AppSpacing.m),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: AppSpacing.s),
            FilledButton(onPressed: _submit, child: const Text('确定')),
          ],
        ),
      ],
    );
  }

  void _submit() {
    final name = widget.controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }
}

/// 歌单封面：优先用前 4 首歌的去重专辑封面拼 2×2；
/// 不足 2 张时回退歌单自带封面 / 占位图标。
class _PlaylistCover extends ConsumerWidget {
  const _PlaylistCover({required this.playlist, this.size = 52});

  final Playlist playlist;
  final double size;

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
              width: size,
              height: size,
              child: Column(
                children: [
                  for (var r = 0; r < 2; r++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var c = 0; c < 2; c++)
                            Expanded(
                              child: CoverArt(
                                albumId: ids[(r * 2 + c) % ids.length],
                                size: size / 2,
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
            child: CoverArt(albumId: ids.first, size: size, radius: 8),
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
        child: CoverArt(albumId: playlist.coverArt!, size: size, radius: 8),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.surfaceOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.queue_music,
        color: AppTheme.textFaintOf(context),
        size: size * 0.5,
      ),
    );
  }
}

/// 歌单卡片（3 列网格）：封面 + 播放量角标 + 名称，长按弹出操作菜单。
class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.size,
    required this.onTap,
    required this.onLongPress,
  });

  final Playlist playlist;
  final double size;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: PressableScale(
        onTap: onTap,
        child: SizedBox(
          width: size,
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
                          color: AppTheme.surfaceOf(context)
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      Center(
                        child: _PlaylistCover(playlist: playlist, size: size),
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
      ),
    );
  }
}

/// 歌单操作底部菜单（长按卡片弹出）
class _PlaylistActionSheet extends StatelessWidget {
  const _PlaylistActionSheet({required this.playlist, required this.ref});

  final Playlist playlist;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: withGlassTintOpacity(
            ref,
            imageBgAwareTint(ref, AppTheme.surfaceOf(context)),
          ),
          borderRadius: BorderRadius.circular(AppRadius.l),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textDimOf(context),
                  fontSize: 13,
                ),
              ),
            ),
            Divider(height: 1, color: SkinTokens.of(context).divider),
            _SheetItem(
              icon: Icons.play_circle_outline,
              label: '播放',
              onTap: () => _handleAction(context, 'play'),
            ),
            _SheetItem(
              icon: Icons.playlist_play,
              label: '加入队列',
              onTap: () => _handleAction(context, 'queue'),
            ),
            _SheetItem(
              icon: Icons.edit_outlined,
              label: '重命名',
              onTap: () => _handleAction(context, 'rename'),
            ),
            _SheetItem(
              icon: Icons.delete_outline,
              label: '删除',
              danger: true,
              onTap: () => _handleAction(context, 'delete'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    Navigator.of(context).pop();
    final adapter = ref.read(serverAdapterProvider);
    if (adapter == null) return;

    if (action == 'rename') {
      final controller = TextEditingController(text: playlist.name);
      final newName = await glassDialog<String>(
        context,
        title: '重命名歌单',
        content: _RenamePlaylistForm(controller: controller),
      );
      controller.dispose();
      if (newName == null || newName.trim().isEmpty) return;
      final ok = await adapter.renamePlaylist(playlist.id, newName.trim());
      if (!ok) {
        showToast('重命名失败', error: true);
        return;
      }
      ref.invalidate(playlistsProvider);
      showToast('已重命名为「$newName」');
      return;
    }

    if (action == 'delete') {
      final confirmed = await glassDialog<bool>(
        context,
        title: '删除歌单',
        content: Text(
          '确定要删除「${playlist.name}」吗？此操作不可恢复。',
          style: TextStyle(color: AppTheme.textDimOf(context), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.heartRed),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      );
      if (confirmed != true) return;
      final ok = await adapter.deletePlaylist(playlist.id);
      if (!ok) {
        showToast('删除失败', error: true);
        return;
      }
      ref.invalidate(playlistsProvider);
      showToast('已删除歌单「${playlist.name}」');
      return;
    }

    final songs = await adapter.fetchPlaylistSongs(playlist.id);
    if (songs.isEmpty) {
      showToast('歌单暂无歌曲');
      return;
    }
    final actions = ref.read(playerActionsProvider);
    if (action == 'play') {
      actions.replaceQueue(songs);
      await actions.play(songs.first);
    } else {
      actions.addToQueue(songs);
      showToast('已将 ${songs.length} 首歌曲加入队列');
    }
  }
}

class _SheetItem extends StatelessWidget {
  const _SheetItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTheme.heartRed : AppTheme.textPrimaryOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: color, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// ---------- 二级页 ----------

/// 专辑列表二级页（对齐设计图「资料库专辑列表」）：
/// 常驻搜索栏（按专辑名/歌手过滤）+ 4 列封面网格（右上角歌曲数角标）。
/// 数据源二选一：[provider]（一次性全量，如艺人专辑）或
/// [paged]（滚动加载分页，资料库专辑入口）。
class AlbumListPage extends ConsumerStatefulWidget {
  const AlbumListPage({
    super.key,
    required this.title,
    this.provider,
    this.paged,
  }) : assert(
         provider != null || paged != null,
         'AlbumListPage 需要 provider 或 paged 之一作为数据源',
       );

  final String title;

  /// 同时接受普通与 autoDispose（含 family 已取参）的 FutureProvider
  final ProviderBase<AsyncValue<List<Album>>>? provider;

  /// 滚动加载分页数据源
  final AutoDisposeNotifierProvider<LibraryAlbumsController, AlbumPagedState>?
  paged;

  @override
  ConsumerState<AlbumListPage> createState() => _AlbumListPageState();
}

class _AlbumListPageState extends ConsumerState<AlbumListPage> {
  final _controller = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Album> _filter(List<Album> albums) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return albums;
    return albums
        .where(
          (a) =>
              a.name.toLowerCase().contains(q) ||
              a.artist.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.paged != null ? _buildPaged() : _buildOneShot();
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: Colors.transparent,
        ),
        bottomNavigationBar: const MiniPlayer(),
        body: body,
      ),
    );
  }

  Widget _buildPaged() {
    final state = ref.watch(widget.paged!);
    final notifier = ref.read(widget.paged!.notifier);
    Widget content;
    if (state.albums.isEmpty) {
      if (state.loading) {
        content = const Center(child: CircularProgressIndicator());
      } else if (state.error) {
        content = errorRetryBox(
          padding: EdgeInsets.zero,
          onRetry: notifier.retry,
        );
      } else {
        content = glassEmptyState(text: '暂无专辑');
      }
    } else {
      content = ScrollBottomLoader(
        onBottom: notifier.loadMore,
        child: _grid(
          _filter(state.albums),
          footer: LoadMoreRow(
            onLoadMore: notifier.loadMore,
            loading: state.loading,
            failed: state.error,
            noMore: state.noMore,
          ),
        ),
      );
    }
    return Column(
      children: [
        ListSearchBar(
          controller: _controller,
          onChanged: (v) => setState(() => _search = v),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildOneShot() {
    final async = ref.watch(widget.provider!);
    return asyncStateBox<Album>(
      async: async,
      emptyText: '暂无专辑',
      onRetry: () => ref.invalidate(widget.provider!),
      onData: (albums) {
        final list = _filter(albums);
        return Column(
          children: [
            ListSearchBar(
              controller: _controller,
              onChanged: (v) => setState(() => _search = v),
            ),
            Expanded(
              child: list.isEmpty
                  ? glassEmptyState(text: '没有匹配的专辑')
                  : _grid(list),
            ),
          ],
        );
      },
    );
  }

  Widget _grid(List<Album> list, {Widget? footer}) {
    const padding = 12.0;
    const spacing = 10.0;
    final cover =
        (MediaQuery.sizeOf(context).width - padding * 2 - spacing * 3) / 4;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(padding, 4, padding, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: spacing,
        mainAxisSpacing: 14,
        // 封面正方形 + 名称/歌手两行文字
        childAspectRatio: cover / (cover + 40),
      ),
      itemCount: list.length + (footer == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (index >= list.length) return footer!;
        final album = list[index];
        return AlbumCard(
          album: album,
          size: cover,
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
        );
      },
    );
  }
}

/// 列表页搜索栏：圆角输入框 + 尾部漏斗图标（过滤当前列表，非全局搜索）。
/// 专辑列表 / 歌手列表等二级页共用。
class ListSearchBar extends ConsumerWidget {
  const ListSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = '搜索专辑/歌手',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: withGlassTintOpacity(
                  ref,
                  imageBgAwareTint(ref, AppTheme.surfaceOf(context)),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search,
                    size: 20,
                    color: AppTheme.textFaintOf(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    // expands 让输入框撑满固定高度，配合 textAlignVertical
                    // 才能真正垂直居中——isCollapsed 固有行高方案受 CJK
                    // 字体度量影响，文字会整体偏高
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      expands: true,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.center,
                      style: TextStyle(
                        color: AppTheme.textPrimaryOf(context),
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: TextStyle(
                          color: AppTheme.textFaintOf(context),
                          fontSize: 16,
                        ),
                        // 玻璃面板内输入框：三层显式全 none，防止主题描边套进来
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.filter_alt_outlined,
            size: 22,
            color: AppTheme.textFaintOf(context),
          ),
        ],
      ),
    );
  }
}
