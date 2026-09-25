import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/offline_banner.dart';
import 'core/theme.dart';
import 'data/providers.dart';
import 'features/reminders/reminder_sync.dart';
import 'features/lock/lock_gate.dart';
import 'router.dart';

class VentrafinApp extends ConsumerWidget {
  const VentrafinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Remember the theme on this phone, so the next start (and the sign-in
    // screen) opens in it before the profile has loaded.
    ref.listen(profileProvider, (_, next) {
      final theme = next.value?.theme;
      if (theme != null) ref.read(sharedPreferencesProvider).setString(kThemePrefKey, theme);
    });
    // Signed out (here, or the session ended): no reminders about someone's
    // bills on a phone that is no longer signed in.
    ref.listen(currentUserIdProvider, (previous, next) {
      if (previous != null && next == null) ref.read(reminderNotificationsProvider).cancelAll();
    });
    // A tapped reminder opens its screen (Add, or Bills). The lock screen
    // still covers it until unlocked.
    ref.listen(reminderOpenedProvider, (_, next) {
      final route = next.value;
      if (route != null) ref.read(routerProvider).go(route);
    });
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Ventrafin',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(themeTokensFor(ref.watch(themeIdProvider))),
      themeMode: ThemeMode.light,
      // The router's parts, with our own back-button dispatcher: while the
      // lock screen is up, back must not pop the screen underneath it.
      routerDelegate: router.routerDelegate,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
      backButtonDispatcher: ref.watch(backButtonDispatcherProvider),
      // Order matters: the lock overlay covers everything, including the
      // offline banner; the banner sits above every screen.
      builder: (context, child) => LockGate(child: OfflineBanner(child: child ?? const SizedBox.shrink())),
    );
  }
}

/// See [LockAwareBackButtonDispatcher].
final backButtonDispatcherProvider = Provider<BackButtonDispatcher>(
  (ref) => LockAwareBackButtonDispatcher(isLocked: () => ref.read(lockOverlayShownProvider)),
);

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
