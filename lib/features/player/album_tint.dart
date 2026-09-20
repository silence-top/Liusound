import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../core/api/server_adapter.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/cover_cache.dart';
import '../../shared/widgets/glass_quality.dart';
import '../auth/auth_controller.dart';
import 'player_controller.dart';

/// 专辑封面主色取色（动态背景，对标 Spotify 沉浸式播放页）。
/// autoDispose 按封面 id 缓存；64px 缩样取 vibrant/muted/dominant，
/// 任何异常返回 null（回退框架色），绝不阻塞播放器打开。
final albumDominantColorProvider = FutureProvider.autoDispose
    .family<Color?, String>((ref, albumId) async {
      if (albumId.isEmpty) return null;
      final adapter = ref.watch(serverAdapterProvider);
      if (adapter == null) return null;
      var disposed = false;
      Timer? expiry;
      ref.onDispose(() {
        disposed = true;
        expiry?.cancel();
      });
      try {
        final ImageSource? cover = adapter.coverImage(albumId);
        if (cover == null) return null;
        // size 仅是布局提示；ResizeImage 才会把取色解码实际限制在 64px。
        final provider = ResizeImage(
          kIsWeb
              ? NetworkImage(cover.url, headers: cover.headers)
              : CachedNetworkImageProvider(
                  cover.url,
                  headers: cover.headers,
                  cacheManager: CoverCacheManager(),
                ),
          width: 64,
          height: 64,
          policy: ResizeImagePolicy.fit,
        );
        final palette = await PaletteGenerator.fromImageProvider(
          provider,
          maximumColorCount: 16,
        );
        final color =
            (palette.vibrantColor ??
                    palette.mutedColor ??
                    palette.dominantColor)
                ?.color;
        if (!disposed && color != null) {
          final link = ref.keepAlive();
          expiry = Timer(const Duration(minutes: 3), link.close);
        }
        return color;
      } catch (_) {
        return null;
      }
    });

/// 最近一次成功取到的封面主色（进程级记忆）：
/// 切歌后新封面取色未到位时，播放页/弹层/迷你条/皮肤沿用上一首颜色，
/// 背景不闪回默认色（用户钦定）；从未取到过时由调用方回退莫奈主色。
final lastAlbumDominantProvider = StateProvider<Color?>((ref) => null);

/// 当前播放歌曲的「生效主色」：本次取色结果 ?? 上一首成功取色。
/// albumTint 全局换肤与播放页/弹层/迷你条共用，保证切歌全程颜色连续。
/// select 只在专辑变化时重建；写记忆走 ref.listen（取色到达后触发），
/// 不在 build 期同步改 state（Riverpod 红线）。
final currentAlbumDominantProvider = Provider.autoDispose<Color?>((ref) {
  final albumId = ref.watch(currentSongProvider.select((s) => s?.albumId));
  if (albumId == null) return null;
  ref.listen<AsyncValue<Color?>>(albumDominantColorProvider(albumId), (
    _,
    next,
  ) {
    final color = next.valueOrNull;
    if (color != null) {
      ref.read(lastAlbumDominantProvider.notifier).state = color;
    }
  });
  return ref.watch(albumDominantColorProvider(albumId)).valueOrNull ??
      ref.watch(lastAlbumDominantProvider);
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

/// 播放页弹层毛玻璃面板：高斯模糊垫底 + alpha 0.90 的封面取色底——透出的只是
/// 模糊色斑，背后内容不可辨，白字可读性不受影响；取色失败回退主题表面色。
/// 底色透明度统一乘全局「面板透明度」系数（设置页滑杆联动，无组件私有硬编码）。
/// [opaque]=true 时默认全实色（去模糊层，反正也不可见）：歌曲上下文弹层
/// （歌曲更多/添加到歌单）用——滑杆降到 100% 以下时同样随之变透明。
class AlbumFrostedPanel extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final base = albumSolidTint(dominant) ?? AppTheme.surfaceOf(context);
    if (opaque) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Container(
          color: withGlassTintOpacity(ref, base),
          padding: padding,
          child: child,
        ),
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          color: withGlassTintOpacity(ref, base.withValues(alpha: 0.90)),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
