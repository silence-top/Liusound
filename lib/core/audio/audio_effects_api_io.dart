import 'package:flutter/services.dart';

import '../platform/app_platform.dart';
import 'audio_effects_api.dart';

final class AudioEffectsApiIo implements AudioEffectsApi {
  static const _channel = MethodChannel('com.silencetop.liusound/audio_effects');

  @override
  bool get isAvailable => AppPlatform.isAndroid;

  @override
  Future<List<EqBand>> init(int sessionId) async {
    if (!isAvailable) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('init', sessionId);
      return raw?.map(EqBand.fromMap).toList() ?? const [];
    } on PlatformException {
      return const [];
    }
  }

  @override
  Future<void> setEq(bool enabled) async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod('setEq', {'enabled': enabled});
    } on PlatformException {
      // 设备不支持时静默降级
    }
  }

  @override
  Future<void> setBandLevel(int index, int levelMb) async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod('setBandLevel', {
        'index': index,
        'level': levelMb,
      });
    } on PlatformException {
      // 同上
    }
  }

  @override
  Future<void> setBass(int strength) async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod('setBass', strength);
    } on PlatformException {
      // 同上
    }
  }

  @override
  Future<void> setVirtualizer(int strength) async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod('setVirtualizer', strength);
    } on PlatformException {
      // 同上
    }
  }

  @override
  Future<void> release() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod('release');
    } on PlatformException {
      // 同上
    }
  }
}

AudioEffectsApi createAudioEffectsApi() => AudioEffectsApiIo();
