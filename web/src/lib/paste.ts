// Rows pasted from Excel (or Google Sheets): the clipboard holds tab-separated
// text. This reads it, works out which column is which (from a heading row
// if there is one, otherwise from the values), and turns each line into a
// grid row that entryRow.ts then validates like a typed one.
import { formatDateIndian, parseDateInput } from './dates'
import {
  AUTO_CATEGORY,
  emptyRow,
  archivedAccountNamed,
  matchAccount,
  parseMethod,
  parseTxnType,
  tidyCell,
  type EntryContext,
  type RawRow,
} from './entryRow'
import { formatAmountInput, parseSignedAmount } from './money'
import { txnTypeLabel, type TxnType } from './models'

export type ColumnRole =
  | 'date'
  | 'description'
  | 'amount'
  | 'withdrawal'
  | 'deposit'
  | 'type'
  | 'category'
  | 'account'
  | 'toAccount'
  | 'method'
  | 'ignore'

export const COLUMN_ROLES: readonly { value: ColumnRole; label: string }[] = [
  { value: 'date', label: 'Date' },
  { value: 'description', label: 'Description' },
  { value: 'amount', label: 'Amount' },
  { value: 'withdrawal', label: 'Amount spent (withdrawal)' },
  { value: 'deposit', label: 'Amount received (deposit)' },
  { value: 'type', label: 'Type' },
  { value: 'category', label: 'Category' },
  { value: 'account', label: 'Account' },
  { value: 'toAccount', label: 'To account' },
  { value: 'method', label: 'Paid by' },
  { value: 'ignore', label: '(ignore)' },
]

/** Roles a sheet can only have one of. */
const SINGLE_ROLES: ReadonlySet<ColumnRole> = new Set(['date', 'amount', 'withdrawal', 'deposit', 'type', 'category', 'account', 'toAccount', 'method'])

// ---------------------------------------------------------------------------
// Clipboard text -> cells
// ---------------------------------------------------------------------------

/**
 * Splits clipboard text into rows of cells. Excel separates cells with tabs
 * and rows with CRLF, and wraps a cell in double quotes when it contains a
 * tab, a line break or a quote (doubling the quotes inside). Blank lines
 * are dropped.
 */
export function splitClipboard(text: string): string[][] {
  return splitDelimited(text, '\t')
}

/**
 * The same for any separator: tab for the clipboard, comma (or semicolon)
 * for CSV files, which quote cells the same way (RFC 4180).
 */
export function splitDelimited(text: string, separator: string): string[][] {
  const rows: string[][] = []
  let row: string[] = []
  let cell = ''
  let inQuotes = false
  let cellStart = true
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]!
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          cell += '"'
          i++
        } else inQuotes = false
      } else cell += ch
      continue
    }
    if (ch === '"' && cellStart) {
      inQuotes = true
      cellStart = false
      continue
    }
    if (ch === separator) {
      row.push(cell)
      cell = ''
      cellStart = true
      continue
    }
    if (ch === '\r' || ch === '\n') {
      row.push(cell)
      rows.push(row)
      row = []
      cell = ''
      cellStart = true
      if (ch === '\r' && text[i + 1] === '\n') i++
      continue
    }
    cell += ch
    cellStart = false
  }
  if (cell !== '' || row.length > 0) {
    row.push(cell)
    rows.push(row)
  }
  return rows.map((r) => r.map((c) => c.replace(/ /g, ' ').trim())).filter((r) => r.some((c) => c !== ''))
}

/** True when pasted text is more than one cell (so it should open the paste preview). */
export function looksLikeRows(text: string): boolean {
  return /[\t\n\r]/.test(text.replace(/[\r\n]+$/, ''))
}

// ---------------------------------------------------------------------------
// Heading row
// ---------------------------------------------------------------------------

