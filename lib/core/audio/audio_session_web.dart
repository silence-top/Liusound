import 'dart:async';

import 'audio_session.dart';

/// web 端无音频会话能力（浏览器自管音频焦点与设备插拔）
final class AudioSessionWeb implements AudioSessionFacade {
  @override
  bool get isAvailable => false;

  @override
  Future<void> configureAsMusic() async {}

  @override
  Stream<void> get becomingNoisyEventStream => const Stream.empty();
}

AudioSessionFacade createAudioSession() => AudioSessionWeb();
