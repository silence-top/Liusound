import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/settings_prefs.dart';

/// 液态玻璃档位：off 关闭模糊（低端设备流畅）；
/// standard 标准 blur；enhanced 增强 blur（更通透）。
enum GlassLevel { off, standard, enhanced }

extension GlassLevelLabel on GlassLevel {
  String get label => switch (this) {
    GlassLevel.off => '关闭（最流畅）',
    GlassLevel.standard => '标准',
    GlassLevel.enhanced => '增强（更通透）',
  };
}

class GlassQualityController extends Notifier<GlassLevel> {
  static const _key = 'glass_quality';

  @override
  GlassLevel build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_key);
      if (saved == null || saved == state.name) return;
      // 迁移旧档位名：high→standard / low→off
      final level = switch (saved) {
        'high' => GlassLevel.standard,
        'low' => GlassLevel.off,
        _ => GlassLevel.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => GlassLevel.standard,
        ),
      };
      if (level != state) state = level;
    });
    return GlassLevel.standard;
  }

  Future<void> setLevel(GlassLevel level) async {
    state = level;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, level.name);
  }
}

final glassQualityProvider =
    NotifierProvider<GlassQualityController, GlassLevel>(
      GlassQualityController.new,
    );

bool shouldUseBlur(BuildContext context) {
  final powerSave = ProviderScope.containerOf(context).read(powerSaveProvider);
  if (powerSave) return false;
  final level = ProviderScope.containerOf(context).read(glassQualityProvider);
  return level != GlassLevel.off;
}

/// 增强档位下所有 BackdropFilter 的模糊半径放大倍率；
/// 省电模式下直接返回 0，配合 shouldUseBlur 双重保险
double glassBlurScale(BuildContext context) {
  final powerSave = ProviderScope.containerOf(context).read(powerSaveProvider);
  if (powerSave) return 0;
  final level = ProviderScope.containerOf(context).read(glassQualityProvider);
  return level == GlassLevel.enhanced ? 1.5 : 1.0;
}
