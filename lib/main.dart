import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/accent.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/server_select_screen.dart';
import 'features/player/audio_handler.dart';
import 'features/player/player_controller.dart';
import 'shared/widgets/glass.dart';
import 'shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 图片内存缓存上限：默认 100MB → 64MB（性能红线：控制常驻内存基线）
  PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20;
  // 全局容器：audio_service 需在 runApp 前读取 handler
  final container = ProviderContainer();
  await AudioService.init(
    builder: () => container.read(audioHandlerProvider),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.silencetop.liusound.audio',
      androidNotificationChannelName: '流声播放',
      androidNotificationOngoing: true,
    ),
  );
  // 音频焦点：音乐模式（播放时降低其他应用音量，避免混音）
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  runApp(
    UncontrolledProviderScope(container: container, child: const MusicApp()),
  );
}

class MusicApp extends ConsumerWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    // 登出（会话从有到无）→ 同步清空播放器与持久化播放状态
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (prev?.activeServerId != next.activeServerId) {
        ref.read(playerActionsProvider).stop();
      }
    });
    // 沉浸式状态栏：全局浅色图标 + 透明底（全屏播放器/详情页无 AppBar 时图标仍可见）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: MaterialApp(
        title: '流声',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(ref.watch(appAccentProvider).color),
        home: !auth.initialized
            ? const _Splash()
            : auth.isAuthenticated
            ? const AppShell()
            : const ServerSelectScreen(),
      ),
    );
  }
}

/// 冷启动恢复会话期间的启动屏：品牌 logo 入场动效（点击可跳过动效，
/// 但会话初始化本身不可跳过——时长由真实 init 决定，无人为 delay）
class _Splash extends StatefulWidget {
  const _Splash();

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..forward();
  late final Animation<double> _scale = Tween(
    begin: 0.85,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _controller.value = 1, // 点击跳过入场动效
      child: Scaffold(
        body: AmbientBackground(
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/app/logo.png',
                      width: 96,
                      height: 96,
                      filterQuality: FilterQuality.medium,
                    ),
                    const SizedBox(height: AppSpacing.l),
                    Text('流声', style: AppText.h1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
