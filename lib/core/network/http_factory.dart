import 'package:dio/dio.dart';

import '../settings/streaming_prefs.dart';

import 'http_factory_web.dart'
    if (dart.library.io) 'http_factory_io.dart'
    show applyPlatformHttp;
export 'http_factory_web.dart'
    if (dart.library.io) 'http_factory_io.dart'
    show applyPlatformHttp;

/// 网络层配置应用器（P1-NetworkRuntime：无全局可变状态）。
/// 网络设置由 serverAdapterProvider 显式注入 adapter 构造函数，
/// adapter 构造时调用 [configureDio] 应用到自己的 Dio；
/// 网络设置变更 → provider 重建 adapter → 重新应用，无需热更新已建连接。
/// 平台专属项（代理/自签证书/hosts 映射）在 `http_factory_io.dart` /
/// `http_factory_web.dart` 按平台实现。
abstract final class NetworkRuntime {
  static void configureDio(Dio dio, NetworkSettings s) {
    dio.options.connectTimeout = Duration(seconds: s.timeoutSeconds);
    dio.options.receiveTimeout = Duration(seconds: s.timeoutSeconds * 2);
    applyPlatformHttp(dio, s);
  }
}
