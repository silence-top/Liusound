import 'package:flutter/material.dart';

/// 溢出才跑的跑马灯文本。
///
/// 默认按 [maxLines] 截断（和普通 Text 完全一致，零动画开销）；
/// 仅当文本真的放不下时，长按可切换为单行往返滚动，把被截断的部分读完。
/// 自研实现，不引入 marquee 依赖；未溢出的场景不会创建任何动画。
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  bool _scrolling = false;

  /// 最近一次布局测得的溢出距离，长按启动滚动时用来定时长
  double _distance = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _exceeds(double maxWidth) {
    if (maxWidth <= 0 || !maxWidth.isFinite) return false;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: widget.maxLines,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }

  double _singleLineWidth() {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width;
  }

  void _start() {
    if (_distance <= 0) return;
    // 滚动速度恒定：约 40ms/px，两端各夹一个最短/最长时长避免过快或拖沓
    final ms = (_distance * 40).clamp(600, 6000).toInt();
    _controller.duration = Duration(milliseconds: ms);
    setState(() => _scrolling = true);
    _controller.repeat(reverse: true);
  }

  void _stop() {
    if (!_scrolling) return;
    _controller.stop();
    _controller.value = 0;
    setState(() => _scrolling = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflow = _exceeds(constraints.maxWidth);
        if (!overflow) {
          _distance = 0;
          return _clamped();
        }
        final overflowBy =
            _singleLineWidth() - constraints.maxWidth;
        _distance = overflowBy > 0 ? overflowBy : 0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (_) => _start(),
          onLongPressEnd: (_) => _stop(),
          onLongPressCancel: _stop,
          child: _scrolling ? _marquee() : _clamped(),
        );
      },
    );
  }

  Widget _clamped() => Text(
        widget.text,
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );

  Widget _marquee() => ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.translate(
            offset: Offset(-_distance * _controller.value, 0),
            child: child,
          ),
          child: Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: widget.style,
          ),
        ),
      );
}
