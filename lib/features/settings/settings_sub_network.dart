part of 'settings_screen.dart';

class _NetworkSettingsPage extends ConsumerWidget {
  const _NetworkSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streaming = ref.watch(streamingSettingsProvider);
    final network = ref.watch(networkSettingsProvider);
    ref.watch(transcodeSupportProvider);

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
              title: const Text('网络设置'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
          _GroupCard(
            title: '音质',
            children: [
              _ActionTile(
                icon: Icons.music_note_outlined,
                title: '在线音质（Wi-Fi）',
                subtitle: streaming.wifiQuality.label,
                onTap: () => _showQualityPicker(context, ref, cellular: false),
              ),
              _divider,
              _ActionTile(
                icon: Icons.cell_tower,
                title: '在线音质（移动网络）',
                subtitle: streaming.cellularQuality.label,
                onTap: () => _showQualityPicker(context, ref, cellular: true),
              ),
              _divider,
              _ActionTile(
                icon: Icons.graphic_eq,
                title: '转码格式',
                subtitle: streaming.transcodeFormat.label,
                onTap: () => _showTranscodeFormatPicker(context, ref),
              ),
            ],
          ),
          _GroupCard(
            title: '连接',
            children: [
              _SwitchTile(
                icon: Icons.import_export,
                title: '移动网络传输',
                subtitle: streaming.cellularAllowed
                    ? '允许在移动网络下播放与下载'
                    : '关闭后仅 Wi-Fi 可播放',
                value: streaming.cellularAllowed,
                onChanged: (v) => ref
                    .read(streamingSettingsProvider.notifier)
                    .set(streaming.copyWith(cellularAllowed: v)),
              ),
              _divider,
              _ActionTile(
                icon: Icons.settings_ethernet,
                title: '网络设置',
                subtitle: network.proxy.isEmpty
                    ? '超时 ${network.timeoutSeconds}s · 直连'
                    : '超时 ${network.timeoutSeconds}s · 代理 ${network.proxy}',
                onTap: () => _showNetworkSettings(context, ref),
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
