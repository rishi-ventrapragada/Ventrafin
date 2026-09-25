// One row of the Add grid, as text, exactly like a spreadsheet row. Typed
// rows and rows pasted from Excel go through the same parser, so both are
// validated the same way (and the same way as the phone's entry form).
import { formatDateIndian, parseDateInput } from './dates'
import { formatAmountInput, parseSignedAmount } from './money'
import {
  PAYMENT_METHODS,
  TXN_TYPES,
  type Account,
  type AccountType,
  type Category,
  type CategoryKind,
  type PaymentMethod,
  type TxnDraft,
  type TxnType,
} from './models'

export const ENTRY_FIELDS = ['date', 'description', 'amount', 'type', 'category', 'account', 'toAccount', 'method'] as const
export type EntryField = (typeof ENTRY_FIELDS)[number]
export type RawRow = Record<EntryField, string>

export const FIELD_LABELS: Readonly<Record<EntryField, string>> = {
  date: 'Date',
  description: 'Description',
  amount: 'Amount',
  type: 'Type',
  category: 'Category',
  account: 'Account',
  toAccount: 'To account',
  method: 'Paid by',
}

/** What the category cell shows when the database should choose. */
export const AUTO_CATEGORY = 'Auto'

/** Longest description the database accepts. */
export const DESCRIPTION_MAX = 500

export interface EntryContext {
  accounts: readonly Account[]
  categories: readonly Category[]
  /** Today in India, `yyyy-mm-dd`. */
  today: string
}

export interface RowIssue {
  field: EntryField
  message: string
  /** Errors stop the row from saving; warnings only explain what will happen. */
  level: 'error' | 'warning'
}

export interface ParsedRow {
  /** Nothing entered: ignored when saving. */
  blank: boolean
  /** Ready to insert (only when there are no errors). */
  draft: TxnDraft | null
  issues: RowIssue[]
}

export function emptyRow(defaults: Partial<RawRow> = {}): RawRow {
  return { date: '', description: '', amount: '', type: '', category: '', account: '', toAccount: '', method: '', ...defaults }
}

const norm = (s: string) => s.trim().toLowerCase().replace(/\s+/g, ' ')

/** A row is blank when nothing but the pre-filled defaults (date, type, account, paid by) is in it. */
export function isBlankRow(raw: RawRow): boolean {
  const category = norm(raw.category)
  return !raw.description.trim() && !raw.amount.trim() && !raw.toAccount.trim() && (!category || category === 'auto')
}

// ---------------------------------------------------------------------------
// Cell vocabularies (what people type in Excel)
// ---------------------------------------------------------------------------

const TYPE_WORDS: Readonly<Record<string, TxnType>> = {
  expense: 'expense', expenses: 'expense', exp: 'expense', e: 'expense', spent: 'expense', spend: 'expense',
  debit: 'expense', dr: 'expense', withdrawal: 'expense', paid: 'expense', payment: 'expense', out: 'expense', '-': 'expense',
  income: 'income', inc: 'income', i: 'income', received: 'income', receipt: 'income', credit: 'income', cr: 'income',
  deposit: 'income', in: 'income', '+': 'income',
  transfer: 'transfer', transfers: 'transfer', trf: 'transfer', tfr: 'transfer', xfer: 'transfer', t: 'transfer',
  self: 'transfer', contra: 'transfer',
}

/** `undefined` for an empty cell, `null` when the text isn't a type. */
export function parseTxnType(text: string): TxnType | null | undefined {
  const s = norm(text)
  if (!s) return undefined
  return TYPE_WORDS[s] ?? TYPE_WORDS[s.replace(/[^a-z+-]/g, '')] ?? null
}

