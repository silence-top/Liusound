import 'package:dio/dio.dart';

/// 401 → 静默重登一次并重放原请求（MediaBrowser 系与 Plex 共用）。
/// QueuedInterceptor 串行化错误处理，避免并发 401 触发多次重登；
/// 重放请求打 extra 标记，再 401 直接放行（密码也失效时如实报错）。
class ReauthInterceptor extends QueuedInterceptor {
  ReauthInterceptor({
    required this.reauthenticate,
    required this.applyFreshCredentials,
    required this.dio,
  });

  /// 用本地保存的账号密码换新凭证；失败抛异常则回落原始 401
  final Future<void> Function() reauthenticate;

  /// 重登成功后把新凭证写回待重放请求（MediaBrowser 改 header，Plex 改 query）
  final void Function(RequestOptions opts) applyFreshCredentials;

  final Dio dio;

  static const _retriedKey = 'liusoundReauthRetried';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    if (err.response?.statusCode == 401 && opts.extra[_retriedKey] != true) {
      try {
        await reauthenticate();
        opts.extra[_retriedKey] = true;
        applyFreshCredentials(opts);
        final response = await dio.fetch<dynamic>(opts);
        return handler.resolve(response);
      } catch (_) {
        // 重登失败：回落到原始 401 错误，由调用方按类型展示
      }
    }
    handler.next(err);
  }
}
