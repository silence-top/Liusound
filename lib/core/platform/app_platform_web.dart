/// web 端平台判定：恒为 web，其余平台标志全 false。
abstract final class AppPlatform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isOhos => false;
  static bool get isWeb => true;
  static bool get isMobile => false;
  static bool get isDesktop => false;

  static String? env(String key) => null;
}
