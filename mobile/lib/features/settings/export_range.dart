/// Which transactions a CSV export covers, and what the file is called.
/// The CSV itself comes from Postgres (`export_transactions_csv`), so the
/// phone and the web save identical files. Same presets and file names as
/// the web app (web/src/lib/exportRange.ts).
library;

import 'package:intl/intl.dart';

import '../../core/india_time.dart';

/// Inclusive dates; null = no limit on that side.
class DateRange {
  const DateRange(this.from, this.to);

  final DateTime? from;
  final DateTime? to;

  @override
  bool operator ==(Object other) => other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'DateRange(${from == null ? '-' : toIsoDate(from!)}, ${to == null ? '-' : toIsoDate(to!)})';
}

enum RangePreset {
  thisMonth('This month'),
  lastMonth('Last month'),
  thisFy('This financial year'),
  lastFy('Last financial year'),
  all('All time'),
  custom('Choose dates');

  const RangePreset(this.label);
  final String label;
}

/// 1 April of the Indian financial year that [today] falls in.
DateTime financialYearStart(DateTime today) => DateTime(today.month >= 4 ? today.year : today.year - 1, 4, 1);

/// `FY 2026-27` for the year starting 1 Apr 2026.
String financialYearLabel(DateTime start) =>
    'FY ${start.year}-${((start.year + 1) % 100).toString().padLeft(2, '0')}';

/// The dates a preset covers (null for [RangePreset.custom]).
DateRange? presetRange(RangePreset preset, DateTime today) {
  final month = YearMonth.of(today);
  DateTime lastDay(YearMonth m) => m.next.firstDay.subtract(const Duration(days: 1));
  switch (preset) {
    case RangePreset.thisMonth:
      return DateRange(month.firstDay, lastDay(month));
    case RangePreset.lastMonth:
      return DateRange(month.previous.firstDay, lastDay(month.previous));
    case RangePreset.thisFy:
      final start = financialYearStart(today);
      return DateRange(start, DateTime(start.year + 1, 3, 31));
    case RangePreset.lastFy:
      final start = DateTime(financialYearStart(today).year - 1, 4, 1);
      return DateRange(start, DateTime(start.year + 1, 3, 31));
    case RangePreset.all:
      return const DateRange(null, null);
    case RangePreset.custom:
      return null;
  }
}

final _dmy = DateFormat('dd/MM/yyyy');

/// `01/04/2026 to 31/03/2027`, `All dates`, `From …`, `Up to …` (same as the web).
String rangeLabel(DateRange r) {
  if (r.from != null && r.to != null) return '${_dmy.format(r.from!)} to ${_dmy.format(r.to!)}';
  if (r.from != null) return 'From ${_dmy.format(r.from!)}';
  if (r.to != null) return 'Up to ${_dmy.format(r.to!)}';
  return 'All dates';
}

/// `ventrafin-transactions-2026-04-01-to-2027-03-31.csv`, `ventrafin-transactions-all-2026-09-25.csv`.
String exportFileName(DateRange r, DateTime today) {
  final part = r.from != null || r.to != null
      ? '${r.from == null ? 'start' : toIsoDate(r.from!)}-to-${toIsoDate(r.to ?? today)}'
      : 'all-${toIsoDate(today)}';
  return 'ventrafin-transactions-$part.csv';
}

/// Data rows in a CSV text (the heading row not counted; quoted line breaks are part of a cell).
int csvRowCount(String csv) {
  var rows = 0;
  var inQuotes = false;
  var lineHasText = false;
  for (var i = 0; i < csv.length; i++) {
    final ch = csv[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
      lineHasText = true;
    } else if (ch == '\n' && !inQuotes) {
      if (lineHasText) rows++;
      lineHasText = false;
    } else if (ch != '\r') {
      lineHasText = true;
    }
  }
  if (lineHasText) rows++;
  return rows > 0 ? rows - 1 : 0;
}
