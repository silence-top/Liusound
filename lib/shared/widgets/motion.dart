import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/motion_tokens.dart';
import '../../core/theme/settings_prefs.dart';

PageRoute<T> fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: MotionTokens.durationTransition,
    reverseTransitionDuration: MotionTokens.durationSnappy,
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, _, child) {
      final curved = animation.drive(
        CurveTween(curve: MotionTokens.curveStandard),
      );
      final bg = animation.drive(
        CurveTween(curve: const Interval(0, 0.3, curve: Curves.easeOut)),
      );
      final reduce = AppMotion.reduceMotion(context);
      return FadeTransition(
        opacity: bg,
        child: ColoredBox(
          color: AppTheme.shellOf(context),
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: reduce ? Offset.zero : const Offset(0, 0.025),
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

class FadeSlideIn extends ConsumerWidget {
  const FadeSlideIn({super.key, required this.child, this.index});

  final Widget child;
  final int? index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final powerSave = ref.watch(powerSaveProvider);
    final reduce = AppMotion.reduceMotion(context) || powerSave;
    final i = index;
    final curve = i == null || reduce
        ? MotionTokens.curveStandard
        : Interval(
            math.min(i * 0.06, 0.3),
            1,
            curve: MotionTokens.curveEmphasized,
          );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.duration(context, MotionTokens.durationEntrance),
      curve: curve,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, reduce ? 0 : AppSpacing.l * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AnimatedScale(
      scale: _down && !AppMotion.reduceMotion(context) ? 0.98 : 1,
      duration: AppMotion.duration(context, MotionTokens.durationFast),
      curve: MotionTokens.curveStandard,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => _down = value),
          onFocusChange: (value) => setState(() => _focused = value),
          borderRadius: BorderRadius.circular(AppRadius.m),
          hoverColor: primary.withValues(alpha: 0.08),
          focusColor: primary.withValues(alpha: 0.12),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.m),
              border: Border.all(
                color: _focused ? primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

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
    duration: MotionTokens.durationSnappy,
    value: 1,
  );

  @override
  void didUpdateWidget(PopOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reduceMotion(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Opacity(
        opacity: 0.65 + 0.35 * _ctrl.value,
        child: Transform.scale(
          scale: reduce
              ? 1
              : 0.88 + 0.12 * MotionTokens.curveStandard.transform(_ctrl.value),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

abstract final class AppMotion {
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, Duration base) {
    final powerSave = ProviderScope.containerOf(context)
        .read(powerSaveProvider);
    return powerSave || reduceMotion(context)
        ? Duration(milliseconds: (base.inMilliseconds * 0.4).round())
        : base;
  }
}
