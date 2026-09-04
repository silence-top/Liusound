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

/// 耳机线控按键动作映射（§9.2）：单击/双击/三击可自定义
enum HeadsetAction { playPause, next, previous, toggleStar }

extension HeadsetActionLabel on HeadsetAction {
  String get label => switch (this) {
    HeadsetAction.playPause => '播放/暂停',
    HeadsetAction.next => '下一首',
    HeadsetAction.previous => '上一首',
    HeadsetAction.toggleStar => '收藏歌曲',
  };
}

class HeadsetClicksState {
  const HeadsetClicksState({
    this.single = HeadsetAction.playPause,
    this.doubleTap = HeadsetAction.next,
    this.triple = HeadsetAction.previous,
  });

  final HeadsetAction single;
  final HeadsetAction doubleTap;
  final HeadsetAction triple;

  HeadsetClicksState copyWith({
    HeadsetAction? single,
    HeadsetAction? doubleTap,
    HeadsetAction? triple,
  }) => HeadsetClicksState(
    single: single ?? this.single,
    doubleTap: doubleTap ?? this.doubleTap,
    triple: triple ?? this.triple,
  );
}

class HeadsetClicksController extends Notifier<HeadsetClicksState> {
  static const _keySingle = 'headset_click_single';
  static const _keyDouble = 'headset_click_double';
  static const _keyTriple = 'headset_click_triple';

  @override
  HeadsetClicksState build() {
    SharedPreferences.getInstance().then((prefs) {
      state = HeadsetClicksState(
        single: _decode(prefs.getString(_keySingle), state.single),
        doubleTap: _decode(prefs.getString(_keyDouble), state.doubleTap),
        triple: _decode(prefs.getString(_keyTriple), state.triple),
      );
    });
    return const HeadsetClicksState();
  }

  static HeadsetAction _decode(String? raw, HeadsetAction fallback) =>
      HeadsetAction.values.asMap()[int.tryParse(raw ?? '')] ?? fallback;

  static String _encode(HeadsetAction a) =>
      HeadsetAction.values.indexOf(a).toString();

  Future<void> set({
    HeadsetAction? single,
    HeadsetAction? doubleTap,
    HeadsetAction? triple,
  }) async {
    state = state.copyWith(
      single: single,
      doubleTap: doubleTap,
      triple: triple,
    );
    final prefs = await SharedPreferences.getInstance();
    if (single != null) await prefs.setString(_keySingle, _encode(single));
    if (doubleTap != null) {
      await prefs.setString(_keyDouble, _encode(doubleTap));
    }
    if (triple != null) await prefs.setString(_keyTriple, _encode(triple));
  }
}

final headsetClicksProvider =
    NotifierProvider<HeadsetClicksController, HeadsetClicksState>(
      HeadsetClicksController.new,
    );
