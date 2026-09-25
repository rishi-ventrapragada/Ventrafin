import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/india_time.dart';
import '../../core/money.dart';
import '../../core/offline_banner.dart';
import '../../core/month_bar.dart';
import '../../core/theme.dart';
import '../../core/visual_badges.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'report_data.dart';

/// Month shown on the Reports screen (defaults to the current month).
class ReportsMonth extends Notifier<YearMonth> {
  @override
  YearMonth build() => YearMonth.of(indiaToday(ref.watch(clockProvider)));

  void set(YearMonth month) => state = month;
}

final reportsMonthProvider = NotifierProvider<ReportsMonth, YearMonth>(ReportsMonth.new);

/// How many months the trends cover: 6 or 12, ending with the chosen month.
class ReportsSpan extends Notifier<int> {
  @override
  int build() => 6;

  void set(int months) => state = months;
}

final reportsSpanProvider = NotifierProvider<ReportsSpan, int>(ReportsSpan.new);

/// Reports (PRD § 4.6): any month's totals and categories against the month
/// before, then 6- or 12-month trends of income against spending and of
/// spending by category. Every number is computed in Postgres
/// (get_month_totals, get_month_comparison, get_monthly_totals,
/// get_monthly_category_totals); charts sit above tables with the same
/// numbers, so nothing is chart-only.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(reportsMonthProvider);
    final span = ref.watch(reportsSpanProvider);
    final thisMonth = YearMonth.of(indiaToday(ref.watch(clockProvider)));
    final months = monthsEnding(month, span);
    final range = (from: months.first, to: months.last);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: MonthBar(
            month: month,
            canGoForward: month.compareTo(thisMonth) < 0,
            onChanged: ref.read(reportsMonthProvider.notifier).set,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(revisionsProvider.notifier).bumpAll();
          try {
            await ref.read(monthlyTotalsProvider(range).future);
          } catch (_) {
            // Each section shows its own error, with Retry.
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          children: [
            _MonthSummaryCard(month: month, range: range),
            _CategoryMonthCard(month: month, range: range, kind: TxnType.expense),
            _CategoryMonthCard(month: month, range: range, kind: TxnType.income),
            _SpanPicker(span: span, months: months),
            _IncomeVsSpendingCard(months: months, range: range),
            _CategoryTrendCard(months: months, range: range),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

Widget _loading() => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));

/// A section that couldn't load: the reason and Retry (the rest of the
/// screen stays usable).
Widget _failed(Object error, VoidCallback onRetry) =>
    LoadError(compact: true, message: describeError(error), onRetry: onRetry);

TextStyle? _head(BuildContext context) =>
    Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

Widget _num(String text, {TextStyle? style, double? width}) {
  final t = Text(text, textAlign: TextAlign.right, maxLines: 1, style: style);
  return width == null ? Expanded(child: t) : SizedBox(width: width, child: t);
}

/// Spending more is red and up; for income, up is green.
class _Change extends StatelessWidget {
  const _Change({required this.now, required this.before, this.upIsGood = false});

  final int now;
  final int before;
  final bool upIsGood;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final diff = now - before;
    if (diff == 0) return Text('same', textAlign: TextAlign.right, style: style);
    if (before == 0) {
      return Text(
        'new',
        textAlign: TextAlign.right,
        style: style?.copyWith(color: upIsGood ? kIncomeColor : kExpenseColor),
      );
    }
    final up = diff > 0;
    final color = up == upIsGood ? kIncomeColor : kExpenseColor;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: color),
          ),
          TextSpan(text: '${percentChange(now, before)!.abs()}%'),
        ],
      ),
      textAlign: TextAlign.right,
      maxLines: 1,
      style: style?.copyWith(color: color, fontWeight: FontWeight.w600),
    );
  }
}

// ---------------------------------------------------------------------------
// The chosen month
// ---------------------------------------------------------------------------

class _MonthSummaryCard extends ConsumerWidget {
  const _MonthSummaryCard({required this.month, required this.range});

  final YearMonth month;
  final MonthRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(monthTotalsProvider(month));
    void retry() => ref.invalidate(monthTotalsProvider(month));
    final counts = ref.watch(monthlyTotalsProvider(range)).value?.where((m) => m.month == month).firstOrNull;
    final t = async.value;
    final body = theme.textTheme.bodyMedium;
    final bold = body?.copyWith(fontWeight: FontWeight.w700);

