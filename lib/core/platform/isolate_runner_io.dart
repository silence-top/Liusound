import 'dart:isolate';
import 'dart:async';

/// io 端：Isolate.run 后台执行，避免大 payload 编解码卡主 isolate
Future<T> runInIsolate<T>(FutureOr<T> Function() compute) =>
    Isolate.run(compute);
