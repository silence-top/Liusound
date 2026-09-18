import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/skin_tokens.dart';
import 'glass.dart';

class SearchEntryBar extends ConsumerWidget {
  const SearchEntryBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = SkinTokens.of(context);
    final radius = BorderRadius.circular(AppRadius.m * tokens.radiusScale);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.s,
        AppSpacing.xl,
        AppSpacing.m,
      ),
      child: Material(
        color: withGlassTintOpacity(ref, imageBgAwareTint(ref, tokens.surface)),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.l,
              vertical: AppSpacing.m,
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: tokens.textDim),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Text(
                    '搜索歌曲、专辑、歌手',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: tokens.textDim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
