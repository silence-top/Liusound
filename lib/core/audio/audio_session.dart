import 'dart:async';

import 'audio_session_web.dart' if (dart.library.io) 'audio_session_io.dart';
export 'audio_session_web.dart' if (dart.library.io) 'audio_session_io.dart';

/// 音频会话门面：封装 audio_session 包的平台差异。
/// 仅 Android/iOS/macOS 支持音频焦点与耳机拔出事件；
/// Windows/Linux/鸿蒙/Web 为 no-op。
abstract class AudioSessionFacade {
  bool get isAvailable;

  /// 配置为音乐播放模式（播放时降低其他应用音量，避免混音）
  Future<void> configureAsMusic();

  /// 耳机拔出/蓝牙断开事件流（平台不支持时返回空流）
  Stream<void> get becomingNoisyEventStream;
}

final AudioSessionFacade audioSession = createAudioSession();
