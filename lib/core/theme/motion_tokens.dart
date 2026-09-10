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

  // ---------- 场景时长 ----------
  /// 页面转场（fadeRoute）/ 跟手落位 / 歌词自动滚动 / 封面淡入（300ms 档）
  static const Duration durationTransition = Duration(milliseconds: 300);

  /// 快速反馈类小动画（转场退场 / 导航指示条）
  static const Duration durationSnappy = Duration(milliseconds: 220);

  /// 封面切换淡入（全屏唱片 350ms 档）
  static const Duration durationCoverFade = Duration(milliseconds: 350);

  /// 氛围/背景类大渐变过渡
  static const Duration durationAmbient = Duration(milliseconds: 600);
}
