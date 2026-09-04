import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/home/home_screen.dart';
import '../features/home/music_library_screen.dart';
import '../features/player/mini_player.dart';
import '../features/settings/settings_screen.dart';
import '../shared/widgets/glass.dart';

/// 主框架（对齐设计图首屏/负一屏）：
/// 顶部沉浸式导航（首页 / 资料库 / 设置）——无卡片容器，直接延伸进状态栏区域，
/// 中间 PageView 保活三页并支持左右滑动，底部 MiniPlayer。
/// 播放期间页面零重建（MiniPlayer 内部自管高频订阅）。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // 对齐设计图首屏：首页（搜索/发现内容）/ 资料库（负一屏）/ 设置，默认首页
  int _index = 0;
  final _pageController = PageController();

  static const _icons = [Icons.search, Icons.music_note, Icons.settings];
  static const _labels = ['首页', '资料库', '设置'];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.shellOf(context),
      body: AmbientBackground(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _index = i),
                children: const [
                  _KeepAlive(child: HomeScreen()),
                  _KeepAlive(child: MusicLibraryScreen()),
                  _KeepAlive(child: SettingsScreen()),
                ],
              ),
            ),
            SafeArea(top: false, child: const MiniPlayer()),
          ],
        ),
      ),
    );
  }

  /// 沉浸式顶部导航：透明无卡片，随 AmbientBackground 延伸进状态栏；
  /// 激活态主色高亮 + 弱底色，未激活白阶弱化
  Widget _buildTopBar() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      color: Colors.transparent,
      padding: EdgeInsets.only(top: topPadding),
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _icons.length; i++)
              Material(
                color: _index == i
                    ? Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: () => _goTo(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _icons[i],
                          size: 20,
                          color: _index == i
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _labels[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _index == i
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: _index == i
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// PageView 子页保活：等效 IndexedStack 的状态保持（页面切换零重建）
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
