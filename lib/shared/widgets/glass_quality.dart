import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GlassLevel { high, low }

class GlassQualityController extends Notifier<GlassLevel> {
  static const _key = 'glass_quality';

  @override
  GlassLevel build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_key);
      if (saved != null && saved != state.name) {
        state = GlassLevel.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => GlassLevel.high,
        );
      }
    });
    return GlassLevel.high;
  }

  Future<void> setLevel(GlassLevel level) async {
    state = level;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, level.name);
  }
}

final glassQualityProvider =
    NotifierProvider<GlassQualityController, GlassLevel>(
        GlassQualityController.new);

bool shouldUseBlur(BuildContext context) {
  final level = ProviderScope.containerOf(context)
      .read(glassQualityProvider);
  return level == GlassLevel.high;
}
