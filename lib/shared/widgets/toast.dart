import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'glass.dart';

/// 全站弹窗提示（替代 Material SnackBar）：玻璃胶囊挂在页面顶部滑入淡出，
/// 面板样式走 GlassSurface，随皮肤/卡片透明度联动（悬浮表面，不受卡片展示开关影响）。
/// [showToast] 不依赖 BuildContext：异步间隙、路由切换后仍可安全调用。
class AppToaster extends StatefulWidget {
  const AppToaster({super.key, required this.child});

  static final GlobalKey<AppToasterState> toasterKey = GlobalKey();

  final Widget child;

  @override
  State<AppToaster> createState() => AppToasterState();
}

class AppToasterState extends State<AppToaster> {
  int _epoch = 0;
  String? _text;
  bool _error = false;
  Timer? _timer;

  void show(
    String message, {
    bool error = false,
    Duration duration = const Duration(seconds: 2),
  }) {
    _timer?.cancel();
    setState(() {
      _epoch++;
      _text = message;
      _error = error;
    });
    _timer = Timer(duration, () {
      if (mounted) setState(() => _text = null);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: SafeArea(
              minimum: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0, -1),
                      end: Offset.zero,
                    ).animate(animation);
                    return ClipRect(
                      child: SlideTransition(
                        position: slide,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                    );
                  },
                  child: _text == null
                      ? const SizedBox.shrink()
                      : ConstrainedBox(
                          key: ValueKey(_epoch),
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: GlassSurface(
                            radius: GlassTokens.radiusPill,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _error
                                      ? Icons.error_outline
                                      : Icons.check_circle_rounded,
                                  size: 16,
                                  color: _error
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _text!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppTheme.textPrimaryOf(context),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 顶部弹窗提示；[error] 为 true 时用警示图标并停留 3 秒
void showToast(String message, {bool error = false, Duration? duration}) {
  AppToaster.toasterKey.currentState?.show(
    message,
    error: error,
    duration: duration ?? Duration(seconds: error ? 3 : 2),
  );
}
