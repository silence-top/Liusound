part of 'full_screen_player.dart';

// ---------- Tab 2：歌曲（大封面，对标 1.x renderCurrentSong） ----------

class _NowPlayingTab extends ConsumerStatefulWidget {
  const _NowPlayingTab();

  @override
  ConsumerState<_NowPlayingTab> createState() => _NowPlayingTabState();
}

class _NowPlayingTabState extends ConsumerState<_NowPlayingTab>
    with
        AutomaticKeepAliveClientMixin,
        TickerProviderStateMixin,
        WidgetsBindingObserver {
  // 控制器不随封面或形态重建，暂停后从原角度继续。
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  late final AnimationController _arm = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: MotionTokens.durationHalo,
  );

  @override
  bool get wantKeepAlive => true;

  StreamSubscription<bool>? _playingSub;
  Animation<double>? _tabPosition;
  int _tabIndex = 1;
  bool _playing = false;
  bool _dependenciesReady = false;
  bool _foreground = true;
  bool _tickerEnabled = false;
  bool _reduceMotion = false;
  bool _routeVisible = true;
  bool _tabVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _playing = ref.read(audioPlayerProvider).playing;
    // initState 不读取 MediaQuery / TickerMode；依赖就绪后才启动动画。
    ref.listenManual(coverStyleProvider, (_, _) => _syncAnimations());
    ref.listenManual(powerSaveProvider, (_, _) => _syncAnimations());
    ref.listenManual(currentSongProvider, (_, _) => _syncAnimations());
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _routeVisible = ModalRoute.isCurrentOf(context) ?? true;
    // TabBarView 会保活相邻页面；不能仅依赖路由或 TickerMode。
    final tab = context.findAncestorWidgetOfExactType<_TabZoom>();
    if (_tabPosition != tab?.position) {
      _tabPosition?.removeListener(_onTabPositionChanged);
      _tabPosition = tab?.position;
      _tabPosition?.addListener(_onTabPositionChanged);
    }
    _tabIndex = tab?.index ?? 1;
    _tabVisible = _isTabVisible;
    _dependenciesReady = true;
    _syncAnimations();
  }

  bool get _isTabVisible =>
      _tabPosition == null || (_tabPosition!.value - _tabIndex).abs() < 1;

  void _onTabPositionChanged() {
    final visible = _isTabVisible;
    if (_tabVisible == visible) return;
    _tabVisible = visible;
    _syncAnimations();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncAnimations();
  }

  void _syncAnimations() {
    if (!_dependenciesReady || !mounted) return;
    final style = ref.read(coverStyleProvider);
    final animate =
        _foreground &&
        _tickerEnabled &&
        _routeVisible &&
        _tabVisible &&
        !_reduceMotion &&
        !ref.read(powerSaveProvider) &&
        ref.read(currentSongProvider) != null;
    final run = animate && _playing && style.spins;
    if (run) {
      if (!_spin.isAnimating) _spin.repeat();
      if (!_glow.isAnimating) _glow.repeat();
    } else {
      _spin.stop();
      _glow.stop();
    }
    final target = _playing ? 1.0 : 0.0;
    if (!animate || style != CoverStyle.vinyl) {
      _arm.stop();
      if (_arm.value != target) _arm.value = target;
    } else if (_playing) {
      if (_arm.value != 1 && _arm.status != AnimationStatus.forward) {
        _arm.animateTo(1, curve: Curves.easeInOutCubic);
      }
    } else if (_arm.value != 0 && _arm.status != AnimationStatus.reverse) {
      _arm.animateBack(0, curve: Curves.easeInOutCubic);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabPosition?.removeListener(_onTabPositionChanged);
    _playingSub?.cancel();
    _spin.dispose();
    _arm.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    final style = ref.watch(coverStyleProvider);
    final quality = ref.watch(currentQualityProvider);
    final still =
        ref.watch(powerSaveProvider) ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    // 取色仅用于盘面细环和低亮光晕，文字与材质不绑定皮肤。
    final glowColor =
        ref.watch(currentAlbumDominantProvider) ?? _RecordTokens.accent;

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
                _coverBlock(
                  song.albumId,
                  style,
                  song.localCoverPath,
                  glowColor,
                  still,
                ),
                const SizedBox(height: AppSpacing.l),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppText.h2.copyWith(
                      color: _RecordTokens.textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppText.aux.copyWith(
                      color: _RecordTokens.textSecondary,
                      height: 1.4,
                    ),
                  ),
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
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: _RecordTokens.qualityBorder),
                    ),
                    child: Text(
                      quality.label,
                      style: AppText.caption.copyWith(
                        letterSpacing: 0.5,
                        color: _RecordTokens.textSecondary,
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
  Widget _coverBlock(
    String albumId,
    CoverStyle style,
    String? localCover,
    Color glowColor,
    bool still,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final extent = math.min(
        _RecordTokens.stageSize,
        math.max(0.0, constraints.maxWidth - AppSpacing.xl),
      );
      final cover = switch (style) {
        CoverStyle.vinyl => _GlowWrap(
          glow: _glow,
          color: glowColor,
          child: _VinylDisc(
            albumId: albumId,
            spin: _spin,
            arm: _arm,
            accent: glowColor,
            localCover: localCover,
          ),
        ),
        CoverStyle.cd => _GlowWrap(
          glow: _glow,
          color: glowColor,
          child: _CdDisc(
            albumId: albumId,
            spin: _spin,
            accent: glowColor,
            localCover: localCover,
          ),
        ),
        CoverStyle.square || CoverStyle.fullBlur => _SquareCover(
          albumId: albumId,
          localCover: localCover,
        ),
      };
      final child = KeyedSubtree(
        // 仅形态参与 key；切专辑不重置盘体与旋转相位。
        key: ValueKey(style),
        child: Center(child: cover),
      );
      return Center(
        child: SizedBox.square(
          dimension: extent,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox.square(
              dimension: _RecordTokens.stageSize,
              child: GestureDetector(
                onDoubleTap: () {
                  final song = ref.read(currentSongProvider);
                  if (song != null) _toggleStar(song);
                },
                child: still
                    ? child
                    : AnimatedSwitcher(
                        duration: MotionTokens.durationCoverFade,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          alignment: Alignment.center,
                          children: [...previous, ?current],
                        ),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.97,
                              end: 1,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: child,
                      ),
              ),
            ),
          ),
        ),
      );
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
    if (ok != true) {
      ref.read(currentSongProvider.notifier).state = song;
      showToast('收藏操作失败', error: true);
      return;
    }
    maybeAutoDownload(ref.read);
  }
}