    Widget row(String label, String now, String before, Widget change, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: body)),
          _num(now, style: bold?.copyWith(color: color)),
          _num(before, style: body),
          SizedBox(width: 62, child: change),
        ],
      ),
    );

    final Widget content;
    if (t == null) {
      content = async.hasError ? _failed(async.error!, retry) : _loading();
    } else {
      final lastNet = t.lastIncomePaise - t.lastExpensePaise;
      int? saved(int income, int net) => income > 0 ? (net * 100 / income).round() : null;
      final savedNow = saved(t.incomePaise, t.netPaise), savedBefore = saved(t.lastIncomePaise, lastNet);
      content = Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 64),
              _num('This month', style: _head(context)),
              _num('Last month', style: _head(context)),
              SizedBox(
                width: 62,
                child: Text('Change', textAlign: TextAlign.right, style: _head(context)),
              ),
            ],
          ),
          const Divider(height: 8),
          row(
            'Spent',
            formatRupeesCompact(t.expensePaise),
            formatRupeesCompact(t.lastExpensePaise),
            _Change(now: t.expensePaise, before: t.lastExpensePaise),
            color: kExpenseColor,
          ),
          row(
            'Income',
            formatRupeesCompact(t.incomePaise),
            formatRupeesCompact(t.lastIncomePaise),
            _Change(now: t.incomePaise, before: t.lastIncomePaise, upIsGood: true),
            color: kIncomeColor,
          ),
          row('Net', formatRupeesCompact(t.netPaise), formatRupeesCompact(lastNet), const SizedBox.shrink()),
          row(
            'Saved',
            savedNow == null ? '–' : '$savedNow%',
            savedBefore == null ? '–' : '$savedBefore%',
            const SizedBox.shrink(),
          ),
          if (counts != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${counts.expenseCount} expenses and ${counts.incomeCount} income entries'
                '${counts.uncategorizedCount > 0 ? ', ${counts.uncategorizedCount} uncategorized' : ''}. '
                'Transfers between your accounts are not counted.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      );
    }
    return _Section(key: const Key('report-month-summary'), title: month.label, child: content);
  }
}

class _CategoryMonthCard extends ConsumerWidget {
  const _CategoryMonthCard({required this.month, required this.range, required this.kind});

  final YearMonth month;
  final MonthRange range;
  final TxnType kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(monthComparisonProvider(month));
    void retry() => ref.invalidate(monthComparisonProvider(month));
    final categories = {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c};
    final counts = <String, int>{
      for (final r in ref.watch(monthlyCategoryTotalsProvider(range)).value ?? const <MonthlyCategoryTotal>[])
        if (r.month == month && r.kind == kind) r.categoryId ?? 'uncategorized': r.count,
    };
    final rows =
        (async.value ?? const <CategoryComparison>[])
            .where((r) => r.kind == kind && (r.thisMonthPaise > 0 || r.lastMonthPaise > 0))
            .toList()
          ..sort((a, b) {
            final c = b.thisMonthPaise.compareTo(a.thisMonthPaise);
            return c != 0 ? c : b.lastMonthPaise.compareTo(a.lastMonthPaise);
          });
    final total = rows.fold<int>(0, (s, r) => s + r.thisMonthPaise);
    final lastTotal = rows.fold<int>(0, (s, r) => s + r.lastMonthPaise);
    final expense = kind == TxnType.expense;

    if (!expense && async.hasValue && rows.isEmpty) return const SizedBox.shrink();

