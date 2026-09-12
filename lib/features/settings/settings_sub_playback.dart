part of 'settings_screen.dart';

class _PlaybackSettingsPage extends ConsumerWidget {
  const _PlaybackSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(loopPlaybackProvider);
    final autoPlay = ref.watch(autoPlayProvider);
    final autoOpen = ref.watch(autoOpenPlayerProvider);
    final sleepRemain = ref.watch(sleepTimerProvider);
    final speed = ref.watch(playbackSpeedProvider);

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
              title: const Text('播放设置'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
          _GroupCard(
            children: [
              _SwitchTile(
                icon: Icons.repeat,
                title: '循环播放',
                subtitle: '关闭后播完整个队列即停止',
                value: loop,
                onChanged: (v) =>
                    ref.read(loopPlaybackProvider.notifier).state = v,
              ),
              _divider,
              _SwitchTile(
                icon: Icons.play_circle_outline,
                title: '启动后自动播放',
                subtitle: '打开应用时恢复上次播放进度并继续播放',
                value: autoPlay,
                onChanged: (v) => _setAutoPlay(ref, v),
              ),
              _divider,
              _SwitchTile(
                icon: Icons.open_in_new_off,
                title: '点歌自动打开播放页',
                subtitle: '关闭后点歌仅播放，不弹出全屏播放器',
                value: autoOpen,
                onChanged: (v) =>
                    ref.read(autoOpenPlayerProvider.notifier).set(v),
              ),
              _divider,
              _ActionTile(
                icon: Icons.timer_outlined,
                title: '定时停止播放',
                subtitle: sleepRemain != null
                    ? '剩余 ${_fmtRemain(sleepRemain)}'
                    : '未启用',
                onTap: () => showSleepTimerPicker(context),
              ),
              _divider,
              _ActionTile(
                icon: Icons.speed,
                title: '播放速度',
                subtitle: speed == 1.0 ? '正常' : '${speed.toStringAsFixed(2)}x',
                onTap: () => showSpeedPicker(context),
              ),
              _divider,
              const _VolumeTile(),
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
