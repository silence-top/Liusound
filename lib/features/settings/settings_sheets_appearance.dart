part of 'settings_screen.dart';

Future<void> _showGlassLevelPicker(BuildContext context, WidgetRef ref) {
  final current = ref.read(glassQualityProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
          child: Text('液态玻璃效果', style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final level in GlassLevel.values)
          ListTile(
            leading: level == current
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const SizedBox(width: 24),
            title: Text(
              level.label,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            onTap: () {
              ref.read(glassQualityProvider.notifier).setLevel(level);
              Navigator.of(context).pop();
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            0,
            AppSpacing.l,
            AppSpacing.m,
          ),
          child: Text(
            '只调节模糊强度；关闭可降低开销。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppTheme.textDimOf(context)),
          ),
        ),
      ],
    ),
    scrollable: true,
  );
}

/// 与内联预览共用控制器：拖动只更新内存，松手保存原有偏好键。
Future<void> _showGlassOpacitySheet(BuildContext context, WidgetRef ref) {
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.l),
          child: Text(
            '面板透明度',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        // 弹层始终演示面板；卡片关闭时仍可看见透明度的实际作用。
        const _PanelMaterialPreview(),
        const SizedBox(height: AppSpacing.l),
        const _GlassOpacityControl(),
      ],
    ),
    scrollable: true,
  );
}

class _GlassOpacityControl extends ConsumerWidget {
  const _GlassOpacityControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opacity = ref.watch(glassTintOpacityProvider);
    final percent = (opacity * 100).round();
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('面板透明度 · $percent%', style: textTheme.titleSmall),
        Semantics(
          label: '面板透明度，100% 为主题默认，数值越小越通透',
          child: Slider(
            value: opacity,
            min: GlassTintOpacityController.min,
            max: 1.0,
            divisions: 16,
            label: '$percent%',
            semanticFormatterCallback: (value) =>
                '${(value * 100).round()}%${value == 1 ? '，主题默认' : ''}',
            onChanged: (value) =>
                ref.read(glassTintOpacityProvider.notifier).preview(value),
            onChangeEnd: (_) =>
                ref.read(glassTintOpacityProvider.notifier).commit(),
          ),
        ),
        Text(
          '100% 为主题默认；数值越小越通透。松手保存。',
          style: textTheme.bodySmall?.copyWith(
            color: AppTheme.textDimOf(context),
          ),
        ),
      ],
    );
  }
}

/// 画布不是卡片容器；其上只放一个真实面板，使用 GlassContainer 同源参数。
class _PanelMaterialPreview extends ConsumerWidget {
  const _PanelMaterialPreview({this.showCard = true});

