import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/india_time.dart';
import '../../core/money.dart';
import '../../core/month_bar.dart';
import '../../core/offline_banner.dart';
import '../../core/category_style.dart';
import '../../core/theme.dart';
import '../../core/visual_badges.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../entry/edit_transaction_screen.dart';
import 'txn_filter.dart';

/// Dense, date-grouped list for one month, or (while searching) for every
/// month. Filters narrow it to a type and/or a category, Uncategorized
/// included; the same menu sorts it by date or amount. Updates live via
/// Realtime.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late final TextEditingController _searchText;

  @override
  void initState() {
    super.initState();
    _searchText = TextEditingController(text: ref.read(txnSearchProvider) ?? '');
  }

  @override
  void dispose() {
    _searchText.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _searchText.clear();
    ref.read(txnSearchProvider.notifier).close();
  }

  @override
  Widget build(BuildContext context) {
    // Closed from elsewhere (the Dashboard's Uncategorized card): empty the box.
    ref.listen(txnSearchProvider, (_, next) {
      if (next == null && _searchText.text.isNotEmpty) _searchText.clear();
    });
    final search = ref.watch(txnSearchProvider);
    final searchOpen = search != null;
    final query = search?.trim() ?? '';
    final filter = ref.watch(txnFilterProvider);
    final sort = ref.watch(txnSortProvider);
    final month = ref.watch(selectedMonthProvider);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider).value ?? const <Category>[];
    final accountsById = {for (final a in accounts) a.id: a};
    final categoriesById = {for (final c in categories) c.id: c};
    final thisMonth = YearMonth.of(indiaToday(ref.watch(clockProvider)));
    final theme = Theme.of(context);
    final fg = theme.appBarTheme.foregroundColor ?? theme.colorScheme.onPrimary;

    // A search looks through every month; otherwise the chosen month.
    final Widget list;
    Widget? status;
    if (query.isNotEmpty) {
      final allAsync = ref.watch(allTransactionsProvider);
      final matches = allAsync.value
          ?.where((t) =>
              filter.matches(t) && txnMatchesSearch(t, query, accounts: accountsById, categories: categoriesById))
          .toList();
      status = _StatusLine(
        key: const Key('search-status'),
        text: matches == null
            ? 'Searching all months…'
            : '${matches.length} ${matches.length == 1 ? 'match' : 'matches'} in all months',
      );
      list = switch (allAsync) {
        AsyncValue(hasValue: true) when matches!.isEmpty => _NoMatches(
            text: filter.isActive ? 'Nothing matches "$query" with these filters.' : 'Nothing matches "$query".',
            onClear: filter.isActive ? ref.read(txnFilterProvider.notifier).clear : null,
          ),
        AsyncValue(hasValue: true) => RefreshIndicator(
            onRefresh: () async {
              ref.read(revisionsProvider.notifier).bumpAll();
              await ref.read(allTransactionsProvider.future);
            },
            child: _GroupedList(txns: matches!, sort: sort, accounts: accountsById, categories: categoriesById),
          ),
        AsyncValue(:final error?) => LoadError(
            message: describeError(error),
            onRetry: () => ref.invalidate(allTransactionsProvider),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    } else {
      final txnsAsync = ref.watch(monthTransactionsProvider(month));
      final shown = txnsAsync.value?.where(filter.matches).toList();
      list = switch (txnsAsync) {
        AsyncValue(:final value?) when value.isEmpty => _Empty(month: month),
        AsyncValue(hasValue: true) when shown!.isEmpty => _NoMatches(
            text: 'No transactions in ${month.label} match these filters.',
            onClear: ref.read(txnFilterProvider.notifier).clear,
          ),
        AsyncValue(hasValue: true) => RefreshIndicator(
            onRefresh: () async {
              ref.read(revisionsProvider.notifier).bumpAll();
              await ref.read(monthTransactionsProvider(month).future);
            },
            child: _GroupedList(txns: shown!, sort: sort, accounts: accountsById, categories: categoriesById),
          ),
        AsyncValue(:final error?) => LoadError(
            message: describeError(error),
            onRetry: () => ref.invalidate(monthTransactionsProvider(month)),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }

    // Back closes the search first (and then, from the tab's first screen,
    // goes to the Dashboard).
    return PopScope(
      canPop: !searchOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        appBar: AppBar(
          title: searchOpen
              ? TextField(
                  key: const Key('txn-search'),
                  controller: _searchText,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  cursorColor: fg,
                  style: theme.textTheme.titleMedium?.copyWith(color: fg),
                  decoration: InputDecoration(
                    hintText: 'Search all months',
                    hintStyle: theme.textTheme.titleMedium?.copyWith(color: fg.withValues(alpha: 0.75)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: ref.read(txnSearchProvider.notifier).setText,
                )
              : const Text('Transactions'),
          actions: [
            if (searchOpen)
              IconButton(
                key: const Key('txn-search-close'),
                tooltip: 'Close search',
                icon: const Icon(Icons.close),
                onPressed: _closeSearch,
              )
            else
              IconButton(
                key: const Key('txn-search-open'),
                tooltip: 'Search all months',
                icon: const Icon(Icons.search),
                onPressed: ref.read(txnSearchProvider.notifier).open,
              ),
            _FilterMenu(filter: filter, sort: sort, categories: categories, color: fg),
          ],
          bottom: query.isNotEmpty
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(44),
                  child: MonthBar(
                    month: month,
                    canGoForward: month.compareTo(thisMonth) < 0,
                    onChanged: ref.read(selectedMonthProvider.notifier).set,
                  ),
                ),
        ),
        body: Column(
          children: [
            if (query.isEmpty)
              _MonthSummary(
                month: month,
                onUncategorized: () => ref.read(txnFilterProvider.notifier).set(const TxnFilter.uncategorized()),
              ),
            ?status,
            if (filter.isActive || sort != TxnSort.newest)
              _ActiveFilters(filter: filter, sort: sort, categories: categories),
            const Divider(height: 1),
            Expanded(child: list),
          ],
        ),
      ),
    );
  }
}

/// Month headline from Postgres (`get_month_totals`), not summed on the phone.
/// Tapping a non-zero Uncategorized count shows just those entries.
class _MonthSummary extends ConsumerWidget {
  const _MonthSummary({required this.month, required this.onUncategorized});

  final YearMonth month;
  final VoidCallback onUncategorized;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(monthTotalsProvider(month)).value;
    final style = Theme.of(context).textTheme.bodySmall;
    Widget cell(String label, String value, {Color? color}) => Column(children: [
          Text(label, style: style),
          Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color)),
        ]);
    final uncategorized = totals?.uncategorizedCount ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: cell('Spent', totals == null ? '…' : formatRupeesCompact(totals.expensePaise),
                color: kExpenseColor),
          ),
          Expanded(
            child: cell('Income', totals == null ? '…' : formatRupeesCompact(totals.incomePaise),
                color: kIncomeColor),
          ),
          Expanded(child: cell('Net', totals == null ? '…' : formatRupeesCompact(totals.netPaise))),
          Expanded(
            child: uncategorized > 0
                ? Tooltip(
                    message: 'Show only the uncategorized ones',
                    child: InkWell(
                      key: const Key('summary-uncategorized'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: onUncategorized,
                      child: cell('Uncategorized', '$uncategorized', color: kUncategorizedInkColor),
                    ),
                  )
                : cell('Uncategorized', totals == null ? '…' : '0'),
          ),
        ],
      ),
    );
  }
}

