import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/india_time.dart';
import '../../core/money.dart';
import '../../core/offline_banner.dart';
import '../../core/theme.dart';
import '../../core/visual_badges.dart';
import '../../data/providers.dart';
import '../dashboard/category_breakdown.dart';
import '../transactions/txn_filter.dart';

/// Dashboard: this month's spending as the headline, this month against
/// last (from `get_month_totals`), quick actions, then the
/// spending-by-category breakdown. Past months and
/// trends are on the Reports screen.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = YearMonth.of(indiaToday(ref.watch(clockProvider)));
    final totals = ref.watch(monthTotalsProvider(month));
    final theme = Theme.of(context);
    final t = totals.value;

    // Label and two amount columns sharing the width; amounts shrink to
    // fit rather than wrap at a large font size.
    Widget amount(String text, TextStyle? style) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(text, maxLines: 1, style: style),
        );
    Widget row(String label, int? now, int? before, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(flex: 4, child: Text(label, style: theme.textTheme.bodyMedium)),
            Expanded(
              flex: 5,
              child: amount(now == null ? '…' : formatRupeesCompact(now),
                  theme.textTheme.titleSmall?.copyWith(color: color)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: amount(before == null ? '' : formatRupeesCompact(before), theme.textTheme.bodySmall),
            ),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(revisionsProvider.notifier).bumpAll();
          try {
            await ref.read(monthTotalsProvider(month).future);
          } catch (_) {
            // Shown on the card, with Retry.
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(month.label, style: theme.textTheme.titleSmall),
                    if (totals.hasError && t == null)
                      LoadError(
                        compact: true,
                        message: describeError(totals.error!),
                        onRetry: () => ref.invalidate(monthTotalsProvider(month)),
                      )
                    else ...[
                      // The number that matters most: spent so far this month.
                      Text('Spent this month', style: theme.textTheme.labelMedium),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          t == null ? '…' : formatRupeesCompact(t.expensePaise),
                          key: const Key('dashboard-spent'),
                          maxLines: 1,
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(color: kExpenseColor, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(children: [
                        const Spacer(flex: 4),
                        Expanded(
                            flex: 5,
                            child: Text('This month', textAlign: TextAlign.right, style: theme.textTheme.labelSmall)),
                        const SizedBox(width: 8),
                        Expanded(
                            flex: 5,
                            child: Text('Last month', textAlign: TextAlign.right, style: theme.textTheme.labelSmall)),
                      ]),
                      const Divider(height: 8),
                      row('Spent', t?.expensePaise, t?.lastExpensePaise, kExpenseColor),
                      row('Income', t?.incomePaise, t?.lastIncomePaise, kIncomeColor),
                      row('Net', t?.netPaise, t == null ? null : t.lastIncomePaise - t.lastExpensePaise,
                          theme.colorScheme.onSurface),
                    ],
                  ],
                ),
              ),
            ),
            if ((t?.uncategorizedCount ?? 0) > 0)
              Card(
                color: kUncategorizedColor.withValues(alpha: 0.1),
                child: ListTile(
                  key: const Key('dashboard-uncategorized'),
                  leading: const UncategorizedAvatar(size: 30),
                  title: Text('${t!.uncategorizedCount} uncategorized this month'),
                  subtitle: const Text('Open one and pick a category. Ventrafin learns from it.'),
                  // Straight to this month's Uncategorized entries.
                  onTap: () {
                    ref.read(selectedMonthProvider.notifier).set(month);
                    ref.read(txnSearchProvider.notifier).close();
                    ref.read(txnFilterProvider.notifier).set(const TxnFilter.uncategorized());
                    context.go('/transactions');
                  },
                ),
              ),
            // The actions stay near the top, whatever the breakdown's height.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('dashboard-add'),
                    onPressed: () => context.go('/add'),
                    icon: const Icon(Icons.add),
                    label: const Text("Add today's expenses"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/transactions'),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Transactions'),
                  ),
                ),
              ]),
            ),
            CategoryBreakdownCard(month: month),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('dashboard-reports'),
              // Pushed over the tabs, so back returns here.
              onPressed: () => context.push('/dashboard/reports'),
              icon: const Icon(Icons.bar_chart),
              label: const Text('Reports: past months and trends'),
            ),
          ],
        ),
      ),
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String title, String subtitle, String path) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(path),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(children: [
        tile(Icons.category_outlined, 'Categories', 'Expense and income categories', '/more/categories'),
        tile(Icons.account_balance_wallet_outlined, 'Accounts', 'Cash, bank and credit card', '/more/accounts'),
        tile(Icons.bar_chart, 'Reports', 'Any month by category, 6- and 12-month trends', '/more/reports'),
        tile(Icons.settings_outlined, 'Settings', 'Reminders, theme, app lock, sign out', '/more/settings'),
      ]),
    );
  }
}
