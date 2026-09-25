import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/unsaved_changes.dart';
import '../../data/providers.dart';
import 'lock_controller.dart';
import 'pattern_hasher.dart';
import 'pattern_pad.dart';

enum _Step { draw, confirm, fingerprint }

/// First run after sign-in (and after "Forgot pattern?"): draw a pattern,
/// draw it again to confirm, then optionally turn on fingerprint unlock.
/// "Not you? Sign out" leads back to sign-in if the wrong Google account
/// was picked.
///
/// With [requireCurrent] (Settings > Change pattern) the current pattern is
/// asked for first.
class SetupLockScreen extends ConsumerStatefulWidget {
  const SetupLockScreen({super.key, this.requireCurrent = false, this.onDone});

  final bool requireCurrent;
  final VoidCallback? onDone;

  @override
  ConsumerState<SetupLockScreen> createState() => _SetupLockScreenState();
}

class _SetupLockScreenState extends ConsumerState<SetupLockScreen> {
  late bool _needCurrent = widget.requireCurrent;
  _Step _step = _Step.draw;
  List<int>? _first;
  String? _message;
  PatternPadState _padState = PatternPadState.idle;
  bool _busy = false;

  String get _title {
    if (_needCurrent) return 'Draw your current pattern';
    return switch (_step) {
      _Step.draw => widget.requireCurrent ? 'Draw a new unlock pattern' : 'Set an unlock pattern',
      _Step.confirm => 'Draw the pattern again to confirm',
      _Step.fingerprint => 'Use fingerprint too?',
    };
  }

  Future<void> _onPattern(List<int> dots) async {
    if (_busy) return;
    if (_needCurrent) {
      setState(() => _busy = true);
      final result = await ref.read(lockControllerProvider.notifier).confirmCurrentPattern(dots);
      if (!mounted) return;
      setState(() {
        _busy = false;
        switch (result) {
          case Unlocked():
            _needCurrent = false;
            _message = null;
            _padState = PatternPadState.idle;
          case WrongPattern(:final attemptsLeft):
            _message = 'Wrong pattern. $attemptsLeft attempts left before a short wait.';
            _padState = PatternPadState.error;
          case CoolingDown(:final until):
            _message = 'Too many wrong attempts. Try again after ${TimeOfDay.fromDateTime(until).format(context)}.';
            _padState = PatternPadState.error;
        }
      });
      return;
    }

    if (dots.length < kMinPatternDots) {
      setState(() {
        _message = 'Connect at least $kMinPatternDots dots.';
        _padState = PatternPadState.error;
      });
      return;
    }

    if (_step == _Step.draw) {
      setState(() {
        _first = dots;
        _step = _Step.confirm;
        _message = null;
        _padState = PatternPadState.idle;
      });
      return;
    }

    if (_step == _Step.confirm) {
      if (!_samePattern(_first!, dots)) {
        setState(() {
          _step = _Step.draw;
          _first = null;
          _message = "Patterns didn't match. Start again.";
          _padState = PatternPadState.error;
        });
        return;
      }
      final canFingerprint = await ref.read(biometricsAvailableProvider.future);
      if (!mounted) return;
      if (canFingerprint) {
        setState(() {
          _step = _Step.fingerprint;
          _message = null;
          _padState = PatternPadState.success;
        });
      } else {
        await _save(enableBiometric: false);
      }
    }
  }

  bool _samePattern(List<int> a, List<int> b) =>
      a.length == b.length && Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

  Future<void> _enableFingerprint() async {
    // Ask for one successful scan so we know it works before relying on it.
    setState(() => _busy = true);
    final ok = await ref.read(localAuthProvider).authenticate(
          localizedReason: 'Confirm your fingerprint for Ventrafin',
          biometricOnly: true,
        ).catchError((_) => false);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await _save(enableBiometric: true);
    } else {
      setState(() => _message = "Fingerprint wasn't confirmed. Try again, or skip for now.");
    }
  }

  Future<void> _save({required bool enableBiometric}) async {
    setState(() => _busy = true);
    try {
      await ref.read(lockControllerProvider.notifier).setPattern(_first!, enableBiometric: enableBiometric);
      if (!mounted) return;
      widget.onDone?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = "Couldn't save the pattern on this phone. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = ref.watch(currentUserProvider)?.email;
    // Dark status-bar icons wherever the page shows through; under the app
    // bar, the AppBar's own style (to suit the brand colour) wins.
    // Changing the pattern: once a new one has been drawn, leaving asks
    // first. (First-run setup has no back; "Not you? Sign out" is its way
    // out.)
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: kDarkStatusBarIcons,
      child: UnsavedChangesScope(
        dirty: widget.requireCurrent && _first != null && !_busy,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.requireCurrent ? 'Change pattern' : 'Secure Ventrafin'),
            automaticallyImplyLeading: widget.requireCurrent,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (!widget.requireCurrent) ...[
                    Text(
                      'The pattern (and fingerprint, if you like) opens the app on this phone. '
                      'It is stored only as a one-way hash, never the pattern itself.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    // The wrong Google account picked: an ordinary sign-out
                    // (nothing is set up yet), back to the sign-in screen.
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (email != null) Text('Signed in as $email', style: theme.textTheme.bodySmall),
                        TextButton(
                          key: const Key('setup-sign-out'),
                          onPressed: _busy ? null : () => ref.read(lockControllerProvider.notifier).signOut(),
                          child: const Text('Not you? Sign out'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(_title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: Text(
                      _message ?? (_step == _Step.fingerprint ? '' : 'Connect at least $kMinPatternDots dots'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _padState == PatternPadState.error ? theme.colorScheme.error : null,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_step == _Step.fingerprint && !_needCurrent) ...[
                    const Icon(Icons.fingerprint, size: 96),
                    const SizedBox(height: 16),
                    const Text(
                      'Unlock with your fingerprint, and use the pattern as a backup.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _busy ? null : _enableFingerprint,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use fingerprint'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _save(enableBiometric: false),
                      child: const Text('Not now, pattern only'),
                    ),
                  ] else
                    PatternPad(onComplete: _onPattern, state: _padState, enabled: !_busy),
                  if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
                  if (_step == _Step.confirm && !_needCurrent)
                    TextButton(
                      onPressed: () => setState(() {
                        _step = _Step.draw;
                        _first = null;
                        _message = null;
                        _padState = PatternPadState.idle;
                      }),
                      child: const Text('Start over'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
