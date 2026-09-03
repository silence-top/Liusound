import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/glass_theme.dart';
import 'glass_quality.dart';

export '../../core/theme/glass_theme.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = GlassTokens.radiusCard,
    this.blur = GlassTokens.blurMedium,
    this.tint,
    this.gradientBorder = true,
    this.padding,
    this.margin,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color? tint;
  final bool gradientBorder;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    // blur<=0（列表卡片纯 tint 提质）不挂 BackdropFilter，避免无谓的 saveLayer
    final useBlur = shouldUseBlur(context) && blur > 0;
    final blurScale = glassBlurScale(context);
    final effectiveTint = tint ?? GlassTokens.tint;
    final borderRadius = BorderRadius.circular(radius);

    // 顶部斜向高光是玻璃反光质感的核心，blur 与纯 tint 两条路径共用
    Widget tinted(Widget child) => Container(
          padding: padding,
          decoration: BoxDecoration(
            color: useBlur
                ? effectiveTint
                : Color.lerp(effectiveTint, Colors.black, 0.15)!,
            borderRadius: borderRadius,
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.45],
            ),
          ),
          child: child,
        );

    Widget result = ClipRRect(
      borderRadius: borderRadius,
      child: useBlur
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(
                  sigmaX: blur * blurScale, sigmaY: blur * blurScale),
              child: tinted(child),
            )
          : tinted(child),
    );

    if (gradientBorder) {
      result = _GradientBorderWrapper(
        radius: radius,
        child: result,
      );
    }

    if (shadow) {
      result = Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(
              color: GlassTokens.shadow,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: result,
      );
    } else if (margin != null) {
      result = Padding(padding: margin!, child: result);
    }

    return RepaintBoundary(child: result);
  }
}

class _GradientBorderWrapper extends StatelessWidget {
  const _GradientBorderWrapper({
    required this.radius,
    required this.child,
  });

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _GradientBorderPainter(radius),
      child: child,
    );
  }
}

/// 顶部亮 → 底部弱的渐变描边（玻璃边缘受光效果）
class _GradientBorderPainter extends CustomPainter {
  const _GradientBorderPainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.08),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GradientBorderPainter oldDelegate) =>
      oldDelegate.radius != radius;
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.radius = GlassTokens.radiusCard,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final card = GlassSurface(
      radius: radius,
      blur: 0,
      tint: GlassTokens.tint,
      gradientBorder: true,
      padding: padding,
      margin: margin,
      shadow: false,
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      );
    }
    return card;
  }
}

class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.blur = GlassTokens.blurMedium,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final pill = GlassSurface(
      radius: GlassTokens.radiusPill,
      blur: blur,
      tint: GlassTokens.tint,
      gradientBorder: true,
      padding: padding,
      margin: margin,
      shadow: true,
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: pill,
      );
    }
    return pill;
  }
}

class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.preferredSize = const Size.fromHeight(56),
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  @override
  final Size preferredSize;

  @override
  Widget build(BuildContext context) {
    final useBlur = shouldUseBlur(context);
    final blurScale = glassBlurScale(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(GlassTokens.radiusCard),
      ),
      child: useBlur
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: GlassTokens.blurMedium * blurScale,
                sigmaY: GlassTokens.blurMedium * blurScale,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: GlassTokens.tint,
                  border: Border(
                    bottom: BorderSide(
                      color: GlassTokens.borderTop,
                      width: 0.5,
                    ),
                  ),
                ),
                child: _buildBar(context),
              ),
            )
          : Container(
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: 0.95),
                border: Border(
                  bottom: BorderSide(
                    color: GlassTokens.borderTop,
                    width: 0.5,
                  ),
                ),
              ),
              child: _buildBar(context),
            ),
    );
  }

  Widget _buildBar(BuildContext context) {
    return SizedBox(
      height: preferredSize.height,
      child: Row(
        children: [
          ?leading,
          if (title != null)
            Expanded(
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
                child: title!,
              ),
            ),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

Future<T?> glassBottomSheet<T>(
  BuildContext context,
  Widget child, {
  bool scrollable = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    barrierColor: Colors.black38,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final content = GlassSurface(
        radius: GlassTokens.radiusSheet,
        blur: GlassTokens.blurHeavy,
        tint: GlassTokens.tint,
        gradientBorder: true,
        padding: EdgeInsets.only(
          top: 12,
          bottom: MediaQuery.of(ctx).padding.bottom + 16,
          left: 16,
          right: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            if (scrollable)
              Flexible(child: SingleChildScrollView(child: child))
            else
              child,
          ],
        ),
      );
      return Padding(
        padding: const EdgeInsets.all(8),
        child: content,
      );
    },
  );
}

/// 为自定义 showModalBottomSheet 提供玻璃容器约束。
/// 用于内容含独立滚动（ReorderableListView / GridView 等）而不适合 glassBottomSheet 的场景。
BoxConstraints glassSheetConstraints(BuildContext context, {double factor = 0.7}) =>
    BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * factor,
    );

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, this.child});

  final Widget? child;

  static Widget _blob(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 大尺度彩色光斑：为玻璃模糊提供可折射的内容，太淡则 blur 几乎不可见
        Positioned(
            top: -140,
            left: -100,
            child: _blob(340, const Color(0x332196F3))),
        Positioned(
            top: 80,
            right: -120,
            child: _blob(300, const Color(0x2E1EB4FF))),
        Positioned(
            bottom: -80,
            left: 20,
            child: _blob(300, const Color(0x267ECFFF))),
        ?child,
      ],
    );
  }
}