/// 播放器专用材质，不读取 AppSkin / SkinTokens；封面主色仅作点缀。
abstract final class _RecordTokens {
  static const double discSize = 280;
  static const double stageSize = 328;
  static const double vinylLabel = 110;
  static const double cdLabel = 124;
  static const double cdHubRadius = 28;
  static const double cdHoleRadius = 10;
  static const double grooveStep = 1.15;
  static const double rimWidth = 0.8;
  static const double spindleSize = 9;
  static const Size armSize = Size(112, 126);

  static const ink = Color(0xFF090B0D);
  static const vinyl = Color(0xFF1C2024);
  static const groove = Color(0xFF707B85);
  static const silver = Color(0xFFCBD3D9);
  static const steel = Color(0xFF8997A6);
  static const light = Color(0xFFF4F7FA);
  static const prismBlue = Color(0xFFA9C9D0);
  static const prismViolet = Color(0xFFC7BFD2);
  static const prismGold = Color(0xFFD8D0B7);
  static const accent = Color(0xFFA7C5D8);
  static const textPrimary = Color(0xFFF7F8FA);
  static const textSecondary = Color(0xFFD1D7DF);
  static const qualityBorder = Color(0x4DF4F7FA);
  static const shadow = Color(0x66000000);
  static const transparent = Color(0x00F4F7FA);

  static const vinylSurface = RadialGradient(
    colors: [vinyl, ink, vinyl, ink],
    stops: [0, 0.44, 0.82, 1],
  );
  static const cdSurface = SweepGradient(
    transform: GradientRotation(-math.pi / 4),
    colors: [
      steel,
      silver,
      light,
      prismBlue,
      steel,
      silver,
      light,
      prismViolet,
      prismGold,
      steel,
    ],
    stops: [0, 0.12, 0.20, 0.25, 0.43, 0.55, 0.69, 0.75, 0.82, 1],
  );
  static const metal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [steel, light, silver, steel],
    stops: [0, 0.28, 0.48, 1],
  );
}

