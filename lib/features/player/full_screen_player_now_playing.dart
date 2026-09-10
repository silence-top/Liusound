part of 'full_screen_player.dart';

// ---------- Tab 2：歌曲（大封面，对标 1.x renderCurrentSong） ----------

class _NowPlayingTab extends ConsumerStatefulWidget {
  const _NowPlayingTab();

  @override
  ConsumerState<_NowPlayingTab> createState() => _NowPlayingTabState();
}

class _NowPlayingTabState extends ConsumerState<_NowPlayingTab>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  // 唱片匀速旋转（18s/圈）；暂停时停在当前位置
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  // 唱针升降（§4.2）：播放时平滑落下贴住唱片，暂停/切歌时抬起
  late final AnimationController _arm = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  bool get wantKeepAlive => true;

  StreamSubscription<bool>? _playingSub;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _playing = ref.read(audioPlayerProvider).playing;
    _syncAnimations();
    _playingSub = ref
        .read(audioPlayerProvider)
        .playerStateStream
        .map((s) => s.playing)
        .distinct()
        .listen((playing) {
          if (!mounted) return;
          _playing = playing;
          _syncAnimations();
        });
  }

  /// 只有会旋转的形态（黑胶 / CD）才让 _spin 持续 tick：
  /// 本 Tab 常驻存活，方形卡片与全屏大图没必要空转一个 18s 控制器
  void _syncAnimations() {
    final style = ref.read(coverStyleProvider);
    if (_playing && style.spins) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
    if (_playing) {
      _arm.forward();
    } else {
      _arm.reverse();
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _spin.dispose();
    _arm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    final style = ref.watch(coverStyleProvider);
    final quality = ref.watch(currentQualityProvider);
    ref.listen(coverStyleProvider, (_, _) => _syncAnimations());

    return Stack(
      children: [
        // 全屏模糊大图：模糊封面铺满 Tab，再压一层暗渐变保证文字可读
        if (style == CoverStyle.fullBlur) ...[
          Positioned.fill(
            child: _BlurredBackdrop(
              albumId: song.albumId,
              localCover: song.localCoverPath,
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x8C000000),
                    Color(0x40000000),
                    Color(0xB3000000),
                  ],
                ),
              ),
            ),
          ),
        ],
        Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _coverBlock(song.albumId, style, song.localCoverPath),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, color: Colors.white38),
                ),
                // 当前实际播放音质（含转码回退后的真实档；本地/离线不显示）
                if (quality != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      quality.label,
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.5,
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 四种唱片形态（§4.2）；方形卡片与全屏大图共用同一张静态玻璃卡。
  /// 双击封面 = 收藏/取消收藏（乐观更新，失败回滚，与底部爱心一致）
  Widget _coverBlock(String albumId, CoverStyle style, String? localCover) =>
      GestureDetector(
        onDoubleTap: () {
          final song = ref.read(currentSongProvider);
          if (song != null) _toggleStar(song);
        },
        child: switch (style) {
          CoverStyle.vinyl => _VinylDisc(
            albumId: albumId,
            spin: _spin,
            arm: _arm,
            localCover: localCover,
          ),
          CoverStyle.cd => _CdDisc(
            albumId: albumId,
            spin: _spin,
            localCover: localCover,
          ),
          CoverStyle.square || CoverStyle.fullBlur => _SquareCover(
            albumId: albumId,
            localCover: localCover,
          ),
        },
      );

  Future<void> _toggleStar(Song song) async {
    final newStarred = !song.starred;
    ref.read(currentSongProvider.notifier).state = song.copyWith(
      starred: newStarred,
    );
    final ok = await ref
        .read(serverAdapterProvider)
        ?.setStar(song.id, newStarred);
    if (ok != true && mounted) {
      ref.read(currentSongProvider.notifier).state = song;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收藏操作失败'), duration: Duration(seconds: 2)),
      );
      return;
    }
    maybeAutoDownload(ref.read);
  }
}

const double _discSize = 280;

/// 经典黑胶：外圈纹理 + 中央方形封面旋转，唱针挂在右上角不随盘转。
class _VinylDisc extends StatelessWidget {
  const _VinylDisc({
    required this.albumId,
    required this.spin,
    required this.arm,
    this.localCover,
  });

  final String albumId;
  final Animation<double> spin;
  final Animation<double> arm;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _discSize,
      height: _discSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: spin,
            builder: (_, child) =>
                Transform.rotate(angle: spin.value * math.pi * 2, child: child),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0xFF2A2A2A),
                        Color(0xFF161616),
                        Color(0xFF060606),
                      ],
                      stops: [0.0, 0.72, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                // 唱片纹路（两圈高光环）
                Container(
                  width: 224,
                  height: 224,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                Container(
                  width: 196,
                  height: 196,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  ),
                ),
                // 中央封面（黑胶圆孔位；切歌淡入过渡）
                _fadeCover(albumId, 120, 8, localCover),
              ],
            ),
          ),
          Positioned(right: 0, top: 2, child: _Tonearm(arm: arm)),
        ],
      ),
    );
  }
}

