part of 'settings_screen.dart';

Future<void> _showEffectsPanel(BuildContext context) {
  String freqLabel(int hz) => hz >= 1000
      ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz'
      : '$hz Hz';

  return glassBottomSheet<void>(
    context,
    Consumer(
      builder: (context, ref, _) {
        final st = ref.watch(audioEffectsProvider);
        final notifier = ref.read(audioEffectsProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '音效',
                style: TextStyle(
                  color: AppTheme.textPrimaryOf(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!Platform.isAndroid)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  '音效仅在 Android 设备上可用',
                  style: TextStyle(
                    color: AppTheme.textDimOf(context),
                    fontSize: 13,
                  ),
                ),
              )
            else if (st.bands.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  '未获取到设备音效通道，播放一首歌曲后重试',
                  style: TextStyle(
                    color: AppTheme.textDimOf(context),
                    fontSize: 13,
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(
                  children: [
                    Text(
                      '均衡器',
                      style: TextStyle(color: AppTheme.textPrimaryOf(context)),
                    ),
                    const Spacer(),
                    Switch(value: st.enabled, onChanged: notifier.setEnabled),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in eqPresets.keys)
                      GestureDetector(
                        onTap: () => notifier.applyPreset(name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: SkinTokens.of(context).borderHairline,
                            ),
                          ),
                          child: Text(
                            name,
                            style: TextStyle(
                              color: AppTheme.textPrimaryOf(context),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (final band in st.bands.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 68,
                        child: Text(
                          freqLabel(band.$2.centerHz),
                          style: TextStyle(
                            color: AppTheme.textDimOf(context),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          min: band.$2.minMb.toDouble(),
                          max: band.$2.maxMb.toDouble(),
                          divisions: ((band.$2.maxMb - band.$2.minMb) / 50)
                              .round(),
                          value: (st.gains[band.$1] ?? 0)
                              .clamp(band.$2.minMb, band.$2.maxMb)
                              .toDouble(),
                          onChanged: (v) =>
                              notifier.setBand(band.$1, v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${((st.gains[band.$1] ?? 0) / 100).toStringAsFixed(1)} dB',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: AppTheme.textDimOf(context),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(
                        '低音增强',
                        style: TextStyle(
                          color: AppTheme.textDimOf(context),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 1000,
                        divisions: 20,
                        value: st.bass.toDouble(),
                        onChanged: (v) => notifier.setBass(v.round()),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(
                        '空间音效',
                        style: TextStyle(
                          color: AppTheme.textDimOf(context),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 1000,
                        divisions: 20,
                        value: st.virtualizer.toDouble(),
                        onChanged: (v) => notifier.setVirtualizer(v.round()),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: jsonEncode(st.gains)),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('EQ 曲线已复制到剪贴板'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.ios_share, size: 16),
                      label: const Text('导出曲线'),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () async {
                        final raw = await Clipboard.getData('text/plain');
                        final text = raw?.text;
                        if (text == null || text.isEmpty) return;
                        try {
                          final map = jsonDecode(text) as Map<String, dynamic>;
                          for (final e in map.entries) {
                            final index = int.parse(e.key);
                            if (index >= st.bands.length) continue;
                            await notifier.setBand(
                              index,
                              (e.value as num).round(),
                            );
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('EQ 曲线已导入'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('剪贴板内容不是有效的 EQ 曲线'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('导入曲线'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
    ),
  );
}

/// 耳机线控映射（§9.2）：单击/双击/三击 → 播放暂停/切歌/收藏
Future<void> _showHeadsetSheet(BuildContext context) {
  Widget row(
    String label,
    HeadsetAction current,
    void Function(HeadsetAction) onPick,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppTheme.textDimOf(context), fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in HeadsetAction.values)
              GestureDetector(
                onTap: () => onPick(a),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: a == current
                          ? Theme.of(context).colorScheme.primary
                          : SkinTokens.of(context).borderHairline,
                    ),
                    color: a == current
                        ? Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.18)
                        : null,
                  ),
                  child: Text(
                    a.label,
                    style: TextStyle(
                      color: AppTheme.textPrimaryOf(context),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  return glassBottomSheet<void>(
    context,
    Consumer(
      builder: (context, ref, _) {
        final cfg = ref.watch(headsetClicksProvider);
        final notifier = ref.read(headsetClicksProvider.notifier);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '耳机线控',
                style: TextStyle(
                  color: AppTheme.textPrimaryOf(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            row('单击', cfg.single, (a) => notifier.set(single: a)),
            row('双击', cfg.doubleTap, (a) => notifier.set(doubleTap: a)),
            row('三击', cfg.triple, (a) => notifier.set(triple: a)),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Text(
                '默认：单击播放/暂停，双击下一首，三击上一首；'
                '长按和音量键由系统控制',
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

/// 主题色选择（§8.1）：六个预设色板，选中后立即生效并持久化
