import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题皮肤（P1 主题系统化）：液态玻璃复刻 + 四套扩展主题。
/// 全部为深色系（白阶文字语义在所有皮肤下保持有效）。
enum AppSkin {
  liquidGlass('液态玻璃', '镜面高光描边 · 内容透色（默认）'),
  deepSpace('深空科幻', '近黑蓝底 · 霓虹青发光点缀'),
  minimal('极简纯色', '无模糊实色卡片 · 强排版'),
  materialYou('Material You', '动态取色跟随系统壁纸（Android 12+）'),
  highContrast('高对比无障碍', '纯黑白 · 去模糊去发光 · 对比度 ≥7:1');

  const AppSkin(this.label, this.desc);
  final String label;
  final String desc;
}

class SkinController extends Notifier<AppSkin> {
  static const _key = 'app_skin';

  @override
  AppSkin build() {
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_key);
      if (saved == null) return;
      final v = AppSkin.values.firstWhere(
        (e) => e.name == saved,
        orElse: () => AppSkin.liquidGlass,
      );
      if (v != state) state = v;
    });
    return AppSkin.liquidGlass;
  }

  Future<void> set(AppSkin skin) async {
    state = skin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, skin.name);
  }
}

final appSkinProvider = NotifierProvider<SkinController, AppSkin>(
  SkinController.new,
);
