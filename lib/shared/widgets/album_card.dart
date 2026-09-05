import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../cover_art.dart';
import 'motion.dart';

/// 专辑网格卡片（资料库/歌手页等列表复用）：
/// 封面 + 右上角歌曲数角标 + 名称/歌手两行文字。
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.onTap,
    this.size = 170,
  });

  final Album album;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              CoverArt(albumId: album.id, size: size, radius: 10),
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFA2C19), // 设计图红色角标
                    borderRadius: BorderRadius.all(Radius.circular(9)),
                  ),
                  child: Text(
                    album.songCount > 99 ? '99+' : '${album.songCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            album.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
