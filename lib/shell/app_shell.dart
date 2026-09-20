import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/motion_tokens.dart';
import '../features/home/home_screen.dart';
import '../features/home/music_library_screen.dart';
import '../features/player/mini_player.dart';
import '../features/player/player_controller.dart';
import '../features/settings/settings_screen.dart';
import '../shared/widgets/glass.dart';
import '../shared/widgets/motion.dart';
import '../shared/widgets/toast.dart';

/// 主框架（对齐设计图首屏/负一屏）：
/// 顶部沉浸式导航（首页 / 资料库 / 设置）——无卡片容器，直接延伸进状态栏区域，
/// 中间 PageView 保活三页并支持左右滑动，底部 MiniPlayer 悬浮叠加（页面内容铺满到屏幕底，
/// 内容从条底下滑过；条占位经 MediaQuery 注入给页面做列表底部避让）。
/// 播放期间页面零重建（MiniPlayer 内部自管高频订阅）。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // 对齐设计图首屏：首页（搜索/发现内容）/ 资料库（负一屏）/ 设置，默认首页
  int _index = 0;
  final _pageController = PageController();
  DateTime? _lastBackAttempt;

  static const _labels = ['首页', '资料库', '设置'];
  static const _idleIcons = [
    Icons.home_outlined,
    Icons.library_music_outlined,
    Icons.settings_outlined,
  ];
  static const _activeIcons = [
    Icons.home_rounded,
    Icons.library_music_rounded,
    Icons.settings_rounded,
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (AppMotion.reduceMotion(context)) {
      _pageController.jumpToPage(index);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: AppMotion.duration(context, MotionTokens.durationTransition),
      curve: MotionTokens.curveEmphasized,
    );
  }

  /// 根页返回拦截：全面屏侧滑/返回键第一次给出提示，2 秒内第二次才真正退出
  void _handleBack(bool didPop, Object? _) {
    if (didPop) return;
    final now = DateTime.now();
    final last = _lastBackAttempt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAttempt = now;
    showToast('再返回一次退出流声');
  }

  @override
  Widget build(BuildContext context) {
    // 只在「有无播放歌曲」这一维度重建（开始/停止播放各一次），切歌不触发
    final hasMiniBar = ref.watch(currentSongProvider.select((s) => s != null));
    final mq = MediaQuery.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        backgroundColor: AppTheme.shellOf(context),
        body: AmbientBackground(
          child: Stack(
            children: [
              MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(
                    bottom:
                        mq.padding.bottom +
                        (hasMiniBar ? kMiniBarOverlaySpace : 0),
                  ),
                ),
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
                  ],
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(top: false, child: MiniPlayer()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        MediaQuery.paddingOf(context).top,
        AppSpacing.xl,
        AppSpacing.xs,
      ),
      child: SizedBox(
        height:
            AppSpacing.xl +
            MediaQuery.textScalerOf(context)
                    .scale(text.titleMedium!.fontSize!) *
                text.titleMedium!.height!,
        child: Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < _labels.length; i++)
                  Expanded(
                    child: Semantics(
                      label: _labels[i],
                      selected: _index == i,
                      child: InkWell(
                        onTap: () => _goTo(i),
                        borderRadius: BorderRadius.circular(AppRadius.s),
                        child: Center(
                          child: SizedBox(
                            width: AppSpacing.xxxl,
                            height: AppSpacing.xxxl,
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: AppMotion.reduceMotion(context)
                                    ? Duration.zero
                                    : AppMotion.duration(
                                        context,
                                        MotionTokens.durationSnappy,
                                      ),
                                child: Icon(
                                  _index == i ? _activeIcons[i] : _idleIcons[i],
                                  key: ValueKey(_index == i),
                                  size: AppSpacing.xl,
                                  color: _index == i
                                      ? Theme.of(context).colorScheme.primary
                                      : AppTheme.textDimOf(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, child) {
                    final page = _pageController.hasClients
                        ? (_pageController.page ?? _index.toDouble())
                        : _index.toDouble();
                    return Align(
                      alignment: Alignment(page.clamp(0.0, 2.0) - 1, 0),
                      child: FractionallySizedBox(
                        widthFactor: 1 / 3,
                        child: child,
                      ),
                    );
                  },
                  child: Center(
                    child: Container(
                      width: AppSpacing.xl,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
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
