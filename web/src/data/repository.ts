// All data access for the web app. Pages never talk to Supabase directly,
// so component tests can substitute an in-memory fake (tests/support).
// Mirrors mobile/lib/data/repository.dart.
import type { YearMonth } from '@/lib/dates'
import type { Account, Category, CategoryComparison, MonthTotals, Txn, TxnDraft, TxnPatch } from '@/lib/models'

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

  /** Rename / restyle a category. The database keeps a renamed built-in category's keywords. */
  updateCategory(id: string, edit: CategoryEdit): Promise<Category>

  /**
   * Live changes for the signed-in user via Supabase Realtime. Returns a
   * function that unsubscribes.
   */
  watchChanges(userId: string, onChange: (c: DataChange) => void, onStatus: (s: LiveStatus) => void): () => void
}
