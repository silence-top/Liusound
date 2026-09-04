import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/background.dart';
import '../../core/theme/glass_theme.dart';
import '../../core/theme/skin_tokens.dart';
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
    this.borderColor,
    this.padding,
    this.margin,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final double blur;
  final Color? tint;
  final bool gradientBorder;

  /// 纯色 1px 描边（音质分级等需要用颜色表达语义的场景）；
  /// 设置后不再叠加白色渐变描边，避免两条边互相干扰
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final tokens = SkinTokens.of(context);
    // blur<=0（列表卡片纯 tint 提质）不挂 BackdropFilter，避免无谓的 saveLayer；
    // 极简/高对比皮肤整体关闭模糊
    final useBlur = shouldUseBlur(context) && blur > 0 && tokens.blurEnabled;
    final blurScale = glassBlurScale(context) * tokens.blurScale;
    // 内容透色：默认 tint 混入主题色，玻璃随 accent 带微弱色感
    final accent = Theme.of(context).colorScheme.primary;
    final effectiveTint =
        tint ??
        Color.alphaBlend(accent.withValues(alpha: 0.08), tokens.glassTint);
    final highlight = tokens.highlightStrength;
    final borderRadius = BorderRadius.circular(radius);

    // 顶部斜向高光是玻璃反光质感的核心，blur 与纯 tint 两条路径共用
    Widget tinted(Widget child) => Container(
      padding: padding,
      decoration: BoxDecoration(
        color: useBlur
            ? effectiveTint
            : Color.lerp(effectiveTint, Colors.black, 0.15)!,
        borderRadius: borderRadius,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 1),
      ),
      foregroundDecoration: highlight <= 0
          ? null
          : BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.10 * highlight),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.45],
              ),
            ),
      // 透明 Material：让内部 ListTile/InkWell 的墨水落在自身 Material 上，
      // 否则会被外层带背景色的 DecoratedBox 挡住（debug 断言 + 水波纹不可见）
      child: Material(type: MaterialType.transparency, child: child),
    );

    Widget result = ClipRRect(
      borderRadius: borderRadius,
      child: useBlur
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: blur * blurScale,
                sigmaY: blur * blurScale,
              ),
              child: tinted(child),
            )
          : tinted(child),
    );

    if (gradientBorder && borderColor == null) {
      result = _GradientBorderWrapper(
        radius: radius,
        strength: highlight,
        accent: accent,
        fallback: tokens.borderHairline,
        child: result,
      );
    }

    if (shadow && (tokens.shadowColor.a > 0 || tokens.glow.a > 0)) {
      result = Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            if (tokens.shadowColor.a > 0)
              BoxShadow(
                color: tokens.shadowColor,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            if (tokens.glow.a > 0)
              BoxShadow(color: tokens.glow, blurRadius: 24),
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
    required this.strength,
    required this.accent,
    required this.fallback,
    required this.child,
  });

  final double radius;
  final double strength;
  final Color accent;
  final Color fallback;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _GradientBorderPainter(
        radius,
        strength: strength,
        accent: accent,
        fallback: fallback,
      ),
      child: child,
    );
  }
}

/// 玻璃边缘受光：顶部亮 → 底部弱的渐变描边，顶部混入 accent（内容透色）；
/// 高光强度为 0（高对比皮肤）时退化为 1px 实色描边保证边缘可见
class _GradientBorderPainter extends CustomPainter {
  const _GradientBorderPainter(
    this.radius, {
    required this.strength,
    required this.accent,
    required this.fallback,
  });

  final double radius;
  final double strength;
  final Color accent;
  final Color fallback;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    if (strength <= 0) {
      paint.color = fallback;
    } else {
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.alphaBlend(
            accent.withValues(alpha: 0.35 * strength),
            Colors.white.withValues(alpha: 0.35 * strength),
          ),
          Colors.white.withValues(alpha: 0.08 * strength),
        ],
      ).createShader(rect);
    }
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GradientBorderPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.strength != strength ||
      oldDelegate.accent != accent ||
      oldDelegate.fallback != fallback;
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
      tint: GlassTokens.tint(context),
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
      tint: GlassTokens.tint(context),
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

