part of 'player_actions.dart';

/// 错误处理与用户可见提示（P1-ErrorHandler）：播放链路的失败文案统一从这里出
mixin PlayerErrorHandler on PlayerActionsBase {
  void _notify(String message) =>
      _ref.read(resumeNoticeProvider.notifier).state = message;

  /// 调试日志（仅在 debug 构建输出，release 零成本）
  void _debugLog(String message) {
    assert(() {
      debugPrint(message);
      return true;
    }());
  }
}