/// One line under the app bar, e.g. "12 matches in all months".
class _StatusLine extends StatelessWidget {
  const _StatusLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

/// The app bar's filter button: one menu with the order (newest, oldest,
/// largest or smallest amount first), the type (All / Expenses / Income /
/// Transfers) and the category (Uncategorized and every category of the
/// chosen type, archived ones last since only older entries use them).
class _FilterMenu extends ConsumerWidget {
  const _FilterMenu({required this.filter, required this.sort, required this.categories, required this.color});

  final TxnFilter filter;
  final TxnSort sort;
  final List<Category> categories;
  final Color color;

  static const _sortIcons = {
    TxnSort.newest: Icons.arrow_downward,
    TxnSort.oldest: Icons.arrow_upward,
    TxnSort.largest: Icons.trending_down,
    TxnSort.smallest: Icons.trending_up,
  };

  static const _types = <(TxnType?, String)>[
    (null, 'All types'),
    (TxnType.expense, 'Expenses'),
    (TxnType.income, 'Income'),
    (TxnType.transfer, 'Transfers'),
  ];

  // Menu values: 'sort:<name>', 'type:<db|all>' or 'category:<id|all|uncategorized>'.
  void _apply(WidgetRef ref, String value) {
    final notifier = ref.read(txnFilterProvider.notifier);
    final (kind, arg) = (value.split(':').first, value.split(':').last);
    if (kind == 'sort') {
      ref.read(txnSortProvider.notifier).set(TxnSort.values.byName(arg));
      return;
    }
    if (kind == 'type') {
      final type = arg == 'all' ? null : TxnType.fromDb(arg);
      // Transfers have no category, so picking them drops the category.
      notifier.set(type == TxnType.transfer ? const TxnFilter(type: TxnType.transfer) : filter.withType(type));
      return;
    }
    // A category means expenses or income, so it replaces Transfers.
    final base = filter.type == TxnType.transfer ? const TxnFilter() : filter;
    notifier.set(switch (arg) {
      'all' => base.withCategory(),
      'uncategorized' => base.withCategory(uncategorized: true),
      _ => base.withCategory(categoryId: arg),
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kinds = switch (filter.type) {
      TxnType.expense => [TxnType.expense],
      TxnType.income => [TxnType.income],
      _ => [TxnType.expense, TxnType.income],
    };
    List<Category> of(TxnType kind) => categories.where((c) => c.kind == kind).toList()
      ..sort((a, b) {
        if (a.archived != b.archived) return a.archived ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    PopupMenuEntry<String> heading(String text) => PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: Text(text, style: theme.textTheme.labelMedium),
        );
    PopupMenuEntry<String> item(String value, bool checked, Widget leading, String text) => CheckedPopupMenuItem(
          key: Key('filter-$value'.replaceFirst(':', '-')),
          value: value,
          checked: checked,
          height: 40,
          child: Row(children: [leading, const SizedBox(width: 10), Flexible(child: Text(text))]),
        );

    return PopupMenuButton<String>(
      key: const Key('txn-filter'),
      tooltip: 'Sort, or filter by type or category',
      icon: Badge(
        isLabelVisible: filter.isActive || sort != TxnSort.newest,
        smallSize: 8,
        child: Icon(filter.isActive ? Icons.filter_alt : Icons.filter_alt_outlined, color: color),
      ),
      onSelected: (v) => _apply(ref, v),
      itemBuilder: (context) => [
        heading('Sort'),
        for (final s in TxnSort.values)
          item('sort:${s.name}', sort == s, Icon(_sortIcons[s], size: 20), s.label),
        const PopupMenuDivider(),
        heading('Type'),
        for (final (type, label) in _types)
          item('type:${type?.db ?? 'all'}', filter.type == type,
              Icon(type?.icon ?? Icons.all_inclusive, size: 20), label),
        const PopupMenuDivider(),
        heading('Category'),
        item('category:all', !filter.hasCategory, const Icon(Icons.all_inclusive, size: 20), 'All categories'),
        item('category:uncategorized', filter.uncategorized, const UncategorizedAvatar(size: 22), 'Uncategorized'),
        for (final kind in kinds) ...[
          heading('${kind.label} categories'),
          for (final c in of(kind))
            item('category:${c.id}', filter.categoryId == c.id, CategoryAvatar(category: c, size: 22),
                c.archived ? '${c.name} (archived)' : c.name),
        ],
      ],
    );
  }
}

/// What the list is narrowed to, e.g. "Expenses · Uncategorized", and the
/// order when it isn't the usual newest first, with Clear (which resets
/// both). Only shown while one is on, so the plain list stays as dense.
class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.filter, required this.sort, required this.categories});