const HEADINGS: Readonly<Record<string, ColumnRole>> = (() => {
  const map: Record<string, ColumnRole> = {}
  const add = (role: ColumnRole, words: string[]) => words.forEach((w) => (map[w] = role))
  add('date', ['date', 'txn date', 'transaction date', 'tran date', 'trans date', 'posting date', 'dt', 'day', 'entry date', 'bill date'])
  add('ignore', [
    'value date', 'value dt', 'balance', 'closing balance', 'running balance', 'available balance', 'bal',
    'chq ref no', 'chq no', 'cheque no', 'ref no', 'reference', 'reference no', 'ref', 'utr', 'sr', 'sr no', 's no',
    'sl no', 'no', 'serial', 'serial no', 'id', 'month', 'week',
  ])
  add('description', [
    'description', 'desc', 'details', 'particulars', 'narration', 'remarks', 'remark', 'item', 'items', 'note',
    'notes', 'memo', 'merchant', 'payee', 'purpose', 'transaction details', 'transaction remarks', 'name', 'spent on',
  ])
  add('amount', ['amount', 'amt', 'rs', 'inr', 'rupees', 'value', 'cost', 'price', 'total', 'amount inr', 'amount rs', 'expense amount', 'txn amount', 'transaction amount'])
  add('withdrawal', [
    'withdrawal', 'withdrawals', 'withdrawal amt', 'withdrawal amount', 'debit', 'debits', 'debit amount', 'debit amt',
    'dr', 'dr amount', 'paid out', 'money out', 'out', 'spent', 'expense', 'expenses',
  ])
  add('deposit', [
    'deposit', 'deposits', 'deposit amt', 'deposit amount', 'credit', 'credits', 'credit amount', 'credit amt', 'cr',
    'cr amount', 'paid in', 'money in', 'in', 'received', 'income',
  ])
  add('type', ['type', 'txn type', 'transaction type', 'kind', 'dr cr', 'cr dr', 'debit credit', 'expense income', 'income expense'])
  add('category', ['category', 'categories', 'head', 'expense head', 'cat', 'group', 'category name'])
  add('account', ['account', 'accounts', 'from account', 'from', 'acct', 'ac', 'a c', 'account name', 'wallet', 'bank', 'source'])
  add('toAccount', ['to account', 'to', 'destination', 'to acct'])
  add('method', ['paid by', 'payment method', 'method', 'mode', 'payment mode', 'pay mode', 'paid via', 'via', 'payment type', 'instrument', 'paid using'])
  return map
})()

