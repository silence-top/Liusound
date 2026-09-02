import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'login_screen.dart';

/// 服务器选择页（对标 1.x ServerSelectScreen：
/// Logo + 标题 + 行式服务器卡片（28px 图标）+ 扫码按钮）
class ServerSelectScreen extends ConsumerWidget {
  const ServerSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Image.asset('assets/app/logo.png', width: 96, height: 96),
              const SizedBox(height: 16),
              Text(
                '选择你的音乐服务',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '支持自建 Navidrome 音乐服务器',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(flex: 3),
              // Navidrome 服务器行（28px 图标 + 16pt 名称 + 箭头）
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LoginScreen(),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset('assets/app/navidrome.png',
                            width: 28, height: 28),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Navidrome',
                            style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 24, color: Color(0xFF666666)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 扫码按钮（1.x 原版占位，保持布局一致）
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.qr_code, size: 24, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('扫码登录',
                          style:
                              TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
