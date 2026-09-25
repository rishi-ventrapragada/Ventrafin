import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../lock/lock_controller.dart';
import '../reminders/reminder_prompt.dart';
import '../reminders/reminder_sync.dart';

/// Bottom navigation: Dashboard / Transactions / Add / Bills / More.
/// Each tab keeps its own navigation stack (go_router StatefulShellRoute).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _asked = false;

  /// Once per install: explain reminders, then Android's permission prompt.
  /// Not while the lock screen is up (the dialog would sit underneath it).
  void _askOnceUnlocked() {
    if (_asked || ref.read(lockControllerProvider)) return;
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeAskForReminderPermission(context, ref);
    });
  }

  @override
  void initState() {
    super.initState();
    _askOnceUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    ref.listen(lockControllerProvider, (_, locked) {
      if (!locked) _askOnceUnlocked();
    });
    // Keep the Realtime subscription open while the signed-in app is showing,
    // and the phone's reminders in step with the settings and bills.
    ref.watch(realtimeSyncProvider);
    ref.watch(reminderSyncProvider);

    // Android back: a screen pushed inside a tab pops first (go_router asks
    // the tab's own navigator before this one). On any other tab's first
    // screen, back returns to the Dashboard; on the Dashboard it leaves the
    // app as usual.
    final onDashboard = navigationShell.currentIndex == 0;
    return PopScope(
      canPop: onDashboard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !onDashboard) navigationShell.goBranch(0);
      },
      child: _scaffold(navigationShell),
    );
  }

  Widget _scaffold(StatefulNavigationShell navigationShell) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          // Tapping the current tab again returns to its first screen.
          initialLocation: i == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transactions'),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Bills'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
