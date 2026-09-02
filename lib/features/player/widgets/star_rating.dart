import 'package:flutter/material.dart';

/// 五星评分组件（详情页头部 / 歌曲操作弹窗共用）：
/// 点击第 n 颗提交 n；再次点击当前星级清零（Subsonic setRating rating=0）。
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    required this.onRating,
    this.size = 22,
    this.color = const Color(0xFFFFC53D),
  });

  final int rating;
  final ValueChanged<int> onRating;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onRating(filled && rating == i + 1 ? 0 : i + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              size: size,
              color: filled ? color : Colors.white24,
            ),
          ),
        );
      }),
    );
  }
}
