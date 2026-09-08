import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../core/api/server_adapter.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';

/// 专辑封面主色取色（动态背景，对标 Spotify 沉浸式播放页）。
/// autoDispose 按封面 id 缓存；64px 缩样取 vibrant/muted/dominant，
/// 任何异常返回 null（回退框架色），绝不阻塞播放器打开。
final albumDominantColorProvider = FutureProvider.autoDispose
    .family<Color?, String>((ref, albumId) async {
      if (albumId.isEmpty) return null;
      final adapter = ref.watch(serverAdapterProvider);
      if (adapter == null) return null;
      try {
        final ImageSource? cover = adapter.coverImage(albumId, size: 64);
        if (cover == null) return null;
        final palette = await PaletteGenerator.fromImageProvider(
          NetworkImage(cover.url),
          size: const Size(64, 64),
          maximumColorCount: 16,
        );
        return (palette.vibrantColor ??
                palette.mutedColor ??
                palette.dominantColor)
            ?.color;
      } catch (_) {
        return null;
      }
    });

/// 播放页自适应面板 tint（内容驱动取色，用户钦定例外）：
/// 与页面背景渐变顶端同一公式（主色 lerp 黑 0.42），半透明叠在
/// 模糊背景上——底部控制栏 / 歌词页浮层 / 队列 / 操作弹窗共用，
/// 整页与弹层随歌曲封面连成同一色系；取色中/失败返回 null（回退默认玻璃 tint）。
Color? albumAdaptiveTint(Color? dominant) => dominant == null
    ? null
    : Color.lerp(dominant, Colors.black, 0.42)!.withValues(alpha: 0.55);

/// 播放页弹层不透明底色（用户钦定去玻璃）：主色 lerp 黑 0.55 实色，
/// 保证白字可读，彻底去掉毛玻璃/透明感；取色失败返回 null（回退主题表面色）。
Color? albumSolidTint(Color? dominant) =>
    dominant == null ? null : Color.lerp(dominant, Colors.black, 0.55)!;

/// 播放页弹层毛玻璃面板（用户要求：试毛玻璃但不要透明）：
/// 高斯模糊垫底 + alpha 0.90 的封面取色底——透出的只是模糊色斑，
/// 背后内容不可辨，白字可读性不受影响；取色失败回退主题表面色
class AlbumFrostedPanel extends StatelessWidget {
  const AlbumFrostedPanel({
    super.key,
    required this.dominant,
    required this.borderRadius,
    this.padding,
    required this.child,
  });

  final Color? dominant;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = albumSolidTint(dominant) ?? AppTheme.surfaceOf(context);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          color: base.withValues(alpha: 0.90),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
