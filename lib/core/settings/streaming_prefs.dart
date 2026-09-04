import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs.dart';

/// 在线音质档位（附录·四）：lossless 不转码播原文件，其余为服务端转码目标码率
enum StreamQuality {
  lossless('无损', 0),
  k320('320 kbps', 320),
  k256('256 kbps', 256),
  k192('192 kbps', 192),
  k128('128 kbps', 128);

  const StreamQuality(this.label, this.bitRate);
  final String label;

  /// 0 = 不转码
  final int bitRate;
}

/// 转码格式（附录·四）
enum TranscodeFormat {
  mp3('MP3'),
  opus('OPUS');

  const TranscodeFormat(this.label);
  final String label;
}

/// 传给 adapter 的播放质量提示；quality == lossless 时不转码
class QualityHint {
  const QualityHint({required this.quality, required this.format});
  final StreamQuality quality;
  final TranscodeFormat format;

  bool get transcode => quality != StreamQuality.lossless;
}

/// 音质与传输设置：Wi-Fi / 蜂窝独立档位 + 转码格式 + 移动网络传输开关
class StreamingSettings {
  const StreamingSettings({
    this.wifiQuality = StreamQuality.lossless,
    this.cellularQuality = StreamQuality.k320,
    this.transcodeFormat = TranscodeFormat.mp3,
    this.cellularAllowed = true,
  });

  final StreamQuality wifiQuality;
  final StreamQuality cellularQuality;
  final TranscodeFormat transcodeFormat;
  final bool cellularAllowed;

  StreamingSettings copyWith({
    StreamQuality? wifiQuality,
    StreamQuality? cellularQuality,
    TranscodeFormat? transcodeFormat,
    bool? cellularAllowed,
  }) => StreamingSettings(
    wifiQuality: wifiQuality ?? this.wifiQuality,
    cellularQuality: cellularQuality ?? this.cellularQuality,
    transcodeFormat: transcodeFormat ?? this.transcodeFormat,
    cellularAllowed: cellularAllowed ?? this.cellularAllowed,
  );
}

class StreamingSettingsController extends Notifier<StreamingSettings> {
  static const _wifiKey = 'quality_wifi';
  static const _cellularKey = 'quality_cellular';
  static const _formatKey = 'transcode_format';
  static const _cellularAllowedKey = 'cellular_allowed';

  @override
  StreamingSettings build() {
    final prefs = ref.watch(sharedPrefsProvider);
    const fallback = StreamingSettings();
    return StreamingSettings(
      wifiQuality: StreamQuality.values.firstWhere(
        (q) => q.name == prefs.getString(_wifiKey),
        orElse: () => fallback.wifiQuality,
      ),
      cellularQuality: StreamQuality.values.firstWhere(
        (q) => q.name == prefs.getString(_cellularKey),
        orElse: () => fallback.cellularQuality,
      ),
      transcodeFormat: TranscodeFormat.values.firstWhere(
        (f) => f.name == prefs.getString(_formatKey),
        orElse: () => fallback.transcodeFormat,
      ),
      cellularAllowed: prefs.getBool(_cellularAllowedKey) ?? true,
    );
  }

  Future<void> set(StreamingSettings s) async {
    state = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wifiKey, s.wifiQuality.name);
    await prefs.setString(_cellularKey, s.cellularQuality.name);
    await prefs.setString(_formatKey, s.transcodeFormat.name);
    await prefs.setBool(_cellularAllowedKey, s.cellularAllowed);
  }
}

final streamingSettingsProvider =
    NotifierProvider<StreamingSettingsController, StreamingSettings>(
      StreamingSettingsController.new,
    );

/// 当前网络适用的音质档位；蜂窝且关闭传输开关时返回 null（播放器据此拒播）
Future<StreamQuality?> resolveCurrentQuality(StreamingSettings s) async {
  try {
    final results = await Connectivity().checkConnectivity();
    final cellular = results.contains(ConnectivityResult.mobile);
    if (cellular && !s.cellularAllowed) return null;
    return cellular ? s.cellularQuality : s.wifiQuality;
  } catch (_) {
    return s.wifiQuality;
  }
}

/// 网络设置（附录·一）：超时 / 代理 / HTTPS 证书校验 / hosts 映射
class NetworkSettings {
  const NetworkSettings({
    this.timeoutSeconds = 10,
    this.proxy = '',
    this.verifyCertificates = true,
    this.hostOverrides = '',
  });

  /// 连接超时秒数（读超时按 2 倍应用）
  final int timeoutSeconds;

  /// 代理地址，如 `127.0.0.1:7890`（空 = 跟随系统）
  final String proxy;

  /// 关闭后跳过 HTTPS 证书校验（自签名内网服务器场景）
  final bool verifyCertificates;

  /// hosts 映射，格式 `域名=IP`，分号分隔多条。
  /// 仅对 HTTP 直连完整生效；HTTPS 握手 SNI 会使用映射 IP，
  /// 证书校验开启时会失败，需配合关闭证书校验使用
  final String hostOverrides;

  Map<String, String> get hostMap => {
    for (final entry in hostOverrides.split(';')) ..._parseEntry(entry),
  };

  static Map<String, String> _parseEntry(String entry) {
    final kv = entry.trim().split('=');
    if (kv.length != 2 || kv[0].isEmpty || kv[1].isEmpty) return const {};
    return {kv[0].trim(): kv[1].trim()};
  }

  NetworkSettings copyWith({
    int? timeoutSeconds,
    String? proxy,
    bool? verifyCertificates,
    String? hostOverrides,
  }) => NetworkSettings(
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    proxy: proxy ?? this.proxy,
    verifyCertificates: verifyCertificates ?? this.verifyCertificates,
    hostOverrides: hostOverrides ?? this.hostOverrides,
  );
}

class NetworkSettingsController extends Notifier<NetworkSettings> {
  static const _timeoutKey = 'net_timeout';
  static const _proxyKey = 'net_proxy';
  static const _verifyKey = 'net_verify_certs';
  static const _hostsKey = 'net_host_overrides';

  @override
  NetworkSettings build() {
    final prefs = ref.watch(sharedPrefsProvider);
    const fallback = NetworkSettings();
    return NetworkSettings(
      timeoutSeconds: prefs.getInt(_timeoutKey) ?? fallback.timeoutSeconds,
      proxy: prefs.getString(_proxyKey) ?? fallback.proxy,
      verifyCertificates:
          prefs.getBool(_verifyKey) ?? fallback.verifyCertificates,
      hostOverrides: prefs.getString(_hostsKey) ?? fallback.hostOverrides,
    );
  }

  Future<void> set(NetworkSettings s) async {
    state = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeoutKey, s.timeoutSeconds);
    await prefs.setString(_proxyKey, s.proxy);
    await prefs.setBool(_verifyKey, s.verifyCertificates);
    await prefs.setString(_hostsKey, s.hostOverrides);
  }
}

final networkSettingsProvider =
    NotifierProvider<NetworkSettingsController, NetworkSettings>(
      NetworkSettingsController.new,
    );
