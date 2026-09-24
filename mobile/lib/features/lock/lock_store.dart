import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pattern_hasher.dart';

/// Wrong-pattern bookkeeping, persisted so that killing the app doesn't reset it.
class LockAttempts {
  const LockAttempts({this.failures = 0, this.lockedUntil});

  factory LockAttempts.fromJson(Map<String, dynamic> j) => LockAttempts(
        failures: j['failures'] as int? ?? 0,
        lockedUntil: j['until'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['until'] as int),
      );

  final int failures;
  final DateTime? lockedUntil;

  Map<String, dynamic> toJson() => {'failures': failures, 'until': lockedUntil?.millisecondsSinceEpoch};
}

/// App-lock data in Android Keystore-backed secure storage, per user id:
/// the pattern *hash* (never the pattern), the fingerprint opt-in and the
/// wrong-attempt counter.
class LockStore {
  LockStore(this._storage);

  final FlutterSecureStorage _storage;

  String _k(String userId, String name) => 'lock.v1.$userId.$name';

  Future<PatternHash?> readPattern(String userId) async {
    final raw = await _storage.read(key: _k(userId, 'pattern'));
    if (raw == null) return null;
    try {
      return PatternHash.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null; // unreadable: treat as "no pattern", the user sets a new one
    }
  }

  Future<bool> hasPattern(String userId) async => (await readPattern(userId)) != null;

  Future<void> writePattern(String userId, PatternHash hash) =>
      _storage.write(key: _k(userId, 'pattern'), value: jsonEncode(hash.toJson()));

  Future<bool> biometricEnabled(String userId) async =>
      (await _storage.read(key: _k(userId, 'biometric'))) == '1';

  Future<void> setBiometricEnabled(String userId, bool enabled) =>
      _storage.write(key: _k(userId, 'biometric'), value: enabled ? '1' : '0');

  Future<LockAttempts> readAttempts(String userId) async {
    final raw = await _storage.read(key: _k(userId, 'attempts'));
    if (raw == null) return const LockAttempts();
    try {
      return LockAttempts.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return const LockAttempts();
    }
  }

  Future<void> writeAttempts(String userId, LockAttempts attempts) =>
      _storage.write(key: _k(userId, 'attempts'), value: jsonEncode(attempts.toJson()));

  /// Removes everything lock-related for this user ("Forgot pattern?").
  Future<void> clear(String userId) async {
    for (final name in ['pattern', 'biometric', 'attempts']) {
      await _storage.delete(key: _k(userId, name));
    }
  }
}
