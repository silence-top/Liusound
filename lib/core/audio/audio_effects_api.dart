import 'audio_effects_api_web.dart'
    if (dart.library.io) 'audio_effects_api_io.dart';
export 'audio_effects_api_web.dart'
    if (dart.library.io) 'audio_effects_api_io.dart';

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

/// 原生音效链通道封装（仅 Android；iOS 无 just_audio 可挂载的 EQ 入口，不可行）。
/// 其他平台返回空波段 / no-op。
abstract class AudioEffectsApi {
  bool get isAvailable;
  Future<List<EqBand>> init(int sessionId);
  Future<void> setEq(bool enabled);
  Future<void> setBandLevel(int index, int levelMb);
  Future<void> setBass(int strength);
  Future<void> setVirtualizer(int strength);
  Future<void> release();
}

final AudioEffectsApi audioEffectsApi = createAudioEffectsApi();
