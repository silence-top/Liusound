/// 省电模式刷新率切换门面（flutter_displaymode 仅 Android；iOS 无公开 API）。
/// 调用方无需关心平台：非 Android 端为 no-op。
library;

export 'display_mode_web.dart' if (dart.library.io) 'display_mode_io.dart';