    final small = theme.textTheme.bodySmall;
    final Widget content;
    if (!async.hasValue) {
      content = async.hasError ? _failed(async.error!, retry) : _loading();
    } else if (rows.isEmpty) {
      content = Text('Nothing spent in ${month.label}.', style: theme.textTheme.bodyMedium);
    } else {
      content = Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('Category', style: _head(context))),
              SizedBox(
                width: 26,
                child: Text('#', textAlign: TextAlign.right, style: _head(context)),
              ),
              SizedBox(
                width: 80,
                child: Text('Amount', textAlign: TextAlign.right, style: _head(context)),
              ),
              SizedBox(
                width: 40,
                child: Text('Share', textAlign: TextAlign.right, style: _head(context)),
              ),
              SizedBox(
                width: 50,
                child: Text('vs last', textAlign: TextAlign.right, style: _head(context)),
              ),
            ],
          ),
          const Divider(height: 8),
          for (final r in rows)
            Padding(
              key: Key('report-${kind.db}-${r.categoryId ?? 'uncategorized'}'),
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  if (r.categoryId == null)
                    const UncategorizedAvatar(size: 24)
                  else if (categories[r.categoryId] case final c?)
                    CategoryAvatar(category: c, size: 24)
                  else
                    ColorIconCircle(icon: Icons.label, color: r.color, size: 24),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r.categoryId == null ? 'Uncategorized' : (categories[r.categoryId]?.name ?? r.categoryName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${counts[r.categoryId ?? 'uncategorized'] ?? 0}',
                      textAlign: TextAlign.right,
                      style: small,
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      formatRupeesCompact(r.thisMonthPaise),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      total > 0 ? '${(r.thisMonthPaise * 100 / total).round()}%' : '',
                      textAlign: TextAlign.right,
                      style: small,
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: _Change(now: r.thisMonthPaise, before: r.lastMonthPaise, upIsGood: !expense),
                  ),
                ],
              ),
            ),
          const Divider(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('Total', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                width: 106,
                child: Text(
                  formatRupeesCompact(total),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 40),
              SizedBox(
                width: 50,
                child: _Change(now: total, before: lastTotal, upIsGood: !expense),
              ),
            ],
          ),
        ],
      );
    }
    return _Section(
      key: Key('report-categories-${kind.db}'),
      title: expense ? 'Spending by category' : 'Income by category',
      subtitle: '${month.label}; # = entries, change against ${month.previous.label}',
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Trends
// ---------------------------------------------------------------------------

class _SpanPicker extends ConsumerWidget {
  const _SpanPicker({required this.span, required this.months});

  final int span;
  final List<YearMonth> months;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(
            'Trends: ${months.first.shortLabel} – ${months.last.shortLabel}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 6, label: Text('6 months')),
              ButtonSegment(value: 12, label: Text('12 months')),
            ],
            selected: {span},
            onSelectionChanged: (s) => ref.read(reportsSpanProvider.notifier).set(s.first),
          ),
        ],
      ),
    );
  }
}

String _monthTick(YearMonth m, List<YearMonth> months) => m.month == 1 || m == months.first
    ? DateFormat("MMM ''yy").format(m.firstDay)
    : DateFormat('MMM').format(m.firstDay);

/// A bar chart with rupee gridlines and month labels; the chosen (last)
/// month's label is bold.
BarChartData _barChart({
  required BuildContext context,
  required List<YearMonth> months,
  required List<BarChartGroupData> groups,
  required int maxPaise,
  required BarTouchTooltipData tooltip,
}) {
  final theme = Theme.of(context);
  final step = niceAxisStep(maxPaise);
  final top = ((maxPaise / step).ceil() * step).clamp(step, 1 << 52);
  final wide = months.length > 6;
  return BarChartData(
    maxY: top.toDouble(),
    minY: 0,
    barGroups: groups,
    alignment: BarChartAlignment.spaceAround,
    borderData: FlBorderData(
      show: true,
      border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
    ),
    gridData: FlGridData(
      drawVerticalLine: false,
      horizontalInterval: step.toDouble(),
      getDrawingHorizontalLine: (_) =>
          FlLine(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6), strokeWidth: 0.6),
    ),
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          interval: step.toDouble(),
          getTitlesWidget: (v, meta) => SideTitleWidget(
            meta: meta,
            child: Text(formatRupeesAxis(v.round()), style: theme.textTheme.labelSmall),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          getTitlesWidget: (v, meta) {
            final i = v.round();
            if (i < 0 || i >= months.length) return const SizedBox.shrink();
            final last = i == months.length - 1;
            if (wide && !last && i.isOdd) return const SizedBox.shrink();
            return SideTitleWidget(
              meta: meta,
              child: Text(
                _monthTick(months[i], months),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: last ? FontWeight.w800 : FontWeight.w400,
                  color: last ? theme.colorScheme.primary : null,
                ),
              ),
            );
          },
        ),
      ),
    ),
    barTouchData: BarTouchData(touchTooltipData: tooltip),
  );
}

BarTouchTooltipData _tooltip(BuildContext context, String Function(int group, int rod) text) => BarTouchTooltipData(
  getTooltipColor: (_) => const Color(0xF2263238),
  fitInsideHorizontally: true,
  fitInsideVertically: true,
  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
    text(group.x, rodIndex),
    const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
  ),
);

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label, this.leading});

  final Color color;
  final String label;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      leading ??
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

class _IncomeVsSpendingCard extends ConsumerWidget {
  const _IncomeVsSpendingCard({required this.months, required this.range});

  final List<YearMonth> months;
  final MonthRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(monthlyTotalsProvider(range));
    void retry() => ref.invalidate(monthlyTotalsProvider(range));
    final data = async.value;

