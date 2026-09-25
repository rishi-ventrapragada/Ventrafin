/// Money helpers. Amounts are ALWAYS integer paise in app state and in the
/// database (CLAUDE.md); rupees exist only as display strings. No doubles.
library;

/// Exclusive upper bound enforced by the database (`amount_paise < 10^15`),
/// which keeps values inside JavaScript's safe-integer range for the web app.
const int kMaxPaiseExclusive = 1000000000000000;

/// Largest number of whole-rupee digits that can stay below [kMaxPaiseExclusive].
const int kMaxRupeeDigits = 13;

/// Formats paise as Indian rupees with Indian digit grouping:
/// `12345600` -> `₹1,23,456.00`, `-5000` -> `-₹50.00`.
String formatRupees(int paise, {bool symbol = true}) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final fraction = (abs % 100).toString().padLeft(2, '0');
  final body = '${groupIndian(rupees.toString())}.$fraction';
  return '${negative ? '-' : ''}${symbol ? '₹' : ''}$body';
}

/// Compact variant for dense lists: drops `.00` for whole rupees
/// (`₹1,250` / `₹1,250.50`).
String formatRupeesCompact(int paise) {
  if (paise % 100 == 0) {
    final negative = paise < 0;
    return '${negative ? '-' : ''}₹${groupIndian((paise.abs() ~/ 100).toString())}';
  }
  return formatRupees(paise);
}

/// Indian grouping of a string of digits: last 3, then groups of 2.
/// `1234567` -> `12,34,567`.
String groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$last3';
}

/// Parses user text into paise, or returns null if it isn't a valid amount.
///
/// Accepts an optional `₹`/`Rs`, spaces and grouping commas (Indian or
/// Western), and at most two decimals: `"1,23,456.5"` -> `12345650`,
/// `"₹ 250"` -> `25000`, `".75"` -> `75`. Rejects negatives, more than two
/// decimals, anything non-numeric and values at or above the database limit.
/// Zero parses to 0; "must be greater than zero" is a validation concern.
int? parseRupeesToPaise(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^(₹|rs\.?|inr)\s*', caseSensitive: false), '');
  s = s.replaceAll(RegExp(r'[\s,]'), '');
  final match = RegExp(r'^(\d*)(?:\.(\d{0,2}))?$').firstMatch(s);
  if (match == null) return null;
  final whole = match.group(1)!;
  final frac = match.group(2) ?? '';
  if (whole.isEmpty && frac.isEmpty) return null;
  final wholeDigits = whole.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (wholeDigits.length > kMaxRupeeDigits) return null;
  final paise = int.parse(wholeDigits.isEmpty ? '0' : wholeDigits) * 100 +
      int.parse(frac.padRight(2, '0'));
  return paise < kMaxPaiseExclusive ? paise : null;
}

/// The amount being typed on the on-screen keypad. Holds exactly what the
/// user typed (so "12." or "12.5" display as typed) and converts to paise
/// without floating point.
class AmountInput {
  const AmountInput([this.text = '']);

  /// Raw typed text: digits with at most one '.' and two decimals.
  final String text;

  bool get isEmpty => text.isEmpty;

  /// Paise value; 0 when nothing (or only '.') has been typed.
  int get paise => parseRupeesToPaise(text == '.' ? '0' : (text.isEmpty ? '0' : text)) ?? 0;

  /// Applies one keypad key: '0'-'9', '.', or 'back'. Keys that would make the
  /// amount invalid (third decimal, second '.', too many digits) are ignored.
  AmountInput press(String key) {
    if (key == 'back') {
      return text.isEmpty ? this : AmountInput(text.substring(0, text.length - 1));
    }
    if (key == '.') {
      if (text.contains('.')) return this;
      return AmountInput(text.isEmpty ? '0.' : '$text.');
    }
    if (!RegExp(r'^\d$').hasMatch(key)) return this;
    final dot = text.indexOf('.');
    if (dot >= 0) {
      if (text.length - dot - 1 >= 2) return this; // already two decimals
      return AmountInput('$text$key');
    }
    if (text == '0') return AmountInput(key); // no leading zeros
    if (text.length >= kMaxRupeeDigits) return this;
    return AmountInput('$text$key');
  }

  /// Display form with Indian grouping, preserving partially typed decimals:
  /// `1234567.5` -> `12,34,567.5`. Empty input shows `0`.
  String get display {
    if (text.isEmpty) return '0';
    final dot = text.indexOf('.');
    final whole = dot >= 0 ? text.substring(0, dot) : text;
    final grouped = groupIndian(whole.isEmpty ? '0' : whole);
    return dot >= 0 ? '$grouped${text.substring(dot)}' : grouped;
  }

  /// Keypad text for an existing amount (used when editing).
  factory AmountInput.fromPaise(int paise) {
    final rupees = paise ~/ 100;
    final fraction = paise % 100;
    if (fraction == 0) return AmountInput('$rupees');
    return AmountInput('$rupees.${fraction.toString().padLeft(2, '0')}');
  }

  @override
  bool operator ==(Object other) => other is AmountInput && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// Short axis labels for charts: `₹950`, `₹9.5k`, `₹12k`, `₹1.2L`, `₹3.4Cr`.
String formatRupeesAxis(int paise) {
  final rupees = paise ~/ 100;
  final sign = rupees < 0 ? '-' : '';
  final r = rupees.abs();
  String one(double v) {
    final s = v.toStringAsFixed(v < 10 ? 1 : 0);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  if (r < 1000) return '$sign₹$r';
  if (r < 100000) return '$sign₹${one(r / 1000)}k';
  if (r < 10000000) return '$sign₹${one(r / 100000)}L';
  return '$sign₹${one(r / 10000000)}Cr';
}

/// A round step for about [lines] gridlines up to [maxPaise]: 1, 2 or 5
/// times a power of ten (whole rupees).
int niceAxisStep(int maxPaise, {int lines = 4}) {
  final raw = maxPaise / lines;
  if (raw <= 100) return 100;
  var magnitude = 100;
  while (magnitude * 10 <= raw) {
    magnitude *= 10;
  }
  for (final m in [1, 2, 5, 10]) {
    if (magnitude * m >= raw) return magnitude * m;
  }
  return magnitude * 10;
}
