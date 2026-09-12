part of 'settings_screen.dart';

class _EffectsSettingsPage extends ConsumerWidget {
  const _EffectsSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effects = ref.watch(audioEffectsProvider);
    final crossfade = ref.watch(crossfadeSecondsProvider);
    final rgMode = ref.watch(replayGainModeProvider);

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: const MiniPlayer(),
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 56,
              backgroundColor: Colors.transparent,
              foregroundColor: AppTheme.textPrimaryOf(context),
              title: const Text('音效设置'),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                12,
                4,
                12,
                48 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
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
                        icon: Icons.volume_up,
                        title: '音量归一化 (ReplayGain)',
                        subtitle: switch (rgMode) {
                          ReplayGainMode.off => '关闭',
                          ReplayGainMode.track => '按曲目增益',
                          ReplayGainMode.album => '按专辑增益',
                        },
                        onTap: () {
                          final next =
                              ReplayGainMode.values[(rgMode.index + 1) %
                                  ReplayGainMode.values.length];
                          ref.read(replayGainModeProvider.notifier).state =
                              next;
                        },
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
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
