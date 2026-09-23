part of 'full_screen_player.dart';

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
  late final AnimationController _spin = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _arm = AnimationController(
    vsync: this,
    duration: MotionTokens.durationSlow,
  );
  late final _rotationTicker = createTicker(_advanceRotation);
  Duration? _lastTick;
  double _speed = 0;
  double _targetSpeed = 0;
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
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    final player = ref.read(audioPlayerProvider);
    _playing =
        player.playing && player.processingState == ProcessingState.ready;
    ref.listenManual(coverStyleProvider, (_, _) => _syncAnimations());
    ref.listenManual(powerSaveProvider, (_, _) => _syncAnimations());
    ref.listenManual(currentSongProvider, (_, _) => _syncAnimations());
    _playingSub = player.playerStateStream
        .map((s) => s.playing && s.processingState == ProcessingState.ready)
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

  void _advanceRotation(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) return;
    final seconds = math.min((elapsed - previous).inMicroseconds / 1e6, 0.05);
    final before = _speed;
    final step = seconds / (MotionTokens.durationAmbient.inMilliseconds / 1000);
    _speed += (_targetSpeed - _speed).clamp(-step, step);
    final period = ref.read(coverStyleProvider) == CoverStyle.cd
        ? MotionTokens.durationCdTurn
        : MotionTokens.durationVinylTurn;
    // 积分转速而非重置角度，暂停/恢复和快速反向时保留盘面相位。
    _spin.value =
        (_spin.value +
            (before + _speed) *
                0.5 *
                seconds /
                (period.inMilliseconds / 1000)) %
        1;
    if (_speed == 0 && _targetSpeed == 0) {
      _rotationTicker.stop();
      _lastTick = null;
    }
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
    _targetSpeed = animate && _playing && style.spins ? 1 : 0;
    if (!animate || !style.spins) {
      _rotationTicker.stop();
      _lastTick = null;
      _speed = 0;
    } else if ((_targetSpeed > 0 || _speed > 0) && !_rotationTicker.isActive) {
      _lastTick = null;
      _rotationTicker.start();
    }
    final target = _playing ? 1.0 : 0.0;
    if (!animate || style != CoverStyle.vinyl) {
      _arm.value = target;
    } else if (_arm.value != target) {
      _arm.animateTo(target, curve: MotionTokens.curveEmphasized);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabPosition?.removeListener(_onTabPositionChanged);
    _playingSub?.cancel();
    _rotationTicker.dispose();
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
    final quality = ref.watch(currentQualityProvider)?.label;
    final accent =
        ref.watch(currentAlbumDominantProvider) ?? _RecordTokens.accent;
    final still =
        ref.watch(powerSaveProvider) ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    final caption = _TrackCaption(
      song: song,
      quality: quality,
      immersive: style == CoverStyle.fullBlur,
    );

    if (style == CoverStyle.fullBlur) {
      return _ImmersiveCover(
        song: song,
        caption: caption,
        onDoubleTap: () => _toggleStar(song),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = math
            .min(
              constraints.maxWidth - AppSpacing.xl,
              math.min(
                _RecordTokens.stageSize,
                math.max(
                  _RecordTokens.compactStage,
                  constraints.maxHeight * 0.68,
                ),
              ),
            )
            .clamp(0.0, _RecordTokens.stageSize);
        final cover = switch (style) {
          CoverStyle.vinyl => _VinylDisc(
            albumId: song.albumId,
            spin: _spin,
            arm: _arm,
            accent: accent,
            localCover: song.localCoverPath,
          ),
          CoverStyle.cd => _CdPresentation(
            albumId: song.albumId,
            spin: _spin,
            localCover: song.localCoverPath,
          ),
          CoverStyle.square => Center(
            child: _SquareCover(
              albumId: song.albumId,
              localCover: song.localCoverPath,
            ),
          ),
          CoverStyle.fullBlur => const SizedBox.shrink(),
        };
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onDoubleTap: () => _toggleStar(song),
                  child: SizedBox.square(
                    dimension: extent,
                    child: FittedBox(
                      child: SizedBox.square(
                        dimension: _RecordTokens.stageSize,
                        child: AnimatedSwitcher(
                          duration: still
                              ? Duration.zero
                              : MotionTokens.durationCoverFade,
                          switchInCurve: MotionTokens.curveStandard,
                          child: KeyedSubtree(
                            key: ValueKey(style),
                            child: cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.l),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: caption,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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

class _TrackCaption extends ConsumerWidget {
  const _TrackCaption({
    required this.song,
    required this.quality,
    required this.immersive,
  });

  final Song song;
  final String? quality;
  final bool immersive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final still =
        ref.watch(powerSaveProvider) || AppMotion.reduceMotion(context);
    final alignment = immersive
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    final textAlign = immersive ? TextAlign.start : TextAlign.center;
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignment,
        children: [
          AnimatedSwitcher(
            duration: still ? Duration.zero : MotionTokens.durationCoverFade,
            switchInCurve: MotionTokens.curveStandard,
            layoutBuilder: (current, previous) => Stack(
              alignment: immersive ? Alignment.centerLeft : Alignment.center,
              children: [
                for (final child in previous) ExcludeSemantics(child: child),
                ?current,
              ],
            ),
            child: Column(
              key: ValueKey((ref.watch(activeServerIdProvider), song.id)),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: alignment,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: textAlign,
                    style: AppText.h2.copyWith(
                      color: _RecordTokens.textPrimary,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: textAlign,
                  style: AppText.aux.copyWith(
                    color: _RecordTokens.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (quality != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              quality!,
              style: AppText.caption.copyWith(
                color: _RecordTokens.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

abstract final class _RecordTokens {
  static const double discSize = 280;
  static const double stageSize = 328;
  static const double compactStage = 196;
  static const double vinylLabel = 104;
  static const double cdSize = 250;
  static const double sleeveSize = 178;
  static const double cdHubRadius = 29;
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
  static const shadow = Color(0x66000000);
  static const transparent = Color(0x00F4F7FA);

  static const vinylSurface = RadialGradient(
    colors: [vinyl, ink, vinyl, ink],
    stops: [0, 0.44, 0.82, 1],
  );
  static const cdSurface = SweepGradient(
    transform: GradientRotation(-math.pi / 4),
    colors: [
      silver,
      light,
      prismBlue,
      silver,
      steel,
      silver,
      light,
      prismViolet,
      prismGold,
      silver,
    ],
    stops: [0, 0.14, 0.20, 0.27, 0.42, 0.51, 0.65, 0.71, 0.79, 1],
  );
  static const metal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [steel, light, silver, steel],
    stops: [0, 0.28, 0.48, 1],
  );
}

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
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _RecordTokens.stageSize,
    child: Stack(
      children: [
        Positioned(
          left: AppSpacing.s,
          top: AppSpacing.xl,
          child: SizedBox.square(
            dimension: _RecordTokens.discSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _VinylSurfacePainter()),
                  ),
                ),
                RotationTransition(
                  turns: spin,
                  child: RepaintBoundary(
                    child: SizedBox.square(
                      dimension: _RecordTokens.discSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Positioned.fill(
                            child: CustomPaint(painter: _VinylGroovesPainter()),
                          ),
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _RecordTokens.ink,
                              border: Border.all(
                                color: accent.withValues(alpha: 0.7),
                              ),
                            ),
                            child: _fadeCover(
                              albumId,
                              _RecordTokens.vinylLabel,
                              _RecordTokens.vinylLabel / 2,
                              localCover,
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
                      child: CustomPaint(painter: _VinylLightPainter()),
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
              ],
            ),
          ),
        ),
        Positioned(right: 0, top: 0, child: _Tonearm(arm: arm)),
      ],
    ),
  );
}

class _CdPresentation extends StatelessWidget {
  const _CdPresentation({
    required this.albumId,
    required this.spin,
    this.localCover,
  });

  final String albumId;
  final Animation<double> spin;
  final String? localCover;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _RecordTokens.stageSize,
    child: Stack(
      children: [
        Positioned(
          right: 0,
          top: AppSpacing.xl,
          child: SizedBox.square(
            dimension: _RecordTokens.cdSize,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _CompactDiscPainter()),
                  ),
                ),
                Positioned.fill(
                  child: RotationTransition(
                    turns: spin,
                    child: const RepaintBoundary(
                      child: CustomPaint(painter: _CdEtchingPainter()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.s,
          bottom: AppSpacing.xl,
          child: Container(
            decoration: BoxDecoration(
              color: _RecordTokens.silver,
              borderRadius: BorderRadius.circular(AppRadius.s),
              boxShadow: [
                BoxShadow(
                  color: _RecordTokens.shadow,
                  blurRadius: AppSpacing.l,
                  offset: const Offset(AppSpacing.s, AppSpacing.s),
                ),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.s),
              border: Border.all(
                color: _RecordTokens.light.withValues(alpha: 0.5),
              ),
            ),
            child: _fadeCover(
              albumId,
              _RecordTokens.sleeveSize,
              AppRadius.s,
              localCover,
            ),
          ),
        ),
      ],
    ),
  );
}

Path _recordAnnulus(Offset center, double outer, double inner) => Path()
  ..fillType = PathFillType.evenOdd
  ..addOval(Rect.fromCircle(center: center, radius: outer))
  ..addOval(Rect.fromCircle(center: center, radius: inner));

class _VinylSurfacePainter extends CustomPainter {
  const _VinylSurfacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final surface = Path()..addOval(bounds);
    canvas.drawShadow(surface, _RecordTokens.shadow, AppSpacing.s, true);
    canvas.drawPath(
      surface,
      Paint()..shader = _RecordTokens.vinylSurface.createShader(bounds),
    );
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _RecordTokens.rimWidth
      ..color = _RecordTokens.light.withValues(alpha: 0.24);
    canvas.drawCircle(center, radius - 1, rim);
    canvas.drawCircle(center, radius - 4, rim..color = _RecordTokens.ink);
  }

  @override
  bool shouldRepaint(_VinylSurfacePainter oldDelegate) => false;
}

class _VinylGroovesPainter extends CustomPainter {
  const _VinylGroovesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - 6;
    final inner = _RecordTokens.vinylLabel / 2 + 8;
    final paint = Paint()..style = PaintingStyle.stroke;
    var index = 0;
    for (double r = outer; r > inner; r -= _RecordTokens.grooveStep) {
      final band = index++ % 9 == 0;
      paint
        ..strokeWidth = band ? 0.7 : 0.35
        ..color = _RecordTokens.groove.withValues(alpha: band ? 0.42 : 0.20);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_VinylGroovesPainter oldDelegate) => false;
}

class _VinylLightPainter extends CustomPainter {
  const _VinylLightPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawPath(
      _recordAnnulus(
        center,
        size.shortestSide / 2 - 2,
        _RecordTokens.vinylLabel / 2 + 4,
      ),
      Paint()
        ..shader = SweepGradient(
          transform: const GradientRotation(-math.pi / 4),
          colors: [
            _RecordTokens.transparent,
            _RecordTokens.light.withValues(alpha: 0.16),
            _RecordTokens.transparent,
            _RecordTokens.transparent,
            _RecordTokens.light.withValues(alpha: 0.10),
            _RecordTokens.transparent,
          ],
          stops: const [0, 0.08, 0.19, 0.49, 0.60, 1],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_VinylLightPainter oldDelegate) => false;
}

class _CompactDiscPainter extends CustomPainter {
  const _CompactDiscPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final surface = _recordAnnulus(center, radius, _RecordTokens.cdHubRadius);
    canvas.drawShadow(surface, _RecordTokens.shadow, AppSpacing.s, true);
    canvas.drawPath(
      surface,
      Paint()..shader = _RecordTokens.cdSurface.createShader(bounds),
    );
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _RecordTokens.rimWidth
      ..color = _RecordTokens.light.withValues(alpha: 0.85);
    canvas.drawCircle(center, radius - 1, edge);
    canvas.drawCircle(
      center,
      radius - 4,
      edge..color = _RecordTokens.steel.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      center,
      radius - 7,
      edge..color = _RecordTokens.light.withValues(alpha: 0.5),
    );
    final hub = _recordAnnulus(
      center,
      _RecordTokens.cdHubRadius,
      _RecordTokens.cdHoleRadius,
    );
    canvas.drawPath(
      hub,
      Paint()
        ..shader = LinearGradient(
          colors: [
            _RecordTokens.light.withValues(alpha: 0.50),
            _RecordTokens.light.withValues(alpha: 0.10),
            _RecordTokens.light.withValues(alpha: 0.38),
          ],
        ).createShader(bounds),
    );
    canvas.drawCircle(center, _RecordTokens.cdHubRadius, edge);
    canvas.drawCircle(center, _RecordTokens.cdHoleRadius, edge);
    canvas.drawCircle(
      center,
      _RecordTokens.cdHubRadius + 5,
      edge..color = _RecordTokens.steel.withValues(alpha: 0.65),
    );
  }

  @override
  bool shouldRepaint(_CompactDiscPainter oldDelegate) => false;
}

class _CdEtchingPainter extends CustomPainter {
  const _CdEtchingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = _RecordTokens.steel.withValues(alpha: 0.7);
    final ring = Rect.fromCircle(
      center: center,
      radius: _RecordTokens.cdHubRadius + 10,
    );
    canvas.drawArc(ring, -math.pi / 2, math.pi / 3, false, paint);
    canvas.drawArc(ring, math.pi / 2, math.pi / 6, false, paint);
    canvas.drawCircle(
      center + const Offset(0, -_RecordTokens.cdHubRadius - 10),
      2,
      Paint()..color = _RecordTokens.light,
    );
  }

  @override
  bool shouldRepaint(_CdEtchingPainter oldDelegate) => false;
}

class _SquareCover extends ConsumerWidget {
  const _SquareCover({required this.albumId, this.localCover});

  final String albumId;
  final String? localCover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final powerSave = ref.watch(powerSaveProvider);
    return Container(
      width: _RecordTokens.discSize,
      height: _RecordTokens.discSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: const [
          BoxShadow(
            color: _RecordTokens.shadow,
            blurRadius: AppSpacing.xl,
            offset: Offset(0, AppSpacing.l),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: BackdropFilter(
          enabled: !powerSave,
          filter: ui.ImageFilter.blur(
            sigmaX: GlassTokens.blurContainer,
            sigmaY: GlassTokens.blurContainer,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _RecordTokens.light.withValues(alpha: 0.24),
                  _RecordTokens.light.withValues(alpha: 0.06),
                  _RecordTokens.light.withValues(alpha: 0.12),
                ],
              ),
              border: Border.all(
                color: _RecordTokens.light.withValues(alpha: 0.35),
              ),
            ),
            child: _fadeCover(
              albumId,
              _RecordTokens.discSize - AppSpacing.m * 2,
              AppRadius.m,
              localCover,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _fadeCover(
  String albumId,
  double size,
  double radius, [
  String? localCover,
]) => Consumer(
  builder: (context, ref, _) {
    final still =
        ref.watch(powerSaveProvider) ||
        AppMotion.reduceMotion(context) ||
        !TickerMode.valuesOf(context).enabled;
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: AnimatedSwitcher(
          duration: still ? Duration.zero : MotionTokens.durationCoverFade,
          switchInCurve: MotionTokens.curveStandard,
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: CoverArt(
            key: ValueKey((
              ref.watch(activeServerIdProvider),
              albumId,
              localCover,
            )),
            albumId: albumId,
            size: size,
            radius: 0,
            localCover: localCover,
          ),
        ),
      ),
    );
  },
);

class _ImmersiveCover extends StatelessWidget {
  const _ImmersiveCover({
    required this.song,
    required this.caption,
    required this.onDoubleTap,
  });

  final Song song;
  final Widget caption;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      onDoubleTap: onDoubleTap,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: _BlurredBackdrop(
                albumId: song.albumId,
                localCover: song.localCoverPath,
              ),
            ),
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _RecordTokens.light,
                  _RecordTokens.light,
                  _RecordTokens.transparent,
                ],
                stops: [0, 0.38, 0.90],
              ).createShader(rect),
              child: FittedBox(
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                child: _fadeCover(
                  song.albumId,
                  math.max(constraints.maxWidth, constraints.maxHeight),
                  0,
                  song.localCoverPath,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _RecordTokens.ink.withValues(alpha: 0.10),
                    _RecordTokens.ink.withValues(alpha: 0.04),
                    _RecordTokens.ink.withValues(alpha: 0.88),
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: caption,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BlurredBackdrop extends ConsumerWidget {
  const _BlurredBackdrop({required this.albumId, this.localCover});

  final String albumId;
  final String? localCover;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ImageFiltered(
    enabled: !ref.watch(powerSaveProvider),
    imageFilter: ui.ImageFilter.blur(
      sigmaX: GlassTokens.blurHeavy,
      sigmaY: GlassTokens.blurHeavy,
      tileMode: TileMode.clamp,
    ),
    child: FittedBox(
      fit: BoxFit.cover,
      child: _fadeCover(albumId, 100, 0, localCover),
    ),
  );
}

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