    final Widget content;
    if (data == null) {
      content = async.hasError ? _failed(async.error!, retry) : _loading();
    } else {
      final byMonth = {for (final m in data) m.month: m};
      final rows = [
        for (final m in months)
          byMonth[m] ??
              MonthlyTotal(
                month: m,
                expensePaise: 0,
                incomePaise: 0,
                expenseCount: 0,
                incomeCount: 0,
                uncategorizedCount: 0,
              ),
      ];
      final maxPaise = rows.fold<int>(0, (s, r) => [s, r.incomePaise, r.expensePaise].reduce((a, b) => a > b ? a : b));
      final rodWidth = months.length > 6 ? 7.0 : 12.0;
      final small = theme.textTheme.bodySmall;
      final totalIn = rows.fold<int>(0, (s, r) => s + r.incomePaise);
      final totalOut = rows.fold<int>(0, (s, r) => s + r.expensePaise);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Wrap(
            spacing: 12,
            children: [
              _LegendDot(color: kIncomeColor, label: 'Income'),
              _LegendDot(color: kExpenseColor, label: 'Spent'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: BarChart(
              _barChart(
                context: context,
                months: months,
                maxPaise: maxPaise,
                groups: [
                  for (var i = 0; i < rows.length; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 2,
                      barRods: [
                        BarChartRodData(
                          toY: rows[i].incomePaise.toDouble(),
                          color: kIncomeColor,
                          width: rodWidth,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                        BarChartRodData(
                          toY: rows[i].expensePaise.toDouble(),
                          color: kExpenseColor,
                          width: rodWidth,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ],
                    ),
                ],
                tooltip: _tooltip(context, (g, rod) {
                  final r = rows[g];
                  return '${r.month.shortLabel}\n${rod == 0 ? 'Income' : 'Spent'} '
                      '${formatRupeesCompact(rod == 0 ? r.incomePaise : r.expensePaise)}';
                }),
              ),
              duration: Duration.zero,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(width: 62, child: Text('Month', style: _head(context))),
              _num('Income', style: _head(context)),
              _num('Spent', style: _head(context)),
              _num('Net', style: _head(context)),
              _num('Saved', style: _head(context), width: 44),
            ],
          ),
          const Divider(height: 8),
          for (final r in rows.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      r.month.shortLabel,
                      style: r.month == months.last ? small?.copyWith(fontWeight: FontWeight.w800) : small,
                    ),
                  ),
                  _num(formatRupeesCompact(r.incomePaise), style: small?.copyWith(color: kIncomeColor)),
                  _num(formatRupeesCompact(r.expensePaise), style: small?.copyWith(color: kExpenseColor)),
                  _num(formatRupeesCompact(r.netPaise), style: small?.copyWith(fontWeight: FontWeight.w600)),
                  _num(r.savedPercent == null ? '–' : '${r.savedPercent}%', style: small, width: 44),
                ],
              ),
            ),
          const Divider(height: 8),
          Row(
            children: [
              SizedBox(
                width: 62,
                child: Text('Total', style: small?.copyWith(fontWeight: FontWeight.w700)),
              ),
              _num(formatRupeesCompact(totalIn), style: small?.copyWith(fontWeight: FontWeight.w700)),
              _num(formatRupeesCompact(totalOut), style: small?.copyWith(fontWeight: FontWeight.w700)),
              _num(formatRupeesCompact(totalIn - totalOut), style: small?.copyWith(fontWeight: FontWeight.w700)),
              _num(totalIn > 0 ? '${((totalIn - totalOut) * 100 / totalIn).round()}%' : '–', style: small, width: 44),
            ],
          ),
        ],
      );
    }
    return _Section(
      key: const Key('report-income-vs-spending'),
      title: 'Income and spending by month',
      subtitle: 'Saved = income not spent',
      child: content,
    );
  }
}

class _CategoryTrendCard extends ConsumerWidget {
  const _CategoryTrendCard({required this.months, required this.range});

  final List<YearMonth> months;
  final MonthRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(monthlyCategoryTotalsProvider(range));
    void retry() => ref.invalidate(monthlyCategoryTotalsProvider(range));
    final categories = {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c};
    final data = async.value;

