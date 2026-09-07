import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../core/api/server_adapter.dart';
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
