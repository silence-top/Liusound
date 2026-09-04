import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/server_adapter.dart';
import '../../core/lyrics/lyrics.dart';
import '../../core/models/models.dart';
import '../../core/storage/app_db.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/glass_quality.dart';
import '../auth/auth_controller.dart';
import 'action_sheets.dart';
import 'cover_style.dart';
import 'player_controller.dart';
import 'queue_modal.dart';

/// 专辑封面主色取色（动态背景，对标 Spotify 沉浸式播放页）。
/// autoDispose 按封面 id 缓存；64px 缩样取 vibrant/muted/dominant，
/// 任何异常返回 null（回退框架色），绝不阻塞播放器打开。
final albumDominantColorProvider = FutureProvider.autoDispose
    .family<Color?, String>((ref, albumId) async {
      if (albumId.isEmpty) return null;
      final adapter = ref.watch(serverAdapterProvider);
      if (adapter == null) return null;
      try {
        final ImageSource? cover = adapter.coverImage(albumId, size: 64);
        if (cover == null) return null;
        final palette = await PaletteGenerator.fromImageProvider(
          NetworkImage(cover.url),
          size: const Size(64, 64),
          maximumColorCount: 16,
        );
        return (palette.vibrantColor ??
                palette.mutedColor ??
                palette.dominantColor)
            ?.color;
      } catch (_) {
        return null;
      }
    });

/// 相似歌曲推荐（按歌曲 id 缓存，对标 1.x getSimilarSongs）。
/// autoDispose：切歌后旧歌曲的推荐缓存自动释放，避免长会话内存累积。
final similarSongsProvider = FutureProvider.autoDispose
    .family<List<Song>, String>((ref, songId) {
      final adapter = ref.watch(serverAdapterProvider);
      if (adapter == null) return <Song>[];
      return adapter.fetchSimilarSongs(songId);
    });

/// 热门歌曲（同歌手按 rating 取前 30，对标 1.x 推荐 Tab 的热门分区）
final hotSongsProvider = FutureProvider.autoDispose.family<List<Song>, String>((
  ref,
  artistId,
) {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return <Song>[];
  return adapter.fetchArtistSongs(artistId).catchError((_) => <Song>[]);
});

/// 歌手简介（§4.1 能力降级：Jellyfin/Emby/Plex 没有相似歌曲，用简介补位）。
/// autoDispose：切歌手后旧简介缓存自动释放。
final artistBioProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  artistId,
) {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null || !adapter.capabilities.artistBio) return null;
  return adapter.fetchArtistBio(artistId).catchError((_) => null);
});

/// 进度条拖动中的临时值（非 null 表示拖动中；歌词高亮跟随拖动位置，
/// 对标 1.x tempCurrentTime / tempCurrentLyricIndex）
final sliderDragValueProvider = StateProvider<double?>((ref) => null);

const double _lyricRowHeight = 42; // 单语歌词行高（当前行 22px 加大字体留有余量）
const double _lyricDualHeight = 64; // 双语歌词行高（原文 + 译文）
const Color _lyricFade = Color(0xEE0A1428); // 歌词渐变遮罩色（#0a1428ee）

/// 歌词行时间戳 mm:ss（§4.3 点击行预览胶囊）
String _fmtLyricTime(double seconds) {
  final total = seconds.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// 从任意入口打开全屏播放器（fullscreenDialog 上滑转场，
/// 返回键 / onClose 均回到原页面）
void openFullScreenPlayer(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          FullScreenPlayer(onClose: () => Navigator.of(context).pop()),
    ),
  );
}

/// 全屏播放器（对标 1.x FullScreenPlayer + QueueModal）：
/// 顶部三 Tab（推荐 / 歌曲 / 歌词）+ 底部固定控制区。
///
/// 性能红线：外壳只 watch [currentSongProvider]（切歌才重建）；
/// 进度条、播放按钮、模式按钮为独立小组件局部订阅高频流。
class FullScreenPlayer extends ConsumerStatefulWidget {
  const FullScreenPlayer({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<FullScreenPlayer> createState() => _FullScreenPlayerState();
}

class _FullScreenPlayerState extends ConsumerState<FullScreenPlayer>
    with TickerProviderStateMixin {
  // 对齐 1.x：默认停留在"歌曲"Tab
  late final TabController _tab = TabController(
    length: 3,
    vsync: this,
    initialIndex: 1,
  );

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    final tabs = const ['推荐', '歌曲', '歌词'];
    // 封面主色 → 播放器背景渐变（取色中/失败回退框架色）
    final tint = ref
        .watch(albumDominantColorProvider(song.albumId))
        .valueOrNull;
    final top = tint == null
        ? AppTheme.shellOf(context)
        : Color.lerp(tint, Colors.black, 0.42)!;
    final bottom = tint == null
        ? AppTheme.shellOf(context)
        : Color.lerp(tint, Colors.black, 0.85)!;

    return Scaffold(
      backgroundColor: AppTheme.shellOf(context),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶栏：下滑关闭 + 居中三 Tab（对齐 1.x）
              // width: double.infinity —— 否则 Stack 收缩到 Tab 行宽度，
              // 左侧关闭图标会与「推荐」文字重叠，点击也被 Tab 手势拦截
              SizedBox(
                height: 48,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: 0,
                      child: IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down),
                        iconSize: 32,
                        color: Colors.white,
                        onPressed: widget.onClose,
                      ),
                    ),
                    ListenableBuilder(
                      listenable: _tab.animation!,
                      builder: (_, _) {
                        // animation.value 就是 TabBarView 摆放页面的实时位置
                        // （拖动/动画每帧更新），与可见页严格同步，
                        // 高亮随手指过渡而不是等落页才跳变
                        final p = _tab.animation!.value;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < tabs.length; i++)
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _tab.animateTo(i),
                                child: Builder(
                                  builder: (context) {
                                    final t = (1 - (i - p).abs()).clamp(
                                      0.0,
                                      1.0,
                                    );
                                    return Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                        vertical: 6,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.12 * t,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          20,
                                        ), // 圆角豁免：Tab 胶囊需随高度全圆贴合
                                        border: t > 0
                                            ? Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.15 * t,
                                                ),
                                                width: 0.5,
                                              )
                                            : null,
                                      ),
                                      child: Text(
                                        tabs[i],
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: t >= 0.5
                                              ? FontWeight.bold
                                              : FontWeight.w400,
                                          color: Color.lerp(
                                            const Color(0xFF888888),
                                            Colors.white,
                                            t,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Tab 内容（三页全部保活，对齐 1.x 保持挂载策略）
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    const _RecommendTab(),
                    const _NowPlayingTab(),
                    _LyricsTab(song: song),
                  ],
                ),
              ),
              const _BottomArea(),
            ],
          ),
        ),
      ),
    );
  }
}

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

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (canSimilar) _SongSection(title: '相似歌曲', async: similar),
        if (canBio) _BioSection(async: bio),
        _SongSection(title: '热门歌曲', async: hot),
      ],
    );
  }
}

