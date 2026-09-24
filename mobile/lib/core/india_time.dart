/// Asia/Kolkata is the app's single timezone (ARCHITECTURE.md § 1). India has
/// no daylight saving, so a fixed +05:30 offset is exact. It also matches the
/// database's `private.local_today()`, so "today" is the same on phone and
/// server even when the phone is set to another timezone.
library;

import 'package:intl/intl.dart';

const Duration kIndiaOffset = Duration(hours: 5, minutes: 30);

/// Clock seam for tests.
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();

/// Today's calendar date in India, as a date-only [DateTime] (local, midnight).
DateTime indiaToday([Clock clock = systemClock]) {
  final ist = clock().toUtc().add(kIndiaOffset);
  return DateTime(ist.year, ist.month, ist.day);
}

/// `yyyy-MM-dd`, the format of Postgres `date` columns.
String toIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Parses a Postgres `date` (`yyyy-MM-dd`) into a date-only [DateTime].
DateTime parseIsoDate(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// A calendar month, used as the Transactions filter and as a provider key.
class YearMonth implements Comparable<YearMonth> {
  const YearMonth(this.year, this.month) : assert(month >= 1 && month <= 12);

  factory YearMonth.of(DateTime d) => YearMonth(d.year, d.month);

  final int year;
  final int month;

  DateTime get firstDay => DateTime(year, month);
  YearMonth get next => month == 12 ? YearMonth(year + 1, 1) : YearMonth(year, month + 1);
  YearMonth get previous => month == 1 ? YearMonth(year - 1, 12) : YearMonth(year, month - 1);

  String get label => DateFormat('MMMM yyyy').format(firstDay);
  String get shortLabel => DateFormat('MMM yyyy').format(firstDay);

  @override
  int compareTo(YearMonth other) =>
      year != other.year ? year.compareTo(other.year) : month.compareTo(other.month);

  @override
  bool operator ==(Object other) => other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}

/// `Thu, 24 Sep 2026`, or "Today" / "Yesterday" relative to India time.
String friendlyDate(DateTime date, {Clock clock = systemClock}) {
  final today = indiaToday(clock);
  final d = DateTime(date.year, date.month, date.day);
  if (d == today) return 'Today, ${DateFormat('d MMM').format(d)}';
  if (d == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday, ${DateFormat('d MMM').format(d)}';
  }
  return DateFormat('EEE, d MMM yyyy').format(d);
}
