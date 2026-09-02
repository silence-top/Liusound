import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/navidrome_client.dart';
import '../../core/storage/auth_store.dart';
import '../../core/subsonic/subsonic.dart';

/// 全局唯一的 REST 客户端
final navidromeClientProvider = Provider<NavidromeClient>((ref) => NavidromeClient());

class AuthState {
  const AuthState({this.session, this.initialized = false});

  final StoredSession? session;
  final bool initialized; // 冷启动恢复是否完成（决定是否显示启动 loading）

  bool get isAuthenticated => session != null;
}

/// 认证状态控制器：冷启动恢复会话 / 登录 / 登出
class AuthController extends Notifier<AuthState> {
  late final AuthStore _store = AuthStore();

  @override
  AuthState build() {
    _restore();
    return const AuthState(); // initialized=false → 启动 loading
  }

  Future<void> _restore() async {
    try {
      final session = await _store.readSession();
      if (session != null) {
        ref.read(navidromeClientProvider).setSession(session);
      }
      state = AuthState(session: session, initialized: true);
    } catch (_) {
      // 恢复失败按未登录处理（安全存储异常等情况）
      state = const AuthState(initialized: true);
    }
  }

  /// 登录：请求成功后持久化会话并同步内存凭证
  Future<void> login(String serverUrl, String username, String password) async {
    final client = ref.read(navidromeClientProvider);
    final result = await client.login(serverUrl, username, password);
    final session = StoredSession(
      serverUrl: serverUrl,
      username: result.username.isNotEmpty ? result.username : username,
      token: result.token,
      subsonicToken: result.subsonicToken,
      subsonicSalt: result.subsonicSalt,
    );
    await _store.saveSession(session);
    client.setSession(session);
    state = AuthState(session: session, initialized: true);
  }

  Future<void> logout() async {
    await _store.clear();
    ref.read(navidromeClientProvider).clearSession();
    state = AuthState(initialized: true);
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Subsonic 直链所需的认证信息（未登录时返回 empty，isValid=false）
final subsonicAuthProvider = Provider<SubsonicAuth>((ref) {
  final session = ref.watch(authControllerProvider).session;
  if (session == null) return SubsonicAuth.empty;
  return SubsonicAuth(
    serverUrl: session.serverUrl,
    username: session.username,
    subsonicToken: session.subsonicToken,
    subsonicSalt: session.subsonicSalt,
  );
});

/// 服务器地址规范化：补 scheme、去尾斜杠（对标 1.x LoginScreen）
String normalizeServerUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return url;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}
