// In-memory stand-in for Supabase, shared by the component tests and the
// demo page (same accounts and categories as mobile/test/support).
import type { CategoryEdit, DataChange, FinanceRepository, LiveStatus, NewTxn } from '@/data/repository'
import { monthOf, previousMonth, type YearMonth } from '@/lib/dates'
import { AppError } from '@/lib/errors'
import type { Account, Category, CategoryComparison, MonthTotals, Txn, TxnPatch } from '@/lib/models'

/** 19:00 UTC on 24 Sep = 00:30 IST on 25 Sep: "today" must be the 25th. */
export const FIXED_NOW = new Date('2026-09-24T19:00:00Z')
export const fixedClock = () => FIXED_NOW

export const ACCOUNTS: Account[] = [
  { id: 'acc-bank', name: 'Bank', type: 'bank' },
  { id: 'acc-cash', name: 'Cash', type: 'cash' },
  { id: 'acc-cc', name: 'Credit Card', type: 'credit' },
]

export const CATEGORIES: Category[] = [
  { id: 'cat-food', name: 'Food', kind: 'expense', color: '#FB8C00', archived: false, icon: 'restaurant' },
  { id: 'cat-groc', name: 'Groceries', kind: 'expense', color: '#43A047', archived: false, icon: 'shopping_cart' },
  { id: 'cat-elec', name: 'Electricity', kind: 'expense', color: '#FDD835', archived: false, icon: 'bolt' },
  { id: 'cat-med', name: 'Medical', kind: 'expense', color: '#E53935', archived: false, icon: 'local_hospital' },
  { id: 'cat-old', name: 'Old stuff', kind: 'expense', color: '#9E9E9E', archived: true, icon: 'label' },
  { id: 'cat-salary', name: 'Salary', kind: 'income', color: '#2E7D32', archived: false, icon: 'account_balance_wallet' },
]

/** A tiny imitation of the database's keyword list, for "auto" results. */
const KEYWORDS: [RegExp, string][] = [
  [/swiggy|zomato/i, 'cat-food'],
  [/dmart|d-mart|bigbasket/i, 'cat-groc'],
  [/msedcl|electricity/i, 'cat-elec'],
  [/salary/i, 'cat-salary'],
]

let seq = 0
const stamp = () => new Date(Date.UTC(2026, 8, 24, 19, 0, seq++)).toISOString()

export function makeTxn(id: string, over: Partial<Txn> = {}): Txn {
  return {
    id,
    date: '2026-09-20',
    amountPaise: 12345,
    description: 'Swiggy dinner',
    type: 'expense',
    accountId: 'acc-cash',
    toAccountId: null,
    categoryId: 'cat-food',
    paymentMethod: 'upi',
    autoCategorized: false,
    createdAt: stamp(),
    updatedAt: stamp(),
    ...over,
  }
}

export class FakeRepository implements FinanceRepository {
  accounts: Account[] = ACCOUNTS.map((a) => ({ ...a }))
  categories: Category[] = CATEGORIES.map((c) => ({ ...c }))
  txns: Txn[] = []
  totals: MonthTotals = { expensePaise: 0, lastExpensePaise: 0, incomePaise: 0, lastIncomePaise: 0, uncategorizedCount: 0 }
  comparison: CategoryComparison[] = []

  /** Every insert call's ids, including failed ones. */
  insertAttempts: string[][] = []
  updates: { id: string; patch: TxnPatch }[] = []
  deletes: string[][] = []
  categoryEdits: { id: string; edit: CategoryEdit }[] = []
  failNextInsertWith: unknown = null
  failNextUpdateWith: unknown = null
  /** Milliseconds every request takes (the demo page uses it to feel real). */
  delay = 0
  /** Compute totals and the comparison from `txns` instead of the fixed values (demo page). */
  liveReports = false

  private listeners: ((c: DataChange) => void)[] = []

  private async wait() {
    if (this.delay) await new Promise((r) => setTimeout(r, this.delay))
  }

  async fetchAccounts() {
    await this.wait()
    return this.accounts.map((a) => ({ ...a }))
  }

  async fetchCategories() {
    await this.wait()
    return this.categories.map((c) => ({ ...c }))
  }