/// 歌手简介分区：玻璃卡片承载长文本，默认折叠 3 行，可展开全文。
/// 后端没给简介时整个分区不渲染（§4.1 要求避免空洞的「暂无数据」）。
class _BioSection extends StatefulWidget {
  const _BioSection({required this.async});

  final AsyncValue<String?>? async;

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
          child: GlassCard(
            radius: AppRadius.m,
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

// ---------- Tab 2：歌曲（大封面，对标 1.x renderCurrentSong） ----------

class _NowPlayingTab extends ConsumerStatefulWidget {
  const _NowPlayingTab();

  @override
  ConsumerState<_NowPlayingTab> createState() => _NowPlayingTabState();
}

class _NowPlayingTabState extends ConsumerState<_NowPlayingTab>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  // 唱片匀速旋转（18s/圈）；暂停时停在当前位置
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  // 唱针升降（§4.2）：播放时平滑落下贴住唱片，暂停/切歌时抬起
  late final AnimationController _arm = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  bool get wantKeepAlive => true;

  StreamSubscription<bool>? _playingSub;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _playing = ref.read(audioPlayerProvider).playing;
    _syncAnimations();
    _playingSub = ref
        .read(audioPlayerProvider)
        .playerStateStream
        .map((s) => s.playing)
        .distinct()
        .listen((playing) {
          if (!mounted) return;
          _playing = playing;
          _syncAnimations();
        });
  }

  /// 只有会旋转的形态（黑胶 / CD）才让 _spin 持续 tick：
  /// 本 Tab 常驻存活，方形卡片与全屏大图没必要空转一个 18s 控制器
  void _syncAnimations() {
    final style = ref.read(coverStyleProvider);
    if (_playing && style.spins) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
    if (_playing) {
      _arm.forward();
    } else {
      _arm.reverse();
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _spin.dispose();
    _arm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    final style = ref.watch(coverStyleProvider);
    ref.listen(coverStyleProvider, (_, _) => _syncAnimations());

    return Stack(
      children: [
        // 全屏模糊大图：模糊封面铺满 Tab，再压一层暗渐变保证文字可读
        if (style == CoverStyle.fullBlur) ...[
          Positioned.fill(
            child: _BlurredBackdrop(
              albumId: song.albumId,
              localCover: song.localCoverPath,
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x8C000000),
                    Color(0x40000000),
                    Color(0xB3000000),
                  ],
                ),
              ),
            ),
          ),
        ],
        Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _coverBlock(song.albumId, style, song.localCoverPath),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, color: Colors.white38),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 四种唱片形态（§4.2）；方形卡片与全屏大图共用同一张静态玻璃卡。
  /// 双击封面 = 收藏/取消收藏（乐观更新，失败回滚，与底部爱心一致）
  Widget _coverBlock(String albumId, CoverStyle style, String? localCover) =>
      GestureDetector(
        onDoubleTap: () {
          final song = ref.read(currentSongProvider);
          if (song != null) _toggleStar(song);
        },
        child: switch (style) {
          CoverStyle.vinyl => _VinylDisc(
            albumId: albumId,
            spin: _spin,
            arm: _arm,
            localCover: localCover,
          ),
          CoverStyle.cd => _CdDisc(
            albumId: albumId,
            spin: _spin,
            localCover: localCover,
          ),
          CoverStyle.square || CoverStyle.fullBlur => _SquareCover(
            albumId: albumId,
            localCover: localCover,
          ),
        },
      );

  Future<void> _toggleStar(Song song) async {
    final newStarred = !song.starred;
    ref.read(currentSongProvider.notifier).state = song.copyWith(
      starred: newStarred,
    );
    final ok = await ref
        .read(serverAdapterProvider)
        ?.setStar(song.id, newStarred);
    if (ok != true && mounted) {
      ref.read(currentSongProvider.notifier).state = song;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收藏操作失败'), duration: Duration(seconds: 2)),
      );
    }
  }
}

