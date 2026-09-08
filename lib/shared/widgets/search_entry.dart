import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'glass.dart';

/// 装饰搜索入口条（点击进全屏搜索页）：圆角半透明表面 + 搜索/扫码图标。
/// 不负责导航——onTap 由调用方传，避免 shared 反向依赖 features/search。
class SearchEntryBar extends ConsumerWidget {
  const SearchEntryBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: withGlassTintOpacity(
            ref,
            imageBgAwareTint(ref, AppTheme.surfaceOf(context)),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 22, color: AppTheme.textFaintOf(context)),
            const SizedBox(width: 10),
            Text(
              '搜索',
              style: TextStyle(
                color: AppTheme.textFaintOf(context),
                fontSize: 15,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.qr_code_scanner,
              size: 22,
              color: AppTheme.textFaintOf(context),
            ),
          ],
        ),
      ),
    );
  }
}
