import 'dart:async';

/// web 端无 isolate：主线程直接执行（大 payload 可能掉帧，Phase 2 再优化）
Future<T> runInIsolate<T>(FutureOr<T> Function() compute) async => compute();