const double _discSize = _RecordTokens.discSize;

/// 黑胶的盘纹与圆形标签转动，斜向光源、轴心与唱针固定在舞台上。
class _VinylDisc extends StatelessWidget {
  const _VinylDisc({
    required this.albumId,
    required this.spin,
    required this.arm,
    required this.accent,
    this.localCover,
  });

  final String albumId;
  final Animation<double> spin;
  final Animation<double> arm;
  final Color accent;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _discSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _RecordSurfacePainter()),
            ),
          ),
          RotationTransition(
            turns: spin,
            child: RepaintBoundary(
              child: SizedBox.square(
                dimension: _discSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(painter: _RecordGroovesPainter()),
                      ),
                    ),
                    _RecordLabel(
                      albumId: albumId,
                      localCover: localCover,
                      size: _RecordTokens.vinylLabel,
                      accent: accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _RecordLightPainter()),
              ),
            ),
          ),
          Container(
            width: _RecordTokens.spindleSize,
            height: _RecordTokens.spindleSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _RecordTokens.metal,
              border: Border.all(color: _RecordTokens.ink, width: 1.5),
            ),
          ),
          Positioned(right: 0, top: 0, child: _Tonearm(arm: arm)),
        ],
      ),
    );
  }
}

/// CD 的金属镀层反射固定，只有刻纹与标签旋转；轴套真实透出背景。
class _CdDisc extends StatelessWidget {
  const _CdDisc({
    required this.albumId,
    required this.spin,
    required this.accent,
    this.localCover,
  });

  final String albumId;
  final Animation<double> spin;
  final Color accent;
  final String? localCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _discSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _RecordSurfacePainter(cd: true)),
            ),
          ),
          RotationTransition(
            turns: spin,
            child: RepaintBoundary(
              child: SizedBox.square(
                dimension: _discSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _RecordGroovesPainter(cd: true),
                        ),
                      ),
                    ),
                    ClipPath(
                      clipper: const _RecordHoleClipper(
                        _RecordTokens.cdHubRadius,
                      ),
                      child: _RecordLabel(
                        albumId: albumId,
                        localCover: localCover,
                        size: _RecordTokens.cdLabel,
                        accent: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _RecordLightPainter(cd: true)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordLabel extends StatelessWidget {
  const _RecordLabel({
    required this.albumId,
    required this.size,
    required this.accent,
    this.localCover,
  });

  final String albumId;
  final double size;
  final Color accent;
  final String? localCover;

  @override
  Widget build(BuildContext context) => Container(
    width: size + 6,
    height: size + 6,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: _RecordTokens.ink,
      border: Border.all(color: accent.withValues(alpha: 0.8)),
    ),
    child: _fadeCover(albumId, size, size / 2, localCover),
  );
}

Path _recordAnnulus(Offset center, double outer, double inner) => Path()
  ..fillType = PathFillType.evenOdd
  ..addOval(Rect.fromCircle(center: center, radius: outer))
  ..addOval(Rect.fromCircle(center: center, radius: inner));

class _RecordHoleClipper extends CustomClipper<Path> {
  const _RecordHoleClipper(this.radius);
  final double radius;

  @override
  Path getClip(Size size) =>
      _recordAnnulus(size.center(Offset.zero), size.shortestSide / 2, radius);

  @override
  bool shouldReclip(_RecordHoleClipper oldClipper) =>
      oldClipper.radius != radius;
}

class _RecordSurfacePainter extends CustomPainter {
  const _RecordSurfacePainter({this.cd = false});
  final bool cd;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final surface = _recordAnnulus(
      center,
      radius,
      cd ? _RecordTokens.cdHubRadius : 0,
    );
    canvas.drawShadow(surface, _RecordTokens.shadow, 7, true);
    canvas.drawPath(
      surface,
      Paint()
        ..shader = (cd ? _RecordTokens.cdSurface : _RecordTokens.vinylSurface)
            .createShader(bounds),
    );
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _RecordTokens.rimWidth
      ..color = _RecordTokens.light.withValues(alpha: cd ? 0.65 : 0.22);
    canvas.drawCircle(center, radius - 0.8, rim);
    canvas.drawCircle(
      center,
      radius - 3,
      rim..color = _RecordTokens.ink.withValues(alpha: cd ? 0.24 : 0.8),
    );
  }

  @override
  bool shouldRepaint(_RecordSurfacePainter oldDelegate) => oldDelegate.cd != cd;
}