/// CD 唱片：斜向彩虹镀层 + 浅色内圈 + 封面作标签区 + 中心孔，随播放旋转。
class _CdDisc extends StatelessWidget {
  const _CdDisc({required this.albumId, required this.spin, this.localCover});

  final String albumId;
  final Animation<double> spin;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _discSize,
      height: _discSize,
      child: AnimatedBuilder(
        animation: spin,
        builder: (_, child) =>
            Transform.rotate(angle: spin.value * math.pi * 2, child: child),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Color(0xFFDDE2E8),
                    Color(0xFFB7C6DC),
                    Color(0xFFEAEFF6),
                    Color(0xFFD3C3E2),
                    Color(0xFFBFDAD6),
                    Color(0xFFDDE2E8),
                  ],
                  stops: [0.0, 0.18, 0.38, 0.58, 0.78, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            // 内圈镀层分隔
            Container(
              width: 188,
              height: 188,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEDEFF3),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
            // 标签区封面（radius 取半径裁成正圆）
            _fadeCover(albumId, 150, 75, localCover),
            // 中心孔
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0C0E12),
                border: Border.all(color: Colors.white24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 方形玻璃卡片：容器级模糊 + 受光描边，不旋转。
class _SquareCover extends StatelessWidget {
  const _SquareCover({required this.albumId, this.localCover});

  final String albumId;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _discSize,
      height: _discSize,
      child: GlassSurface(
        radius: AppRadius.xl,
        blur: GlassTokens.blurContainer,
        tint: GlassTokens.tint(context),
        gradientBorder: true,
        shadow: true,
        padding: const EdgeInsets.all(AppSpacing.m),
        child: _fadeCover(
          albumId,
          _discSize - AppSpacing.m * 2,
          AppRadius.l,
          localCover,
        ),
      ),
    );
  }
}

/// 切歌淡入过渡，三种形态共用
Widget _fadeCover(
  String albumId,
  double size,
  double radius, [
  String? localCover,
]) => AnimatedSwitcher(
  duration: MotionTokens.durationCoverFade,
  child: KeyedSubtree(
    key: ValueKey(albumId),
    child: CoverArt(
      albumId: albumId,
      size: size,
      radius: radius,
      localCover: localCover,
    ),
  ),
);

/// 唱针：支点固定在右上角，播放时平滑摆下贴住唱片，暂停时抬起。
class _Tonearm extends StatelessWidget {
  const _Tonearm({required this.arm});

  final Animation<double> arm;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: arm,
      builder: (_, _) => IgnorePointer(
        child: CustomPaint(
          size: const Size(112, 112),
          painter: _TonearmPainter(arm.value),
        ),
      ),
    );
  }
}

class _TonearmPainter extends CustomPainter {
  const _TonearmPainter(this.progress);

  /// 0 抬起（暂停，甩到盘缘外）→ 1 落下（播放，落在唱片纹路上）
  final double progress;

  static const _raisedDeg = -10.0;
  static const _loweredDeg = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width - 18, 18);
    final angle =
        (_raisedDeg + (_loweredDeg - _raisedDeg) * progress) * math.pi / 180;
    // 负 x 分量：唱针从右上支点向左下摆入盘面（progress 越大越靠里）
    final dir = Offset(-math.sin(angle), math.cos(angle));
    final tip = pivot + dir * (size.height - 26);

    // 臂杆：银色渐变，从支点连到唱头
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFF1F2F4), Color(0xFF9BA2AB)],
        ).createShader(Rect.fromPoints(pivot, tip))
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    // 唱头：跟着臂杆角度摆正，挂在针尖下方
    canvas
      ..save()
      ..translate(tip.dx, tip.dy)
      ..rotate(angle)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(0, 8), width: 12, height: 22),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF24272D),
      )
      ..restore();

    // 支点底座 + 高光
    canvas.drawCircle(pivot, 12, Paint()..color = const Color(0x66000000));
    canvas.drawCircle(
      pivot,
      8,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFF6F7F9), Color(0xFF868D96)],
        ).createShader(Rect.fromCircle(center: pivot, radius: 8)),
    );
  }

  @override
  bool shouldRepaint(_TonearmPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 全屏模糊大图形态的背景：封面放大铺满后高斯模糊。
/// 玻璃档位关闭时降级为不模糊的放大封面，守住低端设备的性能红线。
class _BlurredBackdrop extends StatelessWidget {
  const _BlurredBackdrop({required this.albumId, this.localCover});

  final String albumId;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    final image = FittedBox(
      fit: BoxFit.cover,
      // 模糊背景不需要高清源：小尺寸取源（命中 300 档），模糊后无差异
      child: CoverArt(
        albumId: albumId,
        size: 100,
        radius: 0,
        localCover: localCover,
      ),
    );
    return ClipRect(
      child: shouldUseBlur(context)
          ? ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: 46 * glassBlurScale(context),
                sigmaY: 46 * glassBlurScale(context),
              ),
              child: Opacity(opacity: 0.55, child: image),
            )
          : Opacity(opacity: 0.40, child: image),
    );
  }
}
