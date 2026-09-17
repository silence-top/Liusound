import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/motion_tokens.dart';
import '../../core/theme/settings_prefs.dart';

/// 统一页面转场：不透明底色 + 内容淡入上移（300ms easeOutCubic）。
/// 全应用二级页一律用 `Navigator.push(context, fadeRoute(Page()))`，
/// 替代默认 MaterialPageRoute。
/// 底色在前 30% 转场内快速到位：正转期间下层不再透出（修复弹出页
/// 「透明的」观感），反向整页淡出露出下层，dismiss 手感自然。
PageRoute<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: MotionTokens.durationTransition,
    reverseTransitionDuration: MotionTokens.durationSnappy,
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: MotionTokens.curveStandard,
        reverseCurve: Curves.easeInCubic,
      );
      final bg = CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.3, curve: Curves.easeOut),
        reverseCurve: Curves.linear,
      );
      return FadeTransition(
        opacity: bg,
        child: ColoredBox(
          color: AppTheme.shellOf(context),
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// 列表项入场动效：淡入 + 上移 14px（320ms easeOutCubic）。
/// 传 index 时同批进入的相邻项按 35ms/项错峰（封顶 25% 延迟），
/// 包在列表/网格 item 外层即可，滚动到可视区自动触发，无状态管理。
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index});

  final Widget child;

  /// 同批入场的序号（可选）：用于错峰编排
  final int? index;

  @override
  Widget build(BuildContext context) {
    final i = index;
    final curve = i == null
        ? MotionTokens.curveStandard
        : Interval(
            math.min(i * 0.035, 0.25),
            1.0,
            curve: MotionTokens.curveStandard,
          );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MotionTokens.durationEntrance,
      curve: curve,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// 按压缩放反馈（0.97，120ms），用于卡片类点击区域，
/// 叠加在 InkWell 之上提供更明显的物理按压手感。
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) => setState(() => _down = false),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 值变更时弹跳反馈：缩放过冲回落（1 → 1.25 → 1），
/// 用于收藏爱心等状态切换图标的确认动效。
class PopOnChange extends StatefulWidget {
  const PopOnChange({super.key, required this.value, required this.child});

  final Object value;
  final Widget child;

  @override
  State<PopOnChange> createState() => _PopOnChangeState();
}

class _PopOnChangeState extends State<PopOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: MotionTokens.durationPop,
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.25,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.25,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 55,
    ),
  ]).animate(_ctrl);

  @override
  void didUpdateWidget(PopOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: widget.child,
    );
  }
}

/// §8.5 省电模式动画工具：省电模式下将动画时长压缩为 40%，
/// 减少 GPU 渲染压力同时保留基本过渡反馈
abstract final class AppMotion {
  static Duration duration(BuildContext context, Duration base) {
    final powerSave = ProviderScope.containerOf(context)
        .read(powerSaveProvider);
    return powerSave
        ? Duration(milliseconds: (base.inMilliseconds * 0.4).round())
        : base;
  }
}
