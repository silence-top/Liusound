import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_art.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/toast.dart';
import 'album_tint.dart';
import 'player_controller.dart';

/// 打开播放队列弹窗（对标 1.x QueueModal：底部滑出 + 下拉关闭）。
void showQueueModal(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black38,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(GlassTokens.radiusSheet),
      ),
    ),
    builder: (_) => const _QueueSheet(),
  );
}

/// 队列弹窗的颜色仅由封面派生，不跟随应用皮肤。
class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  static const _modeText = {
    PlayMode.order: '顺序播放',
    PlayMode.shuffle: '随机播放',
    PlayMode.repeatOne: '单曲循环',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    final current = ref.watch(currentSongProvider);
    final mode = ref.watch(playModeProvider);
    final textTheme = Theme.of(context).textTheme;
    final dominant = ref.watch(currentAlbumDominantProvider);
    final panelDominant = dominant ?? AppTheme.lossyText;
    final panelBase = albumSolidTint(panelDominant)!;
    final colors = ColorScheme.fromSeed(
      seedColor: panelDominant,
      brightness: Brightness.dark,
      dynamicSchemeVariant: dominant == null
          ? DynamicSchemeVariant.neutral
          : DynamicSchemeVariant.tonalSpot,
      contrastLevel: 0.5,
    );
    // 按钮走播放页弹层同款白色半透明胶囊，与专辑取色面板同一语言。
    final buttonStyle =
        FilledButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          foregroundColor: colors.onSurface,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
          disabledForegroundColor: colors.onSurface.withValues(alpha: 0.38),
          overlayColor: Colors.white.withValues(alpha: 0.16),
          textStyle: textTheme.labelMedium,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.s),
          ),
        ).copyWith(
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? colors.onSurface
                  : Colors.transparent,
              width: 2,
            ),
          ),
        );
    final modeIcon = switch (mode) {
      PlayMode.order => Icons.repeat,
      PlayMode.shuffle => Icons.shuffle,
      PlayMode.repeatOne => Icons.repeat_one,
    };

    return TooltipTheme(
      data: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(AppRadius.s),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colors.onInverseSurface,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: AlbumFrostedPanel(
          dominant: panelDominant,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(GlassTokens.radiusSheet),
          ),
          padding: EdgeInsets.only(
            top: AppSpacing.s,
            bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.s,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  bottom: AppSpacing.s,
                ),
                decoration: BoxDecoration(
                  color: colors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                  buildDefaultDragHandles: false,
                  // 标题和按钮随列表滚动，极窄屏/大字时也不挤占列表视口。
                  header: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.l,
                      AppSpacing.xs,
                      AppSpacing.l,
                      AppSpacing.s,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              '播放列表 (${queue.length})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s),
                        FilledButton(
                          style: buttonStyle,
                          onPressed: queue.isEmpty
                              ? null
                              : () {
                                  ref.read(playerActionsProvider).clearQueue();
                                  showToast(
                                    '已清空播放队列',
                                    duration: const Duration(seconds: 1),
                                  );
                                },
                          child: const Text('清空'),
                        ),
                        const SizedBox(width: AppSpacing.s),
                        FilledButton.icon(
                          style: buttonStyle,
                          onPressed: () =>
                              ref.read(playerActionsProvider).cyclePlayMode(),
                          icon: Icon(modeIcon, size: 18),
                          label: Text(_modeText[mode] ?? ''),
                        ),
                      ],
                    ),
                  ),
                  footer: queue.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.l),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.queue_music_outlined,
                                size: 32,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(height: AppSpacing.s),
                              Text(
                                '队列为空\n去首页挑几首歌开始播放',
                                textAlign: TextAlign.center,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                  // newIndex 已完成移除位修正，直接插入。
                  onReorderItem: (oldIndex, newIndex) => ref
                      .read(playerActionsProvider)
                      .reorderQueue(oldIndex, newIndex),
                  proxyDecorator: (child, index, animation) => AnimatedBuilder(
                    animation: animation,
                    builder: (_, child) => Material(
                      color: panelBase,
                      shadowColor: colors.shadow,
                      surfaceTintColor: Colors.transparent,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadius.s),
                      ),
                      elevation: animation.value * 6,
                      child: child,
                    ),
                    child: child,
                  ),
                  itemCount: queue.length,
                  itemBuilder: (_, i) {
                    final song = queue[i];
                    final isCurrent = current?.id == song.id;
                    final row = _row(context, ref, song, i, isCurrent, colors);
                    return Dismissible(
                      key: ValueKey(song.id),
                      direction: DismissDirection.endToStart,
                      background: _removeBackground(colors),
                      onDismissed: (_) => ref
                          .read(playerActionsProvider)
                          .removeFromQueue(song.id),
                      child: isCurrent
                          ? Container(
                              clipBehavior: Clip.antiAlias,
                              margin: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.m,
                                ),
                              ),
                              child: row,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: colors.outlineVariant,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: row,
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    Song song,
    int index,
    bool isCurrent,
    ColorScheme colors,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final foreground = colors.onSurface;
    final secondary = colors.onSurfaceVariant;
    return Material(
      type: MaterialType.transparency,
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: InkWell(
          onTap: () {
            Navigator.of(context).pop();
            ref.read(playerActionsProvider).play(song);
          },
          hoverColor: foreground.withValues(alpha: 0.08),
          focusColor: foreground.withValues(alpha: 0.12),
          highlightColor: foreground.withValues(alpha: 0.12),
          splashColor: foreground.withValues(alpha: 0.16),
          // 只设最小行高，文字按系统 TextScaler 自然撑高。
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: ReorderableDragStartListener(
                      index: index,
                      child: isCurrent
                          ? Align(
                              alignment: Alignment.centerRight,
                              child: _CurrentEqualizer(color: foreground),
                            )
                          : Text(
                              '${index + 1}',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: secondary,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  CoverArt(
                    albumId: song.albumId,
                    size: 40,
                    radius: AppRadius.s,
                    localCover: song.localCoverPath,
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyLarge?.copyWith(
                            color: foreground,
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '从播放列表移除',
                    style: IconButton.styleFrom(
                      foregroundColor: secondary,
                      hoverColor: foreground.withValues(alpha: 0.08),
                      focusColor: foreground.withValues(alpha: 0.12),
                      highlightColor: foreground.withValues(alpha: 0.12),
                      minimumSize: const Size(48, 48),
                      visualDensity: VisualDensity.standard,
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => ref
                        .read(playerActionsProvider)
                        .removeFromQueue(song.id),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _removeBackground(ColorScheme colors) => Container(
    alignment: Alignment.centerRight,
    margin: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s,
      vertical: AppSpacing.xs,
    ),
    padding: const EdgeInsets.only(right: AppSpacing.xl),
    decoration: BoxDecoration(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(AppRadius.m),
    ),
    child: Icon(Icons.delete_outline, size: 22, color: colors.onErrorContainer),
  );
}

/// 当前行的电平条：独立订阅播放状态，播放/暂停切换不再整表重建队列列表
/// （流还没吐第一个值时按「播放中」处理，避免刚打开队列电平条就僵住）
class _CurrentEqualizer extends ConsumerWidget {
  const _CurrentEqualizer({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(isPlayingProvider).value ?? true;
    return _EqualizerBars(color: color, playing: playing);
  }
}

/// 播放中电平条：三根竖条按不同相位做三角波起伏，暂停时冻结在低位。
/// 仅当前播放行使用，全场最多一个实例，动画开销可忽略。
class _EqualizerBars extends StatefulWidget {
  const _EqualizerBars({required this.color, this.playing = true});

  final Color color;
  final bool playing;

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  static const _phases = [0.0, 0.38, 0.71];
  static const _minHeight = 4.0;
  static const _maxHeight = 16.0;

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: _maxHeight,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final phase in _phases)
              _bar((_controller.value + phase) % 1.0),
          ],
        ),
      ),
    );
  }

  /// 三角波（0→1→0），避免锯齿波在循环接缝处跳变
  Widget _bar(double t) {
    final wave = t < 0.5 ? t * 2 : (1 - t) * 2;
    return Container(
      width: 3,
      height: _minHeight + (_maxHeight - _minHeight) * wave,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}
