import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/download/auto_download.dart';
import '../../core/lyrics/lyrics.dart';
import '../../core/models/models.dart';
import '../../core/local/local_library.dart' show localSongFingerprint;
import '../../core/storage/app_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/motion_tokens.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/motion.dart';
import '../auth/auth_controller.dart';
import 'action_sheets.dart';
import 'album_tint.dart';
import 'cover_style.dart';
import 'player_controller.dart';
import 'queue_modal.dart';

part 'full_screen_player_recommend.dart';
part 'full_screen_player_now_playing.dart';
part 'full_screen_player_lyrics.dart';
part 'full_screen_player_bottom.dart';

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

/// 从任意入口打开全屏播放器：
/// 自定义转场——背景淡入 + 页面上滑 + 由小放大（类似从 MiniBar 展开成全屏），
/// 关闭反向回落。返回键 / onClose / 下滑手势均回到原页面
void openFullScreenPlayer(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      // 不透明路由：转场期间下层页面持续可见，配合淡入产生「展开」层次感
      opaque: false,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) =>
          FullScreenPlayer(onClose: () => Navigator.of(context).pop()),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(curved),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
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

  /// 下滑收起：跟手位移（px）。ValueNotifier 局部化：拖拽/落位每帧
  /// 只经 ValueListenableBuilder 重建 Transform 变换壳，
  /// 顶栏 / TabBar / TabBarView 子树零重建（性能红线）
  final ValueNotifier<double> _dragOffset = ValueNotifier(0);
  late final AnimationController _settleCtrl = AnimationController(
    vsync: this,
    duration: MotionTokens.durationTransition,
  );
  Animation<double>? _settleAnim;
  bool _dismissPending = false;

  @override
  void initState() {
    super.initState();
    _settleCtrl.addListener(() {
      final a = _settleAnim;
      if (a != null) _dragOffset.value = a.value;
    });
    _settleCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && _dismissPending) {
        widget.onClose();
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _settleCtrl.dispose();
    _dragOffset.dispose();
    super.dispose();
  }

  /// 松手后弹性落位：dismiss=true 时滑出屏幕再关闭，否则回弹原位
  void _beginSettle(
    double target, {
    required Curve curve,
    bool dismiss = false,
  }) {
    _dismissPending = dismiss;
    // 省电模式压缩落位时长（§8.5 AppMotion）：触发时求值，切开关即时生效
    _settleCtrl.duration = AppMotion.duration(
      context,
      MotionTokens.durationTransition,
    );
    _settleAnim = Tween<double>(
      begin: _dragOffset.value,
      end: target,
    ).animate(CurvedAnimation(parent: _settleCtrl, curve: curve));
    _settleCtrl
      ..reset()
      ..forward();
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
      body: GestureDetector(
        // 下滑收起（跟手拖拽）：封面/控制区/空白处下滑，页面实时跟随手指
        // 下移并轻微缩小变暗，松手后超阈值滑出屏幕收起、未超阈值回弹；
        // 歌词/歌曲列表等纵向滚动区由内层滚动手势优先命中，不受影响。
        onVerticalDragUpdate: (d) {
          _settleCtrl.stop();
          _dragOffset.value = (_dragOffset.value + d.delta.dy).clamp(
            0.0,
            double.infinity,
          );
        },
        onVerticalDragEnd: _handleDragEnd,
        onVerticalDragCancel: () => _beginSettle(0, curve: Curves.easeOutCubic),
        child: ValueListenableBuilder<double>(
          valueListenable: _dragOffset,
          // 拖拽/落位每帧只重建 Transform 变换壳；AnimatedContainer 子树
          // 作为 child 缓存，不随手势重建
          builder: (_, dragOffset, child) => Transform.translate(
            offset: Offset(0, dragOffset),
            child: Transform.scale(
              // 跟手下移时轻微缩小 + 变暗，收起更有层次
              scale: 1 - (dragOffset / 2400).clamp(0.0, 0.06),
              child: Opacity(
                opacity: (1 - dragOffset / 900).clamp(0.4, 1.0),
                child: child,
              ),
            ),
          ),
          child: AnimatedContainer(
            duration: MotionTokens.durationAmbient,
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
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 2,
                                                    vertical: 6,
                                                  ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 18,
                                                    vertical: 8,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.12 * t,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      20,
                                                    ), // 圆角豁免：Tab 胶囊需随高度全圆贴合
                                                border: t > 0
                                                    ? Border.all(
                                                        color: Colors.white
                                                            .withValues(
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
        ),
      ),
    );
  }

  /// 松手判定：快速下滑（>900px/s）或拖动超过 120px → 滑出屏幕收起，否则回弹
  void _handleDragEnd(DragEndDetails d) {
    final fling = d.velocity.pixelsPerSecond.dy > 900;
    if (fling || _dragOffset.value > 120) {
      _beginSettle(
        MediaQuery.sizeOf(context).height.toDouble(),
        curve: Curves.easeInCubic,
        dismiss: true,
      );
    } else {
      _beginSettle(0, curve: Curves.easeOutBack);
    }
  }
}
