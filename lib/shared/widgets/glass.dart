import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/local_image.dart';
import '../../core/theme/background.dart';
import '../../core/theme/glass_theme.dart';
import '../../core/theme/skin_tokens.dart';
import '../../core/theme/settings_prefs.dart';
import 'glass_quality.dart';

export '../../core/theme/glass_theme.dart';
export 'glass_quality.dart';

/// ── 主题组件命名契约 ─────────────────────────────────────────
/// 页面层只消费语义组件，不直接判断皮肤枚举或手写颜色；
/// 每个组件的视觉由 [SkinTokens.language] 分派（GlassSurface/AmbientBackground 内部）：
/// - AppStage = 页面舞台（AmbientBackground，含各主题专属装饰）
/// - AppSurface = 卡片/列表/输入框容器（GlassSurface）
/// - AppSheet / AppDialog = glassBottomSheet / glassDialog
/// - AppListEnd = shared/widgets/list_end_mark.dart 的 ListEndMark
typedef AppStage = AmbientBackground;
typedef AppSurface = GlassSurface;

/// 历史名称保留给调用方兼容；绘制由 [SkinTokens.language] 分派。
/// 液态玻璃以外的主题不会退化成“关掉 blur 的玻璃”。
class GlassSurface extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SkinTokens.of(context);
    // 让全局视觉设置成为响应式依赖，已保活页面和底部导航会同步刷新。
    ref.watch(glassQualityProvider);
    ref.watch(powerSaveProvider);
    final tintOpacity = ref.watch(glassTintOpacityProvider);
    // blur<=0（列表卡片纯 tint 提质）不挂 BackdropFilter，避免无谓的 saveLayer；
    // 极简/高对比皮肤整体关闭模糊
    final blurRequested = blur > 0 && tokens.blurEnabled;
    final useBlur = shouldUseBlur(context) && blurRequested;
    final blurScale = glassBlurScale(context) * tokens.blurScale;
    // 内容透色：默认 tint 混入主题色，玻璃随 accent 带微弱色感
    final accent = Theme.of(context).colorScheme.primary;
    final effectiveTint =
        tint ??
        Color.alphaBlend(accent.withValues(alpha: 0.08), tokens.glassTint);
    final highlight = tokens.highlightStrength;
    // 皮肤圆角档位：玻璃面基准圆角 × 皮肤缩放（胶囊 999 保持全圆不缩放）
    final scaledRadius = radius == GlassTokens.radiusPill
        ? radius
        : radius * tokens.radiusScale;
    final borderRadius = BorderRadius.circular(scaledRadius);

    if (tokens.language != SurfaceLanguage.liquidGlass) {
      return RepaintBoundary(
        child: _buildNonGlassSurface(
          context,
          tokens: tokens,
          tintOpacity: tintOpacity,
        ),
      );
    }

    // 本来要挂模糊但档位关闭/省电降级时，0.30 左右的玻璃 tint 会直接透底——
    // 把 tint 叠到皮肤实色 surface 上补成近实色（系数 1.0 时不透明，
    // 用户调低透明度则按比例透出）；blur<=0 的纯 tint 卡片（GlassCard 等）
    // 维持原有 lerp 变暗路径，不受档位影响。三条路径都乘用户透明度系数
    final cardTint = Color.lerp(effectiveTint, Colors.black, 0.15)!;
    final degradedColor = blurRequested
        ? Color.alphaBlend(
            effectiveTint,
            tokens.surface,
          ).withValues(alpha: tintOpacity)
        : cardTint.withValues(
            alpha: (cardTint.a * tintOpacity).clamp(0.0, 1.0),
          );

    // 顶部斜向高光是玻璃反光质感的核心，blur 与纯 tint 两条路径共用
    Widget tinted(Widget child) => Container(
      padding: padding,
      decoration: BoxDecoration(
        color: useBlur
            ? effectiveTint.withValues(
                alpha: (effectiveTint.a * tintOpacity).clamp(0.0, 1.0),
              )
            : degradedColor,
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
                stops: const [0.0, 0.25],
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
        radius: scaledRadius,
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
          borderRadius: BorderRadius.circular(scaledRadius),
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

  Widget _buildNonGlassSurface(
    BuildContext context, {
    required SkinTokens tokens,
    required double tintOpacity,
  }) {
    final requestedTint = tint == tokens.glassTint ? null : tint;
    // 非玻璃面同样走皮肤圆角档位（radiusScale 表达高对比直角/极简小圆角；
    // 胶囊仍保持全圆）。面板底色乘用户透明度系数——所有皮肤都可调透明
    final baseSurface = requestedTint ?? tokens.surface;
    final surfaceColor = baseSurface.withValues(
      alpha: (baseSurface.a * tintOpacity).clamp(0.0, 1.0),
    );
    final effectiveRadius = BorderRadius.circular(
      radius == GlassTokens.radiusPill ? radius : radius * tokens.radiusScale,
    );
    final decoration = switch (tokens.language) {
      SurfaceLanguage.deepSpace => BoxDecoration(
        color: surfaceColor,
        borderRadius: effectiveRadius,
        border: Border.all(color: tokens.borderHairline),
        boxShadow: shadow
            ? [BoxShadow(color: tokens.glow, blurRadius: 18, spreadRadius: -5)]
            : null,
      ),
      SurfaceLanguage.minimal => BoxDecoration(
        color: surfaceColor,
        borderRadius: effectiveRadius,
        border: Border.all(color: tokens.divider),
      ),
      SurfaceLanguage.materialYou => BoxDecoration(
        color: surfaceColor,
        borderRadius: effectiveRadius,
        border: Border.all(color: tokens.borderHairline),
      ),
      SurfaceLanguage.sunset => BoxDecoration(
        color: surfaceColor,
        borderRadius: effectiveRadius,
        border: Border.all(color: tokens.borderHairline),
        boxShadow: shadow
            ? [BoxShadow(color: tokens.glow, blurRadius: 18, spreadRadius: -6)]
            : null,
      ),
      SurfaceLanguage.forest => BoxDecoration(
        color: surfaceColor,
        borderRadius: effectiveRadius,
        border: Border.all(color: tokens.borderHairline),
      ),
      SurfaceLanguage.terminal => BoxDecoration(
        color: surfaceColor,
        borderRadius: effectiveRadius,
        border: Border.all(color: tokens.borderHairline),
        boxShadow: shadow
            ? [BoxShadow(color: tokens.glow, blurRadius: 10, spreadRadius: -4)]
            : null,
      ),
      SurfaceLanguage.albumTint => BoxDecoration(
        color: surfaceColor,
        borderRadius: effectiveRadius,
        border: Border.all(color: tokens.borderHairline),
      ),
      SurfaceLanguage.liquidGlass => throw StateError('Handled above'),
    };
    final result = Container(
      margin: margin,
      padding: padding,
      decoration: decoration,
      child: Material(type: MaterialType.transparency, child: child),
    );
    return result;
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

/// 自定义图片背景时降低卡片底色不透明度（封顶 0.75），
/// 让背景图从卡片后面透出来；无图时原样返回。
Color imageBgAwareTint(WidgetRef ref, Color tint) {
  final hasImage = ref.watch(backgroundProvider.select((b) => b.path != null));
  if (hasImage && tint.a > 0.75) return tint.withValues(alpha: 0.75);
  return tint;
}

class GlassCard extends ConsumerWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.tint,
    this.padding,
    this.margin,
    this.onTap,
    this.radius = GlassTokens.radiusCard,
  });

  final Widget child;

  /// 覆盖默认主题 tint（播放页周边弹层传封面取色，保持与宿主弹层同色系）
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 卡片展示关：内容卡降级为裸排（保留内外边距，去掉卡面/描边/投影）
    if (!ref.watch(cardDisplayProvider)) {
      return _bare(
        onTap: onTap,
        padding: padding,
        margin: margin,
        child: child,
      );
    }
    final effectiveTint = imageBgAwareTint(
      ref,
      tint ?? GlassTokens.tint(context),
    );
    final card = GlassSurface(
      radius: radius,
      blur: 0,
      tint: effectiveTint,
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

/// 卡片展示关时的裸排降级：只保留边距，不画任何卡面
Widget _bare({
  VoidCallback? onTap,
  EdgeInsetsGeometry? padding,
  EdgeInsetsGeometry? margin,
  required Widget child,
}) {
  Widget bare = child;
  if (padding != null) bare = Padding(padding: padding, child: bare);
  if (margin != null) bare = Padding(padding: margin, child: bare);
  if (onTap != null) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: bare,
    );
  }
  return bare;
}

