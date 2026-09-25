// App-side shapes of the database rows (ARCHITECTURE.md § 2), with the same
// labels and icons the phone uses (mobile/lib/data/models.dart and
// mobile/lib/core/visual_badges.dart).
import type { Database } from './database.types'
import { parseHex } from './categoryStyle'

type Tables = Database['public']['Tables']
export type TxnRow = Tables['transactions']['Row']
export type AccountRow = Tables['accounts']['Row']
export type CategoryRow = Tables['categories']['Row']

// ---------------------------------------------------------------------------
// Enums (CHECK constraints in the database)
// ---------------------------------------------------------------------------

export type TxnType = 'expense' | 'income' | 'transfer'
export type CategoryKind = 'expense' | 'income'
export type PaymentMethod = 'cash' | 'upi' | 'debit' | 'card'
export type AccountType = 'cash' | 'bank' | 'credit'

/** An icon from src/lib/icons.generated.ts; `filled` picks the FILL=1 glyph. */
export interface IconRef {
  name: string
  filled?: boolean
}

export const TXN_TYPES: readonly { value: TxnType; label: string; icon: IconRef }[] = [
  { value: 'expense', label: 'Expense', icon: { name: 'do_not_disturb_on' } },
  { value: 'income', label: 'Income', icon: { name: 'add_circle' } },
  { value: 'transfer', label: 'Transfer', icon: { name: 'swap_horiz' } },
]

export const PAYMENT_METHODS: readonly { value: PaymentMethod; label: string; icon: IconRef }[] = [
  { value: 'cash', label: 'Cash', icon: { name: 'payments' } },
  { value: 'upi', label: 'UPI', icon: { name: 'qr_code_2' } },
  { value: 'debit', label: 'Debit', icon: { name: 'atm' } },
  { value: 'card', label: 'Card', icon: { name: 'credit_card', filled: true } },
]

export const ACCOUNT_TYPES: Readonly<Record<AccountType, { label: string; icon: IconRef; color: string }>> = {
  cash: { label: 'Cash', icon: { name: 'payments' }, color: '#2E7D32' },
  bank: { label: 'Bank', icon: { name: 'account_balance', filled: true }, color: '#1565C0' },
  credit: { label: 'Credit card', icon: { name: 'credit_card', filled: true }, color: '#6A1B9A' },
}

export function txnTypeLabel(t: TxnType): string {
  return TXN_TYPES.find((x) => x.value === t)!.label
}

export function methodLabel(m: PaymentMethod | null): string {
  return m ? PAYMENT_METHODS.find((x) => x.value === m)!.label : ''
}

function asTxnType(v: string): TxnType {
  return v === 'income' || v === 'transfer' ? v : 'expense'
}

function asMethod(v: string | null): PaymentMethod | null {
  return v === 'cash' || v === 'upi' || v === 'debit' || v === 'card' ? v : null
}

function asAccountType(v: string): AccountType {
  return v === 'bank' || v === 'credit' ? v : 'cash'
}

