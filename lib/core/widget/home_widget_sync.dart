import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../models/models.dart';

/// 4x2 桌面播放小部件状态推送（Android；iOS WidgetKit 需原生扩展，暂不支持）。
/// 仅在数据实际变化时触发 updateWidget，避免桌面刷新风暴。
class HomeWidgetSync {
  static bool _supported() => Platform.isAndroid;

  static Future<void> push({Song? song, required bool playing}) async {
    if (!_supported()) return;
    try {
      await HomeWidget.saveWidgetData<String>(
        'widget_title',
        song?.title ?? '流声',
      );
      await HomeWidget.saveWidgetData<String>(
        'widget_artist',
        song?.artist ?? '',
      );
      await HomeWidget.saveWidgetData<bool>('widget_playing', playing);
      await HomeWidget.updateWidget(name: 'LiusoundWidgetProvider');
    } catch (_) {
      // 小部件未放置/平台异常时静默
    }
  }
}
