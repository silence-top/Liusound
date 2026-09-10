/// 后台 isolate 计算门面：io 端走 Isolate.run，web 端主线程直接算
/// （web 无 isolate，dart:isolate 的 spawn 在 web 运行时不可用）。
library;

export 'isolate_runner_web.dart' if (dart.library.io) 'isolate_runner_io.dart';