function headingKey(cell: string): string {
  return cell
    .toLowerCase()
    .replace(/[₹()[\]]/g, ' ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
}

/** The role a heading names, if it is a heading Ventrafin recognises. */
export function roleFromHeading(cell: string): ColumnRole | null {
  return HEADINGS[headingKey(cell)] ?? null
}

function looksLikeValue(cell: string, today: string): boolean {
  if (!cell) return false
  const amount = parseSignedAmount(cell)
  if (amount && amount.paise > 0) return true
  return parseDateInput(cell, today)?.ok === true
}

/** Whether the first pasted row is headings rather than a transaction. */
export function isHeadingRow(cells: readonly string[], today: string): boolean {
  const filled = cells.filter((c) => c !== '')
  if (filled.length === 0 || filled.some((c) => looksLikeValue(c, today))) return false
  const recognised = filled.filter((c) => roleFromHeading(c) !== null).length
  return recognised >= 1 && recognised * 2 >= filled.length
}

// ---------------------------------------------------------------------------
// Guessing columns
// ---------------------------------------------------------------------------

export interface PasteTable {
  /** The heading row, if the paste started with one. */
  headings: string[] | null
  /** Data rows, each padded to `columnCount` cells. */
  rows: string[][]
  columnCount: number
}

export function readPaste(text: string, today: string): PasteTable {
  return readTable(splitClipboard(text), today)
}

/** Rows of cells (pasted, or from a CSV file) as a table, with the heading row detected. */
export function readTable(all: readonly string[][], today: string): PasteTable {
  const columnCount = Math.max(0, ...all.map((r) => r.length))
  const padded = all.map((r) => [...r, ...Array<string>(columnCount - r.length).fill('')])
  if (padded.length > 0 && isHeadingRow(padded[0]!, today)) {
    return { headings: padded[0]!, rows: padded.slice(1), columnCount }
  }
  return { headings: null, rows: padded, columnCount }
}

function share(values: readonly string[], test: (v: string) => boolean): number {
  const filled = values.filter((v) => v !== '')
  if (filled.length === 0) return 0
  return filled.filter(test).length / filled.length
}

const ENOUGH = 0.6

/**
 * Which role each column plays. Headings win when present; otherwise each
 * column is judged by its values: dates, amounts, type words, payment
 * methods, account names, category names; the wordiest remaining column is
 * the description. Two amount columns that are never both filled are a bank
 * statement's Withdrawal / Deposit pair.
 */
export function guessRoles(table: PasteTable, ctx: EntryContext): ColumnRole[] {
  const n = table.columnCount
  const roles: ColumnRole[] = Array<ColumnRole>(n).fill('ignore')
  const taken = new Set<ColumnRole>()
  const column = (c: number) => table.rows.map((r) => r[c] ?? '')

  if (table.headings) {
    table.headings.forEach((h, c) => {
      const role = roleFromHeading(h)
      if (!role || role === 'ignore') return
      if (SINGLE_ROLES.has(role) && taken.has(role)) return
      // A heading only counts if the values agree ("Expense" over a column of
      // "Milk", "Petrol" is a description, not an amount).
      if (!valuesFit(role, column(c), ctx)) return
      roles[c] = role
      taken.add(role)
    })
    // (A lone "Debit" or "Spent" column keeps its meaning: every row is spending.)
    if (roles.some((r) => r === 'description')) return roles
    // Headings without a description column: fall through and guess it.
  }

  const free = (c: number) => roles[c] === 'ignore' && !(table.headings && roleFromHeading(table.headings[c] ?? '') === 'ignore')
  const pick = (role: ColumnRole, score: (c: number) => number) => {
    if (taken.has(role)) return
    let best = -1
    let bestScore = ENOUGH
    for (let c = 0; c < n; c++) {
      if (!free(c)) continue
      const s = score(c)
      if (s >= bestScore && (best < 0 || s > bestScore)) {
        best = c
        bestScore = s
      }
    }
    if (best >= 0) {
      roles[best] = role
      taken.add(role)
    }
  }

  pick('date', (c) => share(column(c), (v) => parseDateInput(v, ctx.today)?.ok === true))

  if (!taken.has('amount') && !taken.has('withdrawal') && !taken.has('deposit')) {
    const amountColumns: number[] = []
    for (let c = 0; c < n; c++) {
      if (free(c) && share(column(c), (v) => parseSignedAmount(v) !== null) >= ENOUGH) amountColumns.push(c)
    }
    const [a, b] = amountColumns
    if (a !== undefined && b !== undefined && complementary(column(a), column(b))) {
      roles[a] = 'withdrawal'
      roles[b] = 'deposit'
      taken.add('withdrawal').add('deposit')
    } else if (a !== undefined) {
      roles[a] = 'amount'
      taken.add('amount')
    }
  }

  pick('type', (c) => share(column(c), (v) => Boolean(parseTxnType(v))))
  pick('method', (c) => share(column(c), (v) => {
    const m = parseMethod(v)
    return m !== null && m !== 'invalid'
  }))
  pick('account', (c) => share(column(c), (v) => matchAccount(v, ctx.accounts) !== null || archivedAccountNamed(v, ctx.accounts) !== null))
  const categoryNames = new Set(ctx.categories.map((cat) => cat.name.trim().toLowerCase()))
  pick('category', (c) => share(column(c), (v) => v.toLowerCase() === 'auto' || categoryNames.has(v.toLowerCase())))

  if (!roles.includes('description')) {
    let best = -1
    let bestLetters = 0
    for (let c = 0; c < n; c++) {
      if (!free(c)) continue
      const letters = column(c).join('').replace(/[^\p{L}]/gu, '').length
      if (letters > bestLetters) {
        best = c
        bestLetters = letters
      }
    }
    if (best >= 0) roles[best] = 'description'
  }
  return roles
}

function valuesFit(role: ColumnRole, values: readonly string[], ctx: EntryContext): boolean {
  const filled = values.filter((v) => v !== '')
  if (filled.length === 0) return true
  switch (role) {
    case 'date':
      return share(filled, (v) => parseDateInput(v, ctx.today, { allowExcelSerial: true })?.ok === true) >= 0.5
    case 'amount':
    case 'withdrawal':
    case 'deposit':
      return share(filled, (v) => parseSignedAmount(v) !== null) >= 0.5
    default:
      return true
  }
}

/** Two amount columns where each row fills exactly one: withdrawals and deposits. */
function complementary(a: readonly string[], b: readonly string[]): boolean {
  let rows = 0
  let exactlyOne = 0
  for (let i = 0; i < a.length; i++) {
    const hasA = isNonZeroAmount(a[i] ?? '')
    const hasB = isNonZeroAmount(b[i] ?? '')
    if (!hasA && !hasB) continue
    rows++
    if (hasA !== hasB) exactlyOne++
  }
  return rows > 0 && exactlyOne / rows >= 0.8
}

function isNonZeroAmount(v: string): boolean {
  const a = parseSignedAmount(v)
  return a !== null && a.paise > 0
}

// ---------------------------------------------------------------------------
// Pasted rows -> grid rows
// ---------------------------------------------------------------------------

export interface PasteDefaults {
  /** Account name for rows that don't say. */
  account: string
  /** "Paid by" label for expense rows that don't say. */
  method: string
}

export interface PastedRow {
  raw: RawRow
  /** 1-based line number in what was pasted (headings included). */
  line: number
}

/**
 * Builds grid rows from the pasted cells and the chosen roles. Missing
 * dates become today; missing accounts and (for expenses) payment methods
 * take the Add page's defaults. A sign on the amount (`-500`, `(500)`,
 * `500 Dr`, `500 Cr`) or a Withdrawal / Deposit column decides the type
 * when there is no Type column.
 */
export function toGridRows(table: PasteTable, roles: readonly ColumnRole[], ctx: EntryContext, defaults: PasteDefaults): PastedRow[] {
  const first = (role: ColumnRole) => roles.indexOf(role)
  const hasType = first('type') >= 0
  const offset = table.headings ? 2 : 1

  return table.rows.map((cells, i) => {
    const get = (role: ColumnRole) => {
      const c = first(role)
      return c >= 0 ? (cells[c] ?? '') : ''
    }
    const raw = emptyRow()
    raw.date = get('date')
    raw.description = roles
      .map((r, c) => (r === 'description' ? (cells[c] ?? '') : ''))
      .filter(Boolean)
      .join(' ')
    raw.type = get('type')
    raw.category = get('category')
    raw.account = get('account')
    raw.toAccount = get('toAccount')
    raw.method = get('method')

    let signType: TxnType | undefined
    const withdrawal = get('withdrawal')
    const deposit = get('deposit')
    if (first('withdrawal') >= 0 || first('deposit') >= 0) {
      const w = parseSignedAmount(withdrawal)
      const d = parseSignedAmount(deposit)
      const wOk = w !== null && w.paise > 0
      const dOk = d !== null && d.paise > 0
      if (wOk && dOk) raw.amount = `${withdrawal} / ${deposit}`
      else if (wOk) {
        raw.amount = formatAmountInput(w.paise)
        signType = 'expense'
      } else if (dOk) {
        raw.amount = formatAmountInput(d.paise)
        signType = 'income'
      } else raw.amount = withdrawal || deposit
    } else {
      const text = get('amount')
      const a = parseSignedAmount(text)
      if (a) {
        raw.amount = formatAmountInput(a.paise)
        signType = a.credit ? 'income' : a.negative ? 'expense' : undefined
      } else raw.amount = text
    }
    if (!(hasType && raw.type.trim()) && signType) raw.type = txnTypeLabel(signType)

    const type = parseTxnType(raw.type) ?? 'expense'
    if (!raw.date.trim()) raw.date = formatDateIndian(ctx.today)
    if (!raw.account.trim()) raw.account = defaults.account
    if (!raw.method.trim() && type === 'expense') raw.method = defaults.method
    if (!raw.category.trim()) raw.category = AUTO_CATEGORY

    for (const field of ['date', 'amount', 'type', 'method', 'account', 'toAccount'] as const) {
      raw[field] = tidyCell(field, raw[field], ctx)
    }
    raw.category = tidyCell('category', raw.category, ctx, type)
    return { raw, line: i + offset }
  })
}
