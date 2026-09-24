import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventrafin/core/india_time.dart';
import 'package:ventrafin/core/theme.dart';
import 'package:ventrafin/data/models.dart';
import 'package:ventrafin/data/providers.dart';
import 'package:ventrafin/data/repository.dart';
import 'package:ventrafin/features/entry/add_screen.dart';

/// 19:00 UTC on 24 Sep = 00:30 IST on 25 Sep: "today" must be the 25th.
final _fixedClock = DateTime.utc(2026, 9, 24, 19, 0);

class FakeRepository implements FinanceRepository {
  final accounts = const [
    Account(id: 'acc-bank', name: 'Bank', type: AccountType.bank),
    Account(id: 'acc-cash', name: 'Cash', type: AccountType.cash),
    Account(id: 'acc-cc', name: 'Credit Card', type: AccountType.credit),
  ];
  final categories = const [
    Category(id: 'cat-food', name: 'Food', kind: TxnType.expense, color: Color(0xFFFB8C00), archived: false),
    Category(id: 'cat-groc', name: 'Groceries', kind: TxnType.expense, color: Color(0xFF43A047), archived: false),
    Category(id: 'cat-salary', name: 'Salary', kind: TxnType.income, color: Color(0xFF00897B), archived: false),
  ];

  /// Successful inserts, in order.
  final inserted = <({String id, TxnDraft draft})>[];

  /// Every insert attempt's id, including failed ones.
  final attemptedIds = <String>[];

  Object? failNextInsertWith;

  @override
  Future<List<Account>> fetchAccounts() async => accounts;

  @override
  Future<List<Category>> fetchCategories() async => categories;