const METHOD_WORDS: Readonly<Record<string, PaymentMethod>> = {
  cash: 'cash',
  upi: 'upi', gpay: 'upi', 'g pay': 'upi', 'google pay': 'upi', googlepay: 'upi', phonepe: 'upi', 'phone pe': 'upi',
  paytm: 'upi', bhim: 'upi', 'upi lite': 'upi', 'amazon pay': 'upi', amazonpay: 'upi', qr: 'upi',
  debit: 'debit', 'debit card': 'debit', dc: 'debit', atm: 'debit', 'atm card': 'debit', rupay: 'debit',
  card: 'card', 'credit card': 'card', cc: 'card', credit: 'card', visa: 'card', mastercard: 'card',
  'master card': 'card', amex: 'card',
}
const NO_METHOD = new Set(['-', '—', 'none', 'na', 'n/a', 'nil'])

/** `null` for "none" / empty, `'invalid'` for text that isn't a payment method. */
export function parseMethod(text: string): PaymentMethod | null | 'invalid' {
  const s = norm(text)
  if (!s || NO_METHOD.has(s)) return null
  return METHOD_WORDS[s] ?? 'invalid'
}

const ACCOUNT_TYPE_WORDS: Readonly<Record<string, AccountType>> = {
  cash: 'cash', wallet: 'cash',
  bank: 'bank', 'bank account': 'bank', savings: 'bank', sb: 'bank', current: 'bank',
  'credit card': 'credit', cc: 'credit', credit: 'credit', card: 'credit',
}

/** The account a cell names: its exact name, or a type word when only one account has that type. */
export function matchAccount(text: string, accounts: readonly Account[]): Account | null {
  const s = norm(text)
  if (!s) return null
  const byName = accounts.find((a) => norm(a.name) === s)
  if (byName) return byName
  const type = ACCOUNT_TYPE_WORDS[s]
  if (!type) return null
  const ofType = accounts.filter((a) => a.type === type)
  return ofType.length === 1 ? ofType[0]! : null
}

/** An active category of `kind` with this name (any case). */
export function matchCategory(text: string, kind: CategoryKind, categories: readonly Category[]): Category | null {
  const s = norm(text)
  return categories.find((c) => c.kind === kind && !c.archived && norm(c.name) === s) ?? null
}

export function isAutoCategory(text: string): boolean {
  const s = norm(text)
  return !s || s === 'auto' || s === 'uncategorized' || s === 'uncategorised'
}

// ---------------------------------------------------------------------------
// Tidying a cell after it is typed or pasted (canonical spelling)
// ---------------------------------------------------------------------------

/** The canonical text for a cell (`25-Sep-26` -> `25/09/2026`, `gpay` -> `UPI`), or the text unchanged. */
export function tidyCell(field: EntryField, text: string, ctx: EntryContext, type?: TxnType): string {
  const trimmed = text.trim()
  if (field === 'category' && isAutoCategory(trimmed)) return AUTO_CATEGORY
  if (!trimmed) return ''
  switch (field) {
    case 'date': {
      const d = parseDateInput(trimmed, ctx.today, { allowExcelSerial: true })
      return d?.ok ? formatDateIndian(d.iso) : trimmed
    }
    case 'amount': {
      const a = parseSignedAmount(trimmed)
      return a && !a.negative ? formatAmountInput(a.paise) : trimmed
    }
    case 'type': {
      const t = parseTxnType(trimmed)
      return t ? TXN_TYPES.find((x) => x.value === t)!.label : trimmed
    }
    case 'method': {
      const m = parseMethod(trimmed)
      if (m === null) return ''
      return m === 'invalid' ? trimmed : PAYMENT_METHODS.find((x) => x.value === m)!.label
    }
    case 'account':
    case 'toAccount':
      return matchAccount(trimmed, ctx.accounts)?.name ?? trimmed
    case 'category': {
      if (isAutoCategory(trimmed)) return AUTO_CATEGORY
      const kind: CategoryKind = type === 'income' ? 'income' : 'expense'
      return matchCategory(trimmed, kind, ctx.categories)?.name ?? trimmed
    }
    case 'description':
      return trimmed
  }
}

// ---------------------------------------------------------------------------
// The parser
// ---------------------------------------------------------------------------

