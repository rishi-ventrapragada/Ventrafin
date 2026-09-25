import '../core/india_time.dart';
import 'models.dart';

/// A change reported by Supabase Realtime.
class DataChange {
  const DataChange.table(String this.table) : resync = false;
  const DataChange.resync()
      : table = null,
        resync = true;

  /// The table that changed (`transactions`, `accounts`, `categories`, ...).
  final String? table;

  /// True when the realtime channel (re)connected. Events may have been
  /// missed while it was down, so everything should be re-fetched.
  final bool resync;
}

/// All data access for the app. Screens never talk to Supabase directly, so
/// widget tests can substitute a fake.
abstract interface class FinanceRepository {
  Future<List<Account>> fetchAccounts();

  /// All categories, archived included (old transactions may still use them).
  Future<List<Category>> fetchCategories();

  /// Transactions dated within [month], newest first.
  Future<List<Txn>> fetchTransactions(YearMonth month);

  /// Transactions dated [from]..[to] (both inclusive), newest first. Fetched
  /// in pages, so any number of rows comes back (Supabase caps one request).
  Future<List<Txn>> fetchTransactionsBetween(DateTime from, DateTime to);

  /// A single transaction, or null if it no longer exists.
  Future<Txn?> fetchTransaction(String id);

  /// `get_month_totals(p_month)`: this vs last month, computed in Postgres.
  Future<MonthTotals> fetchMonthTotals(YearMonth month);

  /// `get_month_comparison(p_month)`: per category, this vs last month.
  Future<List<CategoryComparison>> fetchMonthComparison(YearMonth month);

  /// Renames a category and sets its icon (a curated key) and colour
  /// (`#RRGGBB`). The database keeps a renamed built-in category linked to
  /// its keywords, so auto-categorization follows the rename.
  Future<Category> updateCategory(String id, {required String name, required String iconKey, required String colorHex});

  /// Adds a category with only its name and kind: the database picks the
  /// icon (from keywords in the name, else a tag) and the first unused
  /// palette colour. Returns the stored row.
  Future<Category> insertCategory({required String name, required TxnType kind});

  /// Archives a category (hidden from pickers and auto-categorization; its
  /// transactions keep it) or restores it.
  Future<void> setCategoryArchived(String id, bool archived);

  /// Inserts with a client-generated [id], so a retry can't add it twice.
  Future<Account> insertAccount(String id, {required String name, required AccountType type});

  /// Renames an account and/or changes its type.
  Future<void> updateAccount(String id, {required String name, required AccountType type});

  /// Archives an account (hidden from pickers for new entries; its
  /// transactions and bills keep it) or restores it. The database refuses
  /// to archive the last active account.
  Future<void> setAccountArchived(String id, bool archived);

  /// Inserts with a client-generated [id]. Retrying with the same id after an
  /// ambiguous failure (e.g. a timeout) never creates a duplicate. Returns
  /// the stored row, including the category the database auto-assigned.
  Future<Txn> insertTransaction(String id, TxnDraft draft);

  /// Updates every editable column. Changing the category here is what
  /// feeds the database's learning trigger.
  Future<Txn> updateTransaction(String id, TxnDraft draft);

  Future<void> deleteTransaction(String id);

  /// `export_transactions_csv()`: the CSV file both apps share, built in
  /// Postgres. [from] and [to] are inclusive; null means no limit.
  Future<String> exportTransactionsCsv({DateTime? from, DateTime? to});

  /// `get_monthly_totals(from, to)`: one row per month, oldest first,
  /// empty months as zeros.
  Future<List<MonthlyTotal>> fetchMonthlyTotals(YearMonth from, YearMonth to);

  /// `get_monthly_category_totals(from, to)`: per month and category.
  Future<List<MonthlyCategoryTotal>> fetchMonthlyCategoryTotals(YearMonth from, YearMonth to);

  /// The signed-in user's settings (theme, reminders).
  Future<Profile> fetchProfile();

  Future<void> updateProfile(ProfilePatch patch);

  /// `get_bill_schedule()`: every bill with its next unpaid due date and
  /// status, soonest first.
  Future<List<Bill>> fetchBills();

  /// Inserts with a client-generated [id], so a retry can't duplicate it.
  Future<void> insertBill(String id, BillDraft draft);

  Future<void> updateBill(String id, BillDraft draft);

  Future<void> setBillReminder(String id, bool enabled);

  Future<void> deleteBill(String id);

  /// `mark_bill_paid()`: settles [month]'s bill. With [txnId], also logs the
  /// payment as an expense with that id (amount, date and method optional).
  /// Retrying is safe: nothing is paid or logged twice.
  Future<MarkPaidResult> markBillPaid({
    required String billId,
    required YearMonth month,
    String? txnId,
    int? amountPaise,
    DateTime? paidOn,
    PaymentMethod? paymentMethod,
  });

  /// Undo for "Mark paid": moves the bill's paid-through month back.
  Future<void> setBillPaidThrough(String id, YearMonth month);

  /// Live changes for the signed-in user, via Supabase Realtime.
  Stream<DataChange> watchChanges();
}