    final Widget content;
    if (data == null) {
      content = async.hasError ? _failed(async.error!, retry) : _loading();
    } else {
      final trend = buildCategoryTrend(data, months, categories);
      if (trend.rows.isEmpty) {
        content = Text('No spending in these months.', style: theme.textTheme.bodyMedium);
      } else {
        final totals = trend.monthTotals;
        final maxPaise = totals.fold<int>(0, (a, b) => a > b ? a : b);
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (final s in trend.series)
                  _LegendDot(
                    color: s.color,
                    label: s.name,
                    leading: s.category != null
                        ? CategoryAvatar(category: s.category!, size: 16)
                        : s.isUncategorized
                        ? const UncategorizedAvatar(size: 16)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 190,
              child: BarChart(
                _barChart(
                  context: context,
                  months: months,
                  maxPaise: maxPaise,
                  groups: [
                    for (var i = 0; i < months.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: totals[i].toDouble(),
                            width: months.length > 6 ? 14 : 22,
                            color: Colors.transparent,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            rodStackItems: _stack(trend.series, i),
                          ),
                        ],
                      ),
                  ],
                  tooltip: _tooltip(context, (g, _) {
                    final lines = [
                      for (final s in trend.series)
                        if (s.perMonth[g] > 0) '${s.name}: ${formatRupeesCompact(s.perMonth[g])}',
                    ];
                    return '${months[g].shortLabel}: ${formatRupeesCompact(totals[g])}\n${lines.join('\n')}';
                  }),
                ),
                duration: Duration.zero,
              ),
            ),
            const SizedBox(height: 10),
            _PivotTable(trend: trend),
          ],
        );
      }
    }
    return _Section(
      key: const Key('report-category-trend'),
      title: 'Spending by category, month by month',
      subtitle: 'Top $kTrendTopCategories in the chart; every category in the table',
      child: content,
    );
  }

  /// Largest series at the bottom; a white hairline between segments.
  List<BarChartRodStackItem> _stack(List<TrendSeries> series, int month) {
    final items = <BarChartRodStackItem>[];
    var y = 0.0;
    for (final s in series) {
      final v = s.perMonth[month].toDouble();
      if (v <= 0) continue;
      items.add(BarChartRodStackItem(y, y + v, s.color, borderSide: const BorderSide(color: kCardColor, width: 1)));
      y += v;
    }
    return items;
  }
}

/// Category × month, like a spreadsheet pivot: the name column stays put
/// while the months scroll sideways.
class _PivotTable extends StatelessWidget {
  const _PivotTable({required this.trend});

  final CategoryTrend trend;

  static const double _nameW = 118;
  static const double _monthW = 66;
  static const double _totalW = 76;
  static const double _rowH = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final boldSmall = small?.copyWith(fontWeight: FontWeight.w700);
    final months = trend.months;
    final totals = trend.monthTotals;
    final grand = totals.fold<int>(0, (s, v) => s + v);
    final divider = BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6), width: 0.6);

    Widget cell(String text, double width, {TextStyle? style, bool left = false}) => Container(
      width: width,
      height: _rowH,
      alignment: left ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: divider)),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
    );

    final names = Column(
      children: [
        cell('Category', _nameW, style: _head(context), left: true),
        for (final r in trend.rows)
          Container(
            width: _nameW,
            height: _rowH,
            decoration: BoxDecoration(border: Border(bottom: divider)),
            child: Row(
              children: [
                if (r.category != null)
                  CategoryAvatar(category: r.category!, size: 18)
                else if (r.isUncategorized)
                  const UncategorizedAvatar(size: 18)
                else
                  ColorIconCircle(icon: Icons.label, color: r.color, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
                ),
              ],
            ),
          ),
        cell('Total', _nameW, style: boldSmall, left: true),
      ],
    );

    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final m in months)
              cell(
                _monthTick(m, months),
                _monthW,
                style: m == months.last ? _head(context)?.copyWith(fontWeight: FontWeight.w800) : _head(context),
              ),
            cell('Total', _totalW, style: _head(context)),
            cell('Avg', _monthW, style: _head(context)),
          ],
        ),
        for (final r in trend.rows)
          Row(
            children: [
              for (var i = 0; i < months.length; i++)
                cell(r.perMonth[i] == 0 ? '–' : formatRupeesCompact(r.perMonth[i]), _monthW, style: small),
              cell(formatRupeesCompact(r.total), _totalW, style: boldSmall),
              cell(formatRupeesCompact((r.total / months.length).round()), _monthW, style: small),
            ],
          ),
        Row(
          children: [
            for (final t in totals) cell(formatRupeesCompact(t), _monthW, style: boldSmall),
            cell(formatRupeesCompact(grand), _totalW, style: boldSmall),
            cell(formatRupeesCompact((grand / months.length).round()), _monthW, style: boldSmall),
          ],
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        names,
        Expanded(
          child: SingleChildScrollView(
            key: const Key('pivot-scroll'),
            scrollDirection: Axis.horizontal,
            reverse: true, // start at the newest months, like the chart's right edge
            child: grid,
          ),
        ),
      ],
    );
  }
}
