part of 'player_actions.dart';

/// 播放源解析（P1-SourceResolver）：统一优先级
/// 有效本地文件 → 有效下载文件 → 服务端流（转码探测 + 无损回退）。
/// 本文件不落库、不持久化，只负责把 Song 变成正在播放的声音
mixin PlayerSourceResolver
    on PlayerActionsBase, PlayerErrorHandler, PlayerBreakpoint {
  /// 播放指定歌曲（替换当前曲目）。
  /// 点击即切换当前歌（即时反馈），流解析在后台进行，缓冲态由播放键 spinner 呈现；
  /// 代数守卫保证连点时旧播放请求作废，不会与新一轮加载竞争。
  /// 返回本次请求的代数：交叉淡化持有它判断淡入期间是否被手动切歌打断。
  /// 本地歌曲（id 为 local: 前缀）或已离线下载的歌曲直接走本地文件，
  /// 不消耗流量；否则按当前网络（Wi-Fi / 蜂窝）解析音质档位，
  /// 蜂窝下关闭传输开关则拒播
  Future<int> play(Song song) async {
    // 先刷新服务器依赖，再领取代数，避免切服监听把本次新请求也作废。
    final serverId = _ref.read(activeServerIdProvider);
    final adapter = _adapter;
    final breakpoint = _captureLongTrackBreakpoint();
    final gen = ++_playGeneration;
    // 冷启动恢复的待播进度一次性消费：装源完成后、起播前 seek。
    // 播放失败时该进度丢失——重试走正常起播（长音频仍有独立断点），可接受
    final pendingResumeMs = _pendingResumeMs;
    _pendingResumeMs = 0;
    _resumePositionMs = 0;
    _ref.read(loadedPlaybackProvider.notifier).state = null;
    _ref.read(currentQualityProvider.notifier).state = null;
    _ref.read(resumeNoticeProvider.notifier).state = null;
    _ref.read(currentSongProvider.notifier).state = song;
    unawaited(_backfillLyrics(song, gen, serverId));
    // 暂停旧源，失败/门禁拒播时也不会继续播放旧歌。保存只使用切换前快照。
    final paused = _player.pause();
    await _saveLongTrackBreakpoint(breakpoint);
    await paused;
    if (!_isCurrentRequest(gen, serverId)) return gen;
    final localPath =
        localSongPath(song) ?? await findDownloadedSong(song, serverId);
    if (!_isCurrentRequest(gen, serverId)) return gen;
    if (localPath != null && localFs.fileExists(localPath)) {
      await _playLocal(song, serverId, localPath, gen, pendingResumeMs);
      return gen;
    }
    if (adapter == null) return gen;
    final settings = _ref.read(streamingSettingsProvider);
    final quality = await resolveCurrentQuality(settings);
    if (!_isCurrentRequest(gen, serverId)) return gen;
    if (quality == null) {
      _notify('移动网络下传输开关已关闭，播放被阻止');
      return gen;
    }
    // 服务端不支持转码时直接走无损，省一次注定失败的转码请求
    final effectiveQuality = quality == StreamQuality.lossless
        ? quality
        : (await adapter.supportsTranscode()
              ? quality
              : StreamQuality.lossless);
    if (!_isCurrentRequest(gen, serverId)) return gen;
    final hint = QualityHint(
      quality: effectiveQuality,
      format: settings.transcodeFormat,
    );
    try {
      final source = await adapter.resolveStream(song, quality: hint);
      // 写音源前先验代数：连点时旧请求晚到会把旧音源覆写到播放器上，
      // 打断新一轮加载（连点必炸的根源）
      if (!_isCurrentRequest(gen, serverId)) return gen;
      final audioSource = await _setStreamSource(source);
      if (!_isCurrentRequest(gen, serverId)) return gen;
      _ref.read(currentQualityProvider.notifier).state = hint.quality;
      await _startLoaded(song, serverId, gen, audioSource, pendingResumeMs);
    } catch (e) {
      _debugLog('play(${song.id}) quality=${quality.name} failed: $e');
      // 本次已是旧代数：新一轮播放正在跑，旧失败必须静默，
      // 也不能再发起无损回退去和新请求竞争
      if (!_isCurrentRequest(gen, serverId)) return gen;
      // 转码流失败（服务端缺转码器/参数不受支持等）自动回退无损原文件；
      // 原文件流也失败才是真正的网络/鉴权问题
      if (!hint.transcode) {
        _notify('播放失败，请检查服务器连接');
        return gen;
      }
      try {
        final source = await adapter.resolveStream(song);
        if (!_isCurrentRequest(gen, serverId)) return gen;
        final audioSource = await _setStreamSource(source);
        if (!_isCurrentRequest(gen, serverId)) return gen;
        _ref.read(currentQualityProvider.notifier).state =
            StreamQuality.lossless;
        await _startLoaded(song, serverId, gen, audioSource, pendingResumeMs);
      } catch (fallbackError) {
        _debugLog('play(${song.id}) lossless fallback failed: $fallbackError');
        if (_isCurrentRequest(gen, serverId)) _notify('播放失败，请检查服务器连接');
      }
    }
    return gen;
  }

  /// 音源已就位后的公共起播段：恢复待播进度 → ReplayGain → 发起播放。
  /// just_audio 的 play() Future 在首次起播时要到 暂停/停止/播完 才完成，
  /// 只发起不等待，否则调用方（恢复续播/FM start/交叉淡化）会被拖住直到暂停；
  /// 无待播进度时长音频命中断点则起播前跳过去（此前 await play 挡到暂停，
  /// 该分支几乎永不执行——顺带修复）
  Future<void> _startLoaded(
    Song song,
    String serverId,
    int gen,
    AudioSource source,
    int pendingResumeMs,
  ) async {
    if (!_isCurrentRequest(gen, serverId)) return;
    final loaded = LoadedPlayback(
      song: song,
      serverId: serverId,
      generation: gen,
      source: source,
    );
    if (!loaded.ownsPlayer(_player)) return;
    _ref.read(loadedPlaybackProvider.notifier).state = loaded;
    if (pendingResumeMs > 0) {
      await _seekOrIgnore(pendingResumeMs, loaded);
    } else {
      await _resumeLongTrack(loaded);
    }
    if (!_isCurrentPlayback(loaded)) return;
    _applyReplayGain(song);
    unawaited(_player.play());
    unawaited(AudioCache.enforceLimit(_ref.read(cacheSettingsProvider).limit));
  }

  /// 冷启动进度也须属于本次音源且在有效范围内；未知时长不盲目 seek。
  Future<void> _seekOrIgnore(int ms, LoadedPlayback loaded) async {
    try {
      if (!_isCurrentPlayback(loaded)) return;
      final duration = loaded.effectiveDuration(_player);
      if (duration == null || ms <= 0 || ms >= duration.inMilliseconds) return;
      await _player.seek(Duration(milliseconds: ms));
    } catch (_) {}
  }

  /// 播放时按需补拉歌词：曲库快照与队列持久化的 JSON 往返会剥离内嵌歌词，
  /// 命中这类来源的歌曲在播放时向服务端重新请求一次并回填当前歌状态。
  /// 已有歌词（含本地导入）不重复请求；拉取期间切歌/换代则作废
  Future<void> _backfillLyrics(Song song, int gen, String serverId) async {
    if (song.id.startsWith('local:')) return;
    if (parseLyricsData(song.lyrics).lines.isNotEmpty) return;
    final adapter = _adapter;
    if (adapter == null) return;
    final lyrics = await adapter.fetchLyrics(song.id);
    if (lyrics == null || parseLyricsData(lyrics).lines.isEmpty) return;
    if (!_isCurrentRequest(gen, serverId)) return;
    if (_ref.read(currentSongProvider)?.id != song.id) return;
    _ref.read(currentSongProvider.notifier).state = song.copyWith(
      lyrics: lyrics,
    );
  }

  /// 按边听边存开关选择磁盘缓存源或直连源（web 无磁盘缓存，恒直连）
  Future<AudioSource> _setStreamSource(PlaybackSource source) async {
    final cache = _ref.read(cacheSettingsProvider);
    final AudioSource audioSource;
    if (cache.cacheWhileListen && !AppPlatform.isWeb) {
      // 边听边存：保留原缓存/鉴权策略，每次创建独立音源身份。
      // ignore: experimental_member_use
      audioSource = LockCachingAudioSource(
        Uri.parse(source.url),
        headers: source.headers.isNotEmpty ? source.headers : null,
      );
    } else {
      audioSource = AudioSource.uri(
        Uri.parse(source.url),
        headers: source.headers,
      );
    }
    await _player.setAudioSource(audioSource, initialPosition: Duration.zero);
    return audioSource;
  }

  /// 本地文件播放（本地扫描歌曲 / 已离线下载歌曲）
  Future<void> _playLocal(
    Song song,
    String serverId,
    String path,
    int gen,
    int pendingResumeMs,
  ) async {
    if (!_isCurrentRequest(gen, serverId)) return;
    _ref.read(currentQualityProvider.notifier).state = null;
    try {
      final source = AudioSource.file(path);
      await _player.setAudioSource(source, initialPosition: Duration.zero);
      if (!_isCurrentRequest(gen, serverId)) return;
      await _startLoaded(song, serverId, gen, source, pendingResumeMs);
    } catch (_) {
      // 文件被移动/删除等场景给出提示，状态保持可重试
      if (_isCurrentRequest(gen, serverId)) _notify('本地文件播放失败：文件不可读');
    }
  }

  /// ReplayGain 音量归一化：按当前模式选取 gain/peak，dB→线性后做峰值限制，
  /// 关闭时恢复满音量。仅在歌曲携带了增益数据时生效。
  /// 交叉淡化期间跳过：音量由 fade 循环托管，避免淡入被直接顶到目标值
  void _applyReplayGain(Song song) {
    if (_fading) return;
    unawaited(_player.setVolume(_replayGainTargetVolume(song)));
  }

  /// ReplayGain 目标音量（线性倍率，0–1）；无增益数据/关闭模式时为 1.0
  double _replayGainTargetVolume(Song song) {
    final mode = _ref.read(replayGainModeProvider);
    if (mode == ReplayGainMode.off) return 1.0;
    final rg = song.replayGain;
    if (rg == null) return 1.0;
    final gainDb = mode == ReplayGainMode.album
        ? (rg.albumGain ?? rg.trackGain)
        : (rg.trackGain ?? rg.albumGain);
    final peak = mode == ReplayGainMode.album
        ? (rg.albumPeak ?? rg.trackPeak)
        : (rg.trackPeak ?? rg.albumPeak);
    if (gainDb == null) return 1.0;
    var multiplier = pow(10, gainDb / 20).toDouble();
    if (peak != null && peak > 0) {
      multiplier = min(multiplier, peak);
    }
    return min(max(multiplier, 0.0), 1.0);
  }
}
