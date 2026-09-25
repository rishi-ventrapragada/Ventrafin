import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
  List<Account> accounts = const [
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

  /// Every month's transactions, for fetchTransactionsBetween (the search);
  /// null = [transactions].
  List<Txn>? allTransactions;

  /// Every fetchTransactionsBetween call.
  final betweenCalls = <(DateTime, DateTime)>[];

  /// Makes the next fetch of this kind fail.
  Object? failNextFetchTransactionsWith;
  Object? failNextFetchAccountsWith;
  Object? failNextFetchCategoriesWith;
  Object? failNextMonthTotalsWith;
  Object? failNextComparisonWith;

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

  Object? _take(Object? failure, void Function() clear) {
    if (failure != null) clear();
    return failure;
  }

  @override
  Future<List<Account>> fetchAccounts() async {
    final failure = _take(failNextFetchAccountsWith, () => failNextFetchAccountsWith = null);
    if (failure != null) throw failure;
    return accounts;
  }

  @override
  Future<List<Category>> fetchCategories() async {
    final failure = _take(failNextFetchCategoriesWith, () => failNextFetchCategoriesWith = null);
    if (failure != null) throw failure;
    return categories;
  }

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
  Future<List<Txn>> fetchTransactions(YearMonth month) async {
    final failure = _take(failNextFetchTransactionsWith, () => failNextFetchTransactionsWith = null);
    if (failure != null) throw failure;
    return transactions;
  }

  @override
  Future<List<Txn>> fetchTransactionsBetween(DateTime from, DateTime to) async {
    betweenCalls.add((from, to));
    final failure = _take(failNextFetchTransactionsWith, () => failNextFetchTransactionsWith = null);
    if (failure != null) throw failure;
    return (allTransactions ?? transactions).where((t) => !t.date.isBefore(from) && !t.date.isAfter(to)).toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });
  }

  @override
  Future<Txn?> fetchTransaction(String id) async => transactions.where((t) => t.id == id).firstOrNull;

  @override
  Future<MonthTotals> fetchMonthTotals(YearMonth month) async {
    final failure = _take(failNextMonthTotalsWith, () => failNextMonthTotalsWith = null);
    if (failure != null) throw failure;
    return totals;
  }

  @override
  Future<List<CategoryComparison>> fetchMonthComparison(YearMonth month) async {
    final failure = _take(failNextComparisonWith, () => failNextComparisonWith = null);
    if (failure != null) throw failure;
    return comparison;
  }

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

  /// Category and account writes, in order.
  final categoryInserts = <({String name, TxnType kind})>[];
  final categoryArchives = <({String id, bool archived})>[];
  final accountInserts = <({String id, String name, AccountType type})>[];
  final accountUpdates = <({String id, String name, AccountType type})>[];
  final accountArchives = <({String id, bool archived})>[];
  Object? failNextAccountWriteWith;

  @override
  Future<Category> insertCategory({required String name, required TxnType kind}) async {
    categoryInserts.add((name: name, kind: kind));
    // The database picks the icon and colour; a tag and grey here.
    final added = Category(
      id: 'cat-new-${categoryInserts.length}',
      name: name.trim(),
      kind: kind,
      color: const Color(0xFF546E7A),
      archived: false,
    );
    categories = [...categories, added];
    return added;
  }

  @override
  Future<void> setCategoryArchived(String id, bool archived) async {
    categoryArchives.add((id: id, archived: archived));
    categories = [
      for (final c in categories)
        c.id == id
            ? Category(id: c.id, name: c.name, kind: c.kind, color: c.color, archived: archived, iconKey: c.iconKey)
            : c,
    ];
  }

  void _failAccountWrite() {
    final failure = _take(failNextAccountWriteWith, () => failNextAccountWriteWith = null);
    if (failure != null) throw failure;
  }

  @override
  Future<Account> insertAccount(String id, {required String name, required AccountType type}) async {
    _failAccountWrite();
    accountInserts.add((id: id, name: name, type: type));
    final added = Account(id: id, name: name.trim(), type: type);
    accounts = [...accounts, added];
    return added;
  }

  @override
  Future<void> updateAccount(String id, {required String name, required AccountType type}) async {
    _failAccountWrite();
    accountUpdates.add((id: id, name: name, type: type));
    accounts = [
      for (final a in accounts) a.id == id ? Account(id: a.id, name: name.trim(), type: type, archived: a.archived) : a,
    ];
  }

  @override
  Future<void> setAccountArchived(String id, bool archived) async {
    _failAccountWrite();
    accountArchives.add((id: id, archived: archived));
    accounts = [
      for (final a in accounts) a.id == id ? Account(id: a.id, name: a.name, type: a.type, archived: archived) : a,
    ];
  }

  /// Transaction edits, in order.
  final txnUpdates = <({String id, TxnDraft draft})>[];

  @override
  Future<Txn> updateTransaction(String id, TxnDraft draft) async {
    txnUpdates.add((id: id, draft: draft));
    final old = [...transactions, ...?allTransactions].firstWhere((t) => t.id == id);
    return Txn(
      id: id,
      date: draft.date,
      amountPaise: draft.amountPaise,
      description: draft.description.trim(),
      type: draft.type,
      accountId: draft.accountId,
      toAccountId: draft.toAccountId,
      categoryId: draft.categoryId,
      paymentMethod: draft.paymentMethod,
      autoCategorized: false,
      createdAt: old.createdAt,
      updatedAt: old.updatedAt.add(const Duration(seconds: 1)),
    );
  }

  @override
  Future<void> deleteTransaction(String id) async => deletedTxnIds.add(id);

  /// Every export request, and what it returns (the real format is pinned
  /// by supabase/tests/08_csv_export.test.sql).
  final exportCalls = <({DateTime? from, DateTime? to})>[];
  String exportCsv = 'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n'
      '2026-09-20,Swiggy dinner,450.00,Expense,Food,Cash,,UPI\r\n';
  Object? failNextExportWith;

  @override
  Future<String> exportTransactionsCsv({DateTime? from, DateTime? to}) async {
    exportCalls.add((from: from, to: to));
    final failure = failNextExportWith;
    if (failure != null) {
      failNextExportWith = null;
      throw failure;
    }
    return exportCsv;
  }

  /// What fetchMonthlyTotals / fetchMonthlyCategoryTotals return.
  List<MonthlyTotal> monthlyTotals = const [];
  List<MonthlyCategoryTotal> monthlyCategoryTotals = const [];
  final monthlyRanges = <(YearMonth, YearMonth)>[];

  @override
  Future<List<MonthlyTotal>> fetchMonthlyTotals(YearMonth from, YearMonth to) async {
    monthlyRanges.add((from, to));
    return monthlyTotals;
  }

  @override
  Future<List<MonthlyCategoryTotal>> fetchMonthlyCategoryTotals(YearMonth from, YearMonth to) async =>
      monthlyCategoryTotals;

  Profile profile = const Profile(
    theme: 'ocean',
    dailyReminderEnabled: true,
    dailyReminderTime: kDefaultDailyReminderTime,
    billRemindersEnabled: true,
    billReminderDaysBefore: kDefaultBillReminderDaysBefore,
  );
  final profileUpdates = <ProfilePatch>[];
  Object? failNextProfileUpdateWith;

  @override
  Future<Profile> fetchProfile() async => profile;

  @override
  Future<void> updateProfile(ProfilePatch patch) async {
    final failure = failNextProfileUpdateWith;
    if (failure != null) {
      failNextProfileUpdateWith = null;
      throw failure;
    }
    profileUpdates.add(patch);
    profile = patch.applyTo(profile);
  }

  List<Bill> bills = const [];
  final billInserts = <({String id, BillDraft draft})>[];
  final billUpdates = <({String id, BillDraft draft})>[];
  final billDeletes = <String>[];
  final reminderToggles = <({String id, bool enabled})>[];
  final paidCalls = <({String billId, YearMonth month, String? txnId, PaymentMethod? method, int? amountPaise})>[];
  final paidThroughSets = <({String id, YearMonth month})>[];
  final deletedTxnIds = <String>[];

  @override
  Future<List<Bill>> fetchBills() async => bills;

  @override
  Future<void> insertBill(String id, BillDraft draft) async => billInserts.add((id: id, draft: draft));

  @override
  Future<void> updateBill(String id, BillDraft draft) async => billUpdates.add((id: id, draft: draft));

  @override
  Future<void> setBillReminder(String id, bool enabled) async => reminderToggles.add((id: id, enabled: enabled));

  @override
  Future<void> deleteBill(String id) async => billDeletes.add(id);

  @override
  Future<MarkPaidResult> markBillPaid({
    required String billId,
    required YearMonth month,
    String? txnId,
    int? amountPaise,
    DateTime? paidOn,
    PaymentMethod? paymentMethod,
  }) async {
    paidCalls.add((billId: billId, month: month, txnId: txnId, method: paymentMethod, amountPaise: amountPaise));
    return MarkPaidResult(paidThroughMonth: month, transactionId: txnId, alreadyPaid: false);
  }

  @override
  Future<void> setBillPaidThrough(String id, YearMonth month) async => paidThroughSets.add((id: id, month: month));

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
  DateTime? createdAt,
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
      createdAt: createdAt ?? DateTime(2026),
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
  List<Override> overrides = const [],
  ThemeData? theme,
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
        ...overrides,
      ],
      child: MaterialApp(theme: theme ?? buildOceanTheme(), home: home),
    ),
  );
  await tester.pumpAndSettle();
  return (r, sharedPrefs);
}
