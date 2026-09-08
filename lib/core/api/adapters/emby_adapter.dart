import '../../errors/app_error.dart';

import '../../settings/streaming_prefs.dart';
import '../server_adapter.dart';
import '../server_type.dart';
import 'mediabrowser_adapter.dart';

/// Emby 适配器（基于 MediaBrowser 共享基类）。
/// 认证：X-Emby-Authorization 含 MD5 密码哈希 + X-Emby-Token 头。
class EmbyAdapter extends MediaBrowserAdapter {
  EmbyAdapter({
    required ServerConfig config,
    required Map<String, String> secrets,
    NetworkSettings networkSettings = const NetworkSettings(),
  }) : super(
         serverUrl: config.serverUrl,
         username: config.username,
         secrets: secrets,
         networkSettings: networkSettings,
       );

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

  @override
  Future<Map<String, String>> loginWithPassword(String password) async {
    final data = await MediaBrowserAdapter.authenticateByName(
      serverUrl,
      username,
      password,
      client: 'Emby',
      md5Password: true,
    );
    final accessToken = data['AccessToken']?.toString() ?? '';
    final userId = data['User']?['Id']?.toString() ?? '';
    if (accessToken.isEmpty || userId.isEmpty) {
      throw const AuthError('Emby 静默重登失败');
    }
    return {'token': accessToken, 'userId': userId};
  }

  static Future<AdapterSession> signIn(AuthRequest request) async {
    final data = await MediaBrowserAdapter.authenticateByName(
      request.serverUrl,
      request.username,
      request.password,
      client: 'Emby',
      md5Password: true,
    );
    final accessToken = data['AccessToken']?.toString() ?? '';
    final userId = data['User']?['Id']?.toString() ?? '';
    if (accessToken.isEmpty || userId.isEmpty) {
      throw AuthError('Emby 登录响应缺少认证信息');
    }
    return AdapterSession(
      secrets: {'token': accessToken, 'userId': userId},
      displayName: data['User']?['Name']?.toString(),
    );
  }
}
