import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/settings_prefs.dart';

/// 溢出才跑的跑马灯文本。
///
/// 默认按 [maxLines] 截断（和普通 Text 完全一致，零动画开销）；
/// 仅当文本真的放不下时，长按可切换为单行往返滚动，把被截断的部分读完。
/// [autoScroll] 为真时溢出自动做一次往返扫动（单次、有界，不无限循环；
/// 省电模式跳过），扫完后长按仍可手动重看。
/// 自研实现，不引入 marquee 依赖；未溢出的场景不会创建任何动画。
class MarqueeText extends ConsumerStatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 1,
    this.autoScroll = false,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  /// 溢出时自动往返扫动一遍；省电模式（§8.5）保持静态省略号
  final bool autoScroll;

  @override
  ConsumerState<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends ConsumerState<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  bool _scrolling = false;

  /// 最近一次布局测得的溢出距离，长按启动滚动时用来定时长
  double _distance = 0;

  bool _overflow = false;

  /// 每份（文本×样式×宽度）测量结果只自动扫一次，避免父级重建反复起跑
  bool _autoSwept = false;

  bool _powerSave = false;

  // 测量结果缓存：卡片重 build（文本/样式/宽度都没变）时零 TextPainter 开销
  String? _cachedText;
  TextStyle? _cachedStyle;
  int? _cachedMaxLines;
  double _cachedMaxWidth = -1;
  TextScaler? _cachedScaler;

  @override
  void initState() {
    super.initState();
    _powerSave = ref.read(powerSaveProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 溢出判断（按 maxLines 是否截断）与滚动距离（单行全文宽 - 可用宽）。
  /// 单行放得下时只需一次不限宽布局；两者语义不同，多行溢出时才需要第二次
  /// 受限布局兜底判断。
  void _measure(double maxWidth) {
    final scaler = MediaQuery.textScalerOf(context);
    if (widget.text == _cachedText &&
        widget.style == _cachedStyle &&
        widget.maxLines == _cachedMaxLines &&
        maxWidth == _cachedMaxWidth &&
        scaler == _cachedScaler) {
      return;
    }
    _cachedText = widget.text;
    _cachedStyle = widget.style;
    _cachedMaxLines = widget.maxLines;
    _cachedMaxWidth = maxWidth;
    _cachedScaler = scaler;
    _overflow = false;
    _distance = 0;
    _autoSwept = false;
    if (maxWidth <= 0 || !maxWidth.isFinite) return;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      // 系统大字号下实际渲染更宽，测量必须同倍率，否则溢出判断/滚动距离失真
      textScaler: scaler,
    )..layout();
    final singleWidth = painter.width;
    if (singleWidth <= maxWidth) {
      painter.dispose();
      return;
    }
    if (widget.maxLines == 1) {
      _overflow = true;
      _distance = singleWidth - maxWidth;
      painter.dispose();
      return;
    }
    painter
      ..maxLines = widget.maxLines
      ..layout(maxWidth: maxWidth);
    if (painter.didExceedMaxLines) {
      _overflow = true;
      _distance = singleWidth - maxWidth;
    }
    painter.dispose();
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

  /// 自动扫一遍（去 → 回 → 停在开头）；中途被打断（长按接管/省电）不再续跑
  void _sweep() {
    if (_autoSwept || _scrolling || _powerSave || _distance <= 0) return;
    _autoSwept = true;
    final ms = (_distance * 40).clamp(600, 6000).toInt();
    _controller.duration = Duration(milliseconds: ms);
    setState(() => _scrolling = true);
    _controller.forward().whenComplete(() {
      if (!mounted || !_scrolling) return;
      _controller.reverse().whenComplete(() {
        if (!mounted || !_scrolling) return;
        _controller.stop();
        setState(() => _scrolling = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(powerSaveProvider, (_, next) {
      _powerSave = next;
      if (next) _stop();
    });
    return LayoutBuilder(
      builder: (context, constraints) {
        _measure(constraints.maxWidth);
        if (!_overflow) {
          // 文本变短不再溢出时滚动态要复位，但 setState 不能在 build 期调
          if (_scrolling) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _stop();
            });
          }
          return _clamped();
        }
        if (widget.autoScroll) {
          // 单次扫动在布局完成后起跑；长按留给外层卡片菜单，不抢手势
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _sweep();
          });
          return _clamped();
        }
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