export function parseEntryRow(raw: RawRow, ctx: EntryContext): ParsedRow {
  if (isBlankRow(raw)) return { blank: true, draft: null, issues: [] }
  const issues: RowIssue[] = []
  const error = (field: EntryField, message: string) => issues.push({ field, message, level: 'error' })
  const warn = (field: EntryField, message: string) => issues.push({ field, message, level: 'warning' })

  // Type (blank = expense, the everyday case)
  const parsedType = parseTxnType(raw.type)
  if (parsedType === null) error('type', `"${raw.type.trim()}" is not a type. Use Expense, Income or Transfer`)
  const type: TxnType = parsedType ?? 'expense'

  // Date
  let date = ''
  const dateText = raw.date.trim()
  if (!dateText) error('date', 'Enter a date')
  else {
    const d = parseDateInput(dateText, ctx.today, { allowExcelSerial: true })
    if (d?.ok) date = d.iso
    else error('date', d?.error ?? 'Enter a date')
  }

  // Amount
  let amountPaise = 0
  const amountText = raw.amount.trim()
  if (!amountText) error('amount', 'Enter an amount')
  else {
    const a = parseSignedAmount(amountText)
    if (!a) error('amount', `"${amountText}" is not an amount`)
    else if (a.negative) error('amount', 'Enter the amount without a minus sign, and set Type to Expense or Income')
    else if (a.paise <= 0) error('amount', 'Amount must be more than zero')
    else amountPaise = a.paise
  }

  // Description
  const description = raw.description.trim()
  if ([...description].length > DESCRIPTION_MAX) {
    error('description', `Description is too long (${DESCRIPTION_MAX} characters at most)`)
  }

  // Accounts
  let account: Account | null = null
  if (!raw.account.trim()) error('account', 'Choose an account')
  else {
    account = matchAccount(raw.account, ctx.accounts)
    if (!account) error('account', `No account called "${raw.account.trim()}"`)
  }
  let toAccount: Account | null = null
  if (type === 'transfer') {
    if (!raw.toAccount.trim()) error('toAccount', 'Choose the account the money went to')
    else {
      toAccount = matchAccount(raw.toAccount, ctx.accounts)
      if (!toAccount) error('toAccount', `No account called "${raw.toAccount.trim()}"`)
      else if (account && toAccount.id === account.id) error('toAccount', 'Must be different from the "From" account')
    }
  } else if (raw.toAccount.trim()) {
    warn('toAccount', 'Only transfers have a "To" account; it will be ignored')
  }

  // Paid by (required for expenses, as on the phone)
  const method = parseMethod(raw.method)
  if (method === 'invalid') error('method', `"${raw.method.trim()}" is not a payment method. Use Cash, UPI, Debit or Card`)
  else if (type === 'expense' && method === null) error('method', 'Choose how you paid: Cash, UPI, Debit or Card')

  // Category (optional: the database auto-categorizes)
  let categoryId: string | null = null
  const categoryText = raw.category.trim()
  if (type === 'transfer') {
    if (!isAutoCategory(categoryText)) warn('category', 'Transfers have no category; it will be ignored')
  } else if (!isAutoCategory(categoryText)) {
    const kind: CategoryKind = type
    const match = matchCategory(categoryText, kind, ctx.categories)
    if (match) categoryId = match.id
    else {
      const archived = ctx.categories.find((c) => c.kind === kind && c.archived && norm(c.name) === norm(categoryText))
      const otherKind = ctx.categories.find((c) => c.kind !== kind && !c.archived && norm(c.name) === norm(categoryText))
      if (archived) warn('category', `"${archived.name}" is archived. Ventrafin will pick a category`)
      else if (otherKind) warn('category', `"${otherKind.name}" is an ${otherKind.kind} category. Ventrafin will pick one for this ${kind}`)
      else warn('category', `No ${kind} category called "${categoryText}". Ventrafin will pick one`)
    }
  }

  if (issues.some((i) => i.level === 'error')) return { blank: false, draft: null, issues }
  return {
    blank: false,
    issues,
    draft: {
      date,
      amountPaise,
      description,
      type,
      accountId: account!.id,
      toAccountId: type === 'transfer' ? toAccount!.id : null,
      categoryId,
      paymentMethod: method === 'invalid' ? null : method,
    },
  }
}
