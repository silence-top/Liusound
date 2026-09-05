import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lyrics/lyrics.dart';
import '../../core/models/models.dart';
import '../../core/settings/prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/glass.dart';
import 'full_screen_player.dart';
import 'mini_bar_style.dart';
import 'player_controller.dart';
import 'queue_modal.dart';

/// 底部迷你播放条（对标 1.x MiniPlayer）：
/// 圆形旋转封面 + 绿色进度环；点击封面=播放/暂停，点击文字=全屏播放器，
/// 右侧队列按钮打开队列弹窗。副标题优先显示当前歌词行。
///
/// 性能红线：外壳只 watch [currentSongProvider]（仅切歌时重建）；
/// 旋转/进度环/歌词副标题拆为独立小组件，各自局部订阅高频流。
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    final barStyle = ref.watch(miniBarStyleProvider);
    final offset = ref.watch(miniBarOffsetProvider);
    ref.listen(resumeNoticeProvider, (_, message) {
      if (message == null) return;
      ref.read(resumeNoticeProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    });

    final inner = Row(
      children: [
        _SpinCover(song: song),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openFullScreenPlayer(context),
            child: _MiniTextBlock(song: song),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => showQueueModal(context),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.queue_music, size: 28, color: Colors.white),
          ),
        ),
      ],
    );

    final content = switch (barStyle) {
      MiniBarStyle.glass => GlassPill(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
        child: inner,
      ),
      MiniBarStyle.solid => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceOf(context),
          borderRadius: BorderRadius.circular(999),
        ),
        child: inner,
      ),
      MiniBarStyle.gradient => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
              AppTheme.surfaceOf(context),
            ],
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: inner,
      ),
    };

    return _SwipeToSwitch(
      child: offset != 0
          ? Transform.translate(offset: Offset(0, -offset), child: content)
          : content,
    );
  }
}

/// 圆形封面 + 旋转动画（播放时 10s/圈）+ 进度圆环 + 暂停覆盖播放键。
/// 点击 = 播放/暂停（对齐 1.x）。
class _SpinCover extends ConsumerStatefulWidget {
  const _SpinCover({required this.song});

  final Song song;

  @override
  ConsumerState<_SpinCover> createState() => _SpinCoverState();
}

class _SpinCoverState extends ConsumerState<_SpinCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;
    // 同步旋转动画：播放循环、暂停停止并复位（对齐 1.x）
    if (isPlaying && !_rotation.isAnimating) {
      _rotation.repeat();
    } else if (!isPlaying && _rotation.isAnimating) {
      _rotation.stop();
      _rotation.value = 0;
    }

    return GestureDetector(
      onTap: () => ref.read(playerActionsProvider).toggle(),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RotationTransition(
              turns: _rotation,
              child: ClipOval(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: KeyedSubtree(
                    key: ValueKey(widget.song.albumId),
                    child: CoverArt(
                      albumId: widget.song.albumId,
                      size: 44,
                      localCover: widget.song.localCoverPath,
                    ),
                  ),
                ),
              ),
            ),
            if (!isPlaying)
              const Icon(
                Icons.play_circle_filled,
                size: 38,
                color: Colors.white,
              ),
            const _ProgressRing(),
          ],
        ),
      ),
    );
  }
}

/// 绿色进度圆环（仅订阅进度/时长流，事件驱动节流 ~200ms）。
class _ProgressRing extends ConsumerWidget {
  const _ProgressRing();

  static const _stroke = 2.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return CustomPaint(
      size: const Size(48, 48),
      painter: _RingPainter(
        progress: progress,
        stroke: _stroke,
        accentColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.stroke,
    required this.accentColor,
  });

  final double progress;
  final double stroke;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - stroke / 2;
    final center = size.center(Offset.zero);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.2);
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = accentColor; // 进度环与全局主色一致

    canvas.drawCircle(center, radius, trackPaint);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -3.14159265 / 2, // 从顶部开始（对齐 1.x rotate -90deg）
        3.14159265 * 2 * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.accentColor != accentColor;
}

