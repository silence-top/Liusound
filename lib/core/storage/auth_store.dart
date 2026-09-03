import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 统一存储层（对标 1.x services/config.ts + storageService）：
/// - 敏感三要素（token / subsonicToken / subsonicSalt）走 flutter_secure_storage
///   （iOS Keychain / Android Keystore；Web 端由插件加密后落 localStorage）
/// - 非敏感项（serverUrl / username）走 shared_preferences
class AuthStore {
  AuthStore();

  // flutter_secure_storage 11.x 默认已启用平台安全存储（EncryptedSharedPreferences / Keychain）
  static const _secure = FlutterSecureStorage();

  static const _kToken = 'token';
  static const _kSubsonicToken = 'subsonicToken';
  static const _kSubsonicSalt = 'subsonicSalt';
  static const _kServerUrl = 'server_url';
  static const _kUsername = 'username';

  /// 读取已持久化的会话；任一关键项缺失即视为未登录
  Future<StoredSession?> readSession() async {
    final results = await Future.wait([
      _secure.read(key: _kToken),
      _secure.read(key: _kSubsonicToken),
      _secure.read(key: _kSubsonicSalt),
      SharedPreferences.getInstance(),
    ]);
    final token = results[0] as String?;
    final subsonicToken = results[1] as String?;
    final subsonicSalt = results[2] as String?;
    final prefs = results[3] as SharedPreferences;
    final serverUrl = prefs.getString(_kServerUrl) ?? '';
    final username = prefs.getString(_kUsername) ?? '';

    if (token == null || token.isEmpty || serverUrl.isEmpty) return null;
    return StoredSession(
      serverUrl: serverUrl,
      username: username,
      token: token,
      subsonicToken: subsonicToken ?? '',
      subsonicSalt: subsonicSalt ?? '',
    );
  }

  Future<void> saveSession(StoredSession session) => Future.wait([
    _secure.write(key: _kToken, value: session.token),
    _secure.write(key: _kSubsonicToken, value: session.subsonicToken),
    _secure.write(key: _kSubsonicSalt, value: session.subsonicSalt),
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kServerUrl, session.serverUrl);
      await prefs.setString(_kUsername, session.username);
    }(),
  ]);

  /// 登出：清空全部会话数据（含两处敏感存储）
  Future<void> clear() async {
    await Future.wait([
      _secure.delete(key: _kToken),
      _secure.delete(key: _kSubsonicToken),
      _secure.delete(key: _kSubsonicSalt),
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_kServerUrl);
        await prefs.remove(_kUsername);
      }(),
    ]);
  }
}

/// 已持久化的会话（认证三要素 + 服务器信息）
class StoredSession {
  const StoredSession({
    required this.serverUrl,
    required this.username,
    required this.token,
    required this.subsonicToken,
    required this.subsonicSalt,
  });

  final String serverUrl;
  final String username;
  final String token;
  final String subsonicToken;
  final String subsonicSalt;
}
