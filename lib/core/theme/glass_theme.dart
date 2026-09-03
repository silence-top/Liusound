import 'dart:ui' show Color;

abstract final class GlassTokens {
  static const blurHeavy = 28.0;
  static const blurMedium = 18.0;
  static const blurLight = 10.0;

  static const tint = Color(0x4D13243C);
  static const tintLight = Color(0x14FFFFFF);
  static const borderTop = Color(0x33FFFFFF);
  static const borderBottom = Color(0x0AFFFFFF);
  static const shadow = Color(0x40000000);

  // 圆角对齐 AppRadius 档位：l 16 / pill 999 / xl 24
  static const radiusCard = 16.0;
  static const radiusPill = 999.0;
  static const radiusSheet = 24.0;
}
