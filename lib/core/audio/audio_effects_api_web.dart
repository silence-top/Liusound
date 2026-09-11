import 'audio_effects_api.dart';

/// web 端无音效能力（浏览器无 EQ/低音/空间 API）
final class AudioEffectsApiWeb implements AudioEffectsApi {
  @override
  bool get isAvailable => false;

  @override
  Future<List<EqBand>> init(int sessionId) async => const [];

  @override
  Future<void> setEq(bool enabled) async {}

  @override
  Future<void> setBandLevel(int index, int levelMb) async {}

  @override
  Future<void> setBass(int strength) async {}

  @override
  Future<void> setVirtualizer(int strength) async {}

  @override
  Future<void> release() async {}
}

AudioEffectsApi createAudioEffectsApi() => AudioEffectsApiWeb();
