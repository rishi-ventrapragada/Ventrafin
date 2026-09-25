import 'package:flutter/material.dart';

import '../../core/india_time.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

/// The months [to]-(count-1) .. [to], oldest first.
List<YearMonth> monthsEnding(YearMonth to, int count) {
  final out = <YearMonth>[to];
  while (out.length < count) {
    out.insert(0, out.first.previous);
  }
  return out;
}

/// How many categories get their own colour in the trend chart; the rest
/// fold into "Other" (same rule on the web, web/src/lib/reports.ts).
const int kTrendTopCategories = 5;

/// "Other" in the trend: a neutral grey that is not in the category palette,
/// dark enough (3:1 or more) to show against every surface in every theme.
/// Same value on the web.
const Color kOtherSeriesColor = Color(0xFF7F8C93);

/// One row of the spending-by-category trend: a category (or Uncategorized,
/// or Other) with its total in each month.
@immutable
class TrendSeries {
  const TrendSeries({
    required this.key,
    required this.name,
    required this.color,
    required this.category,
    required this.perMonth,
  });

  /// Category id, `uncategorized` or `other`.
  final String key;
  final String name;
  final Color color;

  /// The live category (for its icon), when this series is one.
  final Category? category;

  /// Paise per month, in the same order as the months.
  final List<int> perMonth;

  int get total => perMonth.fold(0, (s, v) => s + v);
  bool get isOther => key == 'other';
  bool get isUncategorized => key == 'uncategorized';
}

@immutable
class CategoryTrend {
  const CategoryTrend({required this.months, required this.series, required this.rows});

  final List<YearMonth> months;

  /// For the chart: the top [kTrendTopCategories] by total over the range,
  /// then "Other" (if anything is left). Largest first.
  final List<TrendSeries> series;

  /// For the table: every category with spending in the range, largest first.
  final List<TrendSeries> rows;

  List<int> get monthTotals => [for (var i = 0; i < months.length; i++) rows.fold(0, (s, r) => s + r.perMonth[i])];
}

/// Expense totals per category per month, shaped for the trend chart and
/// table. Names and colours come from the live categories when loaded, so a
/// rename shows straight away.
CategoryTrend buildCategoryTrend(
  List<MonthlyCategoryTotal> totals,
  List<YearMonth> months,
  Map<String, Category> categoriesById,
) {
  final index = {for (var i = 0; i < months.length; i++) months[i]: i};
  final byKey = <String, List<int>>{};
  final meta = <String, MonthlyCategoryTotal>{};
  for (final t in totals) {
    if (t.kind != TxnType.expense) continue;
    final i = index[t.month];
    if (i == null) continue;
    final key = t.categoryId ?? 'uncategorized';
    (byKey[key] ??= List<int>.filled(months.length, 0))[i] += t.totalPaise;
    meta[key] = t;
  }
  final rows =
      [
        for (final e in byKey.entries)
          () {
            final m = meta[e.key]!;
            final c = m.categoryId == null ? null : categoriesById[m.categoryId];
            return TrendSeries(
              key: e.key,
              name: m.categoryId == null ? 'Uncategorized' : (c?.name ?? m.categoryName),
              color: m.categoryId == null ? kUncategorizedColor : (c?.color ?? m.color),
              category: c,
              perMonth: e.value,
            );
          }(),
      ]..sort((a, b) {
        final byTotal = b.total.compareTo(a.total);
        return byTotal != 0 ? byTotal : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

  final top = rows.take(kTrendTopCategories).toList();
  final rest = rows.skip(kTrendTopCategories).toList();
  final series = [
    ...top,
    if (rest.isNotEmpty)
      TrendSeries(
        key: 'other',
        name: 'Other (${rest.length})',
        color: kOtherSeriesColor,
        category: null,
        perMonth: [for (var i = 0; i < months.length; i++) rest.fold(0, (s, r) => s + r.perMonth[i])],
      ),
  ];
  return CategoryTrend(months: months, series: series, rows: rows);
}

/// Whole-percent change from [before] to [now]; null when [before] is 0.
int? percentChange(int now, int before) => before == 0 ? null : ((now - before) * 100 / before).round();
