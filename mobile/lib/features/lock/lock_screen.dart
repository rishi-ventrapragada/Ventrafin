import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'lock_controller.dart';
import 'pattern_pad.dart';

/// Covers the whole app while it's locked. Tries fingerprint first (if the
/// user turned it on), with the pattern as the fallback, and always shows
/// "Forgot pattern?" (DECISIONS.md D6).
///
/// It's an overlay above the navigator rather than a route, so whatever was
/// on screen (e.g. a half-typed entry) is still there after unlocking.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _message;
  PatternPadState _padState = PatternPadState.idle;
  bool _busy = false;
  DateTime? _cooldownUntil;
  Timer? _ticker;
  bool _autoPrompted = false;

  @override
  void initState() {
    super.initState();
    _loadCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoFingerprint());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadCooldown() async {
    final until = await ref.read(lockControllerProvider.notifier).cooldownUntil();
    if (mounted) _setCooldown(until);
  }

  void _setCooldown(DateTime? until) {
    _ticker?.cancel();
    setState(() => _cooldownUntil = until);
    if (until == null) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(until)) {
        _ticker?.cancel();
        setState(() {
          _cooldownUntil = null;
          _message = null;
          _padState = PatternPadState.idle;
        });
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _maybeAutoFingerprint() async {
    if (_autoPrompted) return;
    _autoPrompted = true;
    final enabled = await ref.read(biometricEnabledProvider.future);
    final available = await ref.read(biometricsAvailableProvider.future);
    if (enabled && available && mounted) await _fingerprint();
  }

  Future<void> _fingerprint() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref.read(lockControllerProvider.notifier).tryBiometric();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _message = 'Fingerprint not recognised. Draw your pattern instead.';
    });
  }

  Future<void> _onPattern(List<int> dots) async {
    if (_busy || _cooldownUntil != null) return;
    setState(() => _busy = true);
    final result = await ref.read(lockControllerProvider.notifier).tryPattern(dots);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Unlocked():
          _message = null;
          _padState = PatternPadState.success;
        case WrongPattern(:final attemptsLeft):
          _message = attemptsLeft == 1
              ? 'Wrong pattern. 1 attempt left before a short wait.'
              : 'Wrong pattern. $attemptsLeft attempts left before a short wait.';
          _padState = PatternPadState.error;
        case CoolingDown(:final until):
          _padState = PatternPadState.error;
          _message = 'Too many wrong attempts.';
          _setCooldown(until);
      }
    });
  }

  Future<void> _forgot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot your pattern?'),
        content: const Text(
          "You'll be signed out of Ventrafin on this phone. Sign in with Google again "
          'and set a new pattern. Your data stays safe in your account.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(lockControllerProvider.notifier).forgotPattern();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = "Couldn't sign out. Check your internet connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = ref.watch(currentUserProvider)?.email;
    final fingerprintOn = (ref.watch(biometricEnabledProvider).value ?? false) &&
        (ref.watch(biometricsAvailableProvider).value ?? false);
    final coolingDown = _cooldownUntil != null;
    final remaining = coolingDown ? _cooldownUntil!.difference(DateTime.now()).inSeconds + 1 : 0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text('Ventrafin is locked', style: theme.textTheme.titleLarge),
                if (email != null) Text(email, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                SizedBox(
                  height: 44,
                  child: Text(
                    coolingDown
                        ? 'Too many wrong attempts. Try again in ${remaining}s.'
                        : (_message ?? 'Draw your pattern to unlock'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: (_padState == PatternPadState.error || coolingDown) ? theme.colorScheme.error : null,
                    ),
                  ),
                ),
                PatternPad(
                  onComplete: _onPattern,
                  state: _padState,
                  enabled: !_busy && !coolingDown,
                ),
                const SizedBox(height: 8),
                if (_busy) const SizedBox(width: 200, child: LinearProgressIndicator()),
                if (fingerprintOn)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _fingerprint,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Use fingerprint'),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _forgot,
                  child: const Text('Forgot pattern?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
