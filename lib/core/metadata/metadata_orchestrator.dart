import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/http_factory.dart';
import '../settings/streaming_prefs.dart';
import 'metadata_plugin.dart';
import 'metadata_store.dart';
import 'plugin_descriptor.dart';
import 'plugin_executor.dart';

/// 随 App 打包的官方插件描述（与用户导入的描述走同一条执行管道）
const officialPluginAssets = [
  'assets/plugins/deezer.json',
  'assets/plugins/theaudiodb.json',
  'assets/plugins/baike.json',
];

final metadataStoreProvider = Provider<MetadataStore>((_) => MetadataStore());

/// 插件系统全局开关（默认开；启动后异步回放持久值）
class MetadataEnabledController extends Notifier<bool> {
  @override
  bool build() {
    Future.microtask(() async {
      try {
        state = await ref.read(metadataStoreProvider).readGlobalEnabled();
      } catch (_) {}
    });
    return true;
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    try {
      await ref.read(metadataStoreProvider).writeGlobalEnabled(enabled);
    } catch (_) {}
  }
}

final metadataEnabledProvider =
    NotifierProvider<MetadataEnabledController, bool>(
      MetadataEnabledController.new,
    );

/// 插件请求专用 Dio：复用用户网络设置（代理/超时/证书/hosts），
/// 网络设置变更时重建
final pluginDioProvider = Provider<Dio>((ref) {
  final dio = Dio();
  NetworkRuntime.configureDio(dio, ref.watch(networkSettingsProvider));
  ref.onDispose(dio.close);
  return dio;
});

/// 已安装插件：官方模板 + 用户导入，按此顺序取数（官方优先）
class InstalledPlugin {
  const InstalledPlugin({
    required this.descriptor,
    required this.official,
    required this.enabled,
  });

  final PluginDescriptor descriptor;
  final bool official;
  final bool enabled;

  DescriptorPlugin buildPlugin(MetadataStore store, JsonFetcher fetch) =>
      DescriptorPlugin(
        descriptor: descriptor,
        fetch: fetch,
        readKey: () => store.readKey(descriptor.id),
      );
}

final pluginRegistryProvider = FutureProvider<List<InstalledPlugin>>((
  ref,
) async {
  final store = ref.watch(metadataStoreProvider);
  final state = await store.readState();
  final official = <InstalledPlugin>[];
  for (final asset in officialPluginAssets) {
    try {
      final descriptor = PluginDescriptor.parse(
        await rootBundle.loadString(asset),
      );
      official.add(
        InstalledPlugin(
          descriptor: descriptor,
          official: true,
          enabled: !state.officialDisabled.contains(descriptor.id),
        ),
      );
    } on Exception {
      // 单个官方资源异常只跳过该插件，不拖垮整个注册表
    }
  }
  final imported = [
    for (final d in state.imported)
      InstalledPlugin(
        descriptor: d,
        official: false,
        enabled: !state.importedDisabled.contains(d.id),
      ),
  ];
  return [...official, ...imported];
});

/// 各插件已保存的 key（设置页写 key 后需 invalidate）
final pluginKeysProvider = FutureProvider<Map<String, String>>((ref) async {
  final store = ref.watch(metadataStoreProvider);
  final registry = await ref.watch(pluginRegistryProvider.future);
  return store.readKeys(registry.map((p) => p.descriptor.id));
});

/// 插件对外暴露的能力位（UI 用它决定分区是否渲染）。
/// required key 未填的插件视为不可用，避免「看似可用实际必败」。
class PluginCaps {
  const PluginCaps({
    this.avatar = false,
    this.similar = false,
    this.bio = false,
  });

  final bool avatar;
  final bool similar;
  final bool bio;
}

final pluginCapsProvider = Provider<PluginCaps>((ref) {
  if (!ref.watch(metadataEnabledProvider)) return const PluginCaps();
  final registry =
      ref.watch(pluginRegistryProvider).valueOrNull ??
      const <InstalledPlugin>[];
  final keys =
      ref.watch(pluginKeysProvider).valueOrNull ?? const <String, String>{};
  if (registry.isEmpty) return const PluginCaps();

  bool cap(bool Function(PluginDescriptor) hasSection) => registry.any((p) {
    if (!p.enabled || !hasSection(p.descriptor)) return false;
    final auth = p.descriptor.auth;
    return auth == null ||
        !auth.required ||
        (keys[p.descriptor.id] ?? '').trim().isNotEmpty;
  });

  return PluginCaps(
    avatar: cap((d) => d.avatar != null),
    similar: cap((d) => d.similar != null),
    bio: cap((d) => d.bio != null),
  );
});

