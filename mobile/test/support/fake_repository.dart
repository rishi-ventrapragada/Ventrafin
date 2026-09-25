import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventrafin/core/india_time.dart';
import 'package:ventrafin/core/theme.dart';
import 'package:ventrafin/data/models.dart';
import 'package:ventrafin/data/providers.dart';
import 'package:ventrafin/data/repository.dart';

/// 19:00 UTC on 24 Sep = 00:30 IST on 25 Sep: "today" must be the 25th.
final fixedClock = DateTime.utc(2026, 9, 24, 19, 0);

/// In-memory stand-in for Supabase, shared by the widget tests.
class FakeRepository implements FinanceRepository {
  final accounts = const [
    Account(id: 'acc-bank', name: 'Bank', type: AccountType.bank),
    Account(id: 'acc-cash', name: 'Cash', type: AccountType.cash),
    Account(id: 'acc-cc', name: 'Credit Card', type: AccountType.credit),
  ];
  List<Category> categories = const [
    Category(
        id: 'cat-food', name: 'Food', kind: TxnType.expense, color: Color(0xFFFB8C00), archived: false,
        iconKey: 'restaurant'),
    Category(
        id: 'cat-groc', name: 'Groceries', kind: TxnType.expense, color: Color(0xFF43A047), archived: false,
        iconKey: 'shopping_cart'),
    Category(
        id: 'cat-elec', name: 'Electricity', kind: TxnType.expense, color: Color(0xFFFDD835), archived: false,
        iconKey: 'bolt'),
    Category(
        id: 'cat-salary', name: 'Salary', kind: TxnType.income, color: Color(0xFF2E7D32), archived: false,
        iconKey: 'account_balance_wallet'),
  ];

  /// What fetchTransactions returns.
  List<Txn> transactions = const [];

  /// What fetchMonthComparison returns.
  List<CategoryComparison> comparison = const [];

  MonthTotals totals = const MonthTotals(
      expensePaise: 0, lastExpensePaise: 0, incomePaise: 0, lastIncomePaise: 0, uncategorizedCount: 0);

  /// Successful inserts, in order.
  final inserted = <({String id, TxnDraft draft})>[];

  /// Every insert attempt's id, including failed ones.
  final attemptedIds = <String>[];

  /// Category edits (rename / restyle), in order.
  final categoryUpdates = <({String id, String name, String iconKey, String colorHex})>[];

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
  Future<List<Txn>> fetchTransactions(YearMonth month) async => transactions;

  @override
  Future<Txn?> fetchTransaction(String id) async => transactions.where((t) => t.id == id).firstOrNull;

  @override
  Future<MonthTotals> fetchMonthTotals(YearMonth month) async => totals;

  @override
  Future<List<CategoryComparison>> fetchMonthComparison(YearMonth month) async => comparison;

  @override
  Future<Category> updateCategory(String id,
      {required String name, required String iconKey, required String colorHex}) async {
    categoryUpdates.add((id: id, name: name, iconKey: iconKey, colorHex: colorHex));
    final old = categories.firstWhere((c) => c.id == id);
    final updated = Category(
      id: old.id,
      name: name.trim(),
      kind: old.kind,
      color: parseHexColor(colorHex),
      archived: old.archived,
      iconKey: iconKey,
    );
    categories = [for (final c in categories) c.id == id ? updated : c];
    return updated;
  }

  @override
  Future<Txn> updateTransaction(String id, TxnDraft draft) => throw UnimplementedError();

  @override
  Future<void> deleteTransaction(String id) => throw UnimplementedError();

  @override
  Stream<DataChange> watchChanges() => const Stream.empty();
}

/// A transaction with sensible defaults, for list/dashboard tests.
Txn testTxn(
  String id, {
  String description = 'Swiggy dinner',
  int amountPaise = 12345,
  TxnType type = TxnType.expense,
  String? categoryId = 'cat-food',
  String accountId = 'acc-cash',
  String? toAccountId,
  PaymentMethod? paymentMethod = PaymentMethod.upi,
  bool autoCategorized = false,
  DateTime? date,
}) =>
    Txn(
      id: id,
      date: date ?? DateTime(2026, 9, 20),
      amountPaise: amountPaise,
      description: description,
      type: type,
      accountId: accountId,
      toAccountId: toAccountId,
      categoryId: type == TxnType.transfer ? null : categoryId,
      paymentMethod: paymentMethod,
      autoCategorized: autoCategorized,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

/// Pumps [home] inside the app theme with the fake repository and fixed
/// clock on a phone-sized surface (412×915 unless [surfaceSize] says otherwise).
Future<(FakeRepository, SharedPreferences)> pumpWithFakes(
  WidgetTester tester,
  Widget home, {
  FakeRepository? repo,
  Map<String, Object> prefs = const {},
  bool online = true,
  Size surfaceSize = const Size(412, 915),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(prefs);
  final sharedPrefs = await SharedPreferences.getInstance();
  final r = repo ?? FakeRepository();
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        repositoryProvider.overrideWithValue(r),
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        currentUserIdProvider.overrideWithValue('user-1'),
        clockProvider.overrideWithValue(() => fixedClock),
        isOnlineProvider.overrideWithValue(online),
      ],
      child: MaterialApp(theme: buildOceanTheme(), home: home),
    ),
  );
  await tester.pumpAndSettle();
  return (r, sharedPrefs);
}
