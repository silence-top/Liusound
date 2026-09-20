part of 'settings_screen.dart';

// ---------- 元数据插件管理 ----------

/// 设置主页入口副标题：展示当前生效的外部能力
String _pluginEntrySubtitle(WidgetRef ref) {
  if (!ref.watch(metadataEnabledProvider)) return '已停用';
  final caps = ref.watch(pluginCapsProvider);
  final labels = <String>[
    if (caps.avatar) '头像',
    if (caps.similar) '相似歌曲',
    if (caps.bio) '歌手简介',
  ];
  return labels.isEmpty ? '无可用插件' : labels.join(' · ');
}

/// 元数据插件（外部歌手头像 / 相似歌曲 / 歌手简介）：
/// 官方模板一键启停，第三方插件导入 JSON 描述即可用（声明式，无代码）。
class _PluginsSettingsPage extends ConsumerWidget {
  const _PluginsSettingsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final global = ref.watch(metadataEnabledProvider);
    final registry = ref.watch(pluginRegistryProvider).valueOrNull ?? const [];
    final keys = ref.watch(pluginKeysProvider).valueOrNull ?? const {};
    final official = registry.where((p) => p.official).toList();
    final imported = registry.where((p) => !p.official).toList();

    return AmbientScaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        foregroundColor: AppTheme.textPrimaryOf(context),
        title: const Text('元数据插件'),
      ),
      bottomNavigationBar: const MiniPlayer(),
      body: CustomScrollView(
        slivers: [
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
                  title: '总开关',
                  children: [
                    _SwitchTile(
                      icon: Icons.extension_outlined,
                      title: '外部元数据插件',
                      subtitle: global
                          ? '向已启用的插件服务发送歌手名，获取头像/相似/简介'
                          : '已停用：不发起任何外部请求',
                      value: global,
                      onChanged: (v) =>
                          ref.read(metadataEnabledProvider.notifier).set(v),
                    ),
                  ],
                ),
                _GroupCard(
                  title: '官方插件',
                  children: [
                    for (final (index, plugin) in official.indexed) ...[
                      if (index > 0) _divider,
                      _SwitchTile(
                        icon: Icons.public_outlined,
                        title: plugin.descriptor.name,
                        subtitle: _pluginCapabilityLabel(plugin.descriptor),
                        value: plugin.enabled,
                        onChanged: global
                            ? (v) {
                                _setPluginEnabled(context, ref, plugin, v);
                              }
                            : null,
                      ),
                      if (plugin.descriptor.auth != null) ...[
                        _divider,
                        _ActionTile(
                          icon: Icons.key_outlined,
                          title: plugin.descriptor.auth!.label,
                          subtitle:
                              (keys[plugin.descriptor.id] ?? '')
                                  .trim()
                                  .isNotEmpty
                              ? '已配置 · 点此修改'
                              : plugin.descriptor.auth!.hint,
                          onTap: () =>
                              _showPluginKeyEditor(context, ref, plugin),
                        ),
                      ],
                    ],
                    if (official.isEmpty)
                      const _InfoTile(
                        icon: Icons.info_outline,
                        title: '官方插件不可用',
                        subtitle: '插件资源加载失败',
                      ),
                  ],
                ),
                if (imported.isNotEmpty)
                  _GroupCard(
                    title: '已导入插件',
                    children: [
                      for (final (index, plugin) in imported.indexed) ...[
                        if (index > 0) _divider,
                        _ImportedPluginTile(
                          plugin: plugin,
                          hasKey: (keys[plugin.descriptor.id] ?? '')
                              .trim()
                              .isNotEmpty,
                          onToggle: global
                              ? (v) {
                                  _setPluginEnabled(context, ref, plugin, v);
                                }
                              : null,
                          onEditKey: plugin.descriptor.auth != null
                              ? () => _showPluginKeyEditor(context, ref, plugin)
                              : null,
                          onDelete: () =>
                              _removeImportedPlugin(context, ref, plugin),
                        ),
                      ],
                    ],
                  ),
                _GroupCard(
                  title: '导入',
                  children: [
                    _ActionTile(
                      icon: Icons.file_upload_outlined,
                      title: '导入插件描述',
                      subtitle: '选择声明式 JSON 描述文件（https 端点）',
                      onTap: () => _importPluginDescriptor(context, ref),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  child: Text(
                    '插件为纯声明式描述（HTTP 端点 + 提取路径），不含可执行代码；'
                    '所有端点强制 https。取数结果按歌手名缓存，清理图片缓存不影响文案缓存。',
                    style: TextStyle(
                      color: AppTheme.textFaintOf(context),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportedPluginTile extends StatelessWidget {
  const _ImportedPluginTile({
    required this.plugin,
    required this.hasKey,
    required this.onToggle,
    required this.onEditKey,
    required this.onDelete,
  });

  final InstalledPlugin plugin;
  final bool hasKey;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onEditKey;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.extension_outlined,
        color: AppTheme.textDimOf(context),
      ),
      title: Text(
        plugin.descriptor.name,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Text(_pluginCapabilityLabel(plugin.descriptor)),
      onTap: onEditKey,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: plugin.enabled,
            activeThumbColor: Theme.of(context).colorScheme.primary,
            onChanged: onToggle,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 22,
              color: AppTheme.textFaintOf(context),
            ),
            tooltip: '删除插件',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

String _pluginCapabilityLabel(PluginDescriptor d) {
  final parts = <String>[
    if (d.avatar != null) '头像',
    if (d.similar != null) '相似歌曲',
    if (d.bio != null) '简介',
  ];
  final auth = d.auth;
  if (auth != null) parts.add(auth.required ? '需 key' : '可选 key');
  return parts.isEmpty ? '未声明能力' : parts.join(' · ');
}

Future<void> _setPluginEnabled(
  BuildContext context,
  WidgetRef ref,
  InstalledPlugin plugin,
  bool enabled,
) async {
  final store = ref.read(metadataStoreProvider);
  final state = await store.readState();
  if (plugin.official) {
    final disabled = Set<String>.of(state.officialDisabled);
    enabled
        ? disabled.remove(plugin.descriptor.id)
        : disabled.add(plugin.descriptor.id);
    await store.writeState(
      PluginState(
        officialDisabled: disabled,
        imported: state.imported,
        importedDisabled: state.importedDisabled,
      ),
    );
  } else {
    final disabled = Set<String>.of(state.importedDisabled);
    enabled
        ? disabled.remove(plugin.descriptor.id)
        : disabled.add(plugin.descriptor.id);
    await store.writeState(
      PluginState(
        officialDisabled: state.officialDisabled,
        imported: state.imported,
        importedDisabled: disabled,
      ),
    );
  }
  ref.invalidate(pluginRegistryProvider);
  ref.invalidate(pluginKeysProvider);
}

Future<void> _removeImportedPlugin(
  BuildContext context,
  WidgetRef ref,
  InstalledPlugin plugin,
) async {
  final confirmed = await glassDialog<bool>(
    context,
    title: '删除插件',
    content: Text(
      '将移除「${plugin.descriptor.name}」及其已保存的 key，确定？',
      style: TextStyle(
        color: AppTheme.textDimOf(context),
        fontSize: 14,
        height: 1.5,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('确定'),
      ),
    ],
  );
  if (confirmed != true) return;
  final store = ref.read(metadataStoreProvider);
  final state = await store.readState();
  await store.writeState(
    PluginState(
      officialDisabled: state.officialDisabled,
      imported: [
        for (final d in state.imported)
          if (d.id != plugin.descriptor.id) d,
      ],
      importedDisabled: state.importedDisabled,
    ),
  );
  await store.writeKey(plugin.descriptor.id, '');
  ref.invalidate(pluginRegistryProvider);
  ref.invalidate(pluginKeysProvider);
  showToast('已删除插件');
}

Future<void> _importPluginDescriptor(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return;
    final raw = await localFs.readTextFile(path);
    if (raw == null) {
      showToast('文件读取失败', error: true);
      return;
    }
    final descriptor = PluginDescriptor.parse(raw);
    final store = ref.read(metadataStoreProvider);
    final state = await store.readState();
    final installedIds = {
      ...state.imported.map((d) => d.id),
      ...?ref
          .read(pluginRegistryProvider)
          .valueOrNull
          ?.map((p) => p.descriptor.id),
    };
    if (installedIds.contains(descriptor.id)) {
      showToast('插件 id「${descriptor.id}」已存在', error: true);
      return;
    }
    await store.writeState(
      PluginState(
        officialDisabled: state.officialDisabled,
        imported: [...state.imported, descriptor],
        importedDisabled: state.importedDisabled,
      ),
    );
    ref.invalidate(pluginRegistryProvider);
    ref.invalidate(pluginKeysProvider);
    showToast('已导入插件：${descriptor.name}');
  } on FormatException catch (e) {
    showToast(e.message, error: true);
  } catch (_) {
    showToast('导入失败', error: true);
  }
}

Future<void> _showPluginKeyEditor(
  BuildContext context,
  WidgetRef ref,
  InstalledPlugin plugin,
) async {
  final auth = plugin.descriptor.auth;
  if (auth == null) return;
  final store = ref.read(metadataStoreProvider);
  final savedKey = await store.readKey(plugin.descriptor.id);
  if (!context.mounted) return;
  final controller = TextEditingController(text: savedKey ?? '');
  final saved = await glassDialog<bool>(
    context,
    title: auth.label,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (auth.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              auth.hint,
              style: TextStyle(
                color: AppTheme.textDimOf(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('保存'),
      ),
    ],
  );
  if (saved != true) return;
  await store.writeKey(plugin.descriptor.id, controller.text);
  ref.invalidate(pluginKeysProvider);
  showToast('key 已保存');
}
