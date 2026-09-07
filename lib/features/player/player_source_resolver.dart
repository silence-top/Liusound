part of 'player_actions.dart';

/// 播放源解析（P1-SourceResolver）：统一优先级
/// 有效本地文件 → 有效下载文件 → 服务端流（转码探测 + 无损回退）。
/// 本文件不落库、不持久化，只负责把 Song 变成正在播放的声音
mixin PlayerSourceResolver
    on PlayerActionsBase, PlayerErrorHandler, PlayerBreakpoint {
  /// 播放指定歌曲（替换当前曲目）。
  /// 点击即切换当前歌（即时反馈），流解析在后台进行，缓冲态由播放键 spinner 呈现；
  /// 代数守卫保证连点时旧播放请求作废，不会与新一轮加载竞争。
  /// 本地歌曲（id 为 local: 前缀）或已离线下载的歌曲直接走本地文件，
  /// 不消耗流量；否则按当前网络（Wi-Fi / 蜂窝）解析音质档位，
  /// 蜂窝下关闭传输开关则拒播
  Future<void> play(Song song) async {
    final gen = ++_playGeneration;
    _ref.read(currentSongProvider.notifier).state = song;
    unawaited(_backfillLyrics(song, gen));
    final localPath = localSongPath(song) ?? await findDownloadedSong(song);
    if (gen != _playGeneration) return;
    if (localPath != null && File(localPath).existsSync()) {
      await _playLocal(song, localPath, gen);
      return;
    }
    final adapter = _adapter;
    if (adapter == null) return;
    final settings = _ref.read(streamingSettingsProvider);
    final quality = await resolveCurrentQuality(settings);
    if (gen != _playGeneration) return;
    if (quality == null) {
      _notify('移动网络下传输开关已关闭，播放被阻止');
      return;
    }
    // 服务端不支持转码时直接走无损，省一次注定失败的转码请求
    final effectiveQuality = quality == StreamQuality.lossless
        ? quality
        : (await adapter.supportsTranscode()
              ? quality
              : StreamQuality.lossless);
    if (gen != _playGeneration) return;
    final hint = QualityHint(
      quality: effectiveQuality,
      format: settings.transcodeFormat,
    );
    await _saveLongTrackBreakpoint();
    try {
      final source = await adapter.resolveStream(song, quality: hint);
      await _setStreamSource(source);
      if (gen != _playGeneration) return;
      _ref.read(currentQualityProvider.notifier).state = hint.quality;
      await _player.play();
      unawaited(
        AudioCache.enforceLimit(_ref.read(cacheSettingsProvider).limit),
      );
      unawaited(_resumeLongTrack(song));
    } catch (e) {
      _debugLog('play(${song.id}) quality=${quality.name} failed: $e');
      // 转码流失败（服务端缺转码器/参数不受支持等）自动回退无损原文件；
      // 原文件流也失败才是真正的网络/鉴权问题
      if (!hint.transcode) {
        _notify('播放失败，请检查服务器连接');
        return;
      }
      try {
        final source = await adapter.resolveStream(song);
        await _setStreamSource(source);
        if (gen != _playGeneration) return;
        _ref.read(currentQualityProvider.notifier).state =
            StreamQuality.lossless;
        await _player.play();
        unawaited(
          AudioCache.enforceLimit(_ref.read(cacheSettingsProvider).limit),
        );
        unawaited(_resumeLongTrack(song));
      } catch (fallbackError) {
        _debugLog('play(${song.id}) lossless fallback failed: $fallbackError');
        if (gen == _playGeneration) _notify('播放失败，请检查服务器连接');
      }
    }
  }

  /// 播放时按需补拉歌词：曲库快照与队列持久化的 JSON 往返会剥离内嵌歌词，
  /// 命中这类来源的歌曲在播放时向服务端重新请求一次并回填当前歌状态。
  /// 已有歌词（含本地导入）不重复请求；拉取期间切歌/换代则作废
  Future<void> _backfillLyrics(Song song, int gen) async {
    if (song.id.startsWith('local:')) return;
    if (parseLyricsData(song.lyrics).lines.isNotEmpty) return;
    final adapter = _adapter;
    if (adapter == null) return;
    final lyrics = await adapter.fetchLyrics(song.id);
    if (lyrics == null || parseLyricsData(lyrics).lines.isEmpty) return;
    if (gen != _playGeneration) return;
    if (_ref.read(currentSongProvider)?.id != song.id) return;
    _ref.read(currentSongProvider.notifier).state = song.copyWith(
      lyrics: lyrics,
    );
  }

  /// 按边听边存开关选择磁盘缓存源或直连源
  Future<void> _setStreamSource(PlaybackSource source) async {
    final cache = _ref.read(cacheSettingsProvider);
    if (cache.cacheWhileListen) {
      // 边听边存：走磁盘缓存源，断网可续播已缓存段落
      // LockCachingAudioSource 在 0.10 仍标记 experimental，API 或随版本变动
      await _player.setAudioSource(
        // ignore: experimental_member_use
        LockCachingAudioSource(
          Uri.parse(source.url),
          headers: source.headers.isNotEmpty ? source.headers : null,
        ),
      );
    } else {
      await _player.setUrl(source.url, headers: source.headers);
    }
  }

  /// 本地文件播放（本地扫描歌曲 / 已离线下载歌曲）
  Future<void> _playLocal(Song song, String path, int gen) async {
    _ref.read(currentQualityProvider.notifier).state = null;
    await _saveLongTrackBreakpoint();
    try {
      await _player.setAudioSource(AudioSource.file(path));
      if (gen != _playGeneration) return;
      await _player.play();
      unawaited(_resumeLongTrack(song));
    } catch (_) {
      // 文件被移动/删除等场景给出提示，状态保持可重试
      if (gen == _playGeneration) _notify('本地文件播放失败：文件不可读');
    }
  }
}
