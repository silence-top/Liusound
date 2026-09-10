import 'dart:io';

/// io 端平台判定。
/// 鸿蒙（OpenHarmony SIG fork）下 Platform.operatingSystem 返回 'ohos'。
abstract final class AppPlatform {
  static final String _os = Platform.operatingSystem;

  static bool get isAndroid => _os == 'android';
  static bool get isIOS => _os == 'ios';
  static bool get isWindows => _os == 'windows';
  static bool get isMacOS => _os == 'macos';
  static bool get isLinux => _os == 'linux';
  static bool get isOhos => _os == 'ohos';
  static bool get isWeb => false;
  static bool get isMobile => isAndroid || isIOS || isOhos;
  static bool get isDesktop => isWindows || isMacOS || isLinux;

  /// 环境变量（web 无此概念返回 null）
  static String? env(String key) => Platform.environment[key];
}