  final bool showCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = SkinTokens.of(context);
    final tint = imageBgAwareTint(ref, GlassTokens.tint(context));
    const inset = EdgeInsets.all(AppSpacing.l);
    final musicRow = Row(
      children: [
        Icon(
          Icons.album_outlined,
          color: theme.colorScheme.primary,
          size: AppSpacing.xxl,
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('一段好时光', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '音乐条 · 样式示意',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textDim,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Icon(
          Icons.play_circle_filled,
          color: theme.colorScheme.primary,
          size: AppSpacing.xxl,
        ),
      ],
    );
    return Semantics(
      image: true,
      label: showCard ? '当前主题、背景与透明度下的面板示意' : '关闭卡片后的音乐条示意',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.m),
          child: ColoredBox(
            color: tokens.shell,
            child: TickerMode(
              enabled: !MediaQuery.disableAnimationsOf(context),
              child: AmbientBackground(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.l,
                    vertical: AppSpacing.xxl,
                  ),
                  child: Align(
                    alignment: Alignment.center,
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: showCard
                          ? GlassSurface(
                              radius: AppRadius.l,
                              blur: GlassTokens.blurContainer,
                              tint: tint,
                              padding: inset,
                              child: musicRow,
                            )
                          : Padding(padding: inset, child: musicRow),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 唱片形态选择（§4.2：黑胶 / CD / 方形玻璃卡片 / 全屏模糊大图）
Future<void> _showCoverStylePicker(BuildContext context, WidgetRef ref) {
  final current = ref.read(coverStyleProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '唱片形态',
            style: TextStyle(
              color: AppTheme.textPrimaryOf(context),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final style in CoverStyle.values)
          ListTile(
            leading: Icon(style.icon, color: AppTheme.textDimOf(context)),
            trailing: style == current
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            title: Text(
              style.label,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 16,
              ),
            ),
            onTap: () {
              ref.read(coverStyleProvider.notifier).setStyle(style);
              Navigator.of(context).pop();
            },
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            '黑胶与 CD 随播放旋转，黑胶带唱针升降动画；'
            '方形卡片与全屏大图保持静态，模糊强度跟随液态玻璃档位',
            style: TextStyle(
              color: AppTheme.textFaintOf(context),
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 悬浮歌词开关：开启前校验悬浮窗权限，未授予则跳系统设置页
Future<void> _toggleFloatingLyrics(
  BuildContext context,
  WidgetRef ref,
  bool v,
) async {
  if (!v) {
    await ref.read(floatingLyricsProvider.notifier).setEnabled(false);
    return;
  }
  if (await FloatingLyrics.hasPermission()) {
    await ref.read(floatingLyricsProvider.notifier).setEnabled(true);
    return;
  }
  // 先记录用户意图；Android 设置页返回后由 permissionChanged 自动启用或回退。
  await ref.read(floatingLyricsProvider.notifier).setEnabled(true);
  showToast('授权后将自动启用悬浮歌词');
  await FloatingLyrics.requestPermission();
}

/// 主题图库直接展开；只有缩略图描绘面板，不嵌套真实卡片。
class _SkinPickerTile extends ConsumerWidget {
  const _SkinPickerTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(appSkinProvider);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('主题', style: textTheme.titleMedium),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '决定页面底色与面板材质，自定义背景优先。',
          style: textTheme.bodySmall?.copyWith(
            color: AppTheme.textDimOf(context),
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        _SkinPreviewGrid(
          current: skin,
          onSelect: (s) => ref.read(appSkinProvider.notifier).set(s),
        ),
      ],
    );
  }
}

class _SkinPreviewGrid extends StatelessWidget {
  const _SkinPreviewGrid({required this.current, required this.onSelect});

  final AppSkin current;
  final ValueChanged<AppSkin> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.m;
        // 手机默认双列；宽屏增列，极窄窗口保留可读的单列回退。
        final columns = constraints.maxWidth < 280
            ? 1
            : (constraints.maxWidth / 220).floor().clamp(2, 4);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final skin in AppSkin.values)
              SizedBox(
                width: width,
                child: _SkinPreviewCard(
                  skin: skin,
                  selected: skin == current,
                  onTap: () => onSelect(skin),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SkinPreviewCard extends StatefulWidget {
  const _SkinPreviewCard({
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  final AppSkin skin;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SkinPreviewCard> createState() => _SkinPreviewCardState();
}

class _SkinPreviewCardState extends State<_SkinPreviewCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 当前主题必须读取动态 token：系统莫奈、封面取色都不能用静态色板代替。
    final tokens = widget.selected
        ? SkinTokens.of(context)
        : SkinTokens.forSkin(widget.skin);
    final accent = theme.colorScheme.primary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(AppRadius.l);
    final description = switch (widget.skin) {
      AppSkin.liquidGlass => '镜面高光 · 通透材质',
      AppSkin.deepSpace => '深蓝夜色 · 霓虹微光',
      AppSkin.minimal => '暖炭纸纹 · 简洁实色',
      AppSkin.materialYou => widget.selected ? '系统色板 · 当前效果' : '系统取色 · 色板示意',
      AppSkin.sunset => '暖橙玫瑰 · 落日柔光',
      AppSkin.forest => '暖绿纸质 · 林间微光',
      AppSkin.terminal => '磷光绿字 · 直角线条',
      AppSkin.albumTint => widget.selected ? '封面色板 · 当前效果' : '随封面取色 · 色板示意',
    };
    return Semantics(
      button: true,
      selected: widget.selected,
      inMutuallyExclusiveGroup: true,
      label: '${widget.skin.label}，$description',
      onTap: widget.onTap,
      child: Material(
        color: tokens.background,
        animationDuration: reduceMotion
            ? Duration.zero
            : MotionTokens.durationFast,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: _focused
                ? tokens.textPrimary
                : widget.selected
                ? accent
                : tokens.borderHairline,
            width: _focused || widget.selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 5 / 3,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _SkinThumbnailPainter(tokens, accent),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            widget.skin.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.selected) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Icon(
                            Icons.check_circle,
                            color: accent,
                            size: AppSpacing.xl,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 墨水位于 CustomPaint 上方，hover / focus / press 不会被缩略图遮住。
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  excludeFromSemantics: true,
                  onTap: widget.onTap,
                  onFocusChange: (value) => setState(() => _focused = value),
                  hoverColor: accent.withValues(alpha: 0.08),
                  focusColor: accent.withValues(alpha: 0.14),
                  highlightColor: accent.withValues(alpha: 0.16),
                  splashColor: accent.withValues(alpha: 0.12),
                  splashFactory: reduceMotion ? NoSplash.splashFactory : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 统一页面骨架：标题笔画、专辑封面、歌曲行与底部播放条。没有真实嵌套卡片。
class _SkinThumbnailPainter extends CustomPainter {
  const _SkinThumbnailPainter(this.tokens, this.accent);

  final SkinTokens tokens;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 240, size.height / 144);
    const bounds = Rect.fromLTWH(0, 0, 240, 144);
    final radius = Radius.circular(AppRadius.s * tokens.radiusScale);
    canvas.clipRRect(RRect.fromRectAndRadius(bounds, radius));
    canvas.drawRect(bounds, Paint()..color = tokens.shell);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tokens.tintLight, tokens.glow, tokens.background],
        ).createShader(bounds),
    );

    void block(Rect rect, Color color, {double? corner}) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          corner == null ? radius : Radius.circular(corner),
        ),
        Paint()..color = color,
      );
    }

    void stroke(
      double x,
      double y,
      double width,
      Color color, {
      double height = 3,
    }) {
      block(Rect.fromLTWH(x, y, width, height), color, corner: height / 2);
    }

    stroke(14, 12, 76, tokens.textPrimary, height: 5);
    stroke(14, 22, 46, tokens.textDim);
    canvas.drawCircle(const Offset(218, 18), 7, Paint()..color = accent);

    for (var index = 0; index < 3; index++) {
      final x = 14.0 + index * 73;
      final cover = Rect.fromLTWH(x, 36, 66, 44);
      canvas.drawRRect(
        RRect.fromRectAndRadius(cover, radius),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(accent, tokens.textDim, index / 3)!,
              tokens.surface,
            ],
          ).createShader(cover),
      );
      canvas.drawCircle(
        cover.center,
        15,
        Paint()
          ..color = tokens.textPrimary.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(cover.center, 3, Paint()..color = tokens.tintLight);
      stroke(x, 86, 41, tokens.textDim);
    }

    block(const Rect.fromLTWH(14, 98, 12, 12), tokens.surface);
    stroke(33, 99, 87, tokens.textPrimary);
    stroke(33, 106, 53, tokens.textDim, height: 2);
    stroke(197, 103, 23, tokens.textDim, height: 2);

    final bar = RRect.fromRectAndRadius(
      const Rect.fromLTWH(8, 118, 224, 22),
      radius,
    );
    canvas.drawRRect(bar, Paint()..color = tokens.surface);
    canvas.drawRRect(
      bar,
      Paint()
        ..color = tokens.borderHairline
        ..style = PaintingStyle.stroke,
    );
    block(const Rect.fromLTWH(15, 123, 12, 12), accent);
    stroke(33, 124, 58, tokens.textPrimary);
    stroke(33, 131, 35, tokens.textDim, height: 2);
    canvas.drawCircle(const Offset(216, 129), 7, Paint()..color = accent);
    canvas.drawPath(
      Path()
        ..moveTo(214, 125)
        ..lineTo(220, 129)
        ..lineTo(214, 133)
        ..close(),
      Paint()..color = tokens.background,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SkinThumbnailPainter oldDelegate) =>
      oldDelegate.tokens != tokens || oldDelegate.accent != accent;
}

/// 从语义色中挑选对比度更高的前景，不随当前主题文本色盲目使用浅色勾选。
Color _accentCheckColor(Color swatch, ColorScheme scheme) {
  final luminance = swatch.computeLuminance();
  double contrast(Color foreground) {
    final other = foreground.computeLuminance();
    return luminance > other
        ? (luminance + 0.05) / (other + 0.05)
        : (other + 0.05) / (luminance + 0.05);
  }

  return contrast(scheme.onSurface) > contrast(scheme.surface)
      ? scheme.onSurface
      : scheme.surface;
}
