import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../reminders/reminder_sync.dart';
import 'lock_controller.dart';
import 'lock_screen.dart';

/// Wraps the whole app (MaterialApp.builder). It:
///  * locks when the app returns from the background after
///    [kRelockAfterBackground];
///  * unlocks right after an interactive Google sign-in (the user has just
///    proved who they are);
///  * shows [LockScreen] over everything while locked, and makes the app
///    underneath unreachable (no taps, no screen reader, no back button).
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _backgroundedAt ??= DateTime.now(),
      onShow: _onShow,
    );
  }

  void _onShow() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since != null && DateTime.now().difference(since) >= kRelockAfterBackground) {
      FocusManager.instance.primaryFocus?.unfocus();
      ref.read(lockControllerProvider.notifier).lock();
    }
    // Back in the foreground: refresh anything on screen in case Realtime
    // missed events while the app was suspended.
    ref.read(revisionsProvider.notifier).bumpAll();
    // Notification or alarm permissions may have changed in Android Settings.
    ref.invalidate(reminderPermissionsProvider);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserIdProvider, (previous, next) {
      if (previous == null && next != null) {
        ref.read(lockControllerProvider.notifier).unlock();
      }
    });

    final signedIn = ref.watch(currentUserIdProvider) != null;
    final hasPattern = ref.watch(hasPatternProvider).value ?? false;
    final locked = ref.watch(lockControllerProvider);
    final showLock = signedIn && hasPattern && locked;

    return Stack(
      children: [
        ExcludeSemantics(
          excluding: showLock,
          child: AbsorbPointer(absorbing: showLock, child: widget.child),
        ),
        if (showLock)
          // Own Navigator so the lock screen can show dialogs ("Forgot pattern?").
          Positioned.fill(
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const LockScreen()),
            ),
          ),
      ],
    );
  }
}
