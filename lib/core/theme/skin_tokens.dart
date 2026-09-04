import 'package:flutter/material.dart';

import 'app_skin.dart';

/// 主题决定组件如何绘制，而不仅是替换一组颜色。
/// 业务页面只使用语义 token；容器/弹层/舞台由此选择各自的视觉实现。
enum SurfaceLanguage {
  liquidGlass,
  deepSpace,
  minimal,
  materialYou,
  highContrast,
}

/// 每主题 token 束（ThemeExtension 注入 ThemeData，组件层经 context 读取）。
/// 尺寸类 token（blur/radius）与主题无关，留在 GlassTokens 常量；
/// 颜色/发光/模糊缩放随皮肤切换。
class SkinTokens extends ThemeExtension<SkinTokens> {
  const SkinTokens({
    required this.background,
    required this.shell,
    required this.detailBg,
    required this.surface,
    required this.divider,
    required this.glassTint,
    required this.tintLight,
    required this.borderTop,
    required this.borderBottom,
    required this.borderHairline,
    required this.shadowColor,
    required this.textDim,
    required this.textFaint,
    required this.glow,
    required this.blurScale,
    required this.blurEnabled,
    required this.highlightStrength,
    required this.language,
  });

  final Color background; // 页面背景（scaffold/appbar）
  final Color shell; // 主框架背景
  final Color detailBg; // 详情/列表二级页背景
  final Color surface; // 卡片 / 输入框
  final Color divider; // 分隔线
  final Color glassTint; // 玻璃面板 tint
  final Color tintLight; // 亮色薄雾
  final Color borderTop; // 玻璃上缘受光
  final Color borderBottom; // 玻璃下缘
  final Color borderHairline; // 1px 均匀微亮描边
  final Color shadowColor; // 投影
  final Color textDim; // 次要文本
  final Color textFaint; // 装饰图标 / 占位
  final Color glow; // 科幻发光（透明 = 无发光）
  final double blurScale; // 模糊强度缩放
  final bool blurEnabled; // 极简/高对比强制关模糊
  final double highlightStrength; // 镜面高光强度（0 = 无高光，改实色描边）
  final SurfaceLanguage language;

  static SkinTokens of(BuildContext c) => Theme.of(c).extension<SkinTokens>()!;

  static const liquidGlass = SkinTokens(
    background: Color(0xFF001B2E),
    shell: Color(0xFF0A1428),
    detailBg: Color(0xFF0A1A2A),
    surface: Color(0xFF1A2C3A),
    divider: Color(0x14FFFFFF),
    glassTint: Color(0x4D13243C),
    tintLight: Color(0x14FFFFFF),
    borderTop: Color(0x33FFFFFF),
    borderBottom: Color(0x0AFFFFFF),
    borderHairline: Color(0x1FFFFFFF),
    shadowColor: Color(0x40000000),
    textDim: Color(0xFF888888),
    textFaint: Color(0xFF444444),
    glow: Color(0x00000000),
    blurScale: 1.0,
    blurEnabled: true,
    highlightStrength: 1.0,
    language: SurfaceLanguage.liquidGlass,
  );

  static const deepSpace = SkinTokens(
    background: Color(0xFF05070E),
    shell: Color(0xFF070A14),
    detailBg: Color(0xFF080D18),
    surface: Color(0xFF0D1322),
    divider: Color(0x1828C8FF),
    glassTint: Color(0x59101830),
    tintLight: Color(0x1A9BE8FF),
    borderTop: Color(0x4048D8FF),
    borderBottom: Color(0x0D28C8FF),
    borderHairline: Color(0x2428C8FF),
    shadowColor: Color(0x66000000),
    textDim: Color(0xFF9FB4CC),
    textFaint: Color(0xFF4A5A72),
    glow: Color(0x3800E5FF),
    blurScale: 1.1,
    blurEnabled: false,
    highlightStrength: 0,
    language: SurfaceLanguage.deepSpace,
  );

  static const minimal = SkinTokens(
    background: Color(0xFF111111),
    shell: Color(0xFF161616),
    detailBg: Color(0xFF141414),
    surface: Color(0xFF1F1F1F),
    divider: Color(0x14FFFFFF),
    glassTint: Color(0xF01F1F1F),
    tintLight: Color(0x0DFFFFFF),
    borderTop: Color(0x1FFFFFFF),
    borderBottom: Color(0x0AFFFFFF),
    borderHairline: Color(0x1FFFFFFF),
    shadowColor: Color(0x33000000),
    textDim: Color(0xFFAAAAAA),
    textFaint: Color(0xFF666666),
    glow: Color(0x00000000),
    blurScale: 0,
    blurEnabled: false,
    highlightStrength: 0.2,
    language: SurfaceLanguage.minimal,
  );

