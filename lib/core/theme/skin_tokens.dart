import 'package:flutter/material.dart';

import 'app_skin.dart';

/// 主题决定组件如何绘制，而不仅是替换一组颜色。
/// 业务页面只使用语义 token；容器/弹层/舞台由此选择各自的视觉实现。
enum SurfaceLanguage {
  liquidGlass,
  deepSpace,
  minimal,
  materialYou,
  sunset,
  forest,
  terminal,
  albumTint,
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
    required this.textPrimary,
    required this.glow,
    required this.blurScale,
    required this.blurEnabled,
    required this.highlightStrength,
    required this.radiusScale,
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
  final Color textPrimary; // 主文本（每套皮肤的白阶主色）
  final Color glow; // 科幻发光（透明 = 无发光）
  final double blurScale; // 模糊强度缩放
  final bool blurEnabled; // 极简/高对比强制关模糊
  final double highlightStrength; // 镜面高光强度（0 = 无高光，改实色描边）
  final double radiusScale; // 圆角档位缩放（玻璃面基准圆角 × scale；1.0 = 现状）
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
    textPrimary: Color(0xFFFFFFFF),
    glow: Color(0x00000000),
    blurScale: 1.0,
    blurEnabled: true,
    highlightStrength: 1.0,
    // 液态玻璃是基准皮肤：scale 恒为 1.0（播放页视觉已冻结在此皮肤）
    radiusScale: 1.0,
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
    textPrimary: Color(0xFFE8F4FF),
    glow: Color(0x3800E5FF),
    blurScale: 1.1,
    blurEnabled: false,
    highlightStrength: 0,
    radiusScale: 0.7, // 赛博几何感：中锐利圆角
    language: SurfaceLanguage.deepSpace,
  );

  static const minimal = SkinTokens(
    // 暖炭纸感：黑阶带微暖色温，与液态玻璃的冷蓝形成对比
    background: Color(0xFF141210),
    shell: Color(0xFF1A1714),
    detailBg: Color(0xFF171412),
    surface: Color(0xFF221E1A),
    divider: Color(0x14FFFFFF),
    glassTint: Color(0xF0221E1A),
    tintLight: Color(0x0DFFFFFF),
    borderTop: Color(0x1FFFFFFF),
    borderBottom: Color(0x0AFFFFFF),
    borderHairline: Color(0x1FFFFFFF),
    shadowColor: Color(0x33000000),
    textDim: Color(0xFFB3ABA2),
    textFaint: Color(0xFF6E655C),
    textPrimary: Color(0xFFF7F3EC),
    glow: Color(0x00000000),
    blurScale: 0,
    blurEnabled: false,
    highlightStrength: 0.2,
    radiusScale: 0.55, // 纸感：小圆角
    language: SurfaceLanguage.minimal,
  );

  static const materialYou = SkinTokens(
    // M3 暗色紫调面（tonal surface）：背景与面板带明显紫罗兰色温
    background: Color(0xFF14121B),
    shell: Color(0xFF1D1B22),
    detailBg: Color(0xFF1A181F),
    surface: Color(0xFF282430),
    divider: Color(0x14FFFFFF),
    glassTint: Color(0x522A2536),
    tintLight: Color(0x14FFFFFF),
    borderTop: Color(0x33FFFFFF),
    borderBottom: Color(0x0AFFFFFF),
    borderHairline: Color(0x1FFFFFFF),
    shadowColor: Color(0x40000000),
    textDim: Color(0xFFCAC4D0),
    textFaint: Color(0xFF79747E),
    textPrimary: Color(0xFFE6E1E5),
    glow: Color(0x00000000),
    blurScale: 1.0,
    blurEnabled: false,
    highlightStrength: 0,
    radiusScale: 1.3, // M3 大圆角
    language: SurfaceLanguage.materialYou,
  );

  static const sunset = SkinTokens(
    // 落日熔金：暖橙玫瑰色温，低垂夕阳光球由舞台绘制
    background: Color(0xFF1A0E0B),
    shell: Color(0xFF241310),
    detailBg: Color(0xFF1F110D),
    surface: Color(0xFF2E1A14),
    divider: Color(0x14FFFFFF),
    glassTint: Color(0xF02E1A14),
    tintLight: Color(0x14FFB27A),
    borderTop: Color(0x26FFC08A),
    borderBottom: Color(0x0AFF8A4C),
    borderHairline: Color(0x22FFB27A),
    shadowColor: Color(0x40000000),
    textDim: Color(0xFFD8B49A),
    textFaint: Color(0xFF8A6A55),
    textPrimary: Color(0xFFFFF3EA),
    glow: Color(0x33FF7A45),
    blurScale: 0,
    blurEnabled: false,
    highlightStrength: 0.15,
    radiusScale: 1.1, // 暖调柔圆
    language: SurfaceLanguage.sunset,
  );

  static const forest = SkinTokens(
    // 林间苔原：暖绿纸质，冠层微光 + 纸纹颗粒由舞台绘制
    background: Color(0xFF0E1410),
    shell: Color(0xFF131A14),
    detailBg: Color(0xFF101712),
    surface: Color(0xFF1C261D),
    divider: Color(0x14FFFFFF),
    glassTint: Color(0xF01C261D),
    tintLight: Color(0x0FFFFFFF),
    borderTop: Color(0x1FFFFFFF),
    borderBottom: Color(0x0AFFFFFF),
    borderHairline: Color(0x1FFFFFFF),
    shadowColor: Color(0x33000000),
    textDim: Color(0xFFAFC0AE),
    textFaint: Color(0xFF6E7C6C),
    textPrimary: Color(0xFFF1F5EE),
    glow: Color(0x00000000),
    blurScale: 0,
    blurEnabled: false,
    highlightStrength: 0.15,
    radiusScale: 0.6, // 自然小圆角
    language: SurfaceLanguage.forest,
  );

  static const terminal = SkinTokens(
    // 终端磷光：纯黑底 + 磷光绿文本/描边/发光，CRT 扫描线由舞台绘制
    background: Color(0xFF000000),
    shell: Color(0xFF050805),
    detailBg: Color(0xFF030503),
    surface: Color(0xFF0A120A),
    divider: Color(0x3333FF66),
    glassTint: Color(0xF00A120A),
    tintLight: Color(0x1433FF66),
    borderTop: Color(0x4033FF66),
    borderBottom: Color(0x1433FF66),
    borderHairline: Color(0x3333FF66),
    shadowColor: Color(0x00000000),
    textDim: Color(0xFF7FE08A),
    textFaint: Color(0xFF3E8A4C),
    textPrimary: Color(0xFF5CFF8A),
    glow: Color(0x4033FF66),
    blurScale: 0,
    blurEnabled: false,
    highlightStrength: 0,
    radiusScale: 0.0, // 终端窗口直角
    language: SurfaceLanguage.terminal,
  );

  /// 封面取色（与播放页同源公式）：由当前歌曲封面主色动态推导整套色板。
  /// 播放页渐变 top = 主色 lerp 黑 0.42 / 弹层底 = lerp 黑 0.55，
  /// 此处沿用同一色系；封面过亮时先压暗，保证白字对比度。
  static SkinTokens albumTint(Color dominant) {
    final base = dominant.computeLuminance() > 0.5
        ? Color.lerp(dominant, Colors.black, 0.45)!
        : dominant;
    Color mixBlack(double t) => Color.lerp(base, Colors.black, t)!;
    Color mixWhite(double t, double alpha) =>
        Color.lerp(base, Colors.white, t)!.withValues(alpha: alpha);
    return SkinTokens(
      background: mixBlack(0.42),
      shell: mixBlack(0.55),
      detailBg: mixBlack(0.60),
      surface: mixBlack(0.50),
      divider: mixWhite(0.4, 0.08),
      glassTint: mixBlack(0.50).withValues(alpha: 0.30),
      tintLight: mixWhite(0.5, 0.07),
      borderTop: mixWhite(0.35, 0.15),
      borderBottom: mixWhite(0.2, 0.04),
      borderHairline: mixWhite(0.3, 0.12),
      shadowColor: const Color(0x40000000),
      textDim: mixWhite(0.62, 1),
      textFaint: mixWhite(0.38, 1),
      textPrimary: Colors.white,
      glow: const Color(0x00000000),
      blurScale: 1.0,
      // 钦定：玻璃特性仅液态玻璃皮肤独有——封面取色卡片实色，顶栏也走实色底
      blurEnabled: false,
      highlightStrength: 0.5,
      radiusScale: 1.0,
      language: SurfaceLanguage.albumTint,
    );
  }

  /// 封面取色回退色板：取色中/取色失败（本地歌曲/无封面）时使用的中性深灰，
  /// 避免整页等待或闪变。
  static const albumTintFallback = SkinTokens(
    background: Color(0xFF101318),
    shell: Color(0xFF151920),
    detailBg: Color(0xFF14181E),
    surface: Color(0xFF1E242C),
    divider: Color(0x14FFFFFF),
    glassTint: Color(0x4D16202C),
    tintLight: Color(0x12FFFFFF),
    borderTop: Color(0x26FFFFFF),
    borderBottom: Color(0x0AFFFFFF),
    borderHairline: Color(0x1FFFFFFF),
    shadowColor: Color(0x40000000),
    textDim: Color(0xFF9AA3AD),
    textFaint: Color(0xFF565E68),
    textPrimary: Color(0xFFFFFFFF),
    glow: Color(0x00000000),
    blurScale: 1.0,
    blurEnabled: false,
    highlightStrength: 0.5,
    radiusScale: 1.0,
    language: SurfaceLanguage.albumTint,
  );

  static SkinTokens forSkin(AppSkin skin, {Color? albumDominant}) =>
      switch (skin) {
        AppSkin.liquidGlass => liquidGlass,
        AppSkin.deepSpace => deepSpace,
        AppSkin.minimal => minimal,
        AppSkin.materialYou => materialYou,
        AppSkin.sunset => sunset,
        AppSkin.forest => forest,
        AppSkin.terminal => terminal,
        AppSkin.albumTint when albumDominant != null => albumTint(
          albumDominant,
        ),
        AppSkin.albumTint => albumTintFallback,
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
    Color? textPrimary,
    Color? glow,
    double? blurScale,
    bool? blurEnabled,
    double? highlightStrength,
    double? radiusScale,
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
    textPrimary: textPrimary ?? this.textPrimary,
    glow: glow ?? this.glow,
    blurScale: blurScale ?? this.blurScale,
    blurEnabled: blurEnabled ?? this.blurEnabled,
    highlightStrength: highlightStrength ?? this.highlightStrength,
    radiusScale: radiusScale ?? this.radiusScale,
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
      textPrimary: cl(textPrimary, other.textPrimary),
      glow: cl(glow, other.glow),
      blurScale: blurScale + (other.blurScale - blurScale) * t,
      blurEnabled: t < 0.5 ? blurEnabled : other.blurEnabled,
      highlightStrength:
          highlightStrength + (other.highlightStrength - highlightStrength) * t,
      radiusScale: radiusScale + (other.radiusScale - radiusScale) * t,
      language: t < 0.5 ? language : other.language,
    );
  }
}
