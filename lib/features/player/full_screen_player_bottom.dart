part of 'full_screen_player.dart';

// ---------- 底部固定区（歌曲信息 + 进度 + 控制行） ----------

class _BottomArea extends ConsumerWidget {
  const _BottomArea();

  /// 收藏/取消收藏：乐观更新当前歌曲（❤ 即时变色），失败回滚
  Future<void> _toggleStar(
    BuildContext context,
    WidgetRef ref,
    Song song,
  ) async {
    final newStarred = !song.starred;
    ref.read(currentSongProvider.notifier).state = song.copyWith(
      starred: newStarred,
    );
    final ok = await ref
        .read(serverAdapterProvider)
        ?.setStar(song.id, newStarred);
    if (ok != true) {
      ref.read(currentSongProvider.notifier).state = song;
      showToast('收藏操作失败', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    // 底部控制栏 tint 跟随封面主色（内容驱动取色）：与歌词区背景同一色系，
    // 半透明叠在模糊背景上，整页上下连成一体而不是固定深色两截；
    // 取色中沿用上一首，从未取到回退莫奈主色
    final barTint =
        albumAdaptiveTint(
          ref.watch(currentAlbumDominantProvider) ??
              Theme.of(context).colorScheme.primary,
        ) ??
        Colors.black.withValues(alpha: 0.55);

    // 播放页材质与皮肤解耦（钦定：播放页不与主题关联）：不用 GlassSurface
    // （非玻璃皮肤会换成表面色 + hairline 描边，控制区上沿出现一条横线），
    // 固定毛玻璃 + 封面取色 tint，任何皮肤下同一观感
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: GlassTokens.blurHeavy,
          sigmaY: GlassTokens.blurHeavy,
        ),
        child: Container(
          color: barTint,
          // 底部留白：SafeArea 吸掉系统导航条后仍再垫一档，
          // 控制行不贴屏幕下缘
          padding: const EdgeInsets.only(bottom: 24),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 8, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song?.title ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song != null
                                  ? '${song.artist} - ${song.album}'
                                  : '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: PopOnChange(
                          value: song?.starred ?? false,
                          child: Icon(
                            (song?.starred ?? false)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 22,
                            color: (song?.starred ?? false)
                                ? const Color(0xFFE57373)
                                : Colors.white,
                          ),
                        ),
                        onPressed: song == null
                            ? null
                            : () => _toggleStar(context, ref, song),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.more_vert,
                          size: 22,
                          color: Colors.white,
                        ),
                        onPressed: song == null
                            ? null
                            : () => showSongActionSheet(context, song),
                      ),
                    ],
                  ),
                ),
                const _ProgressSlider(),
                const _ControlsRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 进度条（拖动值写入 [sliderDragValueProvider] 联动歌词高亮，时间在下方两端）
