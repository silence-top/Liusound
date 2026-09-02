import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import '../features/player/mini_player.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';

/// 主框架：IndexedStack 保活三个页面（切换零重挂载、状态/滚动位置保留），
/// MiniPlayer 常驻于底部导航栏上方。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // 对标 1.x Tab 顺序：搜索 / 主页 / 设置（默认主页）
  int _index = 1;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.search),
      label: '搜索',
    ),
    NavigationDestination(
      icon: Icon(Icons.music_note_outlined),
      selectedIcon: Icon(Icons.music_note),
      label: '主页',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: '设置',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          SearchScreen(),
          HomeScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _index,
            destinations: _destinations,
            onDestinationSelected: (i) => setState(() => _index = i),
          ),
        ],
      ),
    );
  }
}
