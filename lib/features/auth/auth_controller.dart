import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/server_adapter.dart';
import '../../core/api/server_type.dart';
import '../../core/settings/streaming_prefs.dart';
import '../../core/storage/server_repository.dart';

// serverAdapterProvider 等已下沉 core/api/adapter_provider.dart
// （core 层不得反向依赖 features）；re-export 维持既有 import 路径不变
export '../../core/api/adapter_provider.dart'
    show
        activeServerIdProvider,
        serverAdapterProvider,
        transcodeSupportProvider;

class AuthState {
  const AuthState({
    this.servers = const [],
    this.activeServerId,
    this.activeSecrets = const {},
    this.initialized = false,
  });

  final List<ServerConfig> servers;
  final String? activeServerId;
  final Map<String, String> activeSecrets;
  final bool initialized;

  bool get isAuthenticated => activeServerId != null;

  ServerConfig? get activeConfig => servers.cast<ServerConfig?>().firstWhere(
    (s) => s?.id == activeServerId,
    orElse: () => null,
  );

  AuthState copyWith({
    List<ServerConfig>? servers,
    String? activeServerId,
    Map<String, String>? activeSecrets,
    bool? initialized,
  }) => AuthState(
    servers: servers ?? this.servers,
    activeServerId: activeServerId ?? this.activeServerId,
    activeSecrets: activeSecrets ?? this.activeSecrets,
    initialized: initialized ?? this.initialized,
  );
}

class AuthController extends Notifier<AuthState> {
  final _repo = ServerRepository();

  @override
  AuthState build() {
    _restore();
    return const AuthState();
  }

  Future<void> _restore() async {
    try {
      await _repo.migrateLegacySession();
      final servers = await _repo.loadServers();
      final activeId = await _repo.loadActiveId();
      if (servers.isNotEmpty && activeId != null) {
        final secrets = await _repo.loadSecrets(activeId);
        state = AuthState(
          servers: servers,
          activeServerId: activeId,
          activeSecrets: secrets,
          initialized: true,
        );
      } else {
        state = const AuthState(initialized: true);
      }
    } catch (_) {
      state = const AuthState(initialized: true);
    }
  }

  Future<void> login(
    ServerType type,
    String serverUrl,
    String username,
    String password,
  ) async {
    final normalizedUrl = normalizeServerUrl(serverUrl);
    final result = await type.signIn(
      AuthRequest(
        serverUrl: normalizedUrl,
        username: username,
        password: password,
      ),
    );

    final id = '${type.name}-${DateTime.now().millisecondsSinceEpoch}';
    final config = ServerConfig(
      id: id,
      type: type,
      name: type.displayName,
      serverUrl: normalizedUrl,
      username: username,
    );

    final servers = [...state.servers, config];
    // 密码一并入 secrets：token 过期时适配器可静默重登（对齐群晖 SID 重登）
    final secrets = {...result.secrets, 'password': password};
    await _repo.saveServers(servers);
    await _repo.saveSecrets(id, secrets);
    await _repo.saveActiveId(id);

    state = state.copyWith(
      servers: servers,
      activeServerId: id,
      activeSecrets: secrets,
      initialized: true,
    );
  }

  Future<void> switchServer(String id) async {
    if (id == state.activeServerId) return;
    final config = state.servers.cast<ServerConfig?>().firstWhere(
      (s) => s?.id == id,
      orElse: () => null,
    );
    if (config == null) return;
    final secrets = await _repo.loadSecrets(id);
    await _repo.saveActiveId(id);
    state = state.copyWith(activeServerId: id, activeSecrets: secrets);
  }

  /// 编辑表单预填用：读取该服务器存储的密码明文（登录/编辑时随 secrets 存了一份）
  Future<String?> storedPassword(String id) async {
    try {
      return (await _repo.loadSecrets(id))['password'];
    } catch (_) {
      return null;
    }
  }

  /// 编辑服务器（地址/端口/用户名/密码/备注名）：地址或凭证有变化时用新凭证
  /// 完整走一次 signIn（成功拿到新鲜 secrets 一并持久化），失败抛出由 UI 提示、
  /// 原配置不动；仅改备注名跳过网络直接保存。
  /// 编辑当前激活服务器时 state 变更会重建 adapter，新地址/凭证即刻生效
  Future<void> editServer({
    required String id,
    required String serverUrl,
    required String username,
    required String password,
    String? name,
  }) async {
    final config = state.servers.cast<ServerConfig?>().firstWhere(
      (s) => s?.id == id,
      orElse: () => null,
    );
    if (config == null) return;
    final url = normalizeServerUrl(serverUrl);
    final stored = await _repo.loadSecrets(id);
    final credentialsChanged =
        url != config.serverUrl ||
        username != config.username ||
        password != (stored['password'] ?? '');
    final newName = (name == null || name.trim().isEmpty)
        ? config.name
        : name.trim();
    if (!credentialsChanged && newName == config.name) return;
    var secrets = stored;
    if (credentialsChanged) {
      final result = await config.type.signIn(
        AuthRequest(serverUrl: url, username: username, password: password),
      );
      secrets = {...result.secrets, 'password': password};
    }
    final updated = ServerConfig(
      id: config.id,
      type: config.type,
      name: newName,
      serverUrl: url,
      username: username,
      meta: config.meta,
    );
    final servers = state.servers.map((s) => s.id == id ? updated : s).toList();
    await _repo.saveServers(servers);
    if (credentialsChanged) {
      await _repo.saveSecrets(id, secrets);
    }
    // copyWith 传 null = 保留原值：非激活服务器不动 activeSecrets；
    // 激活服务器换凭证时传入新 secrets（adapter 随 state 重建即刻生效）
    state = state.copyWith(
      servers: servers,
      activeSecrets: id == state.activeServerId && credentialsChanged
          ? secrets
          : null,
    );
  }

  /// 检测指定服务器，不能复用当前激活服务器的 adapter。
  Future<bool> validateServer(String id) async {
    final config = state.servers.cast<ServerConfig?>().firstWhere(
      (server) => server?.id == id,
      orElse: () => null,
    );
    if (config == null) return false;
    final secrets = await _repo.loadSecrets(id);
    final adapter = config.type.createAdapter(
      config,
      secrets,
      ref.read(networkSettingsProvider),
    );
    try {
      return await adapter.validateSession();
    } finally {
      adapter.dispose();
    }
  }

  /// 静默重登后持久化刷新的凭证。故意不更新内存 state：state 变更会重建
  /// adapter 并 dispose 掉正在重放请求的旧实例；下次 adapter 重建时从存储读取
  Future<void> updateStoredSecrets(
    String id,
    Map<String, String> secrets,
  ) async {
    try {
      await _repo.saveSecrets(id, secrets);
    } catch (_) {
      // 持久化失败静默：本次内存凭证已更新，后续 401 会再次触发重登
    }
  }

  Future<void> removeServer(String id) async {
    await _repo.deleteServer(id);
    final servers = state.servers.where((s) => s.id != id).toList();
    if (state.activeServerId == id) {
      state = state.copyWith(
        servers: servers,
        activeServerId: null,
        activeSecrets: const {},
      );
    } else {
      state = state.copyWith(servers: servers);
    }
  }

  Future<void> logout() async {
    final activeId = state.activeServerId;
    if (activeId != null) {
      await _repo.deleteServer(activeId);
    }
    final servers = state.servers.where((s) => s.id != activeId).toList();
    state = AuthState(servers: servers, initialized: true);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

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
