part of 'settings_screen.dart';

class _SystemSettingsPage extends ConsumerWidget {
  const _SystemSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(authControllerProvider).activeConfig;
    final floatingLyrics = ref.watch(floatingLyricsProvider);
    final powerSave = ref.watch(powerSaveProvider);
    final showIcons = ref.watch(settingsIconsProvider);
    final endText = ref.watch(listEndTextProvider);
    final appVersion = ref.watch(_packageInfoProvider).valueOrNull;

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
              title: const Text('系统设置'),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
          _GroupCard(
            title: '通用',
            children: [
              if (AppPlatform.isAndroid) ...[
                _SwitchTile(
                  icon: Icons.picture_in_picture_alt,
                  title: '悬浮歌词',
                  subtitle: floatingLyrics ? '小窗显示当前歌词行' : '关闭',
                  value: floatingLyrics,
                  onChanged: (v) => _toggleFloatingLyrics(context, ref, v),
                ),
                _divider,
              ],
              _SwitchTile(
                icon: Icons.battery_saver_outlined,
                title: '省电模式',
                subtitle: powerSave ? '已开启：关闭模糊、压缩动画' : '关闭',
                value: powerSave,
                onChanged: (v) =>
                    ref.read(powerSaveProvider.notifier).setEnabled(v),
              ),
              _divider,
              _SwitchTile(
                icon: Icons.view_list_outlined,
                title: '部分设置项图标',
                subtitle: showIcons ? '显示' : '隐藏',
                value: showIcons,
                onChanged: (v) =>
                    ref.read(settingsIconsProvider.notifier).setVisible(v),
              ),
              _divider,
              _ActionTile(
                icon: Icons.text_fields,
                title: '列表触底文案',
                subtitle: endText,
                onTap: () => _showEndTextEditor(context, ref),
              ),
            ],
          ),
          _GroupCard(
            title: '账户',
            children: [
              _ActionTile(
                icon: Icons.dns_outlined,
                title: config?.type.displayName ?? '未连接',
                subtitle: config != null
                    ? '${config.serverUrl} · ${config.username}'
                    : '点击添加服务器',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ServersScreen(),
                  ),
                ),
              ),
              _divider,
              _InfoTile(
                icon: Icons.info_outline,
                title: '版本',
                subtitle: appVersion == null
                    ? '读取中…'
                    : '${appVersion.version}+${appVersion.buildNumber}',
              ),
              _divider,
              _ActionTile(
                icon: Icons.logout,
                title: '退出登录',
                subtitle: '清除本地会话与播放状态',
                iconColor: AppTheme.heartRed,
                titleColor: AppTheme.heartRed,
                onTap: () => _confirmLogout(context, ref),
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
