import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/core/money.dart';

void main() {
  group('formatRupees (Indian grouping, paise -> ₹)', () {
    test('formats the canonical example', () {
      expect(formatRupees(12345600), '₹1,23,456.00');
    });

    test('small values and paise', () {
      expect(formatRupees(0), '₹0.00');
      expect(formatRupees(5), '₹0.05');
      expect(formatRupees(99), '₹0.99');
      expect(formatRupees(100), '₹1.00');
      expect(formatRupees(25050), '₹250.50');
    });

    test('grouping boundaries: 3 digits, then pairs', () {
      expect(formatRupees(99900), '₹999.00');
      expect(formatRupees(100000), '₹1,000.00');
      expect(formatRupees(9999900), '₹99,999.00');
      expect(formatRupees(10000000), '₹1,00,000.00');
      expect(formatRupees(1000000000), '₹1,00,00,000.00'); // 1 crore
      expect(formatRupees(123456789012), '₹1,23,45,67,890.12');
    });

    test('largest amount the database allows', () {
      expect(formatRupees(kMaxPaiseExclusive - 1), '₹99,99,99,99,99,999.99');
    });

    test('negative values and no-symbol form', () {
      expect(formatRupees(-500000), '-₹5,000.00');
      expect(formatRupees(12345600, symbol: false), '1,23,456.00');
    });

    test('compact form drops .00 only for whole rupees', () {
      expect(formatRupeesCompact(125000), '₹1,250');
      expect(formatRupeesCompact(125050), '₹1,250.50');
      expect(formatRupeesCompact(-10000000), '-₹1,00,000');
    });
  });

  group('parseRupeesToPaise', () {
    test('plain and decimal amounts', () {
      expect(parseRupeesToPaise('250'), 25000);
      expect(parseRupeesToPaise('250.5'), 25050);
      expect(parseRupeesToPaise('250.05'), 25005);
      expect(parseRupeesToPaise('.75'), 75);
      expect(parseRupeesToPaise('0.01'), 1);
      expect(parseRupeesToPaise('0'), 0);
    });

    test('accepts symbols, spaces and Indian or Western grouping', () {
      expect(parseRupeesToPaise('₹1,23,456.00'), 12345600);
      expect(parseRupeesToPaise(' ₹ 1,234 '), 123400);
      expect(parseRupeesToPaise('Rs. 99'), 9900);
      expect(parseRupeesToPaise('INR 5'), 500);
      expect(parseRupeesToPaise('123,456.78'), 12345678);
      expect(parseRupeesToPaise('007'), 700);
    });

    test('rejects invalid input', () {
      for (final bad in ['', ' ', '.', 'abc', '12a', '1.234', '1.2.3', '-5', '+5', '1e5', '₹']) {
        expect(parseRupeesToPaise(bad), isNull, reason: '"$bad" should be rejected');
      }
    });

    test('enforces the database upper bound', () {
      expect(parseRupeesToPaise('9999999999999.99'), kMaxPaiseExclusive - 1);
      expect(parseRupeesToPaise('10000000000000'), isNull);
      expect(parseRupeesToPaise('99999999999999'), isNull);
    });

    test('never goes through floating point (no rounding drift)', () {
      // 0.1 + 0.2 style inputs that break with doubles.
      expect(parseRupeesToPaise('0.29'), 29);
      expect(parseRupeesToPaise('1.13'), 113);
      expect(parseRupeesToPaise('4.35'), 435);
      expect(parseRupeesToPaise('1234567890.99'), 123456789099);
    });

    test('format -> parse round-trips', () {
      for (final p in [0, 1, 99, 100, 12345600, 987654321, kMaxPaiseExclusive - 1]) {
        expect(parseRupeesToPaise(formatRupees(p)), p);
      }
    });
  });

  group('AmountInput (on-screen keypad)', () {
    AmountInput type(String keys) {
      var a = const AmountInput();
      for (final k in keys.split(' ')) {
        a = a.press(k);
      }
      return a;
    }

    test('builds an amount and groups it for display', () {
      final a = type('1 2 3 4 5 6 7');
      expect(a.display, '12,34,567');
      expect(a.paise, 123456700);
    });

    test('decimals: at most one point and two digits', () {
      expect(type('2 5 0 . 5').paise, 25050);
      expect(type('2 5 0 . 5').display, '250.5');
      expect(type('2 5 0 . 5 0 9').text, '250.50');
      expect(type('1 . . 2').text, '1.2');
    });

    test('leading point and leading zeros', () {
      expect(type('.').text, '0.');
      expect(type('. 7 5').paise, 75);
      expect(type('0 0 5').text, '5');
    });

    test('backspace', () {
      expect(type('1 2 back').text, '1');
      expect(type('back').text, '');
      expect(type('1 . 5 back back').text, '1');
    });

    test('empty input is zero and ignores unknown keys', () {
      expect(const AmountInput().paise, 0);
      expect(const AmountInput().display, '0');
      expect(type('x 5 %').text, '5');
    });

    test('caps whole-rupee digits at the database limit', () {
      final a = type(List.filled(20, '9').join(' '));
      expect(a.text.length, kMaxRupeeDigits);
      expect(a.paise, lessThan(kMaxPaiseExclusive));
    });

    test('fromPaise produces editable keypad text', () {
      expect(AmountInput.fromPaise(25000).text, '250');
      expect(AmountInput.fromPaise(25050).text, '250.50');
      expect(AmountInput.fromPaise(5).text, '0.05');
      expect(AmountInput.fromPaise(12345600).paise, 12345600);
    });
  });

  test('groupIndian', () {
    expect(groupIndian('1'), '1');
    expect(groupIndian('123'), '123');
    expect(groupIndian('1234'), '1,234');
    expect(groupIndian('12345'), '12,345');
    expect(groupIndian('123456'), '1,23,456');
    expect(groupIndian('1234567'), '12,34,567');
  });
}
