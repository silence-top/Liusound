import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../server_adapter.dart';
import '../server_type.dart';
import 'mediabrowser_adapter.dart';

/// Emby 适配器（基于 MediaBrowser 共享基类）。
/// 认证：X-Emby-Authorization 含 MD5 密码哈希 + X-Emby-Token 头。
class EmbyAdapter extends MediaBrowserAdapter {
  EmbyAdapter({
    required ServerConfig config,
    required Map<String, String> secrets,
  }) : super(serverUrl: config.serverUrl, secrets: secrets);

  @override
  ServerType get type => ServerType.emby;

  @override
  String get clientName => 'Emby';

  @override
  Map<String, String> get authHeaders => {
    if (token.isNotEmpty) ...{
      'X-Emby-Authorization':
          'MediaBrowser Client="Emby", Device="Flutter", DeviceId="liusound", Version="2.0", Token=$token',
      'X-Emby-Token': token,
    },
  };

  @override
  Map<String, String> extractSecrets(Map<String, dynamic> loginResponse) {
    return {
      'token': loginResponse['AccessToken']?.toString() ?? '',
      'userId': loginResponse['User']?['Id']?.toString() ?? '',
    };
  }

  static Future<AdapterSession> signIn(AuthRequest request) async {
    final pwMd5 = md5.convert(request.password.codeUnits).toString();
    final dio = Dio(
      BaseOptions(
        baseUrl: request.serverUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    try {
      final res = await dio.post<Map<String, dynamic>>(
        '/Users/AuthenticateByName',
        data: {'Username': request.username, 'Pw': pwMd5},
        options: Options(
          headers: {
            'X-Emby-Authorization': 'MediaBrowser Client="Emby", Device="Flutter", DeviceId="liusound", Version="2.0"',
          },
        ),
      );
      final data = res.data ?? const {};
      final accessToken = data['AccessToken']?.toString() ?? '';
      final userId = data['User']?['Id']?.toString() ?? '';
      if (accessToken.isEmpty || userId.isEmpty) {
        throw Exception('Emby 登录响应缺少认证信息');
      }
      return AdapterSession(
        secrets: {'token': accessToken, 'userId': userId},
        displayName: data['User']?['Name']?.toString(),
      );
    } finally {
      dio.close();
    }
  }
}
