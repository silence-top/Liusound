import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/server_type.dart';
import 'auth_store.dart';

class ServerRepository {
  static const _serversKey = 'servers_json';
  static const _activeIdKey = 'active_server_id';
  static const _secretsPrefix = 'server_secrets_';
  static const _secure = FlutterSecureStorage();

  Future<List<ServerConfig>> loadServers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_serversKey);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => ServerConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveServers(List<ServerConfig> servers) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(servers.map((s) => s.toJson()).toList());
    await prefs.setString(_serversKey, raw);
  }

  Future<String?> loadActiveId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeIdKey);
  }

  Future<void> saveActiveId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeIdKey, id);
  }

  Future<Map<String, String>> loadSecrets(String serverId) async {
    final raw = await _secure.read(key: '$_secretsPrefix$serverId');
    if (raw == null || raw.isEmpty) return const {};
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  }

  Future<void> saveSecrets(String serverId, Map<String, String> secrets) async {
    await _secure.write(
      key: '$_secretsPrefix$serverId',
      value: jsonEncode(secrets),
    );
  }

  Future<void> deleteServer(String serverId) async {
    final servers = await loadServers();
    servers.removeWhere((s) => s.id == serverId);
    await saveServers(servers);
    await _secure.delete(key: '$_secretsPrefix$serverId');
    final activeId = await loadActiveId();
    if (activeId == serverId) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeIdKey);
    }
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_serversKey);
    await prefs.remove(_activeIdKey);
    final allKeys = await _secure.readAll();
    for (final key in allKeys.keys) {
      if (key.startsWith(_secretsPrefix)) {
        await _secure.delete(key: key);
      }
    }
  }

  Future<bool> migrateLegacySession() async {
    final servers = await loadServers();
    if (servers.isNotEmpty) return false;

    final legacy = await AuthStore().readSession();
    if (legacy == null) return false;

    final config = ServerConfig(
      id: 'navidrome-legacy',
      type: ServerType.navidrome,
      name: 'Navidrome',
      serverUrl: legacy.serverUrl,
      username: legacy.username,
    );

    await saveServers([config]);
    await saveSecrets(config.id, {
      'token': legacy.token,
      'subsonicToken': legacy.subsonicToken,
      'subsonicSalt': legacy.subsonicSalt,
    });
    await saveActiveId(config.id);
    await AuthStore().clear();
    return true;
  }
}