  static const materialYou = SkinTokens(
    background: Color(0xFF131318),
    shell: Color(0xFF1B1B21),
    detailBg: Color(0xFF191920),
    surface: Color(0xFF232329),
    divider: Color(0x14FFFFFF),
    glassTint: Color(0x52262630),
    tintLight: Color(0x14FFFFFF),
    borderTop: Color(0x33FFFFFF),
    borderBottom: Color(0x0AFFFFFF),
    borderHairline: Color(0x1FFFFFFF),
    shadowColor: Color(0x40000000),
    textDim: Color(0xFFCAC4D0),
    textFaint: Color(0xFF79747E),
    glow: Color(0x00000000),
    blurScale: 1.0,
    blurEnabled: false,
    highlightStrength: 0,
    language: SurfaceLanguage.materialYou,
  );

  static const highContrast = SkinTokens(
    background: Color(0xFF000000),
    shell: Color(0xFF000000),
    detailBg: Color(0xFF000000),
    surface: Color(0xFF111111),
    divider: Color(0x66FFFFFF),
    glassTint: Color(0xE6111111),
    tintLight: Color(0x24FFFFFF),
    borderTop: Color(0x99FFFFFF),
    borderBottom: Color(0x66FFFFFF),
    borderHairline: Color(0x66FFFFFF),
    shadowColor: Color(0x00000000),
    textDim: Color(0xFFE0E0E0),
    textFaint: Color(0xFFB0B0B0),
    glow: Color(0x00000000),
    blurScale: 0,
    blurEnabled: false,
    highlightStrength: 0.0,
    language: SurfaceLanguage.highContrast,
  );

  static SkinTokens forSkin(AppSkin skin) => switch (skin) {
    AppSkin.liquidGlass => liquidGlass,
    AppSkin.deepSpace => deepSpace,
    AppSkin.minimal => minimal,
    AppSkin.materialYou => materialYou,
    AppSkin.highContrast => highContrast,
  };

  @override
  SkinTokens copyWith({
    Color? background,
    Color? shell,
    Color? detailBg,
    Color? surface,
    Color? divider,
    Color? glassTint,
    Color? tintLight,
    Color? borderTop,
    Color? borderBottom,
    Color? borderHairline,
    Color? shadowColor,
    Color? textDim,
    Color? textFaint,
    Color? glow,
    double? blurScale,
    bool? blurEnabled,
    double? highlightStrength,
    SurfaceLanguage? language,
  }) => SkinTokens(
    background: background ?? this.background,
    shell: shell ?? this.shell,
    detailBg: detailBg ?? this.detailBg,
    surface: surface ?? this.surface,
    divider: divider ?? this.divider,
    glassTint: glassTint ?? this.glassTint,
    tintLight: tintLight ?? this.tintLight,
    borderTop: borderTop ?? this.borderTop,
    borderBottom: borderBottom ?? this.borderBottom,
    borderHairline: borderHairline ?? this.borderHairline,
    shadowColor: shadowColor ?? this.shadowColor,
    textDim: textDim ?? this.textDim,
    textFaint: textFaint ?? this.textFaint,
    glow: glow ?? this.glow,
    blurScale: blurScale ?? this.blurScale,
    blurEnabled: blurEnabled ?? this.blurEnabled,
    highlightStrength: highlightStrength ?? this.highlightStrength,
    language: language ?? this.language,
  );

  @override
  SkinTokens lerp(SkinTokens? other, double t) {
    if (other == null) return this;
    Color cl(Color a, Color b) => Color.lerp(a, b, t)!;
    return SkinTokens(
      background: cl(background, other.background),
      shell: cl(shell, other.shell),
      detailBg: cl(detailBg, other.detailBg),
      surface: cl(surface, other.surface),
      divider: cl(divider, other.divider),
      glassTint: cl(glassTint, other.glassTint),
      tintLight: cl(tintLight, other.tintLight),
      borderTop: cl(borderTop, other.borderTop),
      borderBottom: cl(borderBottom, other.borderBottom),
      borderHairline: cl(borderHairline, other.borderHairline),
      shadowColor: cl(shadowColor, other.shadowColor),
      textDim: cl(textDim, other.textDim),
      textFaint: cl(textFaint, other.textFaint),
      glow: cl(glow, other.glow),
      blurScale: blurScale + (other.blurScale - blurScale) * t,
      blurEnabled: t < 0.5 ? blurEnabled : other.blurEnabled,
      highlightStrength:
          highlightStrength + (other.highlightStrength - highlightStrength) * t,
      language: t < 0.5 ? language : other.language,
    );
  }
}
