import 'dart:async';

import 'package:audio_session/audio_session.dart';

import '../platform/app_platform.dart';
import 'audio_session.dart';

final class AudioSessionIo implements AudioSessionFacade {
  @override
  bool get isAvailable =>
      !AppPlatform.isWindows && !AppPlatform.isLinux && !AppPlatform.isOhos;

  @override
  Future<void> configureAsMusic() async {
    if (!isAvailable) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  @override
  Stream<void> get becomingNoisyEventStream {
    if (!isAvailable) return const Stream.empty();
    return AudioSession.instance.then((session) {
      return session.becomingNoisyEventStream;
    }).asStream().asyncExpand((s) => s);
  }
}

AudioSessionFacade createAudioSession() => AudioSessionIo();
