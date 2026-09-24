import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../data/providers.dart';
import '../auth/auth_service.dart';
import 'lock_store.dart';
import 'pattern_hasher.dart';

/// Re-lock when the app comes back after being in the background at least
/// this long. Long enough to check a UPI/bank app mid-entry without having to
/// unlock again, short enough that a phone left on a table is locked.
const Duration kRelockAfterBackground = Duration(seconds: 60);

/// Wrong patterns allowed before a cooldown kicks in.
const int kAttemptsBeforeCooldown = 5;

/// Cooldown after the first 5 misses; doubles each further 5, capped.
const Duration kFirstCooldown = Duration(seconds: 30);
const Duration kMaxCooldown = Duration(minutes: 15);

const secureStorage = FlutterSecureStorage();

final lockStoreProvider = Provider<LockStore>((ref) => LockStore(secureStorage));

final localAuthProvider = Provider<LocalAuthentication>((ref) => LocalAuthentication());

/// Whether the signed-in user has set an unlock pattern on this phone.
/// The router sends users without one to the pattern setup screen.
final hasPatternProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  return ref.watch(lockStoreProvider).hasPattern(userId);
});

/// Fingerprint availability on this device (hardware present and enrolled).
final biometricsAvailableProvider = FutureProvider<bool>((ref) async {
  final auth = ref.watch(localAuthProvider);
  try {
    if (!await auth.isDeviceSupported() || !await auth.canCheckBiometrics) return false;
    return (await auth.getAvailableBiometrics()).isNotEmpty;
  } catch (_) {
    return false;
  }
});

final biometricEnabledProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  return ref.watch(lockStoreProvider).biometricEnabled(userId);
});

/// Result of a pattern attempt on the lock screen.
sealed class UnlockResult {
  const UnlockResult();
}

class Unlocked extends UnlockResult {
  const Unlocked();
}

class WrongPattern extends UnlockResult {
  const WrongPattern(this.attemptsLeft);
  final int attemptsLeft;
}

class CoolingDown extends UnlockResult {
  const CoolingDown(this.until);
  final DateTime until;
}

/// Is the app currently locked? Starts locked on every cold start; the lock
/// overlay only actually shows once a user with a pattern is signed in.
class LockController extends Notifier<bool> {
  @override
  bool build() => true;

  void lock() => state = true;

  void unlock() => state = false;

  String get _userId {
    final id = ref.read(currentUserIdProvider);
    if (id == null) throw StateError('No signed-in user');
    return id;
  }

  LockStore get _store => ref.read(lockStoreProvider);

  /// Current cooldown end, if the user must wait before trying again.
  Future<DateTime?> cooldownUntil() async {
    final attempts = await _store.readAttempts(_userId);
    final until = attempts.lockedUntil;
    return until != null && until.isAfter(DateTime.now()) ? until : null;
  }

  Future<UnlockResult> tryPattern(List<int> dots) async {
    final userId = _userId;
    final attempts = await _store.readAttempts(userId);
    final until = attempts.lockedUntil;
    if (until != null && until.isAfter(DateTime.now())) return CoolingDown(until);

    final stored = await _store.readPattern(userId);
    if (stored != null && await verifyPattern(dots, stored)) {
      await _store.writeAttempts(userId, const LockAttempts());
      unlock();
      return const Unlocked();
    }

    final failures = attempts.failures + 1;
    if (failures % kAttemptsBeforeCooldown == 0) {
      final rounds = failures ~/ kAttemptsBeforeCooldown; // 1, 2, 3...
      var wait = kFirstCooldown * (1 << (rounds - 1).clamp(0, 10));
      if (wait > kMaxCooldown) wait = kMaxCooldown;
      final lockedUntil = DateTime.now().add(wait);
      await _store.writeAttempts(userId, LockAttempts(failures: failures, lockedUntil: lockedUntil));
      return CoolingDown(lockedUntil);
    }
    await _store.writeAttempts(userId, LockAttempts(failures: failures));
    return WrongPattern(kAttemptsBeforeCooldown - failures % kAttemptsBeforeCooldown);
  }

  /// Fingerprint prompt. Returns true and unlocks on success; false if
  /// cancelled, failed or unavailable (the pattern remains available).
  Future<bool> tryBiometric() async {
    try {
      final ok = await ref.read(localAuthProvider).authenticate(
            localizedReason: 'Unlock Ventrafin',
            biometricOnly: true,
            persistAcrossBackgrounding: true,
          );
      if (ok) {
        await _store.writeAttempts(_userId, const LockAttempts());
        unlock();
      }
      return ok;
    } on LocalAuthException {
      return false;
    }
  }

  /// Saves a new pattern (as a salted hash) and optionally enables fingerprint.
  Future<void> setPattern(List<int> dots, {required bool enableBiometric}) async {
    final userId = _userId;
    final hash = await hashPattern(dots);
    await _store.writePattern(userId, hash);
    await _store.writeAttempts(userId, const LockAttempts());
    await _store.setBiometricEnabled(userId, enableBiometric);
    ref.invalidate(hasPatternProvider);
    ref.invalidate(biometricEnabledProvider);
    unlock();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _store.setBiometricEnabled(_userId, enabled);
    ref.invalidate(biometricEnabledProvider);
  }

  /// Checks the current pattern without touching lock state (used before
  /// changing the pattern in Settings). Wrong attempts count like on the
  /// lock screen.
  Future<UnlockResult> confirmCurrentPattern(List<int> dots) async {
    final wasLocked = state;
    final result = await tryPattern(dots);
    if (result is Unlocked && wasLocked) state = true;
    return result;
  }

  /// "Forgot pattern?" (DECISIONS.md D6): forget this phone's lock data for
  /// the user and sign out. After signing in with Google again, the router
  /// sends them to set a new pattern.
  Future<void> forgotPattern() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId != null) await _store.clear(userId);
    await ref.read(authServiceProvider).signOut();
    ref.invalidate(hasPatternProvider);
    ref.invalidate(biometricEnabledProvider);
    state = true;
  }

  /// Ordinary sign-out from Settings. Keeps the pattern for next time.
  Future<void> signOut() async {
    await ref.read(authServiceProvider).signOut();
    ref.invalidate(hasPatternProvider);
    state = true;
  }
}

final lockControllerProvider = NotifierProvider<LockController, bool>(LockController.new);
