import 'package:flutter/material.dart';

import 'skin_tokens.dart';

/// 液态玻璃 token 中枢：
/// - 尺寸类（blur/radius）与主题无关，保持 static const，可作默认参数；
/// - 颜色类随皮肤（SkinTokens ThemeExtension）切换，改为 of(context) 方法。
/// 调用面兼容：`GlassTokens.tint` → `GlassTokens.tint(context)`。
abstract final class GlassTokens {
  // ---- 尺寸（不变） ----
  static const blurHeavy = 28.0;
  static const blurMedium = 18.0;
  static const blurContainer = 12.0; // 容器级浮层（导航栏/单卡），列表行禁用
  static const blurLight = 10.0;

  // 圆角对齐 AppRadius 档位：l 16 / pill 999 / xl 24
  static const radiusCard = 16.0;
  static const radiusPill = 999.0;
  static const radiusSheet = 24.0;

  // ---- 颜色（随皮肤） ----
  static Color tint(BuildContext c) => SkinTokens.of(c).glassTint;
  static Color tintLight(BuildContext c) => SkinTokens.of(c).tintLight;
  static Color borderTop(BuildContext c) => SkinTokens.of(c).borderTop;
  static Color borderBottom(BuildContext c) => SkinTokens.of(c).borderBottom;
  static Color borderHairline(BuildContext c) =>
      SkinTokens.of(c).borderHairline;
  static Color shadow(BuildContext c) => SkinTokens.of(c).shadowColor;
  static double blurScale(BuildContext c) => SkinTokens.of(c).blurScale;
  static bool blurEnabled(BuildContext c) => SkinTokens.of(c).blurEnabled;
  static double highlightStrength(BuildContext c) =>
      SkinTokens.of(c).highlightStrength;
  static Color glow(BuildContext c) => SkinTokens.of(c).glow;
}
