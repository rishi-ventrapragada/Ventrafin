// Pick-list options for the grid cells (ComboInput). The label is what the
// cell holds; keywords are other things people type for the same choice.
import type { ComboOption } from '@/components/comboOption'
import { AUTO_CATEGORY } from './entryRow'
import {
  ACCOUNT_TYPES,
  PAYMENT_METHODS,
  TXN_TYPES,
  activeOnly,
  pickerLabel,
  sortByName,
  type Account,
  type Category,
  type CategoryKind,
  type IconRef,
  type PaymentMethod,
  type TxnType,
} from './models'

export interface TypeOption extends ComboOption {
  value: TxnType
  icon: IconRef
}

const TYPE_KEYWORDS: Record<TxnType, string[]> = {
  expense: ['spent', 'debit', 'dr', 'paid'],
  income: ['received', 'credit', 'cr', 'deposit'],
  transfer: ['trf', 'self', 'move'],
}

export const TYPE_OPTIONS: readonly TypeOption[] = TXN_TYPES.map((t) => ({
  label: t.label,
  value: t.value,
  icon: t.icon,
  keywords: TYPE_KEYWORDS[t.value],
}))

export interface MethodOption extends ComboOption {
  value: PaymentMethod
  icon: IconRef
}

const METHOD_KEYWORDS: Record<PaymentMethod, string[]> = {
  cash: [],
  upi: ['gpay', 'google pay', 'phonepe', 'paytm', 'bhim'],
  debit: ['debit card', 'atm', 'rupay'],
  card: ['credit card', 'cc', 'visa', 'mastercard'],
}

export const METHOD_OPTIONS: readonly MethodOption[] = PAYMENT_METHODS.map((m) => ({
  label: m.label,
  value: m.value,
  icon: m.icon,
  keywords: METHOD_KEYWORDS[m.value],
}))

export interface AccountOption extends ComboOption {
  account: Account
}

/**
 * The active accounts. `keep` is an existing row's account: it stays
 * selectable even if archived, labelled `Old bank (archived)`.
 */
export function accountOptions(accounts: readonly Account[], keep?: string | null): AccountOption[] {
  return activeOnly(accounts, keep).map((a) => ({ label: pickerLabel(a), account: a, hint: ACCOUNT_TYPES[a.type].label }))
}

export interface CategoryOption extends ComboOption {
  /** Null for "Auto". */
  category: Category | null
}

/** "Auto" first, then the active categories of `kind` (plus `keep`, if archived but in use, as `Old stuff (archived)`). */
export function categoryOptions(categories: readonly Category[], kind: CategoryKind, keep?: string | null): CategoryOption[] {
  const active = sortByName(activeOnly(categories, keep).filter((c) => c.kind === kind))
  return [
    { label: AUTO_CATEGORY, category: null, hint: 'Ventrafin picks', keywords: ['uncategorized'] },
    ...active.map((c) => ({ label: pickerLabel(c), category: c })),
  ]
}

// ---------------------------------------------------------------------------
// The Transactions type filter (kept in the URL as ?type=)
// ---------------------------------------------------------------------------

export type TypeFilter = 'all' | TxnType

export const TYPE_FILTER_OPTIONS: { value: TypeFilter; label: string; icon: string }[] = [
  { value: 'all', label: 'All types', icon: 'filter_list' },
  { value: 'expense', label: 'Expenses', icon: TXN_TYPES[0]!.icon.name },
  { value: 'income', label: 'Income', icon: TXN_TYPES[1]!.icon.name },
  { value: 'transfer', label: 'Transfers', icon: TXN_TYPES[2]!.icon.name },
]

/** `?type=` from the URL: expense, income or transfer; anything else is "all". */
export function typeFilterFromQuery(value: unknown): TypeFilter {
  return value === 'expense' || value === 'income' || value === 'transfer' ? value : 'all'
}
