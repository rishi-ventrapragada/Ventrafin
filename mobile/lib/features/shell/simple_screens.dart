import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/india_time.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/visual_badges.dart';
import '../../data/providers.dart';
import '../dashboard/category_breakdown.dart';

/// Dashboard: this month's headline numbers (from `get_month_totals`), the
/// spending-by-category breakdown, and quick actions. Fuller reports come in
/// phase 5.
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
      body: ListView(
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
                    SizedBox(width: 120, child: Text('This month', textAlign: TextAlign.right, style: theme.textTheme.labelSmall)),
                    SizedBox(width: 110, child: Text('Last month', textAlign: TextAlign.right, style: theme.textTheme.labelSmall)),
                  ]),
                  const Divider(),
                  row('Spent', t?.expensePaise, t?.lastExpensePaise, kExpenseColor),
                  row('Income', t?.incomePaise, t?.lastIncomePaise, kIncomeColor),
                  row('Net', t?.netPaise, t == null ? null : t.lastIncomePaise - t.lastExpensePaise, theme.colorScheme.onSurface),
                  if (totals.hasError && t == null)
                    Text("Couldn't load totals.", style: TextStyle(color: theme.colorScheme.error)),
                ],
              ),
            ),
          ),
          if ((t?.uncategorizedCount ?? 0) > 0)
            Card(
              color: kUncategorizedColor.withValues(alpha: 0.1),
              child: ListTile(
                leading: const UncategorizedAvatar(size: 30),
                title: Text('${t!.uncategorizedCount} uncategorized this month'),
                subtitle: const Text('Open one and pick a category. Ventrafin learns from it.'),
                onTap: () => context.go('/transactions'),
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
          const SizedBox(height: 16),
          Text('Month-by-month reports are coming in a later update.',
              style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Placeholder for sections built in later phases.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, required this.icon, required this.note});

  final String title;
  final IconData icon;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(note, textAlign: TextAlign.center),
          ]),
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
        tile(Icons.bar_chart, 'Reports', 'Month-by-month comparisons', '/more/reports'),
        tile(Icons.settings_outlined, 'Settings', 'App lock, fingerprint, sign out', '/more/settings'),
      ]),
    );
  }
}

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: switch (accounts) {
        AsyncValue(:final value?) => ListView(children: [
            for (final a in value)
              ListTile(
                leading: AccountAvatar(type: a.type, size: 34),
                title: Text(a.name),
                subtitle: Text(a.type.label),
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Adding and renaming accounts is coming in a later update.'),
            ),
          ]),
        AsyncValue(:final error?) => Center(child: Text('Could not load accounts: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