/// 插件头像：按注册表顺序取第一个有结果者，结果（含「无结果」负缓存）落盘。
/// family 按歌手名缓存实例，同名重复请求不回源。
final pluginArtistAvatarProvider = FutureProvider.family<String?, String>((
  ref,
  artistName,
) {
  return _queryText(
    ref,
    artistName,
    kind: 'avatar',
    hasSection: (d) => d.avatar != null,
    run: (plugin, name) => plugin.fetchArtistAvatar(name),
  );
});

/// 插件歌手简介（已清洗截断的纯文本）
final pluginArtistBioProvider = FutureProvider.family<String?, String>((
  ref,
  artistName,
) {
  return _queryText(
    ref,
    artistName,
    kind: 'bio',
    hasSection: (d) => d.bio != null,
    run: (plugin, name) => plugin.fetchArtistBio(name),
  );
});

Future<String?> _queryText(
  Ref ref,
  String artistName, {
  required String kind,
  required bool Function(PluginDescriptor) hasSection,
  required Future<String?> Function(MetadataPlugin, String) run,
}) async {
  final query = _MetadataQuery(ref, kind, artistName, hasSection);
  String? result;
  return query.complete(() async {
    if (!await query.prepare()) return null;
    final cached = await query.read();
    if (!query.active) return null;
    if (cached != null) return cached.isEmpty ? null : cached;

    for (final plugin in query.plugins) {
      if (!query.active) break;
      try {
        final value = await run(plugin, artistName);
        if (!query.active) break;
        if (value != null && value.isNotEmpty) {
          result = value;
          await query.save(value);
          return value;
        }
      } catch (_) {
        query.failed = true;
      }
    }
    await query.save('');
    return null;
  }, () => result);
}

/// 相似歌手名（合并全部启用插件，去重保序；本地映射由调用方完成）。
/// 完整正结果保存 7 天，确认空结果保存 15 分钟；部分失败不持久化。
final pluginSimilarNamesProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, artistName) async {
      final query = _MetadataQuery(
        ref,
        'similar',
        artistName,
        (d) => d.similar != null,
      );
      final names = <String>[];
      final result = await query.complete(() async {
        if (!await query.prepare()) return const <String>[];
        final cached = await query.read();
        if (!query.active) return const <String>[];
        if (cached != null) {
          if (cached.isEmpty) return const <String>[];
          try {
            final decoded = jsonDecode(cached);
            if (decoded is List && decoded.every((n) => n is String)) {
              return decoded.cast<String>();
            }
          } on FormatException {
            // 缓存损坏时回源，不当成空结果。
          }
        }
        for (final plugin in query.plugins) {
          if (!query.active) break;
          try {
            final found = await plugin.fetchSimilarArtistNames(artistName);
            if (!query.active) break;
            for (final name in found) {
              if (name != artistName && !names.contains(name)) names.add(name);
              if (names.length >= 12) break;
            }
          } catch (_) {
            query.failed = true;
          }
          if (names.length >= 12) break;
        }
        await query.save(names.isEmpty ? '' : jsonEncode(names));
        return List<String>.of(names);
      }, () => List<String>.of(names));
      if (query.failed && result.isEmpty && !query.disposed) {
        throw const MetadataFetchException();
      }
      return result;
    });

/// 单次查询的依赖快照、总预算和取消状态；不改变对外 provider 类型。
class _MetadataQuery {
  _MetadataQuery(this.ref, this.kind, this.artistName, this.hasSection) {
    // 所有依赖同步注册，不能让缓存命中绕开 registry / key 的 watch。
    enabled = ref.watch(metadataEnabledProvider);
    store = ref.watch(metadataStoreProvider);
    registryFuture = ref.watch(pluginRegistryProvider.future);
    keysFuture = ref.watch(pluginKeysProvider.future);
    fetcher = dioJsonFetcher(ref.watch(pluginDioProvider), cancelToken: token);
    deadline = Timer(const Duration(seconds: 12), () {
      failed = true;
      _stop();
    });
    ref.onDispose(() {
      disposed = true;
      refresh?.cancel();
      deadline.cancel();
      _stop();
    });
  }

