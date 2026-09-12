part of 'settings_screen.dart';

class _PlayerStyleSettingsPage extends ConsumerWidget {
  const _PlayerStyleSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverStyle = ref.watch(coverStyleProvider);
    final barStyle = ref.watch(miniBarStyleProvider);
    final barOffset = ref.watch(miniBarOffsetProvider);

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
              title: const Text('播放器样式'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
          _GroupCard(
            children: [
              _ActionTile(
                icon: coverStyle.icon,
                title: '唱片形态',
                subtitle: coverStyle.label,
                onTap: () => _showCoverStylePicker(context, ref),
              ),
              _divider,
              _ActionTile(
                icon: Icons.tune,
                title: '迷你播放条样式',
                subtitle: barStyle.label,
                onTap: () => _showMiniBarStylePicker(context, ref),
              ),
              _divider,
              _ActionTile(
                icon: Icons.height,
                title: '迷你播放条高度偏移',
                subtitle: barOffset == 0
                    ? '默认'
                    : '${barOffset.toStringAsFixed(0)}px',
                onTap: () => _showMiniBarOffsetPicker(context, ref),
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