  @override
  Future<Txn> insertTransaction(String id, TxnDraft draft) async {
    attemptedIds.add(id);
    final failure = failNextInsertWith;
    if (failure != null) {
      failNextInsertWith = null;
      throw failure;
    }
    inserted.add((id: id, draft: draft));
    // Imitate the database trigger: "swiggy" -> Food when no category given.
    final auto = draft.categoryId == null &&
        draft.type == TxnType.expense &&
        draft.description.toLowerCase().contains('swiggy');
    final now = DateTime.utc(2026, 9, 24, 19);
    return Txn(
      id: id,
      date: draft.date,
      amountPaise: draft.amountPaise,
      description: draft.description.trim(),
      type: draft.type,
      accountId: draft.accountId,
      toAccountId: draft.toAccountId,
      categoryId: auto ? 'cat-food' : draft.categoryId,
      paymentMethod: draft.paymentMethod,
      autoCategorized: auto,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<List<Txn>> fetchTransactions(YearMonth month) async => const [];

  @override
  Future<Txn?> fetchTransaction(String id) async => null;

  @override
  Future<MonthTotals> fetchMonthTotals(YearMonth month) async => const MonthTotals(
      expensePaise: 0, lastExpensePaise: 0, incomePaise: 0, lastIncomePaise: 0, uncategorizedCount: 0);

  @override
  Future<Txn> updateTransaction(String id, TxnDraft draft) => throw UnimplementedError();

  @override
  Future<void> deleteTransaction(String id) => throw UnimplementedError();

  @override
  Stream<DataChange> watchChanges() => const Stream.empty();
}

Future<(FakeRepository, SharedPreferences)> pumpAddScreen(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  bool online = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(412, 915));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final repo = FakeRepository();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        currentUserIdProvider.overrideWithValue('user-1'),
        clockProvider.overrideWithValue(() => _fixedClock),
        isOnlineProvider.overrideWithValue(online),
      ],
      child: MaterialApp(theme: buildOceanTheme(), home: const AddScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (repo, sharedPrefs);
}

Future<void> typeAmount(WidgetTester tester, String keys) async {
  for (final k in keys.split('')) {
    await tester.tap(find.byKey(Key('keypad-${k == '<' ? 'back' : k}')));
    await tester.pump();
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String amountText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('entry-amount-text'))).data!;

bool chipSelected(WidgetTester tester, String method) =>
    tester.widget<ChoiceChip>(find.byKey(Key('method-$method'))).selected;

void main() {
  testWidgets('batch entry: keypad amount, Save & add another keeps context and confirms what was saved',
      (tester) async {
    final (repo, prefs) = await pumpAddScreen(tester);

    // Keypad is shown first; the amount starts at 0.
    expect(find.byKey(const Key('keypad-1')), findsOneWidget);
    expect(amountText(tester), '0');

    // Date defaults to today *in India* (00:30 IST on the 25th).
    expect(find.text('Today, 25 Sep'), findsOneWidget);

    // Entry 1: ₹1,250 Swiggy dinner, UPI.
    await typeAmount(tester, '1250');
    expect(amountText(tester), '1,250');
    await tester.tap(find.byKey(const Key('keypad-done')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-description')), 'Swiggy dinner');
    await tapVisible(tester, find.byKey(const Key('method-upi')));
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));

    expect(repo.inserted, hasLength(1));
    final first = repo.inserted.single.draft;
    expect(first.amountPaise, 125000);
    expect(first.description, 'Swiggy dinner');
    expect(first.type, TxnType.expense);
    expect(first.accountId, 'acc-cash', reason: 'defaults to the Cash account');
    expect(first.paymentMethod, PaymentMethod.upi);
    expect(toIsoDate(first.date), '2026-09-25');
    expect(first.categoryId, isNull, reason: 'left on Auto so the database categorizes it');

    // Clear confirmation, including the category the database picked.
    expect(find.byKey(const Key('just-saved')), findsOneWidget);
    expect(find.textContaining('1 saved this session'), findsOneWidget);
    expect(find.textContaining('₹1,250.00 · Swiggy dinner · Food (auto) · Cash/UPI'), findsOneWidget);

    // Stays on the screen, ready for the next one: amount and description
    // cleared, keypad back, account / method / date kept.
    expect(amountText(tester), '0');
    expect(find.byKey(const Key('keypad-1')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('entry-description'))).controller!.text, isEmpty);
    expect(chipSelected(tester, 'upi'), isTrue);
    expect(find.text('Today, 25 Sep'), findsOneWidget);

    // Entry 2: ₹99.50 chai. No need to pick the method again.
    await typeAmount(tester, '99.5');
    expect(amountText(tester), '99.5');
    await tester.tap(find.byKey(const Key('keypad-done')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-description')), 'Chai');
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));

    expect(repo.inserted, hasLength(2));
    final second = repo.inserted[1].draft;
    expect(second.amountPaise, 9950);
    expect(second.paymentMethod, PaymentMethod.upi);
    expect(second.accountId, 'acc-cash');
    expect(repo.inserted[0].id, isNot(repo.inserted[1].id), reason: 'each entry gets its own id');
    expect(find.textContaining('2 saved this session · ₹1,349.50 spent'), findsOneWidget);
    expect(find.textContaining('Uncategorized'), findsOneWidget, reason: '"Chai" matched nothing');

    // Last-used account and method are remembered for next time.
    expect(prefs.getString('entry.lastAccountId'), 'acc-cash');
    expect(prefs.getString('entry.lastPaymentMethod'), 'upi');
  });

  testWidgets('validation: amount is required, and payment method is required for expenses', (tester) async {
    final (repo, _) = await pumpAddScreen(tester);

    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(find.text('Enter an amount'), findsOneWidget);
    expect(find.text('Choose how you paid'), findsOneWidget);
    expect(repo.attemptedIds, isEmpty);

    await typeAmount(tester, '100');
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(find.text('Enter an amount'), findsNothing);
    expect(find.text('Choose how you paid'), findsOneWidget);
    expect(repo.attemptedIds, isEmpty, reason: 'nothing is sent while the form is invalid');

    await tapVisible(tester, find.byKey(const Key('method-cash')));
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(repo.inserted, hasLength(1));
    expect(repo.inserted.single.draft.amountPaise, 10000);
  });

