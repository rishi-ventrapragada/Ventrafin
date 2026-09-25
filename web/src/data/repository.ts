// All data access for the web app. Pages never talk to Supabase directly,
// so component tests can substitute an in-memory fake (tests/support).
// Mirrors mobile/lib/data/repository.dart.
import type { YearMonth } from '@/lib/dates'
import type {
  Account,
  Bill,
  BillDraft,
  Category,
  CategoryComparison,
  MarkPaidResult,
  MonthlyCategoryTotal,
  MonthlyTotal,
  MonthTotals,
  PaymentMethod,
  Profile,
  Txn,
  TxnDraft,
  TxnPatch,
} from '@/lib/models'

/** Tables published to Supabase Realtime (see the realtime migrations). */
export const REALTIME_TABLES = ['transactions', 'accounts', 'categories', 'recurring_bills', 'profiles'] as const
export type RealtimeTable = (typeof REALTIME_TABLES)[number]

/** A change reported by Realtime: one table changed, or the channel (re)connected. */
export type DataChange = { table: RealtimeTable } | { resync: true }

export type LiveStatus = 'connecting' | 'live' | 'reconnecting'

export interface NewTxn extends TxnDraft {
  /** Client-generated, so retrying a save after an unclear failure can't duplicate it. */
  id: string
}

export interface CategoryEdit {
  name: string
  icon: string
  color: string
}

export interface FinanceRepository {
  fetchAccounts(): Promise<Account[]>

  /** All categories, archived included (old transactions may still use them). */
  fetchCategories(): Promise<Category[]>

  /** Transactions dated within `month`, newest first. */
  fetchTransactions(month: YearMonth): Promise<Txn[]>

  /** `get_month_totals(p_month)`: this vs last month, computed in Postgres. */
  fetchMonthTotals(month: YearMonth): Promise<MonthTotals>

  /** `get_month_comparison(p_month)`: per category, this vs last month. */
  fetchMonthComparison(month: YearMonth): Promise<CategoryComparison[]>

  /**
   * Inserts all rows in one statement (all or nothing) and returns them as
   * stored, including the category the database auto-assigned. Retrying
   * with the same ids after an ambiguous failure never duplicates a row.
   */
  insertTransactions(rows: readonly NewTxn[]): Promise<Txn[]>

  /** Updates some columns. Changing the category feeds the learning trigger. */
  updateTransaction(id: string, patch: TxnPatch): Promise<Txn>

  /** Deletes the rows and returns how many were actually deleted. */
  deleteTransactions(ids: readonly string[]): Promise<number>

  /**
   * Every transaction dated `from`..`to` (inclusive), oldest first, fetched
   * in pages, so a long range isn't cut off. The import uses it to spot
   * rows that are already saved.
   */
  fetchTransactionsBetween(from: string, to: string): Promise<Txn[]>

  /**
   * `export_transactions_csv()`: the CSV file both apps save, built in
   * Postgres. `from`/`to` are inclusive (null = no limit); `ids` keeps only
   * those transactions.
   */
  exportTransactionsCsv(args: { from: string | null; to: string | null; ids?: readonly string[] }): Promise<string>

  /** Rename / restyle a category. The database keeps a renamed built-in category's keywords. */
  updateCategory(id: string, edit: CategoryEdit): Promise<Category>

  /** `get_monthly_totals(from, to)`: one row per month, oldest first, empty months as zeros. */
  fetchMonthlyTotals(from: YearMonth, to: YearMonth): Promise<MonthlyTotal[]>

  /** `get_monthly_category_totals(from, to)`: per month and category. */
  fetchMonthlyCategoryTotals(from: YearMonth, to: YearMonth): Promise<MonthlyCategoryTotal[]>

  /** The signed-in user's settings (theme, reminders). */
  fetchProfile(userId: string): Promise<Profile>

  /** Changes the profile's theme (the phone follows via Realtime). */
  updateProfileTheme(userId: string, theme: string): Promise<void>

  /** `get_bill_schedule()`: every bill with its next unpaid due date and status, soonest first. */
  fetchBills(): Promise<Bill[]>

  /** Inserts with a client-generated `id`, so a retry can't add the bill twice. */
  insertBill(id: string, draft: BillDraft): Promise<void>

  updateBill(id: string, draft: BillDraft): Promise<void>

  setBillReminder(id: string, enabled: boolean): Promise<void>

  deleteBill(id: string): Promise<void>

  /**
   * `mark_bill_paid()`: settles `month`'s bill; with `txnId`, also logs the
   * payment as an expense with that id. Retrying never pays or logs twice.
   */
  markBillPaid(args: {
    billId: string
    month: YearMonth
    txnId: string | null
    amountPaise?: number
    paidOn?: string
    paymentMethod?: PaymentMethod | null
  }): Promise<MarkPaidResult>

  /** Undo for "Mark paid": moves the bill's paid-through month back. */
  setBillPaidThrough(id: string, month: YearMonth): Promise<void>

  /**
   * Live changes for the signed-in user via Supabase Realtime. Returns a
   * function that unsubscribes.
   */
  watchChanges(userId: string, onChange: (c: DataChange) => void, onStatus: (s: LiveStatus) => void): () => void
}
