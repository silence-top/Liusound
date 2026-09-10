import 'package:dio/dio.dart';

import '../settings/streaming_prefs.dart';

/// web 端：浏览器自管代理/证书，hosts 映射与自签放行不可用（CORS 由
/// 服务端放行，Phase 2 评估）；仅保留超时（已在门面统一设置）。
void applyPlatformHttp(Dio dio, NetworkSettings s) {}
