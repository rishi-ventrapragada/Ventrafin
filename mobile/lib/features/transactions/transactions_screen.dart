import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/india_time.dart';
import '../../core/money.dart';
import '../../core/offline_banner.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../entry/edit_transaction_screen.dart';

/// Dense, date-grouped list for one month. Updates live via Realtime.
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final txnsAsync = ref.watch(monthTransactionsProvider(month));
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final thisMonth = YearMonth.of(indiaToday(ref.watch(clockProvider)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _MonthBar(month: month, canGoForward: month.compareTo(thisMonth) < 0),
        ),
      ),
      body: Column(
        children: [
          _MonthSummary(month: month),
          const Divider(height: 1),
          Expanded(
            child: switch (txnsAsync) {
              AsyncValue(:final value?) => value.isEmpty
                  ? _Empty(month: month)
                  : RefreshIndicator(
                      onRefresh: () async {
                        ref.read(revisionsProvider.notifier).bumpAll();
                        await ref.read(monthTransactionsProvider(month).future);
                      },
                      child: _GroupedList(txns: value, accounts: accounts, categories: categories),
                    ),
              AsyncValue(:final error?) => LoadError(
                  message: describeError(error),
                  onRetry: () => ref.invalidate(monthTransactionsProvider(month)),
                ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends ConsumerWidget {
  const _MonthBar({required this.month, required this.canGoForward});

  final YearMonth month;
  final bool canGoForward;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<YearMonth>(
      context: context,
      builder: (context) => _MonthPickerDialog(initial: month),
    );
    if (picked != null) ref.read(selectedMonthProvider.notifier).set(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final notifier = ref.read(selectedMonthProvider.notifier);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          color: onPrimary,
          icon: const Icon(Icons.chevron_left),
          onPressed: () => notifier.set(month.previous),
        ),
        Expanded(
          child: TextButton.icon(
            key: const Key('month-picker'),
            style: TextButton.styleFrom(foregroundColor: onPrimary),
            onPressed: () => _pick(context, ref),
            icon: const Icon(Icons.calendar_month, size: 18),
            label: Text(month.label, style: const TextStyle(fontSize: 16)),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          color: onPrimary,
          disabledColor: onPrimary.withValues(alpha: 0.3),
          icon: const Icon(Icons.chevron_right),
          onPressed: canGoForward ? () => notifier.set(month.next) : null,
        ),
      ],
    );
  }
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initial});

  final YearMonth initial;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return AlertDialog(
      title: Row(
        children: [
          IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('$_year', textAlign: TextAlign.center)),
          IconButton(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right)),
        ],
      ),
      content: SizedBox(
        width: 280,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 4,
          childAspectRatio: 1.6,
          children: [
            for (var m = 1; m <= 12; m++)
              TextButton(
                style: widget.initial == YearMonth(_year, m)
                    ? TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                    : null,
                onPressed: () => Navigator.pop(context, YearMonth(_year, m)),
                child: Text(names[m - 1]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Month headline from Postgres (`get_month_totals`), not summed on the phone.
class _MonthSummary extends ConsumerWidget {
  const _MonthSummary({required this.month});

  final YearMonth month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(monthTotalsProvider(month)).value;
    final style = Theme.of(context).textTheme.bodySmall;
    Widget cell(String label, String value, {Color? color}) => Expanded(
          child: Column(children: [
            Text(label, style: style),
            Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          cell('Spent', totals == null ? '…' : formatRupeesCompact(totals.expensePaise), color: kExpenseColor),
          cell('Income', totals == null ? '…' : formatRupeesCompact(totals.incomePaise), color: kIncomeColor),
          cell('Net', totals == null ? '…' : formatRupeesCompact(totals.netPaise)),
          cell(
            'Uncategorized',
            totals == null ? '…' : '${totals.uncategorizedCount}',
            color: (totals?.uncategorizedCount ?? 0) > 0 ? kUncategorizedColor : null,
          ),
        ],
      ),
    );
  }
}

class _GroupedList extends ConsumerWidget {
  const _GroupedList({required this.txns, required this.accounts, required this.categories});

  final List<Txn> txns;
  final List<Account> accounts;
  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenTxnIdsProvider);
    final byDay = groupBy(txns.where((t) => !hidden.contains(t.id)), (Txn t) => t.date);
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final clock = ref.read(clockProvider);
    final accountsById = {for (final a in accounts) a.id: a};
    final categoriesById = {for (final c in categories) c.id: c};

    final children = <Widget>[];
    for (final day in days) {
      final items = byDay[day]!;
      final spent = items.where((t) => t.type == TxnType.expense).fold<int>(0, (s, t) => s + t.amountPaise);
      children.add(_DayHeader(label: friendlyDate(day, clock: clock), spentPaise: spent, count: items.length));
      for (final t in items) {
        children.add(_TxnRow(txn: t, accounts: accountsById, categories: categoriesById));
        children.add(const Divider(height: 1, indent: 12));
      }
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.spentPaise, required this.count});

  final String label;
  final int spentPaise;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
          Text(
            '$count · spent ${formatRupeesCompact(spentPaise)}',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _TxnRow extends ConsumerWidget {
  const _TxnRow({required this.txn, required this.accounts, required this.categories});

  final Txn txn;
  final Map<String, Account> accounts;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = txn;
    final account = accounts[t.accountId]?.name ?? '…';
    final toAccount = t.toAccountId == null ? null : (accounts[t.toAccountId]?.name ?? '…');
    final category = t.categoryId == null ? null : categories[t.categoryId];

    final (amountText, amountColor) = switch (t.type) {
      TxnType.expense => (formatRupees(t.amountPaise), kExpenseColor),
      TxnType.income => ('+${formatRupees(t.amountPaise)}', kIncomeColor),
      TxnType.transfer => (formatRupees(t.amountPaise), kTransferColor),
    };

    final Widget categoryChip = switch (t.type) {
      TxnType.transfer => _Tag(text: 'Transfer', color: kTransferColor, icon: Icons.swap_horiz),
      _ when category == null => const _Tag(text: 'Uncategorized', color: kUncategorizedColor, icon: Icons.help_outline),
      _ => _Tag(text: category.name, color: category.color, dot: true),
    };

    final details = [
      toAccount == null ? account : '$account → $toAccount',
      if (t.paymentMethod != null) t.paymentMethod!.label,
    ].join(' · ');

    return Dismissible(
      key: ValueKey('txn-${t.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        if (!await confirmDelete(context, t)) return false;
        try {
          await ref.read(repositoryProvider).deleteTransaction(t.id);
          ref.read(hiddenTxnIdsProvider.notifier).hide(t.id);
          ref.read(revisionsProvider.notifier).bump(['transactions']);
          return true;
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: theme.colorScheme.error,
              content: Text('Not deleted. ${describeError(e)}'),
            ));
          }
          return false;
        }
      },
      child: InkWell(
        onTap: () => context.push('/transactions/${t.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.description.isEmpty ? '(no description)' : t.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: t.description.isEmpty ? FontStyle.italic : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    amountText,
                    style: theme.textTheme.bodyMedium?.copyWith(color: amountColor, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  categoryChip,
                  if (t.autoCategorized) ...[
                    const SizedBox(width: 4),
                    Text('auto', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.icon, this.dot = false});

  final String text;
  final Color color;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) Icon(Icons.circle, size: 8, color: color),
          if (icon != null) Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Color.lerp(color, Colors.black, 0.35)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.month});

  final YearMonth month;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long, size: 48),
          const SizedBox(height: 8),
          Text('No transactions in ${month.label}.'),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.go('/add'),
            icon: const Icon(Icons.add),
            label: const Text('Add one'),
          ),
        ],
      ),
    );
  }
}
