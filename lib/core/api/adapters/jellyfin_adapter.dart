import '../../errors/app_error.dart';

import '../../settings/streaming_prefs.dart';
import '../server_adapter.dart';
import '../server_type.dart';
import 'mediabrowser_adapter.dart';

/// Jellyfin 适配器（基于 MediaBrowser 共享基类）。
/// 认证：POST /Users/AuthenticateByName → AccessToken + User.Id。
class JellyfinAdapter extends MediaBrowserAdapter {
  JellyfinAdapter({
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
  ServerType get type => ServerType.jellyfin;

  @override
  String get clientName => 'Jellyfin';

  @override
  Map<String, String> get authHeaders => {
    if (token.isNotEmpty) 'Authorization': 'MediaBrowser Token=$token',
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
      client: 'Jellyfin',
    );
    final accessToken = data['AccessToken']?.toString() ?? '';
    final userId = data['User']?['Id']?.toString() ?? '';
    if (accessToken.isEmpty || userId.isEmpty) {
      throw const AuthError('Jellyfin 静默重登失败');
    }
    return {'token': accessToken, 'userId': userId};
  }

  static Future<AdapterSession> signIn(AuthRequest request) async {
    final data = await MediaBrowserAdapter.authenticateByName(
      request.serverUrl,
      request.username,
      request.password,
      client: 'Jellyfin',
    );
    final accessToken = data['AccessToken']?.toString() ?? '';
    final userId = data['User']?['Id']?.toString() ?? '';
    if (accessToken.isEmpty || userId.isEmpty) {
      throw AuthError('Jellyfin 登录响应缺少认证信息');
    }
    return AdapterSession(
      secrets: {'token': accessToken, 'userId': userId},
      displayName: data['User']?['Name']?.toString(),
    );
  }
}
