import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventrafin/core/month_bar.dart';
import 'package:ventrafin/core/theme.dart';
import 'package:ventrafin/data/models.dart';
import 'package:ventrafin/data/providers.dart';
import 'package:ventrafin/features/transactions/transactions_screen.dart';
import 'package:ventrafin/features/transactions/txn_filter.dart';

import 'support/fake_repository.dart';

/// September 2026 (the month on screen) and three older months.
FakeRepository _repo() {
  final september = [
    testTxn('t1', description: 'Swiggy dinner', date: DateTime(2026, 9, 20)),
    testTxn('t2', description: 'Uber', categoryId: null, date: DateTime(2026, 9, 18)),
    testTxn('t3',
        description: 'Salary Sept', type: TxnType.income, categoryId: 'cat-salary', paymentMethod: null,
        date: DateTime(2026, 9, 1)),
    testTxn('t4',
        description: 'ATM', type: TxnType.transfer, accountId: 'acc-bank', toAccountId: 'acc-cash',
        paymentMethod: null, date: DateTime(2026, 9, 5)),
  ];
  return FakeRepository()
    ..transactions = september
    ..allTransactions = [
      ...september,
      testTxn('a1', description: 'Swiggy lunch', amountPaise: 45000, date: DateTime(2026, 7, 3)),
      testTxn('a2', description: 'DMart', categoryId: 'cat-groc', date: DateTime(2025, 12, 30)),
      testTxn('a3',
          description: 'Card bill', type: TxnType.transfer, accountId: 'acc-bank', toAccountId: 'acc-cc',
          paymentMethod: null, date: DateTime(2026, 8, 10)),
    ]
    ..totals = const MonthTotals(
        expensePaise: 24690, lastExpensePaise: 0, incomePaise: 0, lastIncomePaise: 0, uncategorizedCount: 1);
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('txn-search')), text);
  await tester.pumpAndSettle();
}

