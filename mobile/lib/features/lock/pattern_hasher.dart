import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Minimum number of dots in an unlock pattern (same as Android's own).
const int kMinPatternDots = 4;

/// PBKDF2 iterations for new pattern hashes. A 3x3 pattern has fewer than
/// 400k possibilities, so no hash makes it strong on its own. The hash only
/// has to be slow enough that someone who already has root access to the
/// phone's Keystore-encrypted storage can't brute-force it instantly.
/// 50k keeps each unlock attempt well under a second on a mid-range phone.
/// The count is stored with each hash, so it can be raised later without
/// breaking existing patterns.
const int kPatternIterations = 50000;

/// Canonical text form of a pattern: dot indices 0-8 (row-major), e.g. "0-4-8-5".
String encodePattern(List<int> dots) {
  if (dots.length < kMinPatternDots) {
    throw ArgumentError('A pattern needs at least $kMinPatternDots dots.');
  }
  if (dots.any((d) => d < 0 || d > 8) || dots.toSet().length != dots.length) {
    throw ArgumentError('A pattern uses each of the 9 dots at most once.');
  }
  return dots.join('-');
}

/// What is stored for a pattern. Never the pattern itself.
class PatternHash {
  const PatternHash({required this.salt, required this.hash, required this.iterations});

  factory PatternHash.fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1 || json['alg'] != 'pbkdf2-sha256') {
      throw const FormatException('Unknown pattern hash format');
    }
    return PatternHash(
      salt: base64Decode(json['salt'] as String),
      hash: base64Decode(json['hash'] as String),
      iterations: json['iter'] as int,
    );
  }

  final Uint8List salt;
  final Uint8List hash;
  final int iterations;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'alg': 'pbkdf2-sha256',
        'iter': iterations,
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
      };
}

/// PBKDF2-HMAC-SHA256 (RFC 8018).
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations, int keyLength) {
  if (iterations < 1 || keyLength < 1) throw ArgumentError('iterations and keyLength must be >= 1');
  final hmac = Hmac(sha256, password);
  const hLen = 32;
  final blocks = (keyLength + hLen - 1) ~/ hLen;
  final out = BytesBuilder(copy: false);
  for (var i = 1; i <= blocks; i++) {
    final blockIndex = Uint8List(4)..buffer.asByteData().setUint32(0, i);
    var u = Uint8List.fromList(hmac.convert([...salt, ...blockIndex]).bytes);
    final t = Uint8List.fromList(u);
    for (var c = 1; c < iterations; c++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var k = 0; k < hLen; k++) {
        t[k] ^= u[k];
      }
    }
    out.add(t);
  }
  return Uint8List.fromList(out.takeBytes().sublist(0, keyLength));
}

/// Constant-time comparison, so verification time doesn't leak how many
/// leading bytes matched.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Hashes a new pattern with a fresh random 16-byte salt. Runs off the UI
/// thread (100k iterations would otherwise drop frames).
Future<PatternHash> hashPattern(List<int> dots, {int iterations = kPatternIterations, Random? random}) async {
  final encoded = utf8.encode(encodePattern(dots));
  final rng = random ?? Random.secure();
  final salt = Uint8List.fromList(List<int>.generate(16, (_) => rng.nextInt(256)));
  final hash = await Isolate.run(() => pbkdf2Sha256(encoded, salt, iterations, 32));
  return PatternHash(salt: salt, hash: hash, iterations: iterations);
}

/// True if [dots] is the pattern that produced [stored].
Future<bool> verifyPattern(List<int> dots, PatternHash stored) async {
  if (dots.length < kMinPatternDots) return false;
  final List<int> encoded;
  try {
    encoded = utf8.encode(encodePattern(dots));
  } on ArgumentError {
    return false;
  }
  final salt = stored.salt;
  final iterations = stored.iterations;
  final candidate = await Isolate.run(() => pbkdf2Sha256(encoded, salt, iterations, 32));
  return constantTimeEquals(candidate, stored.hash);
}
