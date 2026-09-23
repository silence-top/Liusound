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

  /// 列表项入场（FadeSlideIn）
  static const Duration durationEntrance = Duration(milliseconds: 320);

  /// 图标状态切换弹跳（PopOnChange）
  static const Duration durationPop = Duration(milliseconds: 380);

  /// 播放键点击扩散脉冲
  static const Duration durationPulse = Duration(milliseconds: 320);

  /// 播放键呼吸光环循环周期
  static const Duration durationHalo = Duration(milliseconds: 2400);

  static const Duration durationVinylTurn = Duration(seconds: 18);
  static const Duration durationCdTurn = Duration(seconds: 12);

  /// 背景光斑漂移循环周期（Lissajous 一整圈）
  static const Duration durationAmbientLoop = Duration(seconds: 26);

  /// 深空星点闪烁循环周期
  static const Duration durationTwinkle = Duration(seconds: 4);
}