class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.tint,
    this.padding,
    this.margin,
    this.onTap,
    this.blur = GlassTokens.blurMedium,
  });

  final Widget child;

  /// 覆盖默认主题 tint（迷你播放条等传封面取色，与播放页同色系）
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final pill = GlassSurface(
      radius: GlassTokens.radiusPill,
      blur: blur,
      tint: tint ?? GlassTokens.tint(context),
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
class GlassContainer extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // 卡片展示关：容器降级为裸排（保留内外边距，去掉模糊/卡面/描边/投影）
    if (!ref.watch(cardDisplayProvider)) {
      return _bare(
        onTap: onTap,
        padding: padding,
        margin: margin,
        child: child,
      );
    }
    final container = GlassSurface(
      radius: radius,
      blur: blur,
      tint: imageBgAwareTint(ref, GlassTokens.tint(context)),
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

class GlassAppBar extends ConsumerWidget implements PreferredSizeWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SkinTokens.of(context);
    final useBlur = shouldUseBlur(context) && tokens.blurEnabled;
    final blurScale = glassBlurScale(context) * tokens.blurScale;
    final tint = withGlassTintOpacity(ref, tokens.glassTint);
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
                  color: tint,
                  border: Border(
                    bottom: BorderSide(color: tokens.borderTop, width: 0.5),
                  ),
                ),
                child: _buildBar(context),
              ),
            )
          : Container(
              decoration: BoxDecoration(
                color: tokens.background.withValues(
                  alpha: 0.95 * ref.watch(glassTintOpacityProvider),
                ),
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
  // 播放器相关弹层可传封面取色 tint（如歌曲操作弹窗的定时/速度选择器），
  // null 时保持主题自适应玻璃
  Color? tint,
}) {
  return showModalBottomSheet<T>(
    context: context,
    barrierColor: Colors.black38,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final content = GlassSurface(
        radius: GlassTokens.radiusSheet,
        blur: GlassTokens.blurHeavy,
        tint: tint ?? GlassTokens.tint(ctx),
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
                style: TextStyle(
                  color: SkinTokens.of(context).textPrimary,
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
    final tokens = SkinTokens.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    // 用户自定义背景图最高优先级：设置后跳过所有皮肤舞台装饰，图片即背景
    // （全皮肤生效，包括封面取色/终端）；未设图时才渲染各皮肤专属舞台
    final hasImage = bg.path != null;
    // 本地文件 → ImageProvider（web 端返回 null，回退皮肤舞台）
    final bgImage = hasImage ? localFileImage(bg.path!) : null;
    return Stack(
      children: [
        if (!hasImage) ...[
          // 液态玻璃独有的折射光源（减淡版：低强度，保留模糊可折物但不抢戏）。
          // 其他主题绝不复用此舞台。
          if (tokens.language == SurfaceLanguage.liquidGlass) ...[
            Positioned(
              top: -140,
              left: -100,
              child: _blob(340, primary.withValues(alpha: 0.10)),
            ),
            Positioned(
              bottom: -80,
              left: 20,
              child: _blob(300, primary.withValues(alpha: 0.075)),
            ),
          ],
          // 深空主题采用星图/扫描线，不使用玻璃光斑。
          if (tokens.language == SurfaceLanguage.deepSpace)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _DeepSpaceStagePainter(primary)),
              ),
            ),
          // 极简：暖炭纸纹颗粒（细微质感，区别于纯色扁平）。
          if (tokens.language == SurfaceLanguage.minimal)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GrainStagePainter(tokens.textFaint, density: 0.6),
                ),
              ),
            ),
          // Material You：M3 柔光球（跟随动态主色）。
          if (tokens.language == SurfaceLanguage.materialYou)
            Positioned(
              top: -120,
              right: -80,
              child: _blob(360, primary.withValues(alpha: 0.16)),
            ),
          // 落日：低垂夕阳暖光球 + 顶部暖晕。
          if (tokens.language == SurfaceLanguage.sunset)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SunsetStagePainter(tokens.glow, primary),
                ),
              ),
            ),
          // 林间：冠层微光 + 纸纹颗粒。
          if (tokens.language == SurfaceLanguage.forest)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ForestStagePainter(tokens.textFaint),
                ),
              ),
            ),
          // 终端：CRT 扫描线 + 顶部磷光晕。
          if (tokens.language == SurfaceLanguage.terminal)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CrtStagePainter(tokens.textPrimary),
                ),
              ),
            ),
          // 封面取色：顶部提亮渐变，复刻播放页「上浅下深」的单色纵深。
          if (tokens.language == SurfaceLanguage.albumTint)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [tokens.tintLight, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
        ],
        if (bgImage != null)
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
                        child: Image(
                          image: bgImage,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      )
                    : Image(
                        image: bgImage,
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

class _DeepSpaceStagePainter extends CustomPainter {
  const _DeepSpaceStagePainter(this.primary);

  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = primary.withValues(alpha: 0.055)
      ..strokeWidth = 1;
    const step = 56.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final star = Paint()..color = primary.withValues(alpha: 0.45);
    for (final point in const [
      Offset(34, 96),
      Offset(164, 178),
      Offset(294, 72),
      Offset(92, 486),
      Offset(342, 624),
      Offset(226, 744),
    ]) {
      if (point.dx < size.width && point.dy < size.height) {
        canvas.drawCircle(point, 1.3, star);
      }
    }
  }

  @override
  bool shouldRepaint(_DeepSpaceStagePainter oldDelegate) =>
      oldDelegate.primary != primary;
}