  async fetchTransactions(month: YearMonth) {
    await this.wait()
    return this.txns
      .filter((t) => {
        const m = monthOf(t.date)
        return m.year === month.year && m.month === month.month
      })
      .sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt))
      .map((t) => ({ ...t }))
  }

  async fetchMonthTotals(month: YearMonth) {
    await this.wait()
    if (!this.liveReports) return { ...this.totals }
    const sum = (m: YearMonth, type: string) =>
      this.inMonth(m).filter((t) => t.type === type).reduce((s, t) => s + t.amountPaise, 0)
    const last = previousMonth(month)
    return {
      expensePaise: sum(month, 'expense'),
      lastExpensePaise: sum(last, 'expense'),
      incomePaise: sum(month, 'income'),
      lastIncomePaise: sum(last, 'income'),
      uncategorizedCount: this.inMonth(month).filter((t) => t.type !== 'transfer' && !t.categoryId).length,
    }
  }

  async fetchMonthComparison(month: YearMonth) {
    await this.wait()
    if (!this.liveReports) return this.comparison.map((c) => ({ ...c }))
    const rows = new Map<string, CategoryComparison>()
    const add = (m: YearMonth, which: 'thisMonthPaise' | 'lastMonthPaise') => {
      for (const t of this.inMonth(m)) {
        if (t.type === 'transfer') continue
        const key = `${t.type}:${t.categoryId}`
        const c = this.categories.find((x) => x.id === t.categoryId)
        const row = rows.get(key) ?? {
          kind: t.type,
          categoryId: t.categoryId,
          categoryName: c?.name ?? 'Uncategorized',
          color: c?.color ?? '#9E9E9E',
          thisMonthPaise: 0,
          lastMonthPaise: 0,
        }
        row[which] += t.amountPaise
        rows.set(key, row)
      }
    }
    add(month, 'thisMonthPaise')
    add(previousMonth(month), 'lastMonthPaise')
    return [...rows.values()]
  }

  private inMonth(m: YearMonth) {
    return this.txns.filter((t) => {
      const tm = monthOf(t.date)
      return tm.year === m.year && tm.month === m.month
    })
  }

  async insertTransactions(rows: readonly NewTxn[]) {
    this.insertAttempts.push(rows.map((r) => r.id))
    await this.wait()
    const failure = this.failNextInsertWith
    if (failure) {
      this.failNextInsertWith = null
      throw failure
    }
    const saved = rows.map((r) => {
      let categoryId = r.type === 'transfer' ? null : r.categoryId
      let auto = false
      if (categoryId === null && r.type !== 'transfer') {
        const hit = KEYWORDS.find(([re, id]) => re.test(r.description) && this.categories.find((c) => c.id === id)?.kind === r.type)
        if (hit) {
          categoryId = hit[1]
          auto = true
        }
      }
      return makeTxn(r.id, {
        date: r.date,
        amountPaise: r.amountPaise,
        description: r.description.trim(),
        type: r.type,
        accountId: r.accountId,
        toAccountId: r.type === 'transfer' ? r.toAccountId : null,
        categoryId,
        paymentMethod: r.paymentMethod,
        autoCategorized: auto,
      })
    })
    this.txns.push(...saved)
    this.emit({ table: 'transactions' })
    return saved.map((t) => ({ ...t }))
  }

  async updateTransaction(id: string, patch: TxnPatch) {
    this.updates.push({ id, patch })
    await this.wait()
    const failure = this.failNextUpdateWith
    if (failure) {
      this.failNextUpdateWith = null
      throw failure
    }
    const i = this.txns.findIndex((t) => t.id === id)
    if (i < 0) throw new AppError('Transaction not found', 'PGRST116')
    const next = { ...this.txns[i]!, ...patch, updatedAt: stamp() }
    if (patch.categoryId !== undefined) next.autoCategorized = false
    if (next.type === 'transfer') next.categoryId = null
    else next.toAccountId = null
    this.txns[i] = next
    this.emit({ table: 'transactions' })
    return { ...next }
  }

  async deleteTransactions(ids: readonly string[]) {
    this.deletes.push([...ids])
    await this.wait()
    const before = this.txns.length
    this.txns = this.txns.filter((t) => !ids.includes(t.id))
    this.emit({ table: 'transactions' })
    return before - this.txns.length
  }

  async updateCategory(id: string, edit: CategoryEdit) {
    this.categoryEdits.push({ id, edit })
    await this.wait()
    const c = this.categories.find((x) => x.id === id)
    if (!c) throw new AppError('Category not found', 'PGRST116')
    if (this.categories.some((x) => x.id !== id && x.kind === c.kind && x.name.toLowerCase() === edit.name.trim().toLowerCase())) {
      throw new AppError('duplicate key value violates unique constraint', '23505')
    }
    Object.assign(c, { name: edit.name.trim(), icon: edit.icon, color: edit.color })
    this.emit({ table: 'categories' })
    return { ...c }
  }

  watchChanges(_userId: string, onChange: (c: DataChange) => void, onStatus: (s: LiveStatus) => void) {
    this.listeners.push(onChange)
    onStatus('live')
    return () => {
      this.listeners = this.listeners.filter((l) => l !== onChange)
    }
  }

  /** Pretend the phone changed something. */
  emit(change: DataChange) {
    this.listeners.forEach((l) => l(change))
  }
}