Future<void> _pickFilter(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(const Key('txn-filter')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Set<String> _shownIds(WidgetTester tester) => {
      for (final e in find.byType(Dismissible).evaluate())
        ((e.widget as Dismissible).key! as ValueKey<String>).value.replaceFirst('txn-', ''),
    };

void main() {
  group('search', () {
    testWidgets('looks through every month: description, category, account and amount', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const TransactionsScreen(), repo: _repo());
      expect(repo.betweenCalls, isEmpty, reason: 'nothing fetched until a search is typed');

      await tester.tap(find.byKey(const Key('txn-search-open')));
      await tester.pumpAndSettle();
      expect(repo.betweenCalls, isEmpty);

      await _search(tester, 'swiggy');
      expect(find.text('2 matches in all months'), findsOneWidget);
      expect(_shownIds(tester), {'t1', 'a1'});
      expect(find.byType(MonthBar), findsNothing, reason: 'the search is not limited to a month');
      expect(repo.betweenCalls, hasLength(1));

      await _search(tester, 'groceries'); // a category name
      expect(_shownIds(tester), {'a2'});
      expect(find.text('1 match in all months'), findsOneWidget);

      await _search(tester, 'credit card'); // the destination account
      expect(_shownIds(tester), {'a3'});

      await _search(tester, '450'); // an amount
      expect(_shownIds(tester), {'a1'});

      await _search(tester, 'zzz');
      expect(find.text('Nothing matches "zzz".'), findsOneWidget);
      expect(repo.betweenCalls, hasLength(1), reason: 'typing filters the rows already fetched');

      // Closing the search returns to the month.
      await tester.tap(find.byKey(const Key('txn-search-close')));
      await tester.pumpAndSettle();
      expect(find.byType(MonthBar), findsOneWidget);
      expect(find.byKey(const Key('search-status')), findsNothing);
      expect(_shownIds(tester), {'t1', 't2', 't3', 't4'});
    });

    testWidgets('results refresh when transactions change (e.g. on the web)', (tester) async {
      final (repo, _) = await pumpWithFakes(tester, const TransactionsScreen(), repo: _repo());
      await tester.tap(find.byKey(const Key('txn-search-open')));
      await tester.pumpAndSettle();
      await _search(tester, 'swiggy');
      expect(find.text('2 matches in all months'), findsOneWidget);

      repo.allTransactions = [
        ...repo.allTransactions!,
        testTxn('a4', description: 'Swiggy Instamart', date: DateTime(2026, 6, 2)),
      ];
      ProviderScope.containerOf(tester.element(find.byType(TransactionsScreen)))
          .read(revisionsProvider.notifier)
          .bump(['transactions']);
      await tester.pumpAndSettle();
      expect(find.text('3 matches in all months'), findsOneWidget);
      expect(repo.betweenCalls, hasLength(2));
    });

    testWidgets('Android back closes the search before anything else', (tester) async {
      await pumpWithFakes(tester, const TransactionsScreen(), repo: _repo());
      await tester.tap(find.byKey(const Key('txn-search-open')));
      await tester.pumpAndSettle();
      await _search(tester, 'swiggy');

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('txn-search')), findsNothing);
      expect(find.byType(MonthBar), findsOneWidget);
    });

    testWidgets('a failed search load says why, with Retry', (tester) async {
      final repo = _repo();
      await pumpWithFakes(tester, const TransactionsScreen(), repo: repo);
      await tester.tap(find.byKey(const Key('txn-search-open')));
      await tester.pumpAndSettle();
      repo.failNextFetchTransactionsWith = const _ServerError();
      await _search(tester, 'swiggy');
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('2 matches in all months'), findsOneWidget);
    });
  });

  group('filters', () {
    testWidgets('by type, by category, Uncategorized; Clear shows everything again', (tester) async {
      await pumpWithFakes(tester, const TransactionsScreen(), repo: _repo());
      expect(_shownIds(tester), {'t1', 't2', 't3', 't4'});
      expect(find.byKey(const Key('active-filters')), findsNothing, reason: 'no extra line until a filter is on');

      await _pickFilter(tester, 'filter-type-income');
      expect(_shownIds(tester), {'t3'});
      expect(find.text('Showing only: Income'), findsOneWidget);

      await _pickFilter(tester, 'filter-type-transfer');
      expect(_shownIds(tester), {'t4'});

      await _pickFilter(tester, 'filter-type-all');
      await _pickFilter(tester, 'filter-category-uncategorized');
      expect(_shownIds(tester), {'t2'});
      expect(find.text('Showing only: Uncategorized'), findsOneWidget);

      await _pickFilter(tester, 'filter-type-expense');
      await _pickFilter(tester, 'filter-category-cat-food');
      expect(_shownIds(tester), {'t1'});
      expect(find.text('Showing only: Expenses · Food'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter-clear')));
      await tester.pumpAndSettle();
      expect(_shownIds(tester), {'t1', 't2', 't3', 't4'});
    });

    testWidgets('nothing in the month matches: says so, with Clear filters', (tester) async {
      await pumpWithFakes(tester, const TransactionsScreen(), repo: _repo());
      await _pickFilter(tester, 'filter-category-cat-groc');
      expect(find.text('No transactions in September 2026 match these filters.'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(_shownIds(tester), hasLength(4));
    });

    testWidgets('filters apply to search results too', (tester) async {
      await pumpWithFakes(tester, const TransactionsScreen(), repo: _repo());
      await _pickFilter(tester, 'filter-type-transfer');
      await tester.tap(find.byKey(const Key('txn-search-open')));
      await tester.pumpAndSettle();
      await _search(tester, 'bank');
      expect(_shownIds(tester), {'t4', 'a3'});
      expect(find.text('2 matches in all months'), findsOneWidget);
    });

    testWidgets('the Uncategorized count is tappable, in the readable amber, and filters the month',
        (tester) async {
      await pumpWithFakes(tester, const TransactionsScreen(), repo: _repo());
      final count = find.descendant(of: find.byKey(const Key('summary-uncategorized')), matching: find.text('1'));
      expect(tester.widget<Text>(count).style?.color, kUncategorizedInkColor);

      await tester.tap(find.byKey(const Key('summary-uncategorized')));
      await tester.pumpAndSettle();
      expect(_shownIds(tester), {'t2'});
      expect(find.text('Showing only: Uncategorized'), findsOneWidget);
    });
  });

  group('matching rules', () {
    final accounts = {for (final a in FakeRepository().accounts) a.id: a};
    final categories = {for (final c in FakeRepository().categories) c.id: c};
    bool matches(Txn t, String q) => txnMatchesSearch(t, q, accounts: accounts, categories: categories);

    test('text in any of description, category, account; amounts as typed', () {
      final t = testTxn('x', description: 'Zomato order', categoryId: 'cat-food', amountPaise: 125050);
      expect(matches(t, 'ZOMATO'), isTrue);
      expect(matches(t, ' food '), isTrue);
      expect(matches(t, 'cash'), isTrue, reason: 'account name');
      expect(matches(t, '1,250.50'), isTrue);
      expect(matches(t, '₹ 1250.5'), isTrue);
      expect(matches(t, '1250'), isFalse, reason: 'a different amount');
      expect(matches(t, ''), isTrue);
      expect(matches(testTxn('u', categoryId: null), 'uncategorized'), isTrue);
    });

    test('filters: Uncategorized never includes transfers', () {
      const f = TxnFilter.uncategorized();
      expect(f.matches(testTxn('a', categoryId: null)), isTrue);
      expect(f.matches(testTxn('b', type: TxnType.transfer, toAccountId: 'acc-bank')), isFalse);
      expect(f.matches(testTxn('c')), isFalse);
      expect(const TxnFilter(type: TxnType.income).matches(testTxn('d')), isFalse);
    });
  });
}

/// A failure that isn't a network error, so the generic wording shows.
class _ServerError implements Exception {
  const _ServerError();
}