  final TxnFilter filter;
  final TxnSort sort;
  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final category = categories.where((c) => c.id == filter.categoryId).firstOrNull;
    final parts = [
      if (filter.type != null)
        switch (filter.type!) {
          TxnType.expense => 'Expenses',
          TxnType.income => 'Income',
          TxnType.transfer => 'Transfers',
        },
      if (filter.uncategorized) 'Uncategorized',
      if (category != null) category.archived ? '${category.name} (archived)' : category.name,
    ];
    return Container(
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      child: Row(
        children: [
          Icon(
            filter.isActive ? Icons.filter_alt : Icons.sort,
            size: 16,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                if (sort != TxnSort.newest) sort.label,
                if (parts.isNotEmpty) 'Showing only: ${parts.join(' · ')}',
              ].join(' · '),
              key: const Key('active-filters'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          TextButton(
            key: const Key('filter-clear'),
            onPressed: () {
              ref.read(txnFilterProvider.notifier).clear();
              ref.read(txnSortProvider.notifier).set(TxnSort.newest);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

/// A month, or a search, with entries but none that pass the filters.
class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.text, required this.onClear});

  final String text;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_list_off, size: 40),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            if (onClear != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onClear, child: const Text('Clear filters')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Newest or oldest first: grouped by day, each day with its count and
/// spending. By amount: one flat list, each row with its date.
class _GroupedList extends ConsumerWidget {
  const _GroupedList({required this.txns, required this.sort, required this.accounts, required this.categories});

  final List<Txn> txns;
  final TxnSort sort;
  final Map<String, Account> accounts;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenTxnIdsProvider);
    final sorted = sortTxns(txns.where((t) => !hidden.contains(t.id)), sort);
    final clock = ref.read(clockProvider);

    final children = <Widget>[];
    if (sort.byAmount) {
      final today = indiaToday(clock);
      for (final t in sorted) {
        children.add(_TxnRow(txn: t, accounts: accounts, categories: categories, today: today));
        children.add(const Divider(height: 1, indent: 12));
      }
    } else {
      // Days come out in the list's order (newest or oldest first).
      final byDay = groupBy(sorted, (Txn t) => t.date);
      for (final MapEntry(key: day, value: items) in byDay.entries) {
        final spent = items.where((t) => t.type == TxnType.expense).fold<int>(0, (s, t) => s + t.amountPaise);
        children.add(_DayHeader(label: friendlyDate(day, clock: clock), spentPaise: spent, count: items.length));
        for (final t in items) {
          children.add(_TxnRow(txn: t, accounts: accounts, categories: categories));
          children.add(const Divider(height: 1, indent: 12));
        }
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
  const _TxnRow({required this.txn, required this.accounts, required this.categories, this.today});

  final Txn txn;
  final Map<String, Account> accounts;
  final Map<String, Category> categories;

  /// Set when the list isn't grouped by day: the row shows its own date
  /// (with the year when it isn't this year's).
  final DateTime? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = txn;
    final category = t.categoryId == null ? null : categories[t.categoryId];

    final (amountText, amountColor) = switch (t.type) {
      TxnType.expense => (formatRupees(t.amountPaise), kExpenseColor),
      TxnType.income => ('+${formatRupees(t.amountPaise)}', kIncomeColor),
      TxnType.transfer => (formatRupees(t.amountPaise), kTransferColor),
    };

    // The circle already says which category; the text label stays for
    // reading, and Uncategorized keeps its attention-grabbing chip.
    final Widget categoryLabel = switch (t.type) {
      TxnType.transfer => const _Label(text: 'Transfer', color: kTransferColor),
      _ when t.categoryId == null => const _UncategorizedChip(),
      _ => _Label(text: category?.name ?? '…', color: category?.color ?? kTransferColor),
    };

    final detailStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final account = accounts[t.accountId];
    final toAccount = t.toAccountId == null ? null : accounts[t.toAccountId];

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
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          child: Row(
            children: [
              TxnAvatar(txn: t, category: category, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (t.description.isNotEmpty) ...[
                          MerchantBadge(description: t.description),
                          const SizedBox(width: 5),
                        ],
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
                        if (today case final today?) ...[
                          Text(
                            DateFormat(t.date.year == today.year ? 'd MMM' : 'd MMM yyyy').format(t.date),
                            key: Key('txn-date-${t.id}'),
                            style: detailStyle,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(child: categoryLabel),
                        if (t.autoCategorized) ...[
                          const SizedBox(width: 4),
                          Text(
                            'auto',
                            key: Key('txn-auto-${t.id}'),
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                        const SizedBox(width: 8),
                        const Spacer(),
                        _Detail(
                          icon: account?.type.icon ?? Icons.account_balance_wallet_outlined,
                          text: account?.name ?? '…',
                          style: detailStyle,
                        ),
                        if (t.toAccountId != null) ...[
                          Icon(Icons.arrow_forward, size: 12, color: detailStyle?.color),
                          const SizedBox(width: 2),
                          _Detail(
                            icon: toAccount?.type.icon ?? Icons.account_balance_wallet_outlined,
                            text: toAccount?.name ?? '…',
                            style: detailStyle,
                          ),
                        ],
                        // Not for transfers: the two accounts already fill
                        // the line on a 360 dp phone.
                        if (t.paymentMethod != null && t.type != TxnType.transfer) ...[
                          const SizedBox(width: 6),
                          _Detail(icon: t.paymentMethod!.icon, text: t.paymentMethod!.label, style: detailStyle),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Category name in its colour (darkened when the colour is pale).
class _Label extends StatelessWidget {
  const _Label({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: readableTextColor(color),
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _UncategorizedChip extends StatelessWidget {
  const _UncategorizedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: kUncategorizedColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: kUncategorizedColor.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        'Uncategorized',
        maxLines: 1,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Color.lerp(kUncategorizedColor, Colors.black, 0.35)),
      ),
    );
  }
}

/// Small icon + text for the account / payment method.
class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text, required this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: style?.color),
        const SizedBox(width: 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 88),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      ],
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
