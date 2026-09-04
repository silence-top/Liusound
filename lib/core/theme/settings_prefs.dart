import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置项图标显隐开关（§8.3）：关闭后所有设置页 ListTile 的 leading 图标隐藏
class SettingsIconsController extends Notifier<bool> {
  static const _key = 'settings_icons_visible';

  @override
  bool build() {
    SharedPreferences.getInstance().then((prefs) {
      final v = prefs.getBool(_key);
      if (v != null && v != state) state = v;
    });
    return true;
  }

  Future<void> setVisible(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, v);
  }
}

final settingsIconsProvider = NotifierProvider<SettingsIconsController, bool>(
  SettingsIconsController.new,
);

/// 列表触底文案（§8.4，不含第三方接口）：自定义「到底啦」提示文字
class ListEndTextController extends Notifier<String> {
  static const _key = 'list_end_text';
  static const defaultText = '- 到底啦 -';

  @override
  String build() {
    SharedPreferences.getInstance().then((prefs) {
      final v = prefs.getString(_key);
      if (v != null && v != state) state = v;
    });
    return defaultText;
  }

  Future<void> setText(String v) async {
    state = v.isEmpty ? defaultText : v;
    final prefs = await SharedPreferences.getInstance();
    if (v.isEmpty || v == defaultText) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, v);
    }
  }
}

final listEndTextProvider = NotifierProvider<ListEndTextController, String>(
  ListEndTextController.new,
);

/// 省电模式开关（§8.5）：开启后关闭复杂模糊、压缩动画时长，降低 CPU/GPU 负载
class PowerSaveController extends Notifier<bool> {
  static const _key = 'power_save';

  @override
  bool build() {
    SharedPreferences.getInstance().then((prefs) {
      final v = prefs.getBool(_key);
      if (v != null && v != state) state = v;
    });
    return false;
  }

  Future<void> setEnabled(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, v);
  }
}

final powerSaveProvider = NotifierProvider<PowerSaveController, bool>(
  PowerSaveController.new,
);

/// Android 悬浮歌词开关：仅 Android 有效（iOS 无悬浮窗能力，入口隐藏），
/// 首次开启前需授予悬浮窗（SYSTEM_ALERT_WINDOW）权限
class FloatingLyricsController extends Notifier<bool> {
  static const _key = 'floating_lyrics';

  @override
  bool build() {
    SharedPreferences.getInstance().then((prefs) {
      final v = prefs.getBool(_key);
      if (v != null && v != state) state = v;
    });
    return false;
  }

  Future<void> setEnabled(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, v);
  }
}

final floatingLyricsProvider = NotifierProvider<FloatingLyricsController, bool>(
  FloatingLyricsController.new,
);
