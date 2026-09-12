part of 'settings_screen.dart';

class _AppearanceSettingsPage extends ConsumerWidget {
  const _AppearanceSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glassLevel = ref.watch(glassQualityProvider);
    final tintOpacity = ref.watch(glassTintOpacityProvider);
    final accent = ref.watch(appAccentProvider);
    final cardsOn = ref.watch(cardDisplayProvider);
    final bgConfig = ref.watch(backgroundProvider);
    final skin = ref.watch(appSkinProvider);

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 56,
              backgroundColor: Colors.transparent,
              foregroundColor: AppTheme.textPrimaryOf(context),
              title: const Text('外观设置'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
          _GroupCard(
            title: '主题',
            children: [
              const _SkinPickerTile(),
              _divider,
              _ActionTile(
                icon: Icons.palette_outlined,
                title: '主题色',
                subtitle: accent.label,
                onTap: () => _showAccentPicker(context, ref),
              ),
              _divider,
              _ActionTile(
                icon: Icons.image_outlined,
                title: '自定义背景',
                subtitle: bgConfig.path != null ? '已设置' : '未设置',
                onTap: () => _showBackgroundSettings(context, ref),
              ),
            ],
          ),
          _GroupCard(
            title: '卡片',
            children: [
              _SwitchTile(
                icon: Icons.dashboard_outlined,
                title: '卡片展示',
                subtitle: '开启后内容用卡片呈现，关闭则封面与列表裸排',
                value: cardsOn,
                onChanged: (v) =>
                    ref.read(cardDisplayProvider.notifier).setEnabled(v),
              ),
              if (skin == AppSkin.liquidGlass) ...[
                _divider,
                _ActionTile(
                  icon: Icons.auto_awesome,
                  title: '液态玻璃效果',
                  subtitle: glassLevel.label,
                  onTap: () => _showGlassLevelPicker(context, ref),
                ),
              ],
              _divider,
              _ActionTile(
                icon: Icons.opacity_outlined,
                title: '卡片透明度',
                subtitle: '${(tintOpacity * 100).round()}%',
                onTap: () => _showGlassOpacitySheet(context, ref),
              ),
            ],
          ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