function asPaise(v: unknown): number {
  const n = Number(v)
  if (!Number.isSafeInteger(n)) throw new RangeError(`Unexpected amount from the server: ${String(v)}`)
  return n
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

export interface Account {
  id: string
  name: string
  type: AccountType
}

export function accountFromRow(r: Pick<AccountRow, 'id' | 'name' | 'type'>): Account {
  return { id: r.id, name: r.name, type: asAccountType(r.type) }
}

export interface Category {
  id: string
  name: string
  kind: CategoryKind
  /** `#RRGGBB` */
  color: string
  archived: boolean
  /** Key from the curated icon set (`categories.icon`). */
  icon: string
}

export function categoryFromRow(r: Pick<CategoryRow, 'id' | 'name' | 'kind' | 'color' | 'archived' | 'icon'>): Category {
  return {
    id: r.id,
    name: r.name,
    kind: r.kind === 'income' ? 'income' : 'expense',
    color: parseHex(r.color),
    archived: r.archived,
    icon: r.icon,
  }
}

/** A row of `public.transactions`. */
export interface Txn {
  id: string
  /** `yyyy-mm-dd` */
  date: string
  amountPaise: number
  description: string
  type: TxnType
  accountId: string
  toAccountId: string | null
  /** Null = Uncategorized (always null for transfers). */
  categoryId: string | null
  paymentMethod: PaymentMethod | null
  autoCategorized: boolean
  createdAt: string
  updatedAt: string
}

export function txnFromRow(r: TxnRow): Txn {
  return {
    id: r.id,
    date: r.date,
    amountPaise: asPaise(r.amount_paise),
    description: r.description ?? '',
    type: asTxnType(r.type),
    accountId: r.account_id,
    toAccountId: r.to_account_id,
    categoryId: r.category_id,
    paymentMethod: asMethod(r.payment_method),
    autoCategorized: r.auto_categorized,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  }
}

/** What the entry grid writes. `categoryId: null` = let the database auto-categorize. */
export interface TxnDraft {
  date: string
  amountPaise: number
  description: string
  type: TxnType
  accountId: string
  toAccountId: string | null
  categoryId: string | null
  paymentMethod: PaymentMethod | null
}

/** One or more columns of an existing transaction, as edited in the table. */
export type TxnPatch = Partial<TxnDraft>

/**
 * Columns sent to Supabase. owner_id is omitted on purpose: it defaults to
 * auth.uid() in the database and RLS verifies it. The categorization trigger
 * clears whichever of category / destination account doesn't fit the type.
 */
export function draftToRow(d: TxnDraft): Tables['transactions']['Insert'] {
  return {
    date: d.date,
    amount_paise: d.amountPaise,
    description: d.description.trim(),
    type: d.type,
    account_id: d.accountId,
    to_account_id: d.type === 'transfer' ? d.toAccountId : null,
    category_id: d.type === 'transfer' ? null : d.categoryId,
    payment_method: d.paymentMethod,
  }
}

export function patchToRow(p: TxnPatch): Tables['transactions']['Update'] {
  const row: Tables['transactions']['Update'] = {}
  if (p.date !== undefined) row.date = p.date
  if (p.amountPaise !== undefined) row.amount_paise = p.amountPaise
  if (p.description !== undefined) row.description = p.description.trim()
  if (p.type !== undefined) row.type = p.type
  if (p.accountId !== undefined) row.account_id = p.accountId
  if (p.toAccountId !== undefined) row.to_account_id = p.toAccountId
  if (p.categoryId !== undefined) row.category_id = p.categoryId
  if (p.paymentMethod !== undefined) row.payment_method = p.paymentMethod
  return row
}

// ---------------------------------------------------------------------------
// Reports (SQL functions; the browser only draws them)
// ---------------------------------------------------------------------------

/** One row of `get_month_totals()`. */
export interface MonthTotals {
  expensePaise: number
  lastExpensePaise: number
  incomePaise: number
  lastIncomePaise: number
  uncategorizedCount: number
}

export function monthTotalsFromRow(r: Database['public']['Functions']['get_month_totals']['Returns'][number]): MonthTotals {
  return {
    expensePaise: asPaise(r.expense_paise),
    lastExpensePaise: asPaise(r.last_expense_paise),
    incomePaise: asPaise(r.income_paise),
    lastIncomePaise: asPaise(r.last_income_paise),
    uncategorizedCount: Number(r.uncategorized_count),
  }
}

/** One row of `get_month_comparison()`. `categoryId: null` is Uncategorized. */
export interface CategoryComparison {
  kind: CategoryKind
  categoryId: string | null
  categoryName: string
  color: string
  thisMonthPaise: number
  lastMonthPaise: number
}

export function comparisonFromRow(
  r: Database['public']['Functions']['get_month_comparison']['Returns'][number],
): CategoryComparison {
  return {
    kind: r.kind === 'income' ? 'income' : 'expense',
    // The generated type says string, but Uncategorized comes back as NULL.
    categoryId: (r.category_id as string | null) ?? null,
    categoryName: r.category_name,
    color: parseHex(r.category_color),
    thisMonthPaise: asPaise(r.this_month_paise),
    lastMonthPaise: asPaise(r.last_month_paise),
  }
}

// ---------------------------------------------------------------------------
// Category names
// ---------------------------------------------------------------------------

/** Longest category name the database accepts (`categories_name_check`). */
export const CATEGORY_NAME_MAX = 40

/**
 * Why `name` can't be used for a category of `kind`, or null if it can.
 * Mirrors the database's rules so the form can say so before saving:
 * 1–40 characters, "Uncategorized" is reserved, and names are unique per
 * kind ignoring case (archived categories count too). Same wording as the
 * phone (`categoryNameError` in mobile/lib/data/models.dart).
 */
export function categoryNameError(
  name: string,
  { kind, existing, exceptId }: { kind: CategoryKind; existing: readonly Category[]; exceptId?: string },
): string | null {
  const trimmed = name.trim()
  if (!trimmed) return 'Enter a name'
  if ([...trimmed].length > CATEGORY_NAME_MAX) return `Keep it to ${CATEGORY_NAME_MAX} characters or fewer`
  const lower = trimmed.toLowerCase()
  if (lower === 'uncategorized') return '"Uncategorized" is reserved for entries without a category'
  const clash = existing.find((c) => c.id !== exceptId && c.kind === kind && c.name.trim().toLowerCase() === lower)
  if (clash) {
    const article = kind === 'income' ? 'an income' : 'an expense'
    return `You already have ${article} category called "${clash.name}"${clash.archived ? ' (archived)' : ''}`
  }
  return null
}

/** Categories sorted by name, case-insensitively. */
export function sortByName<T extends { name: string }>(items: readonly T[]): T[] {
  return [...items].sort((a, b) => a.name.localeCompare(b.name, 'en-IN', { sensitivity: 'base' }))
}
