part of 'full_screen_player.dart';

// ---------- Tab 3：歌词（双语 / 点击跳转 / LRC 菜单 / 音量 / 偏移面板） ----------

class _LyricsTab extends ConsumerStatefulWidget {
  const _LyricsTab({required this.song});

  final Song song;

  @override
  ConsumerState<_LyricsTab> createState() => _LyricsTabState();
}

class _LyricsTabState extends ConsumerState<_LyricsTab>
    with AutomaticKeepAliveClientMixin {
  LyricsData _lyrics = const LyricsData();
  List<LyricLine> _displayLines = const []; // 展示行（LRC 同时间轴双语行已合并）
  List<String?> _displayTranslations = const []; // 与展示行对齐的译文（无则 null）
  double _rowHeight = _lyricRowHeight;
  bool _hasTranslation = false;
  double _offset = 0;
  bool _manualScrolling = false;
  // 程序化 animateTo 计数：滚动通知监听据此排除自动滚动，避免误设 _manualScrolling
  int _autoScrollCount = 0;
  bool _syncScheduled = false;
  bool _showLrcMenu = false;
  bool _showLyricAdjust = false;
  bool _showVolume = false;
  double _volume = 1;
  // 音轨切换（「切换歌词」）：全部音轨缓存 + 当前选中索引 + 弹层开关
  List<(String, List<LyricLine>)> _tracks = const [];
  int _currentTrackIndex = 0;
  bool _showTrackPicker = false;
  // 当前行索引：值变化仅触发对应行的 ValueListenableBuilder 重建（行级更新）
  final ValueNotifier<int> _currentIndex = ValueNotifier(-2);
  // 点击行预览（§4.3）：被选中待跳播的行，右侧浮出「时间戳 + Play」，-1 表示无
  int _previewIndex = -1;
  // 本地导入歌词已生效（优先级高于服务端 JSON，补拉回填不得覆盖）
  bool _usingLocalLyrics = false;
  Timer? _previewTimer;
  Timer? _manualScrollTimer;
  final ScrollController _controller = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _parseLyrics();
    _loadLocalLyrics();
    _loadOffset();
    _volume = ref.read(audioPlayerProvider).volume;
  }

  @override
  void didUpdateWidget(_LyricsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.song.id != oldWidget.song.id) {
      _usingLocalLyrics = false;
      _parseLyrics();
      _loadLocalLyrics();
      _offset = 0;
      _currentIndex.value = -2;
      _previewIndex = -1;
      _previewTimer?.cancel();
      _loadOffset();
    } else if (widget.song.lyrics != oldWidget.song.lyrics) {
      // 同一首歌歌词补拉到位（播放时按需回填）后原地刷新；
      // 本地导入歌词优先级更高，生效时不覆盖
      if (!_usingLocalLyrics) _parseLyrics();
    }
  }

  @override
  void dispose() {
    _manualScrollTimer?.cancel();
    _previewTimer?.cancel();
    _currentIndex.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 解析歌词（含双语译轨 + LRC 同时间轴双语行）并构建展示行
  void _parseLyrics() {
    final data = parseLyricsData(widget.song.lyrics);
    setState(() {
      _lyrics = data;
      _tracks = parseLyricsTracks(widget.song.lyrics);
      _currentTrackIndex = 0;
      _showTrackPicker = false;
      _applyLines(data.lines, data.translations);
    });
  }

  /// 歌词查找键优先级（P0-09）：服务器歌曲 serverId+songId →
  /// 本地歌曲 fingerprint → 「标题|歌手」兜底（兼容历史行）
  List<String> _lyricsLookupKeys() {
    final song = widget.song;
    final keys = <String>[];
    if (song.id.startsWith('local:')) {
      keys.add(AppDb.lyricsLocalKey(localSongFingerprint(song)!));
    } else {
      final serverId = ref.read(authControllerProvider).activeServerId;
      if (serverId != null) {
        keys.add(AppDb.lyricsSongKey(serverId, song.id));
      }
    }
    keys.add(AppDb.lyricsFallbackKey(song.title, song.artist));
    return keys;
  }

  /// 本地导入歌词（SQLite lyrics_local）：命中后优先于服务端 JSON 歌词
  Future<void> _loadLocalLyrics() async {
    final songId = widget.song.id;
    final content = await AppDb.loadLyrics(_lyricsLookupKeys());
    if (content == null || songId != widget.song.id || !mounted) return;
    final lines = parseLrcText(content);
    if (lines.isEmpty) return;
    setState(() {
      _usingLocalLyrics = true;
      _lyrics = LyricsData(lines: lines);
      _tracks = const [];
      _currentTrackIndex = 0;
      _showTrackPicker = false;
      _applyLines(lines, const []);
    });
  }

  /// LRC 手动导入弹层：粘贴文本或选 .lrc 文件，校验时间轴后存库并即时生效
  Future<void> _showImportSheet() async {
    final controller = TextEditingController();
    await glassBottomSheet<void>(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '导入歌词',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextField(
            controller: controller,
            maxLines: 6,
            minLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              hintText: '粘贴 .lrc 歌词文本（[mm:ss.xx] 歌词）',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  try {
                    // pickFiles 一并捕获：无文件选择器实现的平台（鸿蒙等）走同一错误提示
                    final files = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['lrc', 'txt'],
                    );
                    final path = files.isEmpty ? null : files.first.path;
                    if (path == null) return;
                    final text = await localFs.readTextFile(path);
                    if (text == null) {
                      throw Exception('文件读取失败');
                    }
                    controller.text = text;
                  } catch (_) {
                    showToast('文件读取失败', error: true);
                  }
                },
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('选择文件'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  final lines = parseLrcText(controller.text);
                  if (lines.isEmpty) {
                    showToast('未识别到 LRC 时间轴', error: true);
                    return;
                  }
                  final keys = _lyricsLookupKeys();
                  final existing = await AppDb.loadLyrics(keys);
                  if (existing != null && existing.isNotEmpty && mounted) {
                    final overwrite = await glassDialog<bool>(
                      context,
                      title: '覆盖歌词',
                      content: Text(
                        '这首歌已有导入的歌词，保存将覆盖现有内容。确定覆盖？',
                        style: TextStyle(
                          color: AppTheme.textDimOf(context),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('覆盖'),
                        ),
                      ],
                    );
                    if (overwrite != true || !mounted) return;
                  }
                  await AppDb.saveLyrics(
                    lookupKey: keys.first,
                    fallbackKey: AppDb.lyricsFallbackKey(
                      widget.song.title,
                      widget.song.artist,
                    ),
                    title: widget.song.title,
                    artist: widget.song.artist,
                    content: controller.text,
                  );
                  if (mounted) Navigator.of(context).pop();
                  if (!mounted) return;
                  setState(() {
                    _lyrics = LyricsData(lines: lines);
                    _tracks = const [];
                    _currentTrackIndex = 0;
                    _showTrackPicker = false;
                    _applyLines(lines, const []);
                  });
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
    controller.dispose();
  }

  /// 由主轨/译轨构建展示行：LRC 相邻同时间轴两行合并为 原文+译文，
  /// 服务端译轨按时间戳补充对齐（同一行两者都有时优先 LRC 内嵌译文）
  void _applyLines(List<LyricLine> lines, List<LyricLine> translations) {
    final (merged, inline) = mergeDuplicateTimestamps(lines);
    final aligned = alignTranslations(merged, translations);
    _displayLines = merged;
    _displayTranslations = [
      for (var i = 0; i < merged.length; i++) inline[i] ?? aligned[i],
    ];
    _hasTranslation = _displayTranslations.any((t) => t != null);
    _rowHeight = ref.read(bilingualLyricsProvider) && _hasTranslation
        ? _lyricDualHeight
        : _lyricRowHeight;
    _currentIndex.value = -2;
  }

  /// 偏移 key 带服务器 id：不同服务器的同名/同 id 歌曲偏移互不串扰
  String get _offsetKey =>
      '$lyricOffsetKeyPrefix'
      '${ref.read(authControllerProvider).activeServerId ?? 'local'}:'
      '${widget.song.id}';

  Future<void> _loadOffset() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble(_offsetKey) ?? 0;
    if (mounted) setState(() => _offset = v);
  }

  /// 切换双语歌词：状态与持久化由 [bilingualLyricsProvider] 统一负责，
  /// 行高联动与居中保持由 build 中的 ref.listen 处理（MiniBar 同步刷新）
  void _toggleBilingual(bool v) {
    ref.read(bilingualLyricsProvider.notifier).set(v);
  }

  /// 保存偏移（0 表示清除该歌曲的偏移记录，对标 1.x handleSaveLyricOffset）
  Future<void> _persistOffset(double v) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _offsetKey;
    if (v == 0) {
      await prefs.remove(key);
    } else {
      await prefs.setDouble(key, v);
    }
  }

  void _adjustOffset(double delta) => setState(
    () => _offset = double.parse((_offset + delta).toStringAsFixed(2)),
  );

  /// 点击歌词行（§4.3 两段式跳播）：
  /// 首次点非当前行只在该行右侧浮出「时间戳 + Play」预览，再点一次或点 Play 才真正跳播；
  /// 点当前行等于取消预览。预览 4 秒不动自动收起，避免误触后一直挂着。
  void _handleRowTap(int i) {
    if (i == _currentIndex.value) {
      _clearPreview();
      return;
    }
    if (_previewIndex == i) {
      _seekToLine(i);
      return;
    }
    setState(() => _previewIndex = i);
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _previewIndex = -1);
    });
  }

  /// 跳到第 i 行（减去偏移，对齐 1.x handleLyricPress）
  void _seekToLine(int i) {
    final t = _displayLines[i].time - _offset;
    ref
        .read(playerActionsProvider)
        .seek(Duration(milliseconds: (t * 1000).round()));
    _clearPreview();
  }

  void _clearPreview() {
    _previewTimer?.cancel();
    if (_previewIndex == -1) return;
    setState(() => _previewIndex = -1);
  }

  /// 进度/拖动流触发的同步统一推迟到帧后执行：
  /// ref.listen 可能在 build 阶段同步回调，此时 jumpTo/animateTo 会污染布局管线，
  /// 导致后续帧持续断言失败、命中测试失效（真机上表现为所有点击无响应）。
  void _scheduleSyncIndex() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _syncIndex();
    });
  }

  /// 计算当前行并同步高亮/滚动（进度流与拖动流共同触发）
  void _syncIndex() {
    if (_displayLines.isEmpty) return;
    final drag = ref.read(sliderDragValueProvider);
    final double t;
    if (drag != null) {
      t = drag / 1000.0;
    } else {
      t =
          (ref.read(positionProvider).valueOrNull ?? Duration.zero)
              .inMilliseconds /
          1000.0;
    }
    final idx = findLyricIndex(_displayLines, t + _offset);
    if (idx == _currentIndex.value) return;
    _currentIndex.value = idx;
    if (idx < 0 || !_controller.hasClients) return;
    // 列表上下 padding 各为半个视口（见 build），行中心对齐视口中心
    // 只需滚到 idx*行高 + 半行高，首尾行同样可居中
    final target = (idx * _rowHeight + _rowHeight / 2).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    if (drag != null) {
      // 拖动进度条时无动画立即跟随（对齐 1.x handleSliderChange）
      _controller.jumpTo(target);
    } else if (!_manualScrolling) {
      _autoScrollCount++;
      _controller
          .animateTo(
            target,
            // 省电模式压缩滚动时长（§8.5 AppMotion）：触发时求值
            duration: AppMotion.duration(
              context,
              MotionTokens.durationTransition,
            ),
            curve: Curves.easeOut,
          )
          .whenComplete(() => _autoScrollCount--);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.listen(positionProvider, (_, _) => _scheduleSyncIndex());
    ref.listen(sliderDragValueProvider, (_, _) => _scheduleSyncIndex());

    // 双语开关（响应式，MiniBar 双语副标题同源）：变化时行高联动 +
    // 保持当前行居中（原 _toggleBilingual 逻辑）
    final showBilingual = ref.watch(bilingualLyricsProvider);
    ref.listen(bilingualLyricsProvider, (_, v) {
      if (!mounted) return;
      setState(() {
        _rowHeight = v && _hasTranslation ? _lyricDualHeight : _lyricRowHeight;
      });
      if (!_controller.hasClients) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final idx = _currentIndex.value;
        if (idx < 0 || !_controller.hasClients) return;
        final target = (idx * _rowHeight + _rowHeight / 2).clamp(
          0.0,
          _controller.position.maxScrollExtent,
        );
        _controller.jumpTo(target);
      });
    });

    // 歌词页浮层（LRC 菜单/音轨/偏移/音量）随封面主色毛玻璃底（底色近实色不透底）
    final current = ref.watch(currentSongProvider);
    final panelDominant = current == null
        ? null
        : ref.watch(albumDominantColorProvider(current.albumId)).valueOrNull;

    final hasLyrics = _displayLines.isNotEmpty;
    if (!hasLyrics) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂无歌词', style: TextStyle(color: Colors.white38)),
            const SizedBox(height: AppSpacing.m),
            TextButton.icon(
              onPressed: _showImportSheet,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('导入歌词'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            // 歌词主体（手动滚动后暂停自动跟随 2.5s；首尾行可居中）
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) =>
                    NotificationListener<UserScrollNotification>(
                      onNotification: (n) {
                        if (_autoScrollCount == 0 &&
                            n.direction != ScrollDirection.idle) {
                          _manualScrolling = true;
                          _manualScrollTimer?.cancel();
                          _manualScrollTimer = Timer(
                            const Duration(milliseconds: 2500),
                            () => _manualScrolling = false,
                          );
                        }
                        return false;
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ListView.builder(
                            controller: _controller,
                            itemExtent: _rowHeight,
                            padding: EdgeInsets.symmetric(
                              vertical: constraints.maxHeight / 2,
                              horizontal: 20,
                            ),
                            itemCount: _displayLines.length,
                            itemBuilder: (_, i) => ValueListenableBuilder<int>(
                              valueListenable: _currentIndex,
                              builder: (_, current, _) => _LyricRowTile(
                                text: _displayLines[i].text,
                                translation: showBilingual
                                    ? _displayTranslations[i]
                                    : null,
                                // 与当前行的距离驱动景深衰减（§4.3）：
                                // 越远越淡越小；还没定位到当前行时统一按远景处理
                                distance: current < 0 ? 3 : (i - current).abs(),
                                previewTime: i == _previewIndex
                                    ? _displayLines[i].time
                                    : null,
                                onTap: () => _handleRowTap(i),
                                onPreviewTap: () => _seekToLine(i),
                                onDoubleTap: () =>
                                    _toggleBilingual(!showBilingual),
                              ),
                            ),
                          ),
                          // 顶部/底部渐变遮罩（对齐 1.x lyricFadeTop/Bottom）
                          Align(
                            alignment: Alignment.topCenter,
                            child: FractionallySizedBox(
                              heightFactor: 0.2,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      _lyricFade,
                                      _lyricFade.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: 0.15,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      _lyricFade,
                                      _lyricFade.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ),
            ),
            // LRC / 音量按钮行（对齐 1.x lrcRow）
            // 命中区域用 InkWell/IconButton（不透明命中），避免裸 GestureDetector
            // 只能命中文字本身导致的小目标点击失败
            Container(
              height: 42,
              margin: const EdgeInsets.only(left: 28, bottom: 6),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  _lyricBadge(
                    'LRC',
                    onTap: () => setState(() => _showLrcMenu = true),
                  ),
                  // 「译」快速开关（§4.3）：与 LRC 菜单里的双语歌词同一状态。
                  // 没有译轨时不渲染，避免留一个点了没反应的死按钮
                  if (_hasTranslation) ...[
                    const SizedBox(width: 10),
                    _lyricBadge(
                      '译',
                      active: showBilingual,
                      onTap: () => _toggleBilingual(!showBilingual),
                    ),
                  ],
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: () => setState(() => _showVolume = !_showVolume),
                    icon: const Icon(
                      Icons.volume_up,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // LRC 弹出菜单（调整歌词 / 生成翻译 / 切换歌词，对齐 1.x）
        if (_showLrcMenu) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showLrcMenu = false),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 58,
            child: Material(
              color: Colors.transparent,
              child: AlbumFrostedPanel(
                dominant: panelDominant,
                borderRadius: BorderRadius.circular(AppRadius.l),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  // 不用 stretch：Positioned 下宽度无约束，stretch 会迫使
                  // 子项无限宽导致布局崩溃；收缩包裹最宽子项即等效效果
                  children: [
                    _menuItem(Icons.tune, '调整歌词', () {
                      setState(() {
                        _showLrcMenu = false;
                        _showLyricAdjust = true;
                      });
                    }),
                    _menuBilingualItem(),
                    _menuItem(Icons.search, '切换歌词', () {
                      setState(() {
                        _showLrcMenu = false;
                        _showTrackPicker = true;
                      });
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
        // 音轨选择菜单（「切换歌词」）
        if (_showTrackPicker) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showTrackPicker = false),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 58,
            child: Material(
              color: Colors.transparent,
              child: AlbumFrostedPanel(
                dominant: panelDominant,
                borderRadius: BorderRadius.circular(AppRadius.l),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  // 不用 stretch：Positioned 下宽度无约束，stretch 会迫使
                  // 子项无限宽导致布局崩溃；收缩包裹最宽子项即等效效果
                  children: [
                    if (_tracks.length <= 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Text(
                          '没有其他音轨',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      )
                    else
                      for (var i = 0; i < _tracks.length; i++)
                        _menuItem(
                          i == _currentTrackIndex
                              ? Icons.check
                              : Icons.music_note,
                          _trackLabel(_tracks[i].$1, i),
                          () => _selectTrack(i),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
        // 歌词偏移悬浮面板（右侧，对标 1.x lyricAdjustPanel）
        if (_showLyricAdjust)
          Positioned(
            right: 18,
            top: MediaQuery.of(context).size.height * 0.18,
            child: AlbumFrostedPanel(
              dominant: panelDominant,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
              child: SizedBox(
                width: 56,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _adjBtn(Icons.arrow_upward, () => _adjustOffset(0.05)),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '${_offset.toStringAsFixed(2)}s',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _adjBtn(Icons.arrow_downward, () => _adjustOffset(-0.05)),
                    _adjBtn(Icons.refresh, () => setState(() => _offset = 0)),
                    _adjBtn(Icons.check, () {
                      _persistOffset(_offset);
                      setState(() => _showLyricAdjust = false);
                    }),
                    _adjBtn(Icons.content_copy, () {
                      Clipboard.setData(
                        ClipboardData(
                          text: _lyrics.lines.map((l) => l.text).join('\n'),
                        ),
                      );
                      showToast('歌词已复制', duration: const Duration(seconds: 1));
                    }),
                  ],
                ),
              ),
            ),
          ),
        // 音量条弹层（对齐 1.x volumeBarWrap：白条进度 + 百分比）
        if (_showVolume) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showVolume = false),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 70,
            bottom: 50,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _applyVolume(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => _applyVolume(d.localPosition.dx),
              child: AlbumFrostedPanel(
                dominant: panelDominant,
                borderRadius: BorderRadius.circular(GlassTokens.radiusPill),
                child: SizedBox(
                  width: 180,
                  height: 36,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      FractionallySizedBox(
                        widthFactor: _volume.clamp(0.08, 1.0),
                        child: const ColoredBox(color: Color(0xE6FFFFFF)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.volume_up,
                              size: 22,
                              color: _volume > 0.5
                                  ? Colors.black87
                                  : Colors.white38,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(_volume * 100).round()}%',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _volume > 0.5
                                    ? Colors.black87
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 切换主轨歌词（选中的轨替换原文，双语对齐重置）
  void _selectTrack(int index) {
    final (_, lines) = _tracks[index];
    setState(() {
      _currentTrackIndex = index;
      _showTrackPicker = false;
      _lyrics = LyricsData(lines: lines);
      _applyLines(lines, const []);
    });
  }

  String _trackLabel(String lang, int index) =>
      lang.isEmpty ? '音轨 ${index + 1}' : lang.toUpperCase();

  void _applyVolume(double dx) {
    final v = (dx / 180).clamp(0.0, 1.0);
    setState(() => _volume = v);
    ref.read(audioPlayerProvider).setVolume(v);
  }

  /// 双语歌词菜单行：开启时文字高亮、关闭时置灰，点击整行切换（菜单保持展开）
  Widget _menuBilingualItem() {
    final showBilingual = ref.watch(bilingualLyricsProvider);
    return InkWell(
      onTap: () => _toggleBilingual(!showBilingual),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.translate,
              size: 18,
              color: showBilingual
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white38,
            ),
            const SizedBox(width: 12),
            Text(
              '双语歌词',
              style: TextStyle(
                color: showBilingual ? Colors.white : Colors.white38,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 歌词页左下角小徽章（LRC / 译）：统一描边样式，
  /// 开关态只用字色与描边色表达（不做填充按钮，避免与整页 UI 割裂）
  Widget _lyricBadge(String label, {bool active = true, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: active ? Colors.white : Colors.white24),
            // 圆角豁免：徽章沿用 1.x 小圆角
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white38,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adjBtn(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 22, color: Colors.white70),
        onPressed: onTap,
      ),
    );
  }
}

/// 歌词行（§4.3 景深衰减 + 两段式跳播预览）：
/// 字号/字重/透明度按与当前行的距离分级衰减，越远越淡越小；当前行加大加粗
/// 并带双层下投影，像悬浮在背景之上。切换由 AnimatedDefaultTextStyle 平滑过渡。
class _LyricRowTile extends StatelessWidget {
  const _LyricRowTile({
    required this.text,
    required this.translation,
    required this.distance,
    required this.onTap,
    required this.onPreviewTap,
    this.onDoubleTap,
    this.previewTime,
  });

  final String text;
  final String? translation;

  /// 与当前播放行的距离，0 即当前行
  final int distance;
  final VoidCallback onTap;
  final VoidCallback onPreviewTap;

  /// 双击歌词行 = 切换双语翻译
  final VoidCallback? onDoubleTap;

  /// 非 null 表示该行处于待跳播预览态，值为该行时间戳（秒）
  final double? previewTime;

  /// 景深分级：(字号, 字重, 透明度)
  (double, FontWeight, double) get _depth => switch (distance) {
    0 => (22.0, FontWeight.w700, 1.0),
    1 => (18.0, FontWeight.w600, 0.72),
    2 => (16.0, FontWeight.w400, 0.45),
    _ => (15.0, FontWeight.w400, 0.28),
  };

  @override
  Widget build(BuildContext context) {
    final (size, weight, alpha) = _depth;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 预览态左右对称留出胶囊宽度：长句先省略号，不会钻到胶囊底下
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: previewTime != null ? 76 : 0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedDefaultTextStyle(
                  duration: MotionTokens.durationNormal,
                  curve: Curves.easeOut,
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: weight,
                    color: Colors.white.withValues(alpha: alpha),
                    // 双层下投影：当前行像悬浮在背景之上（立体感）
                    shadows: distance == 0
                        ? const [
                            Shadow(
                              offset: Offset(0, 2),
                              blurRadius: 4,
                              color: Color(0x80000000),
                            ),
                            Shadow(
                              offset: Offset(0, 5),
                              blurRadius: 12,
                              color: Color(0x59000000),
                            ),
                          ]
                        : const [],
                  ),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (translation != null)
                  Text(
                    translation!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(
                        alpha: distance == 0 ? 0.75 : alpha * 0.58,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (previewTime != null)
            Align(
              alignment: Alignment.centerRight,
              child: _previewChip(context),
            ),
        ],
      ),
    );
  }

  /// 待跳播胶囊「时间戳 + Play」。
  /// blur 传 0：列表行内绝不挂 BackdropFilter（§2.2 性能红线），
  /// 纯 tint + 语义描边已经够跳；GlassSurface 内置透明 Material，墨水正常。
  Widget _previewChip(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GlassSurface(
      radius: AppRadius.pill,
      blur: 0,
      tint: primary.withValues(alpha: 0.26),
      borderColor: primary.withValues(alpha: 0.65),
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onPreviewTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fmtLyricTime(previewTime!),
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
            const Icon(Icons.play_arrow, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
