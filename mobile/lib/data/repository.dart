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

  /// A single transaction, or null if it no longer exists.
  Future<Txn?> fetchTransaction(String id);

  /// `get_month_totals(p_month)`: this vs last month, computed in Postgres.
  Future<MonthTotals> fetchMonthTotals(YearMonth month);

  /// Inserts with a client-generated [id]. Retrying with the same id after an
  /// ambiguous failure (e.g. a timeout) never creates a duplicate. Returns
  /// the stored row, including the category the database auto-assigned.
  Future<Txn> insertTransaction(String id, TxnDraft draft);

  /// Updates every editable column. Changing the category here is what
  /// feeds the database's learning trigger.
  Future<Txn> updateTransaction(String id, TxnDraft draft);

  Future<void> deleteTransaction(String id);

  /// Live changes for the signed-in user, via Supabase Realtime.
  Stream<DataChange> watchChanges();
}
