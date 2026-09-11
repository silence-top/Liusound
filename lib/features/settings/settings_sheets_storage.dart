part of 'settings_screen.dart';

/// 缓存限额选择（附录·四）：2GB / 5GB / 10GB / 无限制
Future<void> _showCacheLimitPicker(BuildContext context, WidgetRef ref) {
  final settings = ref.read(cacheSettingsProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '缓存限额',
            style: TextStyle(
              color: AppTheme.textPrimaryOf(context),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final l in CacheLimit.values)
          ListTile(
            leading: l == settings.limit
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const SizedBox(width: 24),
            title: Text(
              l.label,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 16,
              ),
            ),
            onTap: () {
              ref
                  .read(cacheSettingsProvider.notifier)
                  .set(settings.copyWith(limit: l));
              Navigator.of(context).pop();
            },
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            '超出限额时从最旧的缓存文件开始清理',
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

/// 清理播放缓存（边听边存产生的音频缓存，不影响离线下载文件）
Future<void> _clearAudioCache(BuildContext context, WidgetRef ref) async {
  final confirmed = await glassDialog<bool>(
    context,
    title: '清理播放缓存',
    content: Text(
      '将删除边听边存产生的音频缓存文件，离线下载不受影响。确定清理？',
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
        child: const Text('清理'),
      ),
    ],
  );
  if (confirmed != true) return;
  await AudioCache.clear();
  ref.invalidate(audioCacheSizeProvider);
  showToast('播放缓存已清理');
}

/// 在线音质分档选择（附录·四）：Wi-Fi 与移动网络独立配置。
/// 服务端转码能力探测不通过时只放行无损（如 Navidrome 未装 ffmpeg）
Future<void> _showQualityPicker(
  BuildContext context,
  WidgetRef ref, {
  required bool cellular,
}) {
  final settings = ref.read(streamingSettingsProvider);
  final current = cellular ? settings.cellularQuality : settings.wifiQuality;
  return glassBottomSheet<void>(
    context,
    // 探测结果异步到达，用 Consumer 订阅让转码档从灰到亮/被移除
    Consumer(
      builder: (context, sheetRef, _) {
        final support = sheetRef.watch(transcodeSupportProvider);
        final transcodeOk = support.value ?? true;
        final probing = support.isLoading;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                cellular ? '在线音质（移动网络）' : '在线音质（Wi-Fi）',
                style: TextStyle(
                  color: AppTheme.textPrimaryOf(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final q in StreamQuality.values)
              if (transcodeOk || q == StreamQuality.lossless)
                ListTile(
                  leading: q == current
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : const SizedBox(width: 24),
                  title: Text(
                    q.label,
                    style: TextStyle(
                      color: AppTheme.textPrimaryOf(context).withValues(
                        alpha: probing && q != StreamQuality.lossless
                            ? 0.4
                            : 1.0,
                      ),
                      fontSize: 16,
                    ),
                  ),
                  trailing: probing && q != StreamQuality.lossless
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: probing && q != StreamQuality.lossless
                      ? null
                      : () {
                          sheetRef
                              .read(streamingSettingsProvider.notifier)
                              .set(
                                cellular
                                    ? settings.copyWith(cellularQuality: q)
                                    : settings.copyWith(wifiQuality: q),
                              );
                          Navigator.of(context).pop();
                        },
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                probing
                    ? '正在检测服务端转码能力…'
                    : transcodeOk
                    ? '无损播放原始文件；其余档位由服务端转码（需后端支持），'
                          '可显著降低流量与加载等待'
                    : '当前服务器不支持服务端转码（如未安装 ffmpeg），仅可无损播放原始文件',
                style: TextStyle(
                  color: AppTheme.textFaintOf(context),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// 转码格式选择（附录·四）：MP3 兼容性最好，OPUS 同码率下音质更佳
Future<void> _showTranscodeFormatPicker(BuildContext context, WidgetRef ref) {
  final settings = ref.read(streamingSettingsProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '转码格式',
            style: TextStyle(
              color: AppTheme.textPrimaryOf(context),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final f in TranscodeFormat.values)
          ListTile(
            leading: f == settings.transcodeFormat
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const SizedBox(width: 24),
            title: Text(
              f.label,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 16,
              ),
            ),
            onTap: () {
              ref
                  .read(streamingSettingsProvider.notifier)
                  .set(settings.copyWith(transcodeFormat: f));
              Navigator.of(context).pop();
            },
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            '仅在选择非无损音质档位时生效；OPUS 需要服务端转码器支持',
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

/// 网络设置（附录·一）：超时 / 代理 / 证书校验 / hosts 映射。
/// 表单做成 StatefulWidget 自持控制器，弹窗退场动画期间不会撞 dispose
class _NetworkSettingsForm extends StatefulWidget {
  const _NetworkSettingsForm({required this.initial, required this.onSave});

  final NetworkSettings initial;
  final void Function(NetworkSettings) onSave;

  @override
  State<_NetworkSettingsForm> createState() => _NetworkSettingsFormState();
}

class _NetworkSettingsFormState extends State<_NetworkSettingsForm> {
  late final TextEditingController _proxy = TextEditingController(
    text: widget.initial.proxy,
  );
  late final TextEditingController _hosts = TextEditingController(
    text: widget.initial.hostOverrides,
  );
  late bool _verify = widget.initial.verifyCertificates;
  late int _timeout = widget.initial.timeoutSeconds;

  @override
  void dispose() {
    _proxy.dispose();
    _hosts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '网络设置',
            style: TextStyle(
              color: AppTheme.textPrimaryOf(context),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          '请求超时（$_timeout 秒）',
          style: TextStyle(color: AppTheme.textDimOf(context), fontSize: 13),
        ),
        Slider(
          value: _timeout.toDouble(),
          min: 5,
          max: 60,
          divisions: 11,
          label: '$_timeout',
          activeColor: Theme.of(context).colorScheme.primary,
          onChanged: (v) => setState(() => _timeout = v.round()),
        ),
        TextField(
          controller: _proxy,
          style: TextStyle(
            color: AppTheme.textPrimaryOf(context),
            fontSize: 14,
          ),
          decoration: InputDecoration(
            labelText: '代理地址（如 127.0.0.1:7890）',
            labelStyle: TextStyle(
              color: AppTheme.textFaintOf(context),
              fontSize: 13,
            ),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            'HTTPS 证书校验',
            style: TextStyle(
              color: AppTheme.textPrimaryOf(context),
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            '自签名内网服务器可关闭',
            style: TextStyle(
              color: AppTheme.textFaintOf(context),
              fontSize: 12,
            ),
          ),
          value: _verify,
          activeThumbColor: Theme.of(context).colorScheme.primary,
          onChanged: (v) => setState(() => _verify = v),
        ),
        TextField(
          controller: _hosts,
          style: TextStyle(
            color: AppTheme.textPrimaryOf(context),
            fontSize: 14,
          ),
          decoration: InputDecoration(
            labelText: 'hosts 映射（域名=IP，分号分隔）',
            labelStyle: TextStyle(
              color: AppTheme.textFaintOf(context),
              fontSize: 13,
            ),
            border: OutlineInputBorder(),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            '仅 HTTP 直连完整生效；HTTPS 握手 SNI 使用映射 IP，'
            '需配合关闭证书校验',
            style: TextStyle(
              color: AppTheme.textFaintOf(context),
              fontSize: 12,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  widget.onSave(
                    NetworkSettings(
                      timeoutSeconds: _timeout,
                      proxy: _proxy.text.trim(),
                      verifyCertificates: _verify,
                      hostOverrides: _hosts.text.trim(),
                    ),
                  );
                  Navigator.of(context).pop();
                },
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _showNetworkSettings(BuildContext context, WidgetRef ref) {
  final initial = ref.read(networkSettingsProvider);
  return glassBottomSheet<void>(
    context,
    _NetworkSettingsForm(
      initial: initial,
      onSave: (s) {
        showToast('网络设置已更新，切换服务器后生效');
        ref.read(networkSettingsProvider.notifier).set(s);
      },
    ),
  );
}
