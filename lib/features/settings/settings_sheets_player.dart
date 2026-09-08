part of 'settings_screen.dart';

Future<void> _showAccentPicker(BuildContext context, WidgetRef ref) {
  final current = ref.read(appAccentProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '主题色',
            style: TextStyle(
              color: AppTheme.textPrimaryOf(context),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final a in AppAccent.values)
                GestureDetector(
                  onTap: () {
                    ref.read(appAccentProvider.notifier).setAccent(a);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: a.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: a == current
                            ? AppTheme.textPrimaryOf(context)
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: a == current
                        ? Icon(
                            Icons.check,
                            color: AppTheme.textPrimaryOf(context),
                            size: 24,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final a in AppAccent.values)
          if (a == current)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                a.label,
                style: TextStyle(
                  color: AppTheme.textFaintOf(context),
                  fontSize: 13,
                ),
              ),
            ),
      ],
    ),
  );
}

/// 自定义背景设置（§8.1）：选图 / 清除 + 不透明度与模糊度滑块
Future<void> _showBackgroundSettings(BuildContext context, WidgetRef ref) {
  return glassBottomSheet<void>(
    context,
    Consumer(
      builder: (context, ref, _) {
        final bg = ref.watch(backgroundProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '自定义背景',
                style: TextStyle(
                  color: AppTheme.textPrimaryOf(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final img = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1920,
                      maxHeight: 1920,
                      imageQuality: 85,
                    );
                    if (img != null) {
                      await ref
                          .read(backgroundProvider.notifier)
                          .setImage(img.path);
                    }
                  },
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('选择图片'),
                ),
                if (bg.path != null) ...[
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(backgroundProvider.notifier).clearImage(),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清除'),
                  ),
                ],
              ],
            ),
            if (bg.path != null) ...[
              const SizedBox(height: 16),
              // 实时预览：弹窗挡住了屏幕背后的真实背景，调滑块时在这里看效果
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.m),
                  child: SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: AppTheme.shellOf(context)),
                        Opacity(
                          opacity: bg.opacity.clamp(0.0, 1.0),
                          child: bg.blur > 0
                              ? ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: bg.blur,
                                    sigmaY: bg.blur,
                                  ),
                                  child: Image.file(
                                    File(bg.path!),
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                                )
                              : Image.file(
                                  File(bg.path!),
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '不透明度 ${(bg.opacity * 100).round()}%',
                      style: TextStyle(
                        color: AppTheme.textDimOf(context),
                        fontSize: 13,
                      ),
                    ),
                    SliderTheme(
                      data: const SliderThemeData(trackHeight: 2),
                      child: Slider(
                        value: bg.opacity,
                        min: 0.05,
                        max: 1.0,
                        activeColor: Theme.of(context).colorScheme.primary,
                        inactiveColor: AppTheme.textFaintOf(context),
                        // 拖动中仅更新内存态实时预览，松手才落盘
                        onChanged: (v) => ref
                            .read(backgroundProvider.notifier)
                            .updateOpacity(v),
                        onChangeEnd: (_) => ref
                            .read(backgroundProvider.notifier)
                            .commitSliders(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '模糊度 ${bg.blur.toStringAsFixed(1)}',
                      style: TextStyle(
                        color: AppTheme.textDimOf(context),
                        fontSize: 13,
                      ),
                    ),
                    SliderTheme(
                      data: const SliderThemeData(trackHeight: 2),
                      child: Slider(
                        value: bg.blur,
                        min: 0,
                        max: 30,
                        activeColor: Theme.of(context).colorScheme.primary,
                        inactiveColor: AppTheme.textFaintOf(context),
                        onChanged: (v) =>
                            ref.read(backgroundProvider.notifier).updateBlur(v),
                        onChangeEnd: (_) => ref
                            .read(backgroundProvider.notifier)
                            .commitSliders(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                '图片仅保存在本地，不会上传到任何服务器',
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

/// 迷你播放条样式选择（§8.2）：毛玻璃 / 纯色 / 渐变
Future<void> _showMiniBarStylePicker(BuildContext context, WidgetRef ref) {
  final current = ref.read(miniBarStyleProvider);
  return glassBottomSheet<void>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            '迷你播放条样式',
            style: TextStyle(
              color: AppTheme.textPrimaryOf(context),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final style in MiniBarStyle.values)
          ListTile(
            leading: Icon(switch (style) {
              MiniBarStyle.glass => Icons.blur_on_outlined,
              MiniBarStyle.solid => Icons.rectangle_outlined,
              MiniBarStyle.gradient => Icons.gradient_outlined,
            }, color: AppTheme.textDimOf(context)),
            trailing: style == current
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            title: Text(
              style.label,
              style: TextStyle(
                color: AppTheme.textPrimaryOf(context),
                fontSize: 16,
              ),
            ),
            onTap: () {
              ref.read(miniBarStyleProvider.notifier).setStyle(style);
              Navigator.of(context).pop();
            },
          ),
        const SizedBox(height: 12),
      ],
    ),
  );
}

/// 迷你播放条高度偏移微调（§8.2）：-20 ~ 40px，步进 2
Future<void> _showMiniBarOffsetPicker(BuildContext context, WidgetRef ref) {
  return glassBottomSheet<void>(
    context,
    Consumer(
      builder: (context, ref, _) {
        final offset = ref.watch(miniBarOffsetProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '迷你播放条高度偏移',
                style: TextStyle(
                  color: AppTheme.textPrimaryOf(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    '${offset.toStringAsFixed(0)}px',
                    style: TextStyle(
                      color: AppTheme.textPrimaryOf(context),
                      fontSize: 20,
                    ),
                  ),
                  SliderTheme(
                    data: const SliderThemeData(trackHeight: 2),
                    child: Slider(
                      value: offset,
                      min: -20,
                      max: 40,
                      divisions: 30,
                      activeColor: Theme.of(context).colorScheme.primary,
                      inactiveColor: AppTheme.textFaintOf(context),
                      onChanged: (v) =>
                          ref.read(miniBarOffsetProvider.notifier).setOffset(v),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                '正值上移、负值下移，用于适配不同底部导航栏高度',
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

/// 列表触底文案编辑（§8.4）
Future<void> _showEndTextEditor(BuildContext context, WidgetRef ref) async {
  // controller 必须由弹窗内容的 State 持有：await 返回时退场动画尚未结束，
  // TextField 仍挂在树上，此时在外层 dispose 会在键盘收起的动画帧命中
  // 已释放对象，炸断元素树清理（_dependents 断言）
  final text = ValueNotifier<String>(ref.read(listEndTextProvider));
  final result = await glassDialog<String>(
    context,
    title: '列表触底文案',
    content: _EndTextEditorField(
      initialText: text.value,
      onChanged: (v) => text.value = v,
      onDone: (v) => Navigator.of(context).pop(v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(text.value.trim()),
        child: const Text('保存'),
      ),
    ],
  );
  text.dispose();
  if (result != null) {
    ref.read(listEndTextProvider.notifier).setText(result);
  }
}

class _EndTextEditorField extends StatefulWidget {
  const _EndTextEditorField({
    required this.initialText,
    required this.onChanged,
    required this.onDone,
  });

  final String initialText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onDone;

  @override
  State<_EndTextEditorField> createState() => _EndTextEditorFieldState();
}

class _EndTextEditorFieldState extends State<_EndTextEditorField> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onChanged: widget.onChanged,
      onSubmitted: widget.onDone,
      decoration: const InputDecoration(
        hintText: '留空恢复默认',
        helperText: '支持占位符：{nTitle} 下一首歌名 / {nArtist} 歌手 / {nAlbum} 专辑',
      ),
    );
  }
}
