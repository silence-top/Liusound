part of 'settings_screen.dart';

class _EffectsSettingsPage extends ConsumerWidget {
  const _EffectsSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effects = ref.watch(audioEffectsProvider);
    final crossfade = ref.watch(crossfadeSecondsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('音效设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        children: [
          _GroupCard(
            children: [
              _ActionTile(
                icon: Icons.swap_horiz,
                title: '交叉淡入淡出',
                subtitle: crossfade == 0 ? '关闭' : '$crossfade 秒',
                onTap: () => showCrossfadePicker(context),
              ),
              _divider,
              _ActionTile(
                icon: Icons.equalizer,
                title: '均衡器 / 低音 / 空间',
                subtitle: effects.enabled ? '已开启' : '关闭',
                onTap: () => _showEffectsPanel(context),
              ),
              _divider,
              _ActionTile(
                icon: Icons.headphones,
                title: '耳机线控',
                subtitle: '自定义单击 / 双击 / 三击动作',
                onTap: () => _showHeadsetSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