/// 一次绘制所有细密沟槽；缓存后只变换图层，不在每个 tick 重新画圆。
class _RecordGroovesPainter extends CustomPainter {
  const _RecordGroovesPainter({this.cd = false});
  final bool cd;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - 5;
    final inner =
        (cd ? _RecordTokens.cdLabel : _RecordTokens.vinylLabel) / 2 + 7;
    final paint = Paint()..style = PaintingStyle.stroke;
    var index = 0;
    for (double r = outer; r > inner; r -= _RecordTokens.grooveStep) {
      final band = index++ % 7 == 0;
      paint
        ..strokeWidth = band ? 0.65 : 0.35
        ..color = (cd ? _RecordTokens.ink : _RecordTokens.groove).withValues(
          alpha: cd ? (band ? 0.09 : 0.04) : (band ? 0.38 : 0.20),
        );
      canvas.drawCircle(center, r, paint);
    }
    canvas.drawCircle(
      center,
      inner - 2,
      paint
        ..strokeWidth = 0.7
        ..color = _RecordTokens.light.withValues(alpha: cd ? 0.25 : 0.12),
    );
  }

  @override
  bool shouldRepaint(_RecordGroovesPainter oldDelegate) => oldDelegate.cd != cd;
}

/// 光源不随 RotationTransition 转动，避免把反射做成旋转的彩虹贴纸。
class _RecordLightPainter extends CustomPainter {
  const _RecordLightPainter({this.cd = false});
  final bool cd;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bounds = Offset.zero & size;
    final labelRadius =
        (cd ? _RecordTokens.cdLabel : _RecordTokens.vinylLabel) / 2 + 3;
    canvas.drawPath(
      _recordAnnulus(center, radius - 2, labelRadius),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _RecordTokens.transparent,
            _RecordTokens.light.withValues(alpha: cd ? 0.32 : 0.13),
            _RecordTokens.transparent,
            _RecordTokens.ink.withValues(alpha: cd ? 0.16 : 0.08),
            _RecordTokens.light.withValues(alpha: cd ? 0.18 : 0.07),
            _RecordTokens.transparent,
          ],
          stops: const [0.05, 0.27, 0.44, 0.57, 0.74, 0.95],
        ).createShader(bounds),
    );
    if (!cd) return;
    final hub = Rect.fromCircle(
      center: center,
      radius: _RecordTokens.cdHubRadius,
    );
    canvas.drawPath(
      _recordAnnulus(
        center,
        _RecordTokens.cdHubRadius,
        _RecordTokens.cdHoleRadius,
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _RecordTokens.light.withValues(alpha: 0.40),
            _RecordTokens.light.withValues(alpha: 0.07),
            _RecordTokens.light.withValues(alpha: 0.22),
          ],
        ).createShader(hub),
    );
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _RecordTokens.rimWidth
      ..color = _RecordTokens.light.withValues(alpha: 0.6);
    canvas.drawCircle(center, _RecordTokens.cdHubRadius - 0.5, edge);
    canvas.drawCircle(center, _RecordTokens.cdHoleRadius + 0.5, edge);
    canvas.drawCircle(
      center,
      _RecordTokens.cdHoleRadius + 2,
      edge..color = _RecordTokens.ink.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(_RecordLightPainter oldDelegate) => oldDelegate.cd != cd;
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

/// 固定尺寸内只淡换图片，不重置盘体、不缩放标签，也不追加扫光。
Widget _fadeCover(
  String albumId,
  double size,
  double radius, [
  String? localCover,
]) => Consumer(
  builder: (context, ref, _) {
    final still =
        ref.watch(powerSaveProvider) ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    final cover = CoverArt(
      key: ValueKey((albumId, localCover)),
      albumId: albumId,
      size: size,
      radius: 0,
      localCover: localCover,
    );
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: still
            ? cover
            : AnimatedSwitcher(
                duration: MotionTokens.durationCoverFade,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: cover,
              ),
      ),
    );
  },
);

