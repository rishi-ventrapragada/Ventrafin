import 'dart:convert';
import 'dart:math';

import 'package:convert/convert.dart' show hex;
import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/features/lock/pattern_hasher.dart';

void main() {
  group('pbkdf2Sha256 matches published PBKDF2-HMAC-SHA256 test vectors', () {
    // Vectors from RFC 7914 §11 and the widely used set derived from RFC 6070.
    String derive(String p, String s, int c, int len) =>
        hex.encode(pbkdf2Sha256(utf8.encode(p), utf8.encode(s), c, len));

    test('c = 1', () {
      expect(derive('password', 'salt', 1, 32),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    });

    test('c = 2', () {
      expect(derive('password', 'salt', 2, 32),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
    });

    test('c = 4096', () {
      expect(derive('password', 'salt', 4096, 32),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('multi-block output (dkLen 40)', () {
      expect(derive('passwordPASSWORDpassword', 'saltSALTsaltSALTsaltSALTsaltSALTsalt', 4096, 40),
          '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9');
    });

    test('RFC 7914 vector (passwd / salt, c = 1, dkLen 64)', () {
      expect(derive('passwd', 'salt', 1, 64),
          '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
          '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783');
    });
  });

  group('pattern hashing', () {
    const pattern = [0, 4, 8, 5];
    // Low iteration count keeps the tests fast; the algorithm is identical.
    const fastIterations = 1000;

    test('encodes patterns canonically and validates them', () {
      expect(encodePattern([0, 1, 2, 5, 8]), '0-1-2-5-8');
      expect(() => encodePattern([0, 1, 2]), throwsArgumentError, reason: 'too short');
      expect(() => encodePattern([0, 1, 2, 1]), throwsArgumentError, reason: 'repeated dot');
      expect(() => encodePattern([0, 1, 2, 9]), throwsArgumentError, reason: 'dot out of range');
    });

    test('the right pattern verifies, wrong ones do not', () async {
      final stored = await hashPattern(pattern, iterations: fastIterations);
      expect(await verifyPattern(pattern, stored), isTrue);
      expect(await verifyPattern([0, 4, 8, 7], stored), isFalse);
      expect(await verifyPattern([5, 8, 4, 0], stored), isFalse, reason: 'order matters');
      expect(await verifyPattern([0, 4, 8], stored), isFalse, reason: 'too short');
      expect(await verifyPattern([0, 4, 8, 5, 2], stored), isFalse, reason: 'extra dot');
    });

    test('stores only salt + hash, never the pattern itself', () async {
      final stored = await hashPattern(pattern, iterations: fastIterations);
      final json = jsonEncode(stored.toJson());
      expect(json, isNot(contains('0-4-8-5')));
      expect(stored.salt.length, 16);
      expect(stored.hash.length, 32);
    });

    test('a fresh random salt each time, so equal patterns hash differently', () async {
      final a = await hashPattern(pattern, iterations: fastIterations);
      final b = await hashPattern(pattern, iterations: fastIterations);
      expect(hex.encode(a.salt), isNot(hex.encode(b.salt)));
      expect(hex.encode(a.hash), isNot(hex.encode(b.hash)));
    });

    test('is deterministic for a given salt (seeded RNG)', () async {
      final a = await hashPattern(pattern, iterations: fastIterations, random: Random(42));
      final b = await hashPattern(pattern, iterations: fastIterations, random: Random(42));
      expect(hex.encode(a.hash), hex.encode(b.hash));
    });

    test('JSON round-trip keeps verification working', () async {
      final stored = await hashPattern(pattern, iterations: fastIterations);
      final restored = PatternHash.fromJson(jsonDecode(jsonEncode(stored.toJson())) as Map<String, dynamic>);
      expect(restored.iterations, fastIterations);
      expect(await verifyPattern(pattern, restored), isTrue);
    });

    test('rejects unknown stored formats', () {
      expect(() => PatternHash.fromJson({'v': 2, 'alg': 'pbkdf2-sha256'}), throwsFormatException);
      expect(() => PatternHash.fromJson({'v': 1, 'alg': 'md5'}), throwsFormatException);
    });

    test('production iteration count is used by default', () async {
      final stored = await hashPattern(pattern);
      expect(stored.iterations, kPatternIterations);
      expect(await verifyPattern(pattern, stored), isTrue);
    });

    test('constantTimeEquals', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2, 3], [1, 2]), isFalse);
    });
  });
}
