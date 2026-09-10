/// 平台判定门面：业务代码统一经 [AppPlatform] 判断运行环境，
/// 禁止直接 import 'dart:io' / 使用 Platform.*（web 编译断点）。
library;

export 'app_platform_web.dart' if (dart.library.io) 'app_platform_io.dart';
