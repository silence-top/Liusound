import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'login_screen.dart';

/// 服务器选择页（对标 1.x ServerSelectScreen：当前内置 Navidrome）
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
              Card(
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.4,
                  ),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Image.asset('assets/app/navidrome.png',
                      width: 44, height: 44),
                  title: const Text('Navidrome',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('开源自建音乐流媒体服务器'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                  ),
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
