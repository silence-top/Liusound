import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../settings/streaming_prefs.dart';

/// 网络层运行时快照：由 serverAdapterProvider 在构建 adapter 前同步，
/// 各 adapter 构造函数调用 [configureDio] 应用到自己的 Dio。
/// 网络设置变更 → provider 重建 adapter → 重新应用，无需热更新已建连接。
abstract final class NetworkRuntime {
  static NetworkSettings settings = const NetworkSettings();

  static void configureDio(Dio dio) {
    final s = settings;
    dio.options.connectTimeout = Duration(seconds: s.timeoutSeconds);
    dio.options.receiveTimeout = Duration(seconds: s.timeoutSeconds * 2);
    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = _createHttpClient;
    }
  }

  static HttpClient _createHttpClient() {
    final s = settings;
    final client = HttpClient();
    client.connectionTimeout = Duration(seconds: s.timeoutSeconds);
    final proxy = s.proxy.trim();
    if (proxy.isNotEmpty) {
      client.findProxy = (uri) => 'PROXY $proxy';
    }
    if (!s.verifyCertificates) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    if (s.hostMap.isNotEmpty) {
      client.connectionFactory = (uri, proxyHost, proxyPort) =>
          _connectWithHosts(uri, s);
    }
    return client;
  }

  /// hosts 映射直连（忽略系统代理）。Dart 的 TLS 握手 SNI 取自传入的
  /// 连接主机名，映射后 SNI 为 IP：HTTP 完整生效；HTTPS 需配合关闭
  /// 证书校验（设置项说明中已注明）。
  static Future<ConnectionTask<Socket>> _connectWithHosts(
    Uri uri,
    NetworkSettings s,
  ) async {
    final hosts = s.hostMap;
    final mapped = hosts[uri.host];
    final port = uri.port != 0 ? uri.port : (uri.isScheme('https') ? 443 : 80);
    final target = mapped ?? uri.host;
    if (uri.isScheme('https')) {
      return SecureSocket.startConnect(
        target,
        port,
        onBadCertificate: s.verifyCertificates ? null : (_) => true,
      );
    }
    return Socket.startConnect(target, port);
  }
}
