import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/streaming_prefs.dart';
import 'server_adapter.dart';
import 'server_type.dart';

/// 当前激活服务器的会话快照。core 层不依赖 features/auth：
/// 由组合根（main.dart）用 authControllerProvider 覆写提供，
/// 未覆写时视为未登录（adapter 为 null）。
class ActiveServerSession {
  const ActiveServerSession({
    required this.config,
    required this.secrets,
    required this.saveSecrets,
  });

  final ServerConfig config;
  final Map<String, String> secrets;

  /// 静默重登拿到新凭证后的持久化入口（features/auth 提供）
  final void Function(String id, Map<String, String> secrets) saveSecrets;
}

final activeServerSessionProvider = Provider<ActiveServerSession?>((ref) {
  return null;
});

/// 当前激活服务器 adapter（网络设置变更时重建；登录态变化时重建/销毁）
final serverAdapterProvider = Provider<ServerAdapter?>((ref) {
  final session = ref.watch(activeServerSessionProvider);
  // 网络设置显式注入 adapter（P1-NetworkRuntime：无全局可变状态）；
  // 网络设置变更时重建 adapter，让超时/代理/证书/hosts 重新生效
  final net = ref.watch(networkSettingsProvider);
  if (session == null) return null;
  final adapter = session.config.type.createAdapter(
    session.config,
    session.secrets,
    net,
  );
  // 静默重登的适配器（Jellyfin/Emby/Plex/群晖）把新凭证回写存储
  // 类型提升对 mixin 交叉类型不生效，需显式转换才能拿到 onSecretsUpdated
  final SecretsUpdatable? sink = adapter is SecretsUpdatable
      ? adapter as SecretsUpdatable
      : null;
  sink?.onSecretsUpdated = (fresh) =>
      session.saveSecrets(session.config.id, fresh);
  ref.onDispose(adapter.dispose);
  return adapter;
});

/// 当前激活服务器 id（未登录为空串；core 层换服中止/缓存 key/队列归属用）
final activeServerIdProvider = Provider<String>((ref) {
  return ref.watch(activeServerSessionProvider)?.config.id ?? '';
});

/// 服务端转码能力（后台静默探测，真结果缓存在 adapter 会话内）。
/// 探测完成前 value 为 null，UI 先按支持显示、播放侧另有回退兜底
final transcodeSupportProvider = FutureProvider<bool>((ref) async {
  final adapter = ref.watch(serverAdapterProvider);
  if (adapter == null) return false;
  return adapter.supportsTranscode();
});
