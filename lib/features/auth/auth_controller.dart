import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/server_adapter.dart';
import '../../core/api/server_type.dart';
import '../../core/network/http_factory.dart';
import '../../core/settings/streaming_prefs.dart';
import '../../core/storage/server_repository.dart';

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
    await _repo.saveServers(servers);
    await _repo.saveSecrets(id, result.secrets);
    await _repo.saveActiveId(id);

    state = state.copyWith(
      servers: servers,
      activeServerId: id,
      activeSecrets: result.secrets,
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

  /// 检测指定服务器，不能复用当前激活服务器的 adapter。
  Future<bool> validateServer(String id) async {
    final config = state.servers.cast<ServerConfig?>().firstWhere(
      (server) => server?.id == id,
      orElse: () => null,
    );
    if (config == null) return false;
    final secrets = await _repo.loadSecrets(id);
    final adapter = config.type.createAdapter(config, secrets);
    try {
      return await adapter.validateSession();
    } finally {
      adapter.dispose();
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

final serverAdapterProvider = Provider<ServerAdapter?>((ref) {
  final auth = ref.watch(authControllerProvider);
  // 网络设置变更时重建 adapter，让超时/代理/证书/hosts 重新生效
  final net = ref.watch(networkSettingsProvider);
  NetworkRuntime.settings = net;
  final config = auth.activeConfig;
  if (config == null) return null;
  final adapter = config.type.createAdapter(config, auth.activeSecrets);
  ref.onDispose(adapter.dispose);
  return adapter;
});

/// 服务端转码能力（后台静默探测，真结果缓存在 adapter 会话内）。
/// 探测完成前 value 为 null，UI 先按支持显示、播放侧另有回退兜底
final transcodeSupportProvider = FutureProvider<bool>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return false;
  return adapter.supportsTranscode();
});

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