class _ProgressSlider extends ConsumerWidget {
  const _ProgressSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;
    final buffered = ref.watch(bufferedPositionProvider).valueOrNull;
    final drag = ref.watch(sliderDragValueProvider);
    final maxMs = duration.inMilliseconds.toDouble();
    final value = (drag ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs <= 0 ? 1.0 : maxMs,
    );
    final bufferedMs = math
        .max(buffered?.inMilliseconds.toDouble() ?? 0, value)
        .clamp(0.0, maxMs <= 0 ? 1.0 : maxMs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          SliderTheme(
            data: const SliderThemeData(
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value,
              max: maxMs <= 0 ? 1 : maxMs,
              // 缓冲条：白色半透明副轨道，体现边放边加载的已缓冲区间
              secondaryTrackValue: bufferedMs,
              secondaryActiveColor: Colors.white38,
              activeColor: Colors.white,
              inactiveColor: const Color(0xFF444444),
              onChanged: (v) =>
                  ref.read(sliderDragValueProvider.notifier).state = v,
              onChangeEnd: (v) {
                ref.read(sliderDragValueProvider.notifier).state = null;
                ref
                    .read(playerActionsProvider)
                    .seek(Duration(milliseconds: v.round()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatTime(
                    drag != null
                        ? Duration(milliseconds: drag.round())
                        : position,
                  ),
                  style: const TextStyle(fontSize: 12, color: Colors.white38),
                ),
                Text(
                  _formatTime(duration),
                  style: const TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 控制行：模式 / 上一首 / 大播放键 / 下一首 / 队列
class _ControlsRow extends ConsumerWidget {
  const _ControlsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const _ModeButton(),
          IconButton(
            tooltip: '上一首',
            iconSize: 28,
            color: Colors.white,
            icon: const Icon(Icons.skip_previous),
            onPressed: () => ref.read(playerActionsProvider).playPrevious(),
          ),
          const _PlayButton(),
          IconButton(
            tooltip: '下一首',
            iconSize: 28,
            color: Colors.white,
            icon: const Icon(Icons.skip_next),
            onPressed: () => ref.read(playerActionsProvider).playNext(),
          ),
          IconButton(
            tooltip: '播放队列',
            iconSize: 24,
            color: Colors.white,
            icon: const Icon(Icons.queue_music),
            onPressed: () => showQueueModal(context),
          ),
        ],
      ),
    );
  }
}

/// 播放模式按钮（仅订阅 playMode，点击在 顺序→随机→单曲循环 间切换）
class _ModeButton extends ConsumerWidget {
  const _ModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(playModeProvider);
    final icon = switch (mode) {
      PlayMode.order => Icons.repeat,
      PlayMode.shuffle => Icons.shuffle,
      PlayMode.repeatOne => Icons.repeat_one,
    };
    return IconButton(
      tooltip: switch (mode) {
        PlayMode.order => '顺序播放',
        PlayMode.shuffle => '随机播放',
        PlayMode.repeatOne => '单曲循环',
      },
      iconSize: 24,
      color: Colors.white,
      icon: PopOnChange(value: mode, child: Icon(icon)),
      onPressed: () => ref.read(playerActionsProvider).cyclePlayMode(),
    );
  }
}

/// 播放/暂停大按钮：56 圆形白描边 + 半透明底（对齐 1.x playPauseBtn）
/// 缓冲中（起播/卡顿加载）显示 spinner，给出「在加载」的可见反馈。
/// 播放中呼吸光环 + 点击扩散脉冲 + 图标 morph；省电模式光环静止（§8.5）。
class _PlayButton extends ConsumerStatefulWidget {
  const _PlayButton();

  @override
  ConsumerState<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends ConsumerState<_PlayButton>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _visible = false;
  bool _foreground = true;
  bool _reduceMotion = false;
  // 播放中呼吸光环；暂停/省电停转
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: MotionTokens.durationHalo,
  );

  // 点击扩散脉冲：一圈白光从按钮边缘扩散淡出
  late final AnimationController _ping = AnimationController(
    vsync: this,
    duration: MotionTokens.durationPulse,
  );

  void _syncHalo(bool isPlaying) {
    final run =
        isPlaying &&
        _visible &&
        _foreground &&
        !_reduceMotion &&
        !ref.read(powerSaveProvider);
    if (run && !_halo.isAnimating) {
      _halo.repeat();
    } else if (!run && _halo.isAnimating) {
      _halo.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncHalo(ref.read(isPlayingProvider).valueOrNull ?? false);
    if (_reduceMotion) _ping.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncHalo(ref.read(isPlayingProvider).valueOrNull ?? false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _halo.dispose();
    _ping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;
    final buffering = ref.watch(isBufferingProvider).valueOrNull ?? false;
    ref.listen(isPlayingProvider, (_, next) {
      _syncHalo(next.valueOrNull ?? false);
    });
    ref.listen(powerSaveProvider, (_, _) {
      _syncHalo(ref.read(isPlayingProvider).valueOrNull ?? false);
    });

    final icon = buffering
        ? const Padding(
            padding: EdgeInsets.all(15),
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          )
        : AnimatedSwitcher(
            duration: AppMotion.duration(context, MotionTokens.durationNormal),
            switchInCurve: MotionTokens.curveStandard,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(
                  begin: _reduceMotion ? 1 : 0.88,
                  end: 1,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              key: ValueKey(isPlaying),
              size: 36,
              color: Colors.white,
            ),
          );

    return Semantics(
      button: true,
      label: isPlaying ? '暂停' : '播放',
      child: InkResponse(
        radius: 44,
        onTap: () {
          if (!_reduceMotion && !ref.read(powerSaveProvider)) {
            _ping
              ..reset()
              ..forward();
          }
          ref.read(playerActionsProvider).toggle();
        },
        // 布局占位与原 56 按钮 + 水平 margin 一致，光环/脉冲 OverflowBox 外溢
        child: SizedBox(
          width: 72,
          height: 56,
          child: OverflowBox(
            maxWidth: 88,
            maxHeight: 88,
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 呼吸光环（播放中）
                AnimatedBuilder(
                  animation: _halo,
                  builder: (_, _) {
                    final t = 0.5 + 0.5 * math.sin(_halo.value * math.pi * 2);
                    return Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22 * t),
                          width: 1.5,
                        ),
                      ),
                    );
                  },
                ),
                // 点击扩散脉冲（一次性）
                AnimatedBuilder(
                  animation: _ping,
                  builder: (_, _) {
                    final t = Curves.easeOut.transform(_ping.value);
                    return Container(
                      width: 56 + 28 * t,
                      height: 56 + 28 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35 * (1 - t)),
                          width: 1.5,
                        ),
                      ),
                    );
                  },
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: ShapeDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    shape: CircleBorder(
                      side: BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  child: icon,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
