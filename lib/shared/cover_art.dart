import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/subsonic/subsonic.dart';
import '../features/auth/auth_controller.dart';

/// 统一封面组件：
/// - Subsonic getCoverArt（服务端 300px 裁剪）
/// - memCacheWidth 限制解码尺寸，避免全尺寸位图驻留内存（性能红线）
/// - 磁盘 LRU 缓存 + 默认占位图
class CoverArt extends ConsumerWidget {
  const CoverArt({
    super.key,
    required this.albumId,
    this.size = 120,
    this.radius = 10,
  });

  final String albumId;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(subsonicAuthProvider);
    final placeholder = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/app/default-album.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );

    if (!auth.isValid || albumId.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: Subsonic.coverArtUrl(auth, albumId),
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: 300,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }
}
