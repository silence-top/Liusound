import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/home/home_screen.dart';
import '../features/home/music_library_screen.dart';
import '../features/player/mini_player.dart';
import '../features/settings/settings_screen.dart';
import '../shared/widgets/glass.dart';

/// 主框架（对齐设计图首屏/负一屏）：
/// 顶部图标式 Tab 栏（搜索=首页 / 音乐库 / 设置），中间 IndexedStack 保活三页，
/// 底部 MiniPlayer。播放期间页面零重建（MiniPlayer 内部自管高频订阅）。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // 对齐设计图首屏：搜索（首页内容）/ 音乐库（负一屏）/ 设置，默认搜索
  int _index = 0;

  static const _icons = [
    Icons.search,
    Icons.music_note,
    Icons.settings,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.shell,
      body: AmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              GlassPill(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  height: 56,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < _icons.length; i++)
                        Expanded(
                          child: Center(
                            child: Material(
                              color: _index == i
                                  ? AppTheme.primary.withValues(alpha: 0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => setState(() => _index = i),
                                child: SizedBox(
                                  width: 56,
                                  height: 48,
                                  child: Icon(
                                    _icons[i],
                                    size: 28,
                                    color: _index == i
                                        ? AppTheme.primary
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: const [
                    HomeScreen(),
                    MusicLibraryScreen(),
                    SettingsScreen(),
                  ],
                ),
              ),
              const MiniPlayer(),
            ],
          ),
        ),
      ),
    );
  }
}