const double _discSize = 280;

/// 经典黑胶：外圈纹理 + 中央方形封面旋转，唱针挂在右上角不随盘转。
class _VinylDisc extends StatelessWidget {
  const _VinylDisc({
    required this.albumId,
    required this.spin,
    required this.arm,
    this.localCover,
  });

  final String albumId;
  final Animation<double> spin;
  final Animation<double> arm;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _discSize,
      height: _discSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: spin,
            builder: (_, child) =>
                Transform.rotate(angle: spin.value * math.pi * 2, child: child),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFF2A2A2A),
                        Color(0xFF161616),
                        Color(0xFF060606),
                      ],
                      stops: [0.0, 0.72, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                // 唱片纹路（两圈高光环）
                Container(
                  width: 224,
                  height: 224,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                Container(
                  width: 196,
                  height: 196,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  ),
                ),
                // 中央封面（黑胶圆孔位；切歌淡入过渡）
                _fadeCover(albumId, 120, 8, localCover),
              ],
            ),
          ),
          Positioned(right: 0, top: 2, child: _Tonearm(arm: arm)),
        ],
      ),
    );
  }
}

/// CD 唱片：斜向彩虹镀层 + 浅色内圈 + 封面作标签区 + 中心孔，随播放旋转。
class _CdDisc extends StatelessWidget {
  const _CdDisc({required this.albumId, required this.spin, this.localCover});

  final String albumId;
  final Animation<double> spin;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _discSize,
      height: _discSize,
      child: AnimatedBuilder(
        animation: spin,
        builder: (_, child) =>
            Transform.rotate(angle: spin.value * math.pi * 2, child: child),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Color(0xFFDDE2E8),
                    Color(0xFFB7C6DC),
                    Color(0xFFEAEFF6),
                    Color(0xFFD3C3E2),
                    Color(0xFFBFDAD6),
                    Color(0xFFDDE2E8),
                  ],
                  stops: [0.0, 0.18, 0.38, 0.58, 0.78, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            // 内圈镀层分隔
            Container(
              width: 188,
              height: 188,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEDEFF3),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            // 标签区封面（radius 取半径裁成正圆）
            _fadeCover(albumId, 150, 75, localCover),
            // 中心孔
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0C0E12),
                border: Border.all(color: Colors.white24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 方形玻璃卡片：容器级模糊 + 受光描边，不旋转。
class _SquareCover extends StatelessWidget {
  const _SquareCover({required this.albumId, this.localCover});

  final String albumId;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _discSize,
      height: _discSize,
      child: GlassSurface(
        radius: AppRadius.xl,
        blur: GlassTokens.blurContainer,
        tint: GlassTokens.tint(context),
        gradientBorder: true,
        shadow: true,
        padding: const EdgeInsets.all(AppSpacing.m),
        child: _fadeCover(
          albumId,
          _discSize - AppSpacing.m * 2,
          AppRadius.l,
          localCover,
        ),
      ),
    );
  }
}

/// 切歌淡入过渡，三种形态共用
Widget _fadeCover(
  String albumId,
  double size,
  double radius, [
  String? localCover,
]) => AnimatedSwitcher(
  duration: const Duration(milliseconds: 350),
  child: KeyedSubtree(
    key: ValueKey(albumId),
    child: CoverArt(
      albumId: albumId,
      size: size,
      radius: radius,
      localCover: localCover,
    ),
  ),
);

/// 唱针：支点固定在右上角，播放时平滑摆下贴住唱片，暂停时抬起。
class _Tonearm extends StatelessWidget {
  const _Tonearm({required this.arm});

  final Animation<double> arm;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: arm,
      builder: (_, _) => IgnorePointer(
        child: CustomPaint(
          size: const Size(112, 112),
          painter: _TonearmPainter(arm.value),
        ),
      ),
    );
  }
}

class _TonearmPainter extends CustomPainter {
  const _TonearmPainter(this.progress);

  /// 0 抬起 → 1 落下
  final double progress;

  static const _raisedDeg = 6.0;
  static const _loweredDeg = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width - 18, 18);
    final angle =
        (_raisedDeg + (_loweredDeg - _raisedDeg) * progress) * math.pi / 180;
    final dir = Offset(math.sin(angle), math.cos(angle));
    final tip = pivot + dir * (size.height - 26);

    // 臂杆：银色渐变，从支点连到唱头
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFF1F2F4), Color(0xFF9BA2AB)],
        ).createShader(Rect.fromPoints(pivot, tip))
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    // 唱头：跟着臂杆角度摆正，挂在针尖下方
    canvas
      ..save()
      ..translate(tip.dx, tip.dy)
      ..rotate(-angle)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(0, 8), width: 12, height: 22),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF24272D),
      )
      ..restore();

    // 支点底座 + 高光
    canvas.drawCircle(pivot, 12, Paint()..color = const Color(0x66000000));
    canvas.drawCircle(
      pivot,
      8,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFF6F7F9), Color(0xFF868D96)],
        ).createShader(Rect.fromCircle(center: pivot, radius: 8)),
    );
  }

  @override
  bool shouldRepaint(_TonearmPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 全屏模糊大图形态的背景：封面放大铺满后高斯模糊。
/// 玻璃档位关闭时降级为不模糊的放大封面，守住低端设备的性能红线。
class _BlurredBackdrop extends StatelessWidget {
  const _BlurredBackdrop({required this.albumId, this.localCover});

  final String albumId;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    final image = FittedBox(
      fit: BoxFit.cover,
      child: CoverArt(
        albumId: albumId,
        size: 400,
        radius: 0,
        localCover: localCover,
      ),
    );
    return ClipRect(
      child: shouldUseBlur(context)
          ? ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 46 * glassBlurScale(context),
                sigmaY: 46 * glassBlurScale(context),
              ),
              child: Opacity(opacity: 0.55, child: image),
            )
          : Opacity(opacity: 0.40, child: image),
    );
  }
}

