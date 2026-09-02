import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lyrics/lyrics.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import 'full_screen_player.dart';
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

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.miniPlayer,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _SpinCover(song: song),
          const SizedBox(width: 12),
          // 文字区：点击进入全屏播放器
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openFullScreen(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  _LyricSubtitle(song: song),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 队列按钮：打开队列弹窗
          GestureDetector(
            onTap: () => showQueueModal(context),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.queue_music,
                  size: 28, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            FullScreenPlayer(onClose: () => Navigator.of(context).pop()),
      ),
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
                child: CoverArt(albumId: widget.song.albumId, size: 44),
              ),
            ),
            if (!isPlaying)
              const Icon(Icons.play_circle_filled,
                  size: 38, color: Colors.white),
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
      painter: _RingPainter(progress: progress, stroke: _stroke),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.stroke});

  final double progress;
  final double stroke;

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
      ..color = AppTheme.queueActive; // #1DB954

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
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// 副标题：优先当前歌词行，其次下一行，无歌词时显示「歌手 - 专辑」（对齐 1.x）。
class _LyricSubtitle extends ConsumerStatefulWidget {
  const _LyricSubtitle({required this.song});

  final Song song;

  @override
  ConsumerState<_LyricSubtitle> createState() => _LyricSubtitleState();
}

class _LyricSubtitleState extends ConsumerState<_LyricSubtitle> {
  List<LyricLine> _lines = const [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(_LyricSubtitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.song.id != oldWidget.song.id) {
      _parse();
    }
  }

  void _parse() {
    setState(() => _lines = parseLyricsData(widget.song.lyrics).lines);
  }

  @override
  Widget build(BuildContext context) {
    String text;
    if (_lines.isEmpty) {
      text = '${widget.song.artist} - ${widget.song.album}';
    } else {
      final position =
          ref.watch(positionProvider).valueOrNull ?? Duration.zero;
      final idx =
          findLyricIndex(_lines, position.inMilliseconds / 1000.0);
      // 前奏（-1）时显示第一句（对齐 1.x currentLyric→nextLyric 回退）
      text = idx >= 0 ? _lines[idx].text : _lines.first.text;
    }

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        color: Colors.white.withValues(alpha: 0.8),
      ),
    );
  }
}