  final Ref ref;
  final String kind;
  final String artistName;
  final bool Function(PluginDescriptor) hasSection;
  final token = CancelToken();
  final stopped = Completer<void>();
  late final bool enabled;
  late final MetadataStore store;
  late final Future<List<InstalledPlugin>> registryFuture;
  late final Future<Map<String, String>> keysFuture;
  late final JsonFetcher fetcher;
  late final Timer deadline;
  Timer? refresh;
  bool active = true;
  bool disposed = false;
  bool failed = false;
  bool negative = false;
  String scope = '';
  Map<String, String> keys = const {};
  List<DescriptorPlugin> plugins = const [];

  void _stop() {
    active = false;
    token.cancel();
    if (!stopped.isCompleted) stopped.complete();
  }

  Future<T> complete<T>(
    Future<T> Function() work,
    T Function() fallback,
  ) async {
    try {
      return await Future.any([work(), stopped.future.then((_) => fallback())]);
    } catch (_) {
      failed = true;
      return fallback();
    } finally {
      deadline.cancel();
      _stop();
      // 非 autoDispose 的头像/简介也不能永久记住一次失败或负结果。
      if (!disposed && (failed || negative)) {
        refresh = Timer(
          failed ? const Duration(seconds: 30) : MetadataStore.negativeTtl,
          ref.invalidateSelf,
        );
      }
    }
  }

  Future<bool> prepare() async {
    // Future.wait 同时接住两个依赖的异常；禁用时也不遗留未处理的 Future。
    final pending = Future.wait<Object>([registryFuture, keysFuture]);
    if (!enabled) {
      unawaited(
        pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      return false;
    }
    final dependencies = await pending;
    if (!active) return false;
    final registry = dependencies[0] as List<InstalledPlugin>;
    keys = Map<String, String>.of(dependencies[1] as Map<String, String>);
    final usable = registry.where((p) {
      return p.enabled &&
          hasSection(p.descriptor) &&
          (p.descriptor.auth?.required != true ||
              (keys[p.descriptor.id] ?? '').trim().isNotEmpty);
    }).toList();
    if (usable.isEmpty) return false; // 无可用插件不是源确认的空结果。

    // JSON map 键排序，插件顺序保留（顺序影响优先级），不用不稳定的 hashCode。
    scope = sha256
        .convert(
          utf8.encode(
            jsonEncode(
              _canonical([
                for (final p in usable)
                  {
                    'descriptor': p.descriptor.toJson(),
                    'key': (keys[p.descriptor.id] ?? '').trim(),
                  },
              ]),
            ),
          ),
        )
        .toString();
    plugins = [
      for (final p in usable)
        DescriptorPlugin(
          descriptor: p.descriptor,
          fetch: fetcher,
          // 请求使用与摘要相同的快照，避免读 key 与配置变更竞态。
          readKey: () async => keys[p.descriptor.id],
        ),
    ];
    return true;
  }

  Future<String?> read() async {
    try {
      final value = await store.readCacheEntry(kind, artistName, scope: scope);
      negative = value == '';
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String value) async {
    if (!active || failed || plugins.isEmpty) return;
    negative = value.isEmpty;
    // 上游可能在图片 URL/文本中回显凭证；这些结果可展示，但绝不落盘。
    if (keys.values.any((raw) {
      final key = raw.trim();
      return key.isNotEmpty &&
          (value.contains(key) ||
              value.contains(Uri.encodeComponent(key)) ||
              artistName.contains(key) ||
              artistName.contains(Uri.encodeComponent(key)));
    })) {
      return;
    }
    try {
      await store.writeCacheEntry(
        kind,
        artistName,
        value,
        scope: scope,
        shouldWrite: () => active && !failed,
      );
    } catch (_) {
      // 持久化失败不丢弃已取得的有效结果。
      failed = true;
    }
  }
}

Object? _canonical(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