/// 纸纹颗粒：seeded Random 保证每帧点位固定（静态背景不闪烁），density 控密度。
class _GrainStagePainter extends CustomPainter {
  const _GrainStagePainter(this.color, {this.density = 1.0});

  final Color color;
  final double density;

  @override
  void paint(Canvas canvas, Size size) {
    final rand = Random(7);
    final grain = Paint()..color = color.withValues(alpha: 0.05);
    final count = (size.width * size.height / 900 * density)
        .clamp(0, 900)
        .toInt();
    for (var i = 0; i < count; i++) {
      final x = rand.nextDouble() * size.width;
      final y = rand.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 0.7, grain);
    }
  }

  @override
  bool shouldRepaint(_GrainStagePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.density != density;
}

/// 落日舞台：顶部暖晕 + 低垂夕阳径向光球。
class _SunsetStagePainter extends CustomPainter {
  const _SunsetStagePainter(this.glow, this.primary);

  final Color glow;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final washRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.55);
    final wash = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [primary.withValues(alpha: 0.10), Colors.transparent],
      ).createShader(washRect);
    canvas.drawRect(washRect, wash);

    final sunCenter = Offset(size.width * 0.5, size.height * 0.94);
    final sunRadius = size.width * 0.72;
    final sun = Paint()
      ..shader = RadialGradient(
        colors: [glow.withValues(alpha: 0.55), glow.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: sunRadius));
    canvas.drawCircle(sunCenter, sunRadius, sun);
  }

  @override
  bool shouldRepaint(_SunsetStagePainter oldDelegate) =>
      oldDelegate.glow != glow || oldDelegate.primary != primary;
}

/// 林间舞台：顶部冠层微光 + 纸纹颗粒。
class _ForestStagePainter extends CustomPainter {
  const _ForestStagePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final canopyRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.6);
    final canopy = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.10), Colors.transparent],
      ).createShader(canopyRect);
    canvas.drawRect(canopyRect, canopy);

    final rand = Random(11);
    final grain = Paint()..color = color.withValues(alpha: 0.05);
    final count = (size.width * size.height / 1100).clamp(0, 700).toInt();
    for (var i = 0; i < count; i++) {
      final x = rand.nextDouble() * size.width;
      final y = rand.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), 0.7, grain);
    }
  }

  @override
  bool shouldRepaint(_ForestStagePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 终端舞台：CRT 水平扫描线 + 顶部磷光晕。
class _CrtStagePainter extends CustomPainter {
  const _CrtStagePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 3.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final glowCenter = Offset(size.width * 0.5, -size.height * 0.08);
    final glowRadius = size.width * 0.9;
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.10), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius));
    canvas.drawCircle(glowCenter, glowRadius, vignette);
  }

  @override
  bool shouldRepaint(_CrtStagePainter oldDelegate) =>
      oldDelegate.color != color;
}
