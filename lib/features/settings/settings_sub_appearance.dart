part of 'settings_screen.dart';

class _AppearanceSettingsPage extends ConsumerWidget {
  const _AppearanceSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glassLevel = ref.watch(glassQualityProvider);
    final accent = ref.watch(appAccentProvider);
    final cardsOn = ref.watch(cardDisplayProvider);
    final tintOpacity = ref.watch(glassTintOpacityProvider);
    final bgConfig = ref.watch(backgroundProvider);
    final skin = ref.watch(appSkinProvider);
    final textTheme = Theme.of(context).textTheme;
    final followsSystemAccent =
        skin == AppSkin.materialYou && !ref.watch(accentExplicitProvider);

    return AmbientScaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        foregroundColor: AppTheme.textPrimaryOf(context),
        title: const Text('外观设置'),
      ),
      bottomNavigationBar: const MiniPlayer(),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.l,
              AppSpacing.xs,
              AppSpacing.l,
              AppSpacing.xxxl + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _SkinPickerTile(),
                const SizedBox(height: AppSpacing.xl),
                _GroupCard(
                  title: '颜色与背景',
                  children: [
                    _ActionTile(
                      icon: Icons.palette_outlined,
                      title: '主题色',
                      subtitle:
                          '${followsSystemAccent ? '跟随系统（不可用时使用预设）' : accent.label} · 按钮与重点',
                      onTap: () => _showAccentPicker(context, ref),
                    ),
                    _divider,
                    _ActionTile(
                      icon: Icons.image_outlined,
                      title: '自定义背景',
                      subtitle: bgConfig.path != null
                          ? '已设置 · 优先于主题背景'
                          : '未设置 · 使用主题背景',
                      onTap: () => _showBackgroundSettings(context, ref),
                    ),
                  ],
                ),
                _GroupCard(
                  title: '面板与卡片',
                  children: [
                    _SwitchTile(
                      icon: Icons.dashboard_outlined,
                      title: '卡片展示',
                      subtitle: '只改变分组承载方式，不影响内容与背景',
                      value: cardsOn,
                      onChanged: (v) =>
                          ref.read(cardDisplayProvider.notifier).setEnabled(v),
                    ),
                    _divider,
                    _ActionTile(
                      icon: Icons.opacity,
                      title: '面板透明度',
                      subtitle: '${(tintOpacity * 100).round()}% · 点击在弹层中调节',
                      onTap: () => _showGlassOpacitySheet(context),
                    ),
                    if (skin == AppSkin.liquidGlass) ...[
                      _divider,
                      _ActionTile(
                        icon: Icons.auto_awesome,
                        title: '液态玻璃效果',
                        subtitle: '${glassLevel.label} · 调节模糊强度',
                        onTap: () => _showGlassLevelPicker(context, ref),
                      ),
                    ],
                  ],
                ),
                Semantics(
                  header: true,
                  child: Text('实时预览', style: textTheme.titleMedium),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  cardsOn ? '分组卡片示意 · 跟随当前主题与背景' : '弹层示意 · 关闭卡片不影响弹窗与菜单',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppTheme.textDimOf(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                _PanelMaterialPreview(showCard: cardsOn),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
