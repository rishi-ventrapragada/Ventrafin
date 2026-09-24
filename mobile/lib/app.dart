import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/offline_banner.dart';
import 'core/theme.dart';
import 'features/lock/lock_gate.dart';
import 'router.dart';

class VentrafinApp extends ConsumerWidget {
  const VentrafinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Ventrafin',
      debugShowCheckedModeBanner: false,
      theme: buildOceanTheme(),
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
      // Order matters: the lock overlay covers everything, including the
      // offline banner; the banner sits above every screen.
      builder: (context, child) => LockGate(child: OfflineBanner(child: child ?? const SizedBox.shrink())),
    );
  }
}

/// Shown instead of the app when the build-time config is missing or wrong.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildOceanTheme(),
      home: Scaffold(
        appBar: AppBar(title: const Text('Ventrafin: setup needed')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('This build was made without its configuration. Rebuild with:'),
            const SizedBox(height: 8),
            const SelectableText('flutter run --dart-define-from-file=config/dev.json'),
            const SizedBox(height: 16),
            for (final p in problems) Text('• $p'),
          ],
        ),
      ),
    );
  }
}
