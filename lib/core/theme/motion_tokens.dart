import 'package:flutter/animation.dart';

/// 动效令牌（P1-MotionTokens）：全局统一的时长与曲线。
/// 页面转场 / 弹层 / MiniPlayer / 淡入淡出 / AnimatedSize / 列表入场
/// 一律从这里取值，禁止散落硬编码 Duration/Curve
abstract final class MotionTokens {
  // ---------- 时长 ----------
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);

  // ---------- 曲线 ----------
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEmphasized = Curves.easeInOutCubicEmphasized;
  static const Curve curveDecelerated = Curves.easeOutCirc;
}
