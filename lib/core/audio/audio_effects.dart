import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/player/player_controller.dart';

const _channelName = 'com.silencetop.liusound/audio_effects';

/// 设备 EQ 波段信息（center 单位 Hz，min/max 单位毫贝，通常 -1500..1500）
class EqBand {
  const EqBand({
    required this.centerHz,
    required this.minMb,
    required this.maxMb,
  });

  final int centerHz;
  final int minMb;
  final int maxMb;

  static EqBand fromMap(Object? raw) {
    final m = raw! as Map<Object?, Object?>;
    return EqBand(
      centerHz: (m['centerHz'] as num).round(),
      minMb: (m['minMb'] as num).round(),
      maxMb: (m['maxMb'] as num).round(),
    );
  }
}

/// 原生音效链通道封装（仅 Android；iOS 无 just_audio 可挂载的 EQ 入口，不可行）
class AudioEffectsApi {
  static const _channel = MethodChannel(_channelName);

  static Future<List<EqBand>> init(int sessionId) async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('init', sessionId);
      return raw?.map(EqBand.fromMap).toList() ?? const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<void> setEq(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setEq', {'enabled': enabled});
    } on PlatformException {
      // 设备不支持时静默降级
    }
  }

  static Future<void> setBandLevel(int index, int levelMb) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setBandLevel', {
        'index': index,
        'level': levelMb,
      });
    } on PlatformException {
      // 同上
    }
  }

  static Future<void> setBass(int strength) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setBass', strength);
    } on PlatformException {
      // 同上
    }
  }

  static Future<void> setVirtualizer(int strength) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setVirtualizer', strength);
    } on PlatformException {
      // 同上
    }
  }

  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('release');
    } on PlatformException {
      // 同上
    }
  }
}

/// 预设曲线：按 10 个标准频点（Hz）给出 dB 值，设备波段按频点线性插值映射
const standardFreqs = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

const eqPresets = <String, List<int>>{
  '平直': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  '流行': [0, 1, 3, 4, 3, 1, 0, -1, -1, 0],
  '摇滚': [5, 4, 3, 1, -1, 0, 3, 4, 4, 3],
  '古典': [3, 3, 2, 1, 0, 0, 0, 1, 2, 3],
  '人声': [-3, -2, 0, 3, 4, 4, 3, 1, 0, -1],
  '电子': [5, 4, 2, 0, -1, 0, 2, 3, 4, 5],
};

/// 把某频点的预设 dB 插值出来（标准频点之间按几何平均插值）
double _presetGainAt(List<int> preset, int freq) {
  if (freq <= standardFreqs.first) return preset.first.toDouble();
  if (freq >= standardFreqs.last) return preset.last.toDouble();
  for (var i = 0; i < standardFreqs.length - 1; i++) {
    final lo = standardFreqs[i];
    final hi = standardFreqs[i + 1];
    if (freq >= lo && freq <= hi) {
      final t = (math.log(freq) - math.log(lo)) / (math.log(hi) - math.log(lo));
      return preset[i] + (preset[i + 1] - preset[i]) * t;
    }
  }
  return 0;
}

/// 音效状态：波段 + 全部持久化参数（EQ 开关/各波段增益/低音/空间）
class AudioEffectsState {
  const AudioEffectsState({
    this.bands = const [],
    this.enabled = false,
    this.gains = const {},
    this.bass = 0,
    this.virtualizer = 0,
    this.ready = false,
  });

  final List<EqBand> bands;
  final bool enabled;
  final Map<int, int> gains; // 波段下标 -> 毫贝
  final int bass; // 0..1000
  final int virtualizer; // 0..1000
  final bool ready; // 原生会话已挂载

  AudioEffectsState copyWith({
    List<EqBand>? bands,
    bool? enabled,
    Map<int, int>? gains,
    int? bass,
    int? virtualizer,
    bool? ready,
  }) {
    return AudioEffectsState(
      bands: bands ?? this.bands,
      enabled: enabled ?? this.enabled,
      gains: gains ?? this.gains,
      bass: bass ?? this.bass,
      virtualizer: virtualizer ?? this.virtualizer,
      ready: ready ?? this.ready,
    );
  }
}

