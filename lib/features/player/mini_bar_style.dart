import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/prefs.dart';

/// 迷你播放条样式（§8.2）：纯色 / 毛玻璃 / 渐变
enum MiniBarStyle {
  glass('毛玻璃'),
  solid('纯色'),
  gradient('渐变');

  const MiniBarStyle(this.label);
  final String label;
}

class MiniBarStyleController extends Notifier<MiniBarStyle> {
  static const _key = 'mini_bar_style';

  @override
  MiniBarStyle build() {
    final prefs = ref.watch(sharedPrefsProvider);
    final saved = prefs.getString(_key);
    if (saved == null) return MiniBarStyle.glass;
    return MiniBarStyle.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => MiniBarStyle.glass,
    );
  }

  Future<void> setStyle(MiniBarStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, style.name);
  }
}

final miniBarStyleProvider =
    NotifierProvider<MiniBarStyleController, MiniBarStyle>(
      MiniBarStyleController.new,
    );

/// 控制栏高度偏移（§8.2），单位逻辑像素，持久化
class MiniBarOffsetController extends Notifier<double> {
  static const _key = 'mini_bar_offset';

  @override
  double build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return prefs.getDouble(_key) ?? 0.0;
  }

  Future<void> setOffset(double v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, v);
  }
}

final miniBarOffsetProvider = NotifierProvider<MiniBarOffsetController, double>(
  MiniBarOffsetController.new,
);
