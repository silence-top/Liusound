import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/audio/audio_effects.dart';
import 'core/download/auto_download.dart';
import 'core/floating/floating_lyrics.dart';
import 'core/scrobble/scrobble_service.dart';
import 'core/settings/prefs.dart';
import 'core/theme/accent.dart';
import 'core/theme/app_skin.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/settings_prefs.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/server_select_screen.dart';
import 'features/player/audio_handler.dart';
import 'features/player/player_controller.dart';
import 'shared/widgets/glass.dart';
import 'shell/app_shell.dart';

/// 省电模式 → Android 刷新率切换（flutter_displaymode；iOS 无公开 API，忽略）
bool? _lastDisplayPowerSave;
void _applyDisplayMode(bool powerSave) {
  if (!Platform.isAndroid || _lastDisplayPowerSave == powerSave) return;
  _lastDisplayPowerSave = powerSave;
  (powerSave
          ? FlutterDisplayMode.setLowRefreshRate()
          : FlutterDisplayMode.setHighRefreshRate())
      .catchError((_) {});
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FloatingLyrics.initialize();
  // 偏好先于整棵 provider 树加载：所有设置控制器可同步读取，无异步回填竞态
  final prefs = await SharedPreferences.getInstance();
  // 图片内存缓存上限：默认 100MB → 64MB（性能红线：控制常驻内存基线）
  PaintingBinding.instance.imageCache.maximumSizeBytes = 64 << 20;
  // 全局容器：audio_service 需在 runApp 前读取 handler
  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  FloatingLyrics.permissionChanges.listen((granted) {
    if (!granted) {
      container.read(floatingLyricsProvider.notifier).setEnabled(false);
      return;
    }
    if (!container.read(floatingLyricsProvider)) return;
    final line = container.read(floatingLyricsLineProvider);
    if (line != null) FloatingLyrics.update(line);
  });
  FloatingLyrics.closed.listen((_) {
    container.read(floatingLyricsProvider.notifier).setEnabled(false);
  });
  // 自动下载补跑：网络切到 Wi-Fi 时补跑一轮（收藏变化在收藏成功处触发）
  Connectivity().onConnectivityChanged.listen((results) {
    final wifi = results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
    );
    if (wifi) maybeAutoDownload(container.read);
  });
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
    // Scrobble 上报服务随 App 存活（50%/2min 触发 + 离线队列补发）
    ref.watch(scrobbleServiceProvider);
    // 音效链随 App 存活：监听音频会话并在会话建立后挂载 EQ/低音/空间
    ref.watch(audioEffectsProvider);
    final skin = ref.watch(appSkinProvider);
    final accent = ref.watch(appAccentProvider);
    final explicit = ref.watch(accentExplicitProvider);
    // 登出（会话从有到无）→ 同步清空播放器与持久化播放状态
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (prev?.activeServerId != next.activeServerId) {
        ref.read(playerActionsProvider).stop();
      }
    });
    // 省电模式 → 低刷新率（Android）
    _applyDisplayMode(ref.watch(powerSaveProvider));
    // 悬浮歌词：当前行变化即推送到 Android 小窗，null 时隐藏
    ref.listen<String?>(floatingLyricsLineProvider, (_, line) {
      if (line == null) {
        FloatingLyrics.hide();
      } else {
        FloatingLyrics.update(line);
      }
    });
    // 沉浸式状态栏：全局浅色图标 + 透明底（全屏播放器/详情页无 AppBar 时图标仍可见）
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      // DynamicColorBuilder 取系统动态色：仅 Material You 皮肤且用户未显式
      // 选过主题色时以壁纸色为主色，否则跟随用户选择
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          final effectiveAccent =
              skin == AppSkin.materialYou && darkDynamic != null && !explicit
              ? darkDynamic.primary
              : accent.color;
          return MaterialApp(
            title: '流声',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(
              skin,
              effectiveAccent,
              materialSurface: darkDynamic?.surface,
              materialSurfaceHigh: darkDynamic?.surfaceContainerHigh,
              materialSurfaceLowest: darkDynamic?.surfaceContainerLowest,
              materialOutline: darkDynamic?.outline,
              materialOutlineVariant: darkDynamic?.outlineVariant,
              materialOnSurface: darkDynamic?.onSurface,
              materialOnSurfaceVariant: darkDynamic?.onSurfaceVariant,
            ),
            home: !auth.initialized
                ? const _Splash()
                : auth.isAuthenticated
                ? const AppShell()
                : const ServerSelectScreen(),
          );
        },
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