/// 容器级液态玻璃浮层：12px 背景模糊 + 1px 受光描边 + 投影，营造浮空层叠感。
/// 性能红线：仅用于非滚动 chrome 或单卡（导航栏 / 服务器卡 / 分组外框），
/// 列表滚动项一律用 blur 为 0 的 [GlassCard]，禁止逐行挂 BackdropFilter。
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.radius = GlassTokens.radiusCard,
    this.blur = GlassTokens.blurContainer,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final container = GlassSurface(
      radius: radius,
      blur: blur,
      tint: GlassTokens.tint(context),
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
        child: container,
      );
    }
    return container;
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
    final tokens = SkinTokens.of(context);
    final useBlur = shouldUseBlur(context) && tokens.blurEnabled;
    final blurScale = glassBlurScale(context) * tokens.blurScale;
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
                  color: tokens.glassTint,
                  border: Border(
                    bottom: BorderSide(color: tokens.borderTop, width: 0.5),
                  ),
                ),
                child: _buildBar(context),
              ),
            )
          : Container(
              decoration: BoxDecoration(
                color: tokens.background.withValues(alpha: 0.95),
                border: Border(
                  bottom: BorderSide(color: tokens.borderTop, width: 0.5),
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
                // H3 字阶，与 AppBar titleTextStyle 保持一致
                style: Theme.of(context).textTheme.titleMedium!,
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
        tint: GlassTokens.tint(ctx),
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
                // 圆角豁免：sheet 顶部拖动条 4px 高，仅 2px 圆角
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
      return Padding(padding: const EdgeInsets.all(8), child: content);
    },
  );
}

/// 为自定义 showModalBottomSheet 提供玻璃容器约束。
/// 用于内容含独立滚动（ReorderableListView / GridView 等）而不适合 glassBottomSheet 的场景。
BoxConstraints glassSheetConstraints(
  BuildContext context, {
  double factor = 0.7,
}) => BoxConstraints(maxHeight: MediaQuery.of(context).size.height * factor);

/// 玻璃对话框：AlertDialog 的液态玻璃替代，标题 + 可滚动内容 + 右下操作区。
Future<T?> glassDialog<T>(
  BuildContext context, {
  required Widget content,
  String? title,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black38,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: GlassSurface(
        radius: GlassTokens.radiusSheet,
        blur: GlassTokens.blurHeavy,
        tint: Color.alphaBlend(
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          SkinTokens.of(context).glassTint,
        ),
        gradientBorder: true,
        shadow: false,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Flexible(child: SingleChildScrollView(child: content)),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ],
        ),
      ),
    ),
  );
}

class AmbientBackground extends ConsumerWidget {
  const AmbientBackground({super.key, this.child});

  final Widget? child;

  static Widget _blob(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = ref.watch(backgroundProvider);
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        // 大尺度彩色光斑：为玻璃模糊提供可折射的内容，太淡则 blur 几乎不可见
        Positioned(
          top: -140,
          left: -100,
          child: _blob(340, primary.withValues(alpha: 0.20)),
        ),
        Positioned(
          top: 80,
          right: -120,
          child: _blob(300, primary.withValues(alpha: 0.18)),
        ),
        Positioned(
          bottom: -80,
          left: 20,
          child: _blob(300, primary.withValues(alpha: 0.15)),
        ),
        // §8.1 自定义背景图：全屏铺底 + 不透明度 + 可选模糊
        if (bg.path != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: bg.opacity.clamp(0.0, 1.0),
                child: bg.blur > 0
                    ? ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: bg.blur,
                          sigmaY: bg.blur,
                        ),
                        child: Image.file(
                          File(bg.path!),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      )
                    : Image.file(
                        File(bg.path!),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
              ),
            ),
          ),
        ?child,
      ],
    );
  }
}
