import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/server_adapter.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/auth_controller.dart';

/// 统一封面组件：
/// - ServerAdapter coverImage（服务端 300px 裁剪）
/// - memCacheWidth 按显示尺寸 × DPR 动态限制解码尺寸（上限 300），
///   避免小图（列表 44px）也解码到 300px 的内存浪费（性能红线）
/// - 磁盘 LRU 缓存 + 默认占位图
class CoverArt extends ConsumerWidget {
  const CoverArt({
    super.key,
    required this.albumId,
    this.size = 120,
    this.radius = AppRadius.m,
  });

  final String albumId;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ref.watch(serverAdapterProvider);
    final placeholder = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/app/default-album.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );

    if (albumId.isEmpty) return placeholder;

    final ImageSource? coverSrc = adapter?.coverImage(albumId);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: coverSrc?.url ?? '',
        httpHeaders: coverSrc?.headers,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth:
            (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(80, 300),
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }
}