  testWidgets('income does not require a payment method', (tester) async {
    final (repo, _) = await pumpAddScreen(tester);
    await tapVisible(tester, find.text('Income'));
    await typeAmount(tester, '50000');
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(repo.inserted, hasLength(1));
    expect(repo.inserted.single.draft.type, TxnType.income);
    expect(repo.inserted.single.draft.paymentMethod, isNull);
  });

  testWidgets('transfer: needs a different destination account and never sends a category', (tester) async {
    final (repo, _) = await pumpAddScreen(tester);

    await tapVisible(tester, find.text('Transfer'));
    expect(find.byKey(const Key('entry-to-account')), findsOneWidget);
    expect(find.byKey(const Key('entry-category')), findsNothing);

    await typeAmount(tester, '2000');
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(find.text('Choose the account the money went to'), findsOneWidget);
    expect(repo.attemptedIds, isEmpty);

    await tapVisible(tester, find.byKey(const Key('entry-to-account')));
    await tester.tap(find.text('Bank').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));

    expect(repo.inserted, hasLength(1));
    final d = repo.inserted.single.draft;
    expect(d.type, TxnType.transfer);
    expect(d.accountId, 'acc-cash');
    expect(d.toAccountId, 'acc-bank');
    expect(d.toRow()['category_id'], isNull);
  });

  testWidgets('a failed save is reported, keeps the form, and the retry reuses the same id', (tester) async {
    final (repo, _) = await pumpAddScreen(tester);
    repo.failNextInsertWith = const SocketException('Network is unreachable');

    await typeAmount(tester, '250');
    await tester.tap(find.byKey(const Key('keypad-done')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('entry-description')), 'DMart');
    await tapVisible(tester, find.byKey(const Key('method-card')));
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));

    // Never silent: a dialog explains it wasn't saved.
    expect(find.text('Not saved'), findsOneWidget);
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(repo.inserted, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Nothing lost.
    expect(amountText(tester), '250');
    expect(tester.widget<TextField>(find.byKey(const Key('entry-description'))).controller!.text, 'DMart');
    expect(chipSelected(tester, 'card'), isTrue);

    // Retry succeeds with the same client-generated id (no duplicate possible).
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));
    expect(repo.inserted, hasLength(1));
    expect(repo.attemptedIds, hasLength(2));
    expect(repo.attemptedIds[0], repo.attemptedIds[1]);
  });

  testWidgets('offline: save is refused with a clear message', (tester) async {
    final (repo, _) = await pumpAddScreen(tester, online: false);
    await typeAmount(tester, '75');
    await tapVisible(tester, find.byKey(const Key('method-cash')));
    await tapVisible(tester, find.byKey(const Key('entry-save-another')));

    expect(find.text('Not saved'), findsOneWidget);
    expect(find.textContaining("no internet connection"), findsOneWidget);
    expect(repo.attemptedIds, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(amountText(tester), '75');
  });

  testWidgets('remembers the last-used account and payment method', (tester) async {
    await pumpAddScreen(tester, prefs: {
      'entry.lastAccountId': 'acc-bank',
      'entry.lastPaymentMethod': 'card',
    });
    expect(
      tester.widget<DropdownButtonFormField<String>>(find.byKey(const Key('entry-account'))).initialValue,
      'acc-bank',
    );
    expect(find.text('Bank'), findsOneWidget);
    expect(chipSelected(tester, 'card'), isTrue);
  });

  testWidgets('keypad: backspace, decimals and grouping', (tester) async {
    await pumpAddScreen(tester);
    await typeAmount(tester, '1234567');
    expect(amountText(tester), '12,34,567');
    await typeAmount(tester, '<<');
    expect(amountText(tester), '12,345');
    await typeAmount(tester, '.999');
    expect(amountText(tester), '12,345.99', reason: 'a third decimal is ignored');
  });
}
