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

/// glassBottomSheet 用近实色取色 tint（定时停止/播放速度选择器）：
/// 同 albumSolidTint 公式但 alpha 0.90——GlassSurface 自带毛玻璃模糊，
/// 底色近实色后透出的只是模糊色斑，与播放页毛玻璃面板同一观感。
Color? albumFrostedTint(Color? dominant) => dominant == null
    ? null
    : Color.lerp(dominant, Colors.black, 0.55)!.withValues(alpha: 0.90);

/// 播放页弹层毛玻璃面板（用户要求：试毛玻璃但不要透明）：
/// 高斯模糊垫底 + alpha 0.90 的封面取色底——透出的只是模糊色斑，
/// 背后内容不可辨，白字可读性不受影响；取色失败回退主题表面色。
/// [opaque]=true 时完全实色（去模糊层，反正也不可见）：歌曲上下文弹层
/// （歌曲更多/添加到歌单）用——既然取了封面色就不要任何透明感。
class AlbumFrostedPanel extends StatelessWidget {
  const AlbumFrostedPanel({
    super.key,
    required this.dominant,
    required this.borderRadius,
    this.padding,
    required this.child,
    this.opaque = false,
  });

  final Color? dominant;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final Widget child;
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final base = albumSolidTint(dominant) ?? AppTheme.surfaceOf(context);
    if (opaque) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Container(color: base, padding: padding, child: child),
      );
    }
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
