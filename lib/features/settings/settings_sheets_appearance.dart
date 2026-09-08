part of 'settings_screen.dart';

Future<void> _showGlassLevelPicker(BuildContext context, WidgetRef ref) {
  final current = ref.read(glassQualityProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '液态玻璃效果',
            style: TextStyle(
              color: AppTheme.textPrimaryOf(context),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
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
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 16,
              ),
            ),
            onTap: () {
              ref.read(glassQualityProvider.notifier).setLevel(level);
              Navigator.of(context).pop();
            },
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            '关闭在低端设备上更流畅；增强提高模糊强度，高配设备体验更佳',
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
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('授权后将自动启用悬浮歌词')));
  }
  await FloatingLyrics.requestPermission();
}

/// 主题选择：内联预览卡网格（P1 主题系统化）。
/// 不用玻璃底部弹层——选择后设置页立即切换主题，展开状态用于对比预览。
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
    return GestureDetector(
      onTap: onTap,
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
                color: t.textDim,
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
    );
  }
}

/// 音效面板（Android）：EQ 波段滑杆 + 预设曲线 + 低音/空间近似 + 参数剪贴板导入导出
