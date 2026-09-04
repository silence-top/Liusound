import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题色预设（§8.1）：每个选项是一个明确的 Color，不走 M3 tone-mapping，
/// 保证切换后按钮/激活态颜色与用户选择的色值完全一致。
enum AppAccent {
  blue('流声蓝', Color(0xFF2196F3)),
  pink('樱花粉', Color(0xFFF06292)),
  purple('暮山紫', Color(0xFF9575CD)),
  green('薄荷绿', Color(0xFF26A69A)),
  orange('落日橙', Color(0xFFFF8A65)),
  night('极夜黑', Color(0xFF90A4AE));

  const AppAccent(this.label, this.color);
  final String label;
  final Color color;
}

class AccentController extends Notifier<AppAccent> {
  static const _key = 'app_accent';

  @override
  AppAccent build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_key);
      if (saved == null) return;
      final v = AppAccent.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => AppAccent.blue,
      );
      if (v != state) state = v;
    });
    return AppAccent.blue;
  }

  Future<void> setAccent(AppAccent accent) async {
    state = accent;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, accent.name);
  }
}

final appAccentProvider = NotifierProvider<AccentController, AppAccent>(
  AccentController.new,
);