/// 中部文字块：播放时双行歌词（双语歌单第二行译文，跟随全局双语开关），
/// 暂停或无歌词时显示歌名 + 歌手。局部订阅 isPlaying/position 高频流，外壳零重建。
class _MiniTextBlock extends ConsumerStatefulWidget {
  const _MiniTextBlock({required this.song});

  final Song song;

  @override
  ConsumerState<_MiniTextBlock> createState() => _MiniTextBlockState();
}

class _MiniTextBlockState extends ConsumerState<_MiniTextBlock> {
  List<LyricLine> _lines = const [];
  List<String?> _translations = const [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(_MiniTextBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.song.id != oldWidget.song.id) {
      _parse();
    }
  }

  void _parse() {
    final data = parseLyricsData(widget.song.lyrics);
    final (merged, inline) = mergeDuplicateTimestamps(data.lines);
    final aligned = alignTranslations(merged, data.translations);
    setState(() {
      _lines = merged;
      _translations = [
        for (var i = 0; i < merged.length; i++) inline[i] ?? aligned[i],
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;
    final showBilingual =
        ref.watch(sharedPrefsProvider).getBool(bilingualLyricsKey) ?? true;

    String? main;
    String? sub;
    if (isPlaying && _lines.isNotEmpty) {
      final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
      final idx = findLyricIndex(_lines, position.inMilliseconds / 1000.0);
      // 前奏（-1）时显示第一句（对齐全屏播放页回退策略）
      final i = idx >= 0 ? idx : 0;
      main = _lines[i].text;
      if (showBilingual) sub = _translations[i];
      // 非双语或本行无译文 → 第二行滚动预览下一句，保持双行歌词形态
      if (sub == null || sub.isEmpty) {
        sub = i + 1 < _lines.length ? _lines[i + 1].text : null;
      }
    } else {
      main = widget.song.title;
      sub = widget.song.artist;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          main,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isPlaying && _lines.isNotEmpty ? 15 : 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        if (sub != null && sub.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
        ],
      ],
    );
  }
}

/// 左右滑动切歌 + 上滑打开全屏播放器（现代播放器标配）：拖动跟手（阻尼 0.55），
/// 位移超阈值或快滑即触发，松手回位。与行内点击互不干扰。
class _SwipeToSwitch extends ConsumerStatefulWidget {
  const _SwipeToSwitch({required this.child});

  final Widget child;

  @override
  ConsumerState<_SwipeToSwitch> createState() => _SwipeToSwitchState();
}

class _SwipeToSwitchState extends ConsumerState<_SwipeToSwitch> {
  static const _trigger = 72.0; // 位移触发阈值（逻辑像素）
  static const _velocity = 600.0; // 快滑触发速度
  static const _upTrigger = 50.0; // 上滑打开全屏的位移阈值
  static const _upVelocity = -500.0;
  double _dx = 0;
  double _dy = 0;

  void _end(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dx;
    final hit = _dx.abs() > _trigger || v.abs() > _velocity;
    final forward = _dx < 0 || v < 0; // 左滑 → 下一首
    setState(() => _dx = 0);
    if (!hit) return;
    final actions = ref.read(playerActionsProvider);
    if (forward) {
      actions.playNext();
    } else {
      actions.playPrevious();
    }
  }

  void _verticalEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    final hit = _dy < -_upTrigger || v < _upVelocity;
    setState(() => _dy = 0);
    if (hit) openFullScreenPlayer(context);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) =>
          setState(() => _dx = (_dx + d.delta.dx).clamp(-90.0, 90.0)),
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      onVerticalDragUpdate: (d) =>
          setState(() => _dy = (_dy + d.delta.dy).clamp(-90.0, 0.0)),
      onVerticalDragEnd: _verticalEnd,
      onVerticalDragCancel: () => setState(() => _dy = 0),
      child: Transform.translate(
        offset: Offset(_dx * 0.55, _dy * 0.55),
        child: widget.child,
      ),
    );
  }
}
