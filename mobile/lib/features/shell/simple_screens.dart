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

/// Dashboard: this month's headline numbers (from `get_month_totals`), the
/// spending-by-category breakdown, and quick actions. Past months and
/// trends are on the Reports screen.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = YearMonth.of(indiaToday(ref.watch(clockProvider)));
    final totals = ref.watch(monthTotalsProvider(month));
    final theme = Theme.of(context);
    final t = totals.value;

    Widget row(String label, int? now, int? before, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            SizedBox(
              width: 120,
              child: Text(now == null ? '…' : formatRupees(now),
                  textAlign: TextAlign.right, style: theme.textTheme.titleSmall?.copyWith(color: color)),
            ),
            SizedBox(
              width: 110,
              child: Text(before == null ? '' : formatRupeesCompact(before),
                  textAlign: TextAlign.right, style: theme.textTheme.bodySmall),
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
                    Row(children: [
                      Expanded(child: Text(month.label, style: theme.textTheme.titleMedium)),
                      SizedBox(
                          width: 120,
                          child: Text('This month', textAlign: TextAlign.right, style: theme.textTheme.labelSmall)),
                      SizedBox(
                          width: 110,
                          child: Text('Last month', textAlign: TextAlign.right, style: theme.textTheme.labelSmall)),
                    ]),
                    const Divider(),
                    if (totals.hasError && t == null)
                      LoadError(
                        compact: true,
                        message: describeError(totals.error!),
                        onRetry: () => ref.invalidate(monthTotalsProvider(month)),
                      )
                    else ...[
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
            CategoryBreakdownCard(month: month),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
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