// ---------- Tab 3：歌词（双语 / 点击跳转 / LRC 菜单 / 音量 / 偏移面板） ----------

class _LyricsTab extends ConsumerStatefulWidget {
  const _LyricsTab({required this.song});

  final Song song;

  @override
  ConsumerState<_LyricsTab> createState() => _LyricsTabState();
}

class _LyricsTabState extends ConsumerState<_LyricsTab>
    with AutomaticKeepAliveClientMixin {
  LyricsData _lyrics = const LyricsData();
  List<LyricLine> _displayLines = const []; // 展示行（LRC 同时间轴双语行已合并）
  List<String?> _displayTranslations = const []; // 与展示行对齐的译文（无则 null）
  double _rowHeight = _lyricRowHeight;
  bool _hasTranslation = false;
  bool _showBilingual = true; // 双语歌词开关（默认开，全局持久化）
  double _offset = 0;
  bool _manualScrolling = false;
  // 程序化 animateTo 计数：滚动通知监听据此排除自动滚动，避免误设 _manualScrolling
  int _autoScrollCount = 0;
  bool _syncScheduled = false;
  bool _showLrcMenu = false;
  bool _showLyricAdjust = false;
  bool _showVolume = false;
  double _volume = 1;
  // 音轨切换（「切换歌词」）：全部音轨缓存 + 当前选中索引 + 弹层开关
  List<(String, List<LyricLine>)> _tracks = const [];
  int _currentTrackIndex = 0;
  bool _showTrackPicker = false;
  // 当前行索引：值变化仅触发对应行的 ValueListenableBuilder 重建（行级更新）
  final ValueNotifier<int> _currentIndex = ValueNotifier(-2);
  // 点击行预览（§4.3）：被选中待跳播的行，右侧浮出「时间戳 + Play」，-1 表示无
  int _previewIndex = -1;
  Timer? _previewTimer;
  Timer? _manualScrollTimer;
  final ScrollController _controller = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _parseLyrics();
    _loadLocalLyrics();
    _loadOffset();
    _loadBilingual();
    _volume = ref.read(audioPlayerProvider).volume;
  }

  @override
  void didUpdateWidget(_LyricsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.song.id != oldWidget.song.id) {
      _parseLyrics();
      _loadLocalLyrics();
      _offset = 0;
      _currentIndex.value = -2;
      _previewIndex = -1;
      _previewTimer?.cancel();
      _loadOffset();
    }
  }

  @override
  void dispose() {
    _manualScrollTimer?.cancel();
    _previewTimer?.cancel();
    _currentIndex.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 解析歌词（含双语译轨 + LRC 同时间轴双语行）并构建展示行
  void _parseLyrics() {
    final data = parseLyricsData(widget.song.lyrics);
    setState(() {
      _lyrics = data;
      _tracks = parseLyricsTracks(widget.song.lyrics);
      _currentTrackIndex = 0;
      _showTrackPicker = false;
      _applyLines(data.lines, data.translations);
    });
  }

  /// 本地导入歌词（SQLite lyrics_local，按「标题|歌手」键）：
  /// 命中后优先于服务端 JSON 歌词
  Future<void> _loadLocalLyrics() async {
    final songId = widget.song.id;
    final content = await AppDb.loadLocalLyrics(
      widget.song.title,
      widget.song.artist,
    );
    if (content == null || songId != widget.song.id || !mounted) return;
    final lines = parseLrcText(content);
    if (lines.isEmpty) return;
    setState(() {
      _lyrics = LyricsData(lines: lines);
      _tracks = const [];
      _currentTrackIndex = 0;
      _showTrackPicker = false;
      _applyLines(lines, const []);
    });
  }

  /// LRC 手动导入弹层：粘贴文本或选 .lrc 文件，校验时间轴后存库并即时生效
  Future<void> _showImportSheet() async {
    final controller = TextEditingController();
    await glassBottomSheet<void>(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '导入歌词',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextField(
            controller: controller,
            maxLines: 6,
            minLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              hintText: '粘贴 .lrc 歌词文本（[mm:ss.xx] 歌词）',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  final files = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['lrc', 'txt'],
                  );
                  final path = files.isEmpty ? null : files.first.path;
                  if (path == null) return;
                  try {
                    controller.text = await File(path).readAsString();
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('文件读取失败')));
                    }
                  }
                },
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('选择文件'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  final lines = parseLrcText(controller.text);
                  if (lines.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('未识别到 LRC 时间轴')),
                    );
                    return;
                  }
                  await AppDb.saveLocalLyrics(
                    widget.song.title,
                    widget.song.artist,
                    controller.text,
                  );
                  if (mounted) Navigator.of(context).pop();
                  if (!mounted) return;
                  setState(() {
                    _lyrics = LyricsData(lines: lines);
                    _tracks = const [];
                    _currentTrackIndex = 0;
                    _showTrackPicker = false;
                    _applyLines(lines, const []);
                  });
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
    controller.dispose();
  }

  /// 由主轨/译轨构建展示行：LRC 相邻同时间轴两行合并为 原文+译文，
  /// 服务端译轨按时间戳补充对齐（同一行两者都有时优先 LRC 内嵌译文）
  void _applyLines(List<LyricLine> lines, List<LyricLine> translations) {
    final (merged, inline) = mergeDuplicateTimestamps(lines);
    final aligned = alignTranslations(merged, translations);
    _displayLines = merged;
    _displayTranslations = [
      for (var i = 0; i < merged.length; i++) inline[i] ?? aligned[i],
    ];
    _hasTranslation = _displayTranslations.any((t) => t != null);
    _rowHeight = _showBilingual && _hasTranslation
        ? _lyricDualHeight
        : _lyricRowHeight;
    _currentIndex.value = -2;
  }

  Future<void> _loadOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble('$lyricOffsetKeyPrefix${widget.song.id}') ?? 0;
    if (mounted) setState(() => _offset = v);
  }

  /// 读取双语歌词开关（全局，默认开）
  Future<void> _loadBilingual() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(bilingualLyricsKey) ?? true;
    if (mounted) {
      setState(() {
        _showBilingual = v;
        _rowHeight = v && _hasTranslation ? _lyricDualHeight : _lyricRowHeight;
      });
    }
  }

  /// 切换双语歌词并持久化（保持当前行居中）
  Future<void> _toggleBilingual(bool v) async {
    setState(() {
      _showBilingual = v;
      _rowHeight = v && _hasTranslation ? _lyricDualHeight : _lyricRowHeight;
    });
    SharedPreferences.getInstance().then(
      (p) => p.setBool(bilingualLyricsKey, v),
    );
    if (!_controller.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final idx = _currentIndex.value;
      if (idx < 0 || !_controller.hasClients) return;
      final target = (idx * _rowHeight + _rowHeight / 2).clamp(
        0.0,
        _controller.position.maxScrollExtent,
      );
      _controller.jumpTo(target);
    });
  }

  /// 保存偏移（0 表示清除该歌曲的偏移记录，对标 1.x handleSaveLyricOffset）
  Future<void> _persistOffset(double v) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$lyricOffsetKeyPrefix${widget.song.id}';
    if (v == 0) {
      await prefs.remove(key);
    } else {
      await prefs.setDouble(key, v);
    }
  }

  void _adjustOffset(double delta) => setState(
    () => _offset = double.parse((_offset + delta).toStringAsFixed(2)),
  );

  /// 点击歌词行（§4.3 两段式跳播）：
  /// 首次点非当前行只在该行右侧浮出「时间戳 + Play」预览，再点一次或点 Play 才真正跳播；
  /// 点当前行等于取消预览。预览 4 秒不动自动收起，避免误触后一直挂着。
  void _handleRowTap(int i) {
    if (i == _currentIndex.value) {
      _clearPreview();
      return;
    }
    if (_previewIndex == i) {
      _seekToLine(i);
      return;
    }
    setState(() => _previewIndex = i);
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _previewIndex = -1);
    });
  }

  /// 跳到第 i 行（减去偏移，对齐 1.x handleLyricPress）
  void _seekToLine(int i) {
    final t = _displayLines[i].time - _offset;
    ref
        .read(playerActionsProvider)
        .seek(Duration(milliseconds: (t * 1000).round()));
    _clearPreview();
  }

  void _clearPreview() {
    _previewTimer?.cancel();
    if (_previewIndex == -1) return;
    setState(() => _previewIndex = -1);
  }

  /// 进度/拖动流触发的同步统一推迟到帧后执行：
  /// ref.listen 可能在 build 阶段同步回调，此时 jumpTo/animateTo 会污染布局管线，
  /// 导致后续帧持续断言失败、命中测试失效（真机上表现为所有点击无响应）。
  void _scheduleSyncIndex() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _syncIndex();
    });
  }

  /// 计算当前行并同步高亮/滚动（进度流与拖动流共同触发）
  void _syncIndex() {
    if (_displayLines.isEmpty) return;
    final drag = ref.read(sliderDragValueProvider);
    final double t;
    if (drag != null) {
      t = drag / 1000.0;
    } else {
      t =
          (ref.read(positionProvider).valueOrNull ?? Duration.zero)
              .inMilliseconds /
          1000.0;
    }
    final idx = findLyricIndex(_displayLines, t + _offset);
    if (idx == _currentIndex.value) return;
    _currentIndex.value = idx;
    if (idx < 0 || !_controller.hasClients) return;
    // 列表上下 padding 各为半个视口（见 build），行中心对齐视口中心
    // 只需滚到 idx*行高 + 半行高，首尾行同样可居中
    final target = (idx * _rowHeight + _rowHeight / 2).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    if (drag != null) {
      // 拖动进度条时无动画立即跟随（对齐 1.x handleSliderChange）
      _controller.jumpTo(target);
    } else if (!_manualScrolling) {
      _autoScrollCount++;
      _controller
          .animateTo(
            target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          )
          .whenComplete(() => _autoScrollCount--);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.listen(positionProvider, (_, _) => _scheduleSyncIndex());
    ref.listen(sliderDragValueProvider, (_, _) => _scheduleSyncIndex());

    final hasLyrics = _displayLines.isNotEmpty;
    if (!hasLyrics) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂无歌词', style: TextStyle(color: Colors.white38)),
            const SizedBox(height: AppSpacing.m),
            TextButton.icon(
              onPressed: _showImportSheet,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('导入歌词'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            // 歌词主体（手动滚动后暂停自动跟随 2.5s；首尾行可居中）
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) =>
                    NotificationListener<UserScrollNotification>(
                      onNotification: (n) {
                        if (_autoScrollCount == 0 &&
                            n.direction != ScrollDirection.idle) {
                          _manualScrolling = true;
                          _manualScrollTimer?.cancel();
                          _manualScrollTimer = Timer(
                            const Duration(milliseconds: 2500),
                            () => _manualScrolling = false,
                          );
                        }
                        return false;
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ListView.builder(
                            controller: _controller,
                            itemExtent: _rowHeight,
                            padding: EdgeInsets.symmetric(
                              vertical: constraints.maxHeight / 2,
                              horizontal: 20,
                            ),
                            itemCount: _displayLines.length,
                            itemBuilder: (_, i) => ValueListenableBuilder<int>(
                              valueListenable: _currentIndex,
                              builder: (_, current, _) => _LyricRowTile(
                                text: _displayLines[i].text,
                                translation: _showBilingual
                                    ? _displayTranslations[i]
                                    : null,
                                // 与当前行的距离驱动景深衰减（§4.3）：
                                // 越远越淡越小；还没定位到当前行时统一按远景处理
                                distance: current < 0 ? 3 : (i - current).abs(),
                                previewTime: i == _previewIndex
                                    ? _displayLines[i].time
                                    : null,
                                onTap: () => _handleRowTap(i),
                                onPreviewTap: () => _seekToLine(i),
                                onDoubleTap: () =>
                                    _toggleBilingual(!_showBilingual),
                              ),
                            ),
                          ),
                          // 顶部/底部渐变遮罩（对齐 1.x lyricFadeTop/Bottom）
                          Align(
                            alignment: Alignment.topCenter,
                            child: FractionallySizedBox(
                              heightFactor: 0.2,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      _lyricFade,
                                      _lyricFade.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: 0.15,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      _lyricFade,
                                      _lyricFade.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ),
            ),
            // LRC / 音量按钮行（对齐 1.x lrcRow）
            // 命中区域用 InkWell/IconButton（不透明命中），避免裸 GestureDetector
            // 只能命中文字本身导致的小目标点击失败
            Container(
              height: 42,
              margin: const EdgeInsets.only(left: 28, bottom: 6),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  _lyricBadge(
                    'LRC',
                    onTap: () => setState(() => _showLrcMenu = true),
                  ),
                  // 「译」快速开关（§4.3）：与 LRC 菜单里的双语歌词同一状态。
                  // 没有译轨时不渲染，避免留一个点了没反应的死按钮
                  if (_hasTranslation) ...[
                    const SizedBox(width: 10),
                    _lyricBadge(
                      '译',
                      active: _showBilingual,
                      onTap: () => _toggleBilingual(!_showBilingual),
                    ),
                  ],
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: () => setState(() => _showVolume = !_showVolume),
                    icon: const Icon(
                      Icons.volume_up,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // LRC 弹出菜单（调整歌词 / 生成翻译 / 切换歌词，对齐 1.x）
        if (_showLrcMenu) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showLrcMenu = false),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 58,
            child: Material(
              color: Colors.transparent,
              child: GlassSurface(
                radius: AppRadius.l,
                blur: GlassTokens.blurMedium,
                tint: GlassTokens.tint(context),
                gradientBorder: true,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  // 不用 stretch：Positioned 下宽度无约束，stretch 会迫使
                  // 子项无限宽导致布局崩溃；收缩包裹最宽子项即等效效果
                  children: [
                    _menuItem(Icons.tune, '调整歌词', () {
                      setState(() {
                        _showLrcMenu = false;
                        _showLyricAdjust = true;
                      });
                    }),
                    _menuBilingualItem(),
                    _menuItem(Icons.search, '切换歌词', () {
                      setState(() {
                        _showLrcMenu = false;
                        _showTrackPicker = true;
                      });
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
        // 音轨选择菜单（「切换歌词」）
        if (_showTrackPicker) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showTrackPicker = false),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 58,
            child: Material(
              color: Colors.transparent,
              child: GlassSurface(
                radius: AppRadius.l,
                blur: GlassTokens.blurMedium,
                tint: GlassTokens.tint(context),
                gradientBorder: true,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  // 不用 stretch：Positioned 下宽度无约束，stretch 会迫使
                  // 子项无限宽导致布局崩溃；收缩包裹最宽子项即等效效果
                  children: [
                    if (_tracks.length <= 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          '没有其他音轨',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      )
                    else
                      for (var i = 0; i < _tracks.length; i++)
                        _menuItem(
                          i == _currentTrackIndex
                              ? Icons.check
                              : Icons.music_note,
                          _trackLabel(_tracks[i].$1, i),
                          () => _selectTrack(i),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
        // 歌词偏移悬浮面板（右侧，对标 1.x lyricAdjustPanel）
        if (_showLyricAdjust)
          Positioned(
            right: 18,
            top: MediaQuery.of(context).size.height * 0.18,
            child: GlassSurface(
              radius: AppRadius.xl,
              blur: GlassTokens.blurMedium,
              tint: GlassTokens.tint(context),
              gradientBorder: true,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
              child: SizedBox(
                width: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _adjBtn(Icons.arrow_upward, () => _adjustOffset(0.05)),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${_offset.toStringAsFixed(2)}s',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _adjBtn(Icons.arrow_downward, () => _adjustOffset(-0.05)),
                    _adjBtn(Icons.refresh, () => setState(() => _offset = 0)),
                    _adjBtn(Icons.check, () {
                      _persistOffset(_offset);
                      setState(() => _showLyricAdjust = false);
                    }),
                    _adjBtn(Icons.content_copy, () {
                      Clipboard.setData(
                        ClipboardData(
                          text: _lyrics.lines.map((l) => l.text).join('\n'),
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('歌词已复制'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        // 音量条弹层（对齐 1.x volumeBarWrap：白条进度 + 百分比）
        if (_showVolume) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showVolume = false),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 70,
            bottom: 50,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _applyVolume(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => _applyVolume(d.localPosition.dx),
              child: GlassSurface(
                radius: GlassTokens.radiusPill,
                blur: GlassTokens.blurMedium,
                tint: GlassTokens.tint(context),
                gradientBorder: true,
                child: SizedBox(
                  width: 180,
                  height: 36,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      FractionallySizedBox(
                        widthFactor: _volume.clamp(0.08, 1.0),
                        child: const ColoredBox(color: Color(0xE6FFFFFF)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.volume_up,
                              size: 22,
                              color: _volume > 0.5
                                  ? Colors.black87
                                  : Colors.white38,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(_volume * 100).round()}%',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _volume > 0.5
                                    ? Colors.black87
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 切换主轨歌词（选中的轨替换原文，双语对齐重置）
  void _selectTrack(int index) {
    final (_, lines) = _tracks[index];
    setState(() {
      _currentTrackIndex = index;
      _showTrackPicker = false;
      _lyrics = LyricsData(lines: lines);
      _applyLines(lines, const []);
    });
  }

  String _trackLabel(String lang, int index) =>
      lang.isEmpty ? '音轨 ${index + 1}' : lang.toUpperCase();

  void _applyVolume(double dx) {
    final v = (dx / 180).clamp(0.0, 1.0);
    setState(() => _volume = v);
    ref.read(audioPlayerProvider).setVolume(v);
  }

  /// 双语歌词菜单行：开启时文字高亮、关闭时置灰，点击整行切换（菜单保持展开）
  Widget _menuBilingualItem() {
    return InkWell(
      onTap: () => _toggleBilingual(!_showBilingual),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.translate,
              size: 18,
              color: _showBilingual
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white38,
            ),
            const SizedBox(width: 12),
            Text(
              '双语歌词',
              style: TextStyle(
                color: _showBilingual ? Colors.white : Colors.white38,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 歌词页左下角小徽章（LRC / 译）：统一描边样式，
  /// 开关态只用字色与描边色表达（不做填充按钮，避免与整页 UI 割裂）
  Widget _lyricBadge(String label, {bool active = true, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: active ? Colors.white : Colors.white24),
            // 圆角豁免：徽章沿用 1.x 小圆角
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white38,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adjBtn(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 22, color: Colors.white70),
        onPressed: onTap,
      ),
    );
  }
}

/// 歌词行（§4.3 景深衰减 + 两段式跳播预览）：
/// 字号/字重/透明度按与当前行的距离分级衰减，越远越淡越小；当前行加大加粗
/// 并带双层下投影，像悬浮在背景之上。切换由 AnimatedDefaultTextStyle 平滑过渡。
class _LyricRowTile extends StatelessWidget {
  const _LyricRowTile({
    required this.text,
    required this.translation,
    required this.distance,
    required this.onTap,
    required this.onPreviewTap,
    this.onDoubleTap,
    this.previewTime,
  });

  final String text;
  final String? translation;

  /// 与当前播放行的距离，0 即当前行
  final int distance;
  final VoidCallback onTap;
  final VoidCallback onPreviewTap;

  /// 双击歌词行 = 切换双语翻译
  final VoidCallback? onDoubleTap;

  /// 非 null 表示该行处于待跳播预览态，值为该行时间戳（秒）
  final double? previewTime;

  /// 景深分级：(字号, 字重, 透明度)
  (double, FontWeight, double) get _depth => switch (distance) {
    0 => (22.0, FontWeight.w700, 1.0),
    1 => (18.0, FontWeight.w600, 0.72),
    2 => (16.0, FontWeight.w400, 0.45),
    _ => (15.0, FontWeight.w400, 0.28),
  };

  @override
  Widget build(BuildContext context) {
    final (size, weight, alpha) = _depth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 预览态左右对称留出胶囊宽度：长句先省略号，不会钻到胶囊底下
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: previewTime != null ? 76 : 0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: weight,
                    color: Colors.white.withValues(alpha: alpha),
                    // 双层下投影：当前行像悬浮在背景之上（立体感）
                    shadows: distance == 0
                        ? const [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 4,
                              color: Color(0x80000000),
                            ),
                            Shadow(
                              offset: Offset(0, 5),
                              blurRadius: 12,
                              color: Color(0x59000000),
                            ),
                          ]
                        : const [],
                  ),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (translation != null)
                  Text(
                    translation!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(
                        alpha: distance == 0 ? 0.75 : alpha * 0.58,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (previewTime != null)
            Align(
              alignment: Alignment.centerRight,
              child: _previewChip(context),
            ),
        ],
      ),
    );
  }

  /// 待跳播胶囊「时间戳 + Play」。
  /// blur 传 0：列表行内绝不挂 BackdropFilter（§2.2 性能红线），
  /// 纯 tint + 语义描边已经够跳；GlassSurface 内置透明 Material，墨水正常。
  Widget _previewChip(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GlassSurface(
      radius: AppRadius.pill,
      blur: 0,
      tint: primary.withValues(alpha: 0.26),
      borderColor: primary.withValues(alpha: 0.65),
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onPreviewTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fmtLyricTime(previewTime!),
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
            const Icon(Icons.play_arrow, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ---------- 底部固定区（歌曲信息 + 进度 + 控制行） ----------

class _BottomArea extends ConsumerWidget {
  const _BottomArea();

  /// 收藏/取消收藏：乐观更新当前歌曲（❤ 即时变色），失败回滚
  Future<void> _toggleStar(
    BuildContext context,
    WidgetRef ref,
    Song song,
  ) async {
    final newStarred = !song.starred;
    ref.read(currentSongProvider.notifier).state = song.copyWith(
      starred: newStarred,
    );
    final ok = await ref
        .read(serverAdapterProvider)
        ?.setStar(song.id, newStarred);
    if (ok != true && context.mounted) {
      ref.read(currentSongProvider.notifier).state = song;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收藏操作失败'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);

    return GlassSurface(
      radius: 0,
      blur: GlassTokens.blurHeavy,
      tint: Colors.black.withValues(alpha: 0.25),
      gradientBorder: false,
      shadow: false,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song?.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song != null ? '${song.artist} - ${song.album}' : '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    (song?.starred ?? false)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 22,
                    color: (song?.starred ?? false)
                        ? const Color(0xFFE57373)
                        : Colors.white,
                  ),
                  onPressed: song == null
                      ? null
                      : () => _toggleStar(context, ref, song),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.more_vert,
                    size: 22,
                    color: Colors.white,
                  ),
                  onPressed: song == null
                      ? null
                      : () => showSongActionSheet(context, song),
                ),
              ],
            ),
          ),
          const _ProgressSlider(),
          const _ControlsRow(),
        ],
      ),
    );
  }
}

/// 进度条（拖动值写入 [sliderDragValueProvider] 联动歌词高亮，时间在下方两端）
class _ProgressSlider extends ConsumerWidget {
  const _ProgressSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;
    final drag = ref.watch(sliderDragValueProvider);
    final maxMs = duration.inMilliseconds.toDouble();
    final value = (drag ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs <= 0 ? 1.0 : maxMs,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          SliderTheme(
            data: const SliderThemeData(
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              max: maxMs <= 0 ? 1 : maxMs,
              activeColor: Colors.white,
              inactiveColor: const Color(0xFF444444),
              onChanged: (v) =>
                  ref.read(sliderDragValueProvider.notifier).state = v,
              onChangeEnd: (v) {
                ref.read(sliderDragValueProvider.notifier).state = null;
                ref
                    .read(playerActionsProvider)
                    .seek(Duration(milliseconds: v.round()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(
                    drag != null
                        ? Duration(milliseconds: drag.round())
                        : position,
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.white38),
                ),
                Text(
                  _formatTime(duration),
                  style: const TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 控制行：模式 / 上一首 / 大播放键 / 下一首 / 队列（对齐 1.x controlsRow）
class _ControlsRow extends ConsumerWidget {
  const _ControlsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _ModeButton(),
          IconButton(
            iconSize: 28,
            color: Colors.white,
            icon: const Icon(Icons.skip_previous),
            onPressed: () => ref.read(playerActionsProvider).playPrevious(),
          ),
          const _PlayButton(),
          IconButton(
            iconSize: 28,
            color: Colors.white,
            icon: const Icon(Icons.skip_next),
            onPressed: () => ref.read(playerActionsProvider).playNext(),
          ),
          IconButton(
            iconSize: 24,
            color: Colors.white,
            icon: const Icon(Icons.queue_music),
            onPressed: () => showQueueModal(context),
          ),
        ],
      ),
    );
  }
}

/// 播放模式按钮（仅订阅 playMode，点击在 顺序→随机→单曲循环 间切换）
class _ModeButton extends ConsumerWidget {
  const _ModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playModeProvider);
    final icon = switch (mode) {
      PlayMode.order => Icons.repeat,
      PlayMode.shuffle => Icons.shuffle,
      PlayMode.repeatOne => Icons.repeat_one,
    };
    return IconButton(
      iconSize: 24,
      color: Colors.white,
      icon: Icon(icon),
      onPressed: () => ref.read(playerActionsProvider).cyclePlayMode(),
    );
  }
}

/// 播放/暂停大按钮：56 圆形白描边 + 半透明底（对齐 1.x playPauseBtn）
class _PlayButton extends ConsumerWidget {
  const _PlayButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;
    return GestureDetector(
      onTap: () => ref.read(playerActionsProvider).toggle(),
      child: Container(
        width: 56,
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: ShapeDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
        ),
        child: Icon(
          isPlaying ? Icons.pause : Icons.play_arrow,
          size: 36,
          color: Colors.white,
        ),
      ),
    );
  }
}
