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

Future<void> _showGlassOpacitySheet(BuildContext context) {
  return glassBottomSheet<void>(
    context,
    const Padding(
      padding: EdgeInsets.all(AppSpacing.s),
      child: _GlassOpacityControl(),
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
        const SizedBox(height: AppSpacing.xs),
        Text(
          '拖动滑杆，直接查看此弹层的透明效果。',
          style: textTheme.bodySmall?.copyWith(
            color: AppTheme.textDimOf(context),
          ),
        ),
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
        Row(
          children: [
            Expanded(child: Text('更通透', style: textTheme.bodySmall)),
            Expanded(
              child: Text(
                '主题默认',
                textAlign: TextAlign.end,
                style: textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        Text(
          '只调节底色，文字与图标不变淡；100% 保留主题原始效果，松手保存。\n'
          '影响分组卡片、通用弹窗、菜单、提示和播放页弹层；播放页弹层保留底色下限，避免背景干扰阅读。\n'
          '不影响页面背景、迷你播放条、播放器封面和底部控制栏；模糊强度单独调节。',
          style: textTheme.bodySmall?.copyWith(
            color: AppTheme.textDimOf(context),
          ),
        ),
      ],
    );
  }
}

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
              Text(
                showCard ? '我的音乐' : '操作面板',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                showCard ? '收藏的歌曲与本地音乐' : '弹窗与菜单仍可调节',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textDim,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Icon(Icons.chevron_right, color: tokens.textDim, size: AppSpacing.xxl),
      ],
    );
    return Semantics(
      image: true,
      label: showCard ? '当前主题、背景与透明度下的分组卡片示意' : '关闭卡片后的弹层示意',
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
                      child: GlassSurface(
                        radius: showCard
                            ? AppRadius.l
                            : GlassTokens.radiusSheet,
                        blur: showCard ? 0 : GlassTokens.blurHeavy,
                        tint: tint,
                        shadow: !showCard,
                        padding: inset,
                        child: musicRow,
                      ),
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
            '黑胶呈现沟槽与唱针，CD 搭配银色光盘与专辑封套；'
            '玻璃卡片装裱完整封面，全屏大图无边框铺开。省电模式下关闭旋转与模糊。',
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

/// 主题选择入口：设置行点击展开双列预览卡。
class _SkinPickerTile extends ConsumerStatefulWidget {
  const _SkinPickerTile();

  @override
  ConsumerState<_SkinPickerTile> createState() => _SkinPickerTileState();
}

class _SkinPickerTileState extends ConsumerState<_SkinPickerTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final skin = ref.watch(appSkinProvider);
    return Column(
      children: [
        _ActionTile(
          icon: Icons.style_outlined,
          title: '主题',
          subtitle: _open ? '点击收起预览' : skin.label,
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _SkinPreviewGrid(
              current: skin,
              onSelect: (s) => ref.read(appSkinProvider.notifier).set(s),
            ),
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
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in AppSkin.values)
              SizedBox(
                width: width,
                child: _SkinPreviewCard(
                  skin: s,
                  selected: s == current,
                  accent: accent,
                  onTap: () => onSelect(s),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 每主题一张迷你预览卡：底色 / 面板色 / 描边 / 发光 / 主题色点，用各主题
/// 自己的 token 绘制，切换后卡片内容即时反映新主题的实际观感。
class _SkinPreviewCard extends StatelessWidget {
  const _SkinPreviewCard({
    required this.skin,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final AppSkin skin;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = SkinTokens.forSkin(skin);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${skin.label}，${skin.desc}',
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        hoverColor: accent.withValues(alpha: 0.08),
        highlightColor: accent.withValues(alpha: 0.12),
        splashColor: accent.withValues(alpha: 0.12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : t.borderHairline,
              width: selected ? 2 : 1,
            ),
            boxShadow: t.glow.a == 0
                ? null
                : [BoxShadow(color: t.glow, blurRadius: 12, spreadRadius: -4)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 20,
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: t.borderHairline),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                skin.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? t.textPrimary : t.textDim,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              Text(
                skin.desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textFaint, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
