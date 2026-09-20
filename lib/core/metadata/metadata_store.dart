import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_descriptor.dart';

/// 插件系统持久化：非敏感状态（全局开关 / 官方模板停用项 / 导入的描述 /
/// 结果缓存）走 shared_preferences，插件 API key 走 flutter_secure_storage。
class MetadataStore {
  static const _stateKey = 'metadata_plugin_state_v1';
  static const _cacheKey = 'metadata_cache_v1';
  static const _globalKey = 'metadata_plugins_enabled';
  static const _keyPrefix = 'metadata_plugin_key_';
  static const _secure = FlutterSecureStorage();

  // ---- 全局开关 ----

  Future<bool> readGlobalEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_globalKey) ?? true;

  Future<void> writeGlobalEnabled(bool enabled) async =>
      (await SharedPreferences.getInstance()).setBool(_globalKey, enabled);

  // ---- 插件注册状态 ----

  Future<PluginState> readState() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_stateKey) ?? '';
    if (raw.isEmpty) return const PluginState();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const PluginState();
      final imported = <PluginDescriptor>[];
      for (final item in (json['imported'] as List? ?? const [])) {
        if (item is! Map<String, dynamic>) continue;
        // 单条导入描述损坏只跳过该条，不影响其余插件
        try {
          imported.add(PluginDescriptor.parse(jsonEncode(item)));
        } on FormatException {
          continue;
        }
      }
      return PluginState(
        officialDisabled: _stringSet(json['officialDisabled']),
        imported: imported,
        importedDisabled: _stringSet(json['importedDisabled']),
      );
    } catch (_) {
      return const PluginState();
    }
  }

  Future<void> writeState(PluginState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _stateKey,
      jsonEncode({
        'officialDisabled': state.officialDisabled.toList(),
        'imported': [for (final d in state.imported) d.toJson()],
        'importedDisabled': state.importedDisabled.toList(),
      }),
    );
  }

  static Set<String> _stringSet(Object? raw) => {
    if (raw is List)
      for (final item in raw)
        if (item is String) item,
  };

  // ---- 插件 API key（安全存储）----

  Future<String?> readKey(String pluginId) =>
      _secure.read(key: '$_keyPrefix$pluginId');

  Future<void> writeKey(String pluginId, String key) async {
    if (key.trim().isEmpty) {
      await _secure.delete(key: '$_keyPrefix$pluginId');
    } else {
      await _secure.write(key: '$_keyPrefix$pluginId', value: key.trim());
    }
  }

  Future<Map<String, String>> readKeys(Iterable<String> pluginIds) async {
    final out = <String, String>{};
    for (final id in pluginIds) {
      final key = await readKey(id);
      if (key != null && key.isNotEmpty) out[id] = key;
    }
    return out;
  }

  // ---- 取数结果缓存 ----

  /// 头像 URL 有效期（图片本体另由 CoverCacheManager 缓存）
  static const _avatarPositiveTtl = Duration(days: 30);
  static const _bioPositiveTtl = Duration(days: 7);

  /// 相似歌手名有效期（歌手间关联基本稳定，与简介同级）
  static const _similarPositiveTtl = Duration(days: 7);

  /// 「确认无结果」负缓存有效期，避免对源反复打必败请求
  static const _negativeTtl = Duration(days: 7);

  /// 读缓存；过期或不存在返回 null。value 为空串表示负缓存命中（确认无结果），
  /// 与「未缓存」null 区分开。
  Future<String?> readCacheEntry(String kind, String name) async {
    final all = await _readCache();
    final entry = all[kind]?[name] as Map<String, Object?>?;
    if (entry == null) return null;
    final saved = (entry['t'] as num?)?.toInt() ?? 0;
    final negative = (entry['v'] as String? ?? '').isEmpty;
    final ttl = negative
        ? _negativeTtl
        : switch (kind) {
            'avatar' => _avatarPositiveTtl,
            'similar' => _similarPositiveTtl,
            _ => _bioPositiveTtl,
          };
    if (DateTime.now().millisecondsSinceEpoch - saved > ttl.inMilliseconds) {
      return null;
    }
    return entry['v'] as String? ?? '';
  }

  Future<void> writeCacheEntry(String kind, String name, String value) {
    return _enqueueWrite(() async {
      final all = await _readCache();
      final bucket = Map<String, Object?>.of(all[kind] ?? const {});
      bucket[name] = {'v': value, 't': DateTime.now().millisecondsSinceEpoch};
      all[kind] = bucket;
      (await SharedPreferences.getInstance()).setString(
        _cacheKey,
        jsonEncode(all),
      );
    });
  }

  /// 序列化写队列：并发写同一 JSON 文件会互相覆盖，串行保安全
  Future<void> _enqueueWrite(Future<void> Function() task) async {
    _pending = _pending.then((_) => task());
    await _pending;
  }

  Future<void> _pending = Future.value();

  Future<Map<String, Map<String, Object?>>> _readCache() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(_cacheKey) ?? '';
    if (raw.isEmpty) return <String, Map<String, Object?>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      return decoded.map(
        (k, v) => MapEntry<String, Map<String, Object?>>(k, _castBucket(v)),
      );
    } catch (_) {
      return <String, Map<String, Object?>>{};
    }
  }

  static Map<String, Object?> _castBucket(Object? raw) =>
      raw is Map ? Map<String, Object?>.from(raw) : const {};
}

/// 插件注册持久状态。官方模板默认启用（记录停用项），导入即启用。
class PluginState {
  const PluginState({
    this.officialDisabled = const {},
    this.imported = const [],
    this.importedDisabled = const {},
  });

  final Set<String> officialDisabled;
  final List<PluginDescriptor> imported;
  final Set<String> importedDisabled;
}
