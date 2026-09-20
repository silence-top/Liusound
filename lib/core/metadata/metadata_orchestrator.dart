import 'dart:convert';

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
  final registry = await ref.watch(pluginRegistryProvider.future);
  return ref
      .watch(metadataStoreProvider)
      .readKeys(registry.map((p) => p.descriptor.id));
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
  if (!ref.watch(metadataEnabledProvider)) return null;
  final store = ref.watch(metadataStoreProvider);
  final cached = await store.readCacheEntry(kind, artistName);
  if (cached != null) return cached.isEmpty ? null : cached;

  final registry = await ref.watch(pluginRegistryProvider.future);
  final keys = await ref.watch(pluginKeysProvider.future);
  final fetcher = dioJsonFetcher(ref.watch(pluginDioProvider));
  for (final p in registry) {
    if (!p.enabled || !hasSection(p.descriptor)) continue;
    final auth = p.descriptor.auth;
    if (auth != null &&
        auth.required &&
        (keys[p.descriptor.id] ?? '').trim().isEmpty) {
      continue;
    }
    final result = await run(p.buildPlugin(store, fetcher), artistName);
    if (result != null && result.isNotEmpty) {
      await store.writeCacheEntry(kind, artistName, result);
      return result;
    }
  }
  // 全部来源无结果：写负缓存，避免每次重建都打外部请求
  await store.writeCacheEntry(kind, artistName, '');
  return null;
}

/// 相似歌手名（合并全部启用插件，去重保序；本地映射由调用方完成）。
/// 结果（含空负缓存）落盘 7 天：相似歌曲链路长（搜索+related+逐歌手取歌），
/// 不缓存的话每次重进推荐页都全量重打外部源。
final pluginSimilarNamesProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, artistName) async {
      if (!ref.watch(metadataEnabledProvider)) return const [];
      final store = ref.watch(metadataStoreProvider);
      final cached = await store.readCacheEntry('similar', artistName);
      if (cached != null) {
        if (cached.isEmpty) return const [];
        try {
          final decoded = jsonDecode(cached);
          if (decoded is List) {
            return [
              for (final n in decoded)
                if (n is String) n,
            ];
          }
        } catch (_) {}
      }
      final registry = await ref.watch(pluginRegistryProvider.future);
      final keys = await ref.watch(pluginKeysProvider.future);
      final fetcher = dioJsonFetcher(ref.watch(pluginDioProvider));
      final names = <String>[];
      for (final p in registry) {
        final step = p.descriptor.similar;
        if (!p.enabled || step == null) continue;
        final auth = p.descriptor.auth;
        if (auth != null &&
            auth.required &&
            (keys[p.descriptor.id] ?? '').trim().isEmpty) {
          continue;
        }
        for (final name
            in await p
                .buildPlugin(store, fetcher)
                .fetchSimilarArtistNames(artistName)) {
          if (name != artistName && !names.contains(name)) names.add(name);
          if (names.length >= 12) break;
        }
        if (names.length >= 12) break;
      }
      await store.writeCacheEntry('similar', artistName, jsonEncode(names));
      return names;
    });
