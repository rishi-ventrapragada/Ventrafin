import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_style.dart';
import '../../core/errors.dart';
import '../../core/india_time.dart';
import '../../core/money.dart';
import '../../core/offline_banner.dart';
import '../../core/theme.dart';
import '../../core/visual_badges.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// This month's spending by category: a donut in category colours (with
/// icons on the larger slices) and a dense this-vs-last-month table.
/// Numbers come from Postgres (`get_month_comparison`); the phone only
/// draws them.
class CategoryBreakdownCard extends ConsumerWidget {
  const CategoryBreakdownCard({super.key, required this.month});

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(monthComparisonProvider(month));
    final categories = {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c};

    final rows = (async.value ?? const <CategoryComparison>[])
        .where((r) => r.kind == TxnType.expense && (r.thisMonthPaise > 0 || r.lastMonthPaise > 0))
        .map((r) => _Row(r, r.categoryId == null ? null : categories[r.categoryId]))
        .toList()
      ..sort((a, b) {
        final byThis = b.data.thisMonthPaise.compareTo(a.data.thisMonthPaise);
        return byThis != 0 ? byThis : b.data.lastMonthPaise.compareTo(a.data.lastMonthPaise);
      });
    final total = rows.fold<int>(0, (s, r) => s + r.data.thisMonthPaise);

    final Widget body;
    if (!async.hasValue && async.hasError) {
      body = LoadError(
        compact: true,
        message: describeError(async.error!),
        onRetry: () => ref.invalidate(monthComparisonProvider(month)),
      );
    } else if (!async.hasValue) {
      body = const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    } else if (rows.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('Nothing spent yet in ${month.label}.', style: theme.textTheme.bodyMedium),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total > 0)
            Row(children: [
              _Donut(rows: rows.where((r) => r.data.thisMonthPaise > 0).toList(), total: total),
              const SizedBox(width: 12),
              Expanded(child: _TopShares(rows: rows.where((r) => r.data.thisMonthPaise > 0).toList(), total: total)),
            ])
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Nothing spent yet in ${month.label}.', style: theme.textTheme.bodyMedium),
            ),
          const SizedBox(height: 8),
          _Table(rows: rows),
        ],
      );
    }

    return Card(
      key: const Key('category-breakdown'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Spending by category', style: theme.textTheme.titleMedium)),
              Text(month.label, style: theme.textTheme.labelMedium),
            ]),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}

/// A comparison row plus the live category (for its icon and current colour).
class _Row {
  const _Row(this.data, this.category);

  final CategoryComparison data;
  final Category? category;

  bool get uncategorized => data.categoryId == null;
  String get name => category?.name ?? data.categoryName;
  Color get color => uncategorized ? kUncategorizedColor : (category?.color ?? data.color);
  IconData get icon => uncategorized ? Icons.question_mark : (category?.icon ?? Icons.label);

  Widget avatar(double size) {
    if (uncategorized) return UncategorizedAvatar(size: size);
    final c = category;
    return c == null ? ColorIconCircle(icon: Icons.label, color: data.color, size: size) : CategoryAvatar(category: c, size: size);
  }
}

class _Donut extends StatelessWidget {
  const _Donut({required this.rows, required this.total});

  final List<_Row> rows;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: 136,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(
          PieChartData(
            centerSpaceRadius: 40,
            sectionsSpace: 1.5,
            startDegreeOffset: -90,
            pieTouchData: PieTouchData(enabled: false),
            sections: [
              for (final r in rows)
                PieChartSectionData(
                  // Chart geometry only; money itself stays integer paise.
                  value: r.data.thisMonthPaise.toDouble(),
                  color: r.color,
                  radius: 26,
                  showTitle: false,
                  badgeWidget: r.data.thisMonthPaise * 100 >= total * 8
                      ? Icon(r.icon, size: 15, color: foregroundOn(r.color))
                      : null,
                ),
            ],
          ),
          duration: Duration.zero,
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Spent', style: theme.textTheme.labelSmall),
          Text(formatRupeesCompact(total),
              style: theme.textTheme.labelLarge?.copyWith(color: kExpenseColor, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}

/// Biggest categories with their share of this month's spending.
class _TopShares extends StatelessWidget {
  const _TopShares({required this.rows, required this.total});

  final List<_Row> rows;
  final int total;

  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows.take(_shown))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              r.avatar(18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ),
              Text(
                '${(r.data.thisMonthPaise * 100 / total).round()}%',
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ]),
          ),
        if (rows.length > _shown)
          Text('+${rows.length - _shown} more below', style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// Every category with spending this month or last: dense, Excel-style.
class _Table extends StatelessWidget {
  const _Table({required this.rows});

  final List<_Row> rows;

  static const double _thisW = 82;
  static const double _lastW = 76;
  static const double _changeW = 74;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final head = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final num = theme.textTheme.bodySmall;

    Widget cell(String text, double width, {TextStyle? style}) =>
        SizedBox(width: width, child: Text(text, textAlign: TextAlign.right, maxLines: 1, style: style));

    return Column(children: [
      Row(children: [
        Expanded(child: Text('Category', style: head)),
        cell('This month', _thisW, style: head),
        cell('Last month', _lastW, style: head),
        cell('Change', _changeW, style: head),
      ]),
      const Divider(height: 8),
      for (final r in rows)
        Padding(
          key: Key('breakdown-${r.data.categoryId ?? 'uncategorized'}'),
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            r.avatar(22),
            const SizedBox(width: 6),
            Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: num)),
            cell(formatRupeesCompact(r.data.thisMonthPaise), _thisW,
                style: num?.copyWith(fontWeight: FontWeight.w600)),
            cell(formatRupeesCompact(r.data.lastMonthPaise), _lastW, style: num),
            SizedBox(width: _changeW, child: _Change(r.data)),
          ]),
        ),
    ]);
  }
}

/// Spent more than last month: red, up. Less: green, down.
class _Change extends StatelessWidget {
  const _Change(this.data);

  final CategoryComparison data;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    final diff = data.changePaise;
    if (diff == 0) return Text('same', textAlign: TextAlign.right, style: style);
    if (data.lastMonthPaise == 0) {
      return Text('new', textAlign: TextAlign.right, style: style?.copyWith(color: kExpenseColor));
    }
    final up = diff > 0;
    final color = up ? kExpenseColor : kIncomeColor;
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: color),
      Flexible(
        child: Text(
          formatRupeesCompact(diff.abs()),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    ]);
  }
}