/// 柔和的封面色反射限制在舞台边界内，不再向小屏边缘外溢。
class _GlowWrap extends StatelessWidget {
  const _GlowWrap({
    required this.glow,
    required this.color,
    required this.child,
  });

  final Animation<double> glow;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _RecordTokens.stageSize,
    child: Stack(
      alignment: Alignment.center,
      children: [
        RepaintBoundary(
          child: _DiscGlow(glow: glow, color: color),
        ),
        child,
      ],
    ),
  );
}

class _DiscGlow extends StatelessWidget {
  const _DiscGlow({required this.glow, required this.color});

  final Animation<double> glow;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: glow,
    builder: (_, _) {
      final t = 0.5 + 0.5 * math.sin(glow.value * math.pi * 2);
      return Container(
        width: _RecordTokens.stageSize,
        height: _RecordTokens.stageSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.055 + 0.03 * t),
              color.withValues(alpha: 0),
            ],
            stops: const [0.65, 0.84, 1],
          ),
        ),
      );
    },
  );
}

/// 唱针：支点固定在右上角，播放时平滑摆下贴住唱片，暂停时抬起。
class _Tonearm extends StatelessWidget {
  const _Tonearm({required this.arm});

  final Animation<double> arm;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: _RecordTokens.armSize,
        painter: _TonearmPainter(arm),
      ),
    ),
  );
}

class _TonearmPainter extends CustomPainter {
  _TonearmPainter(this.arm) : super(repaint: arm);

  /// 0 抬起 → 1 落在沟槽上；动画仅使这个小图层重绘。
  final Animation<double> arm;
  static const _raisedDeg = -12.0;
  static const _loweredDeg = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width - 18, 18);
    final angle =
        (_raisedDeg + (_loweredDeg - _raisedDeg) * arm.value) * math.pi / 180;
    canvas
      ..save()
      ..translate(pivot.dx, pivot.dy)
      ..rotate(angle);

    final rod = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 64)
      ..quadraticBezierTo(0, 70, -2, 77);
    canvas.drawPath(
      rod.shift(const Offset(2, 3)),
      Paint()
        ..color = _RecordTokens.shadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      rod,
      Paint()
        ..shader = _RecordTokens.metal.createShader(
          const Rect.fromLTWH(-3, 0, 6, 80),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      rod.shift(const Offset(-1, 0)),
      Paint()
        ..color = _RecordTokens.light.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );
    // 配重、哑黑唱头与金属压片，不叠加发光效果。
    final metal = Paint()
      ..shader = _RecordTokens.metal.createShader(
        const Rect.fromLTWH(-6, -15, 12, 12),
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-6, -15, 12, 11),
        const Radius.circular(2),
      ),
      metal,
    );
    final cartridge = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-8, 76, 12, 22),
      const Radius.circular(2),
    );
    canvas.drawRRect(cartridge, Paint()..color = _RecordTokens.ink);
    canvas.drawRRect(
      cartridge,
      Paint()
        ..color = _RecordTokens.steel
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.drawRect(
      const Rect.fromLTWH(-7, 77, 10, 5),
      Paint()
        ..shader = _RecordTokens.metal.createShader(
          const Rect.fromLTWH(-7, 77, 10, 5),
        ),
    );
    final detail = Paint()
      ..color = _RecordTokens.silver
      ..strokeWidth = 0.7;
    for (var y = 86.0; y <= 92; y += 3) {
      canvas.drawLine(Offset(-5, y), Offset(1, y), detail);
    }
    canvas.drawLine(
      const Offset(-2, 98),
      const Offset(-2, 103),
      detail..color = _RecordTokens.light,
    );
    canvas.restore();

    canvas.drawCircle(pivot, 12, Paint()..color = _RecordTokens.shadow);
    canvas.drawCircle(
      pivot,
      10,
      Paint()
        ..shader = _RecordTokens.metal.createShader(
          Rect.fromCircle(center: pivot, radius: 10),
        ),
    );
    canvas.drawCircle(pivot, 6, Paint()..color = _RecordTokens.vinyl);
    canvas.drawCircle(pivot, 3.5, Paint()..color = _RecordTokens.silver);
    canvas.drawLine(
      pivot - const Offset(2, 0),
      pivot + const Offset(2, 0),
      Paint()
        ..color = _RecordTokens.ink
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_TonearmPainter oldDelegate) => oldDelegate.arm != arm;
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