class AudioEffectsController extends Notifier<AudioEffectsState> {
  static const _keyEnabled = 'eq_enabled';
  static const _keyGains = 'eq_gains';
  static const _keyBass = 'eq_bass';
  static const _keyVirtualizer = 'eq_virtualizer';

  StreamSubscription<int?>? _sub;
  int? _sessionId;

  @override
  AudioEffectsState build() {
    if (Platform.isAndroid) {
      final player = ref.watch(audioPlayerProvider);
      unawaited(_attachSession(player.androidAudioSessionId));
      _sub = player.androidAudioSessionIdStream.listen((sid) {
        if (sid != null && sid != _sessionId) _attachSession(sid);
      });
      ref.onDispose(() {
        _sub?.cancel();
        AudioEffectsApi.release();
      });
    }
    _loadPrefs();
    return const AudioEffectsState();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final gains = <int, int>{};
    final raw = prefs.getString(_keyGains);
    if (raw != null) {
      try {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          gains[int.parse(k)] = (v as num).round();
        });
      } catch (_) {}
    }
    state = state.copyWith(
      enabled: prefs.getBool(_keyEnabled) ?? false,
      gains: gains,
      bass: prefs.getInt(_keyBass) ?? 0,
      virtualizer: prefs.getInt(_keyVirtualizer) ?? 0,
    );
  }

  /// 挂载到播放器的 Android 音频会话；换会话（如蓝牙重连）时重新挂
  Future<void> _attachSession(int? sessionId) async {
    if (sessionId == null || sessionId == _sessionId) return;
    _sessionId = sessionId;
    final bands = await AudioEffectsApi.init(sessionId);
    if (bands.isEmpty) {
      _sessionId = null;
      return;
    }
    state = state.copyWith(bands: bands, ready: true);
    await _pushAll();
  }

  Future<void> _pushAll() async {
    await AudioEffectsApi.setEq(state.enabled);
    for (final band in state.bands.indexed) {
      final level = state.gains[band.$1] ?? 0;
      await AudioEffectsApi.setBandLevel(
        band.$1,
        level.clamp(band.$2.minMb, band.$2.maxMb),
      );
    }
    await AudioEffectsApi.setBass(state.bass);
    await AudioEffectsApi.setVirtualizer(state.virtualizer);
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    await AudioEffectsApi.setEq(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, v);
  }

  Future<void> setBand(int index, int levelMb) async {
    final band = state.bands.isEmpty ? null : state.bands[index];
    final clamped = band == null
        ? levelMb
        : levelMb.clamp(band.minMb, band.maxMb);
    state = state.copyWith(gains: {...state.gains, index: clamped});
    await AudioEffectsApi.setBandLevel(index, clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGains, jsonEncode(state.gains));
  }

  /// 应用预设：设备波段按频点插值映射到标准频点曲线
  Future<void> applyPreset(String name) async {
    final preset = eqPresets[name];
    if (preset == null) return;
    for (final band in state.bands.indexed) {
      final db = _presetGainAt(preset, band.$2.centerHz);
      await setBand(band.$1, (db * 100).round());
    }
  }

  Future<void> setBass(int v) async {
    state = state.copyWith(bass: v.clamp(0, 1000));
    await AudioEffectsApi.setBass(state.bass);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBass, state.bass);
  }

  Future<void> setVirtualizer(int v) async {
    state = state.copyWith(virtualizer: v.clamp(0, 1000));
    await AudioEffectsApi.setVirtualizer(state.virtualizer);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyVirtualizer, state.virtualizer);
  }
}

final audioEffectsProvider =
    NotifierProvider<AudioEffectsController, AudioEffectsState>(
      AudioEffectsController.new,
    );
