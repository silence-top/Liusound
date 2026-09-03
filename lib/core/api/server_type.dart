import 'package:flutter/material.dart';

import 'server_adapter.dart';
import 'adapters/navidrome_adapter.dart';
import 'adapters/subsonic_adapter.dart';
import 'adapters/jellyfin_adapter.dart';
import 'adapters/emby_adapter.dart';
import 'adapters/plex_adapter.dart';
import 'adapters/audio_station_adapter.dart';

enum ServerType {
  navidrome,
  subsonic,
  jellyfin,
  emby,
  audioStation,
  plex;

  String get displayName => switch (this) {
    ServerType.navidrome => 'Navidrome',
    ServerType.subsonic => 'Subsonic',
    ServerType.jellyfin => 'Jellyfin',
    ServerType.emby => 'Emby',
    ServerType.audioStation => 'Audio Station',
    ServerType.plex => 'Plex',
  };

  String get urlHint => switch (this) {
    ServerType.navidrome => '例如 192.168.1.10:4533',
    ServerType.subsonic => '例如 192.168.1.10:4040',
    ServerType.jellyfin => '例如 192.168.1.10:8096',
    ServerType.emby => '例如 192.168.1.10:8096',
    ServerType.audioStation => '例如 192.168.1.10:5000',
    ServerType.plex => '例如 192.168.1.10:32400',
  };

  String get tagline => switch (this) {
    ServerType.navidrome => '开源音乐流媒体',
    ServerType.subsonic => '经典音乐服务器协议',
    ServerType.jellyfin => '免费媒体系统',
    ServerType.emby => '个人媒体服务器',
    ServerType.audioStation => 'Synology NAS 音乐',
    ServerType.plex => '流媒体平台',
  };

  IconData get fallbackIcon => switch (this) {
    ServerType.navidrome => Icons.library_music,
    ServerType.subsonic => Icons.graphic_eq,
    ServerType.jellyfin => Icons.movie_creation_outlined,
    ServerType.emby => Icons.live_tv,
    ServerType.audioStation => Icons.storage,
    ServerType.plex => Icons.play_circle_outline,
  };

  bool get hasLogoAsset => true;

  String get iconAsset => 'assets/app/$name.png';

  bool get implemented => true;

  ServerAdapter createAdapter(
    ServerConfig config,
    Map<String, String> secrets,
  ) {
    return switch (this) {
      ServerType.navidrome => NavidromeAdapter(
        config: config,
        secrets: secrets,
      ),
      ServerType.subsonic => SubsonicAdapter(config: config, secrets: secrets),
      ServerType.jellyfin => JellyfinAdapter(config: config, secrets: secrets),
      ServerType.emby => EmbyAdapter(config: config, secrets: secrets),
      ServerType.plex => PlexAdapter(config: config, secrets: secrets),
      ServerType.audioStation => AudioStationAdapter(
        config: config,
        secrets: secrets,
      ),
    };
  }

  Future<AdapterSession> signIn(AuthRequest request) {
    return switch (this) {
      ServerType.navidrome => NavidromeAdapter.signIn(request),
      ServerType.subsonic => SubsonicAdapter.signIn(request),
      ServerType.jellyfin => JellyfinAdapter.signIn(request),
      ServerType.emby => EmbyAdapter.signIn(request),
      ServerType.plex => PlexAdapter.signIn(request),
      ServerType.audioStation => AudioStationAdapter.signIn(request),
    };
  }
}

class ServerConfig {
  const ServerConfig({
    required this.id,
    required this.type,
    required this.name,
    required this.serverUrl,
    required this.username,
    this.meta = const {},
  });

  final String id;
  final ServerType type;
  final String name;
  final String serverUrl;
  final String username;
  final Map<String, String> meta;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'serverUrl': serverUrl,
    'username': username,
    'meta': meta,
  };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
    id: json['id'] as String,
    type: ServerType.values.firstWhere((t) => t.name == json['type']),
    name: json['name'] as String,
    serverUrl: json['serverUrl'] as String,
    username: json['username'] as String,
    meta:
        (json['meta'] as Map<String, dynamic>?)?.cast<String, String>() ??
        const {},
  );
}
