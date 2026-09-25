import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../reminders/reminder_sync.dart';
import 'lock_controller.dart';
import 'lock_screen.dart';

/// Whether the lock screen is covering the app: someone with a pattern is
/// signed in and hasn't unlocked yet.
final lockOverlayShownProvider = Provider<bool>((ref) {
  final signedIn = ref.watch(currentUserIdProvider) != null;
  final hasPattern = ref.watch(hasPatternProvider).value ?? false;
  return signedIn && hasPattern && ref.watch(lockControllerProvider);
});

/// The lock overlay's own navigator (for its dialogs, e.g. "Forgot pattern?").
final lockNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'lock');

/// The app's Android back button handler (MaterialApp.router's
/// backButtonDispatcher). While locked, back must never reach the router,
/// which would pop the hidden screen underneath (an Edit transaction or a
/// bill form with unsaved changes). It closes a dialog of the lock screen's
/// instead, if one is open, and otherwise does nothing. Unlocked, the router
/// handles it as usual.
///
/// This has to happen here rather than with a PopScope in [LockGate]: the
/// gate sits above the router's navigator, where a PopScope has no route to
/// attach to.
class LockAwareBackButtonDispatcher extends RootBackButtonDispatcher {
  LockAwareBackButtonDispatcher({required this.isLocked});

  final bool Function() isLocked;

  @override
  Future<bool> didPopRoute() async {
    if (!isLocked()) return super.didPopRoute();
    await lockNavigatorKey.currentState?.maybePop();
    return true;
  }
}

/// Wraps the whole app (MaterialApp.builder). It:
///  * locks when the app returns from the background after
///    [kRelockAfterBackground];
///  * unlocks right after an interactive Google sign-in (the user has just
///    proved who they are);
///  * shows [LockScreen] over everything while locked, and makes the app
///    underneath unreachable (no taps, no screen reader; the back button is
///    kept away from it by [LockAwareBackButtonDispatcher]).
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

    final showLock = ref.watch(lockOverlayShownProvider);

    return Stack(
      children: [
        ExcludeSemantics(
          excluding: showLock,
          child: AbsorbPointer(absorbing: showLock, child: widget.child),
        ),
        if (showLock)
          // Own Navigator so the lock screen can show dialogs ("Forgot pattern?").
          // Dark status-bar icons: the lock screen is near-white in every theme.
          Positioned.fill(
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: kDarkStatusBarIcons,
              child: Navigator(
                key: lockNavigatorKey,
                onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const LockScreen()),
              ),
            ),
          ),
      ],
    );
  }
}
