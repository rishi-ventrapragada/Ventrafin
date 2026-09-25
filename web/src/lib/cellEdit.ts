// Editing one cell of an existing transaction in the Transactions table:
// the text shown in the editor, and the change to save when it's done.
// Uses the same vocabularies and rules as new entries (entryRow.ts).
import { formatDateIndian, parseDateInput } from './dates'
import {
  AUTO_CATEGORY,
  DESCRIPTION_MAX,
  archivedAccountNamed,
  isAutoCategory,
  matchAccount,
  matchCategory,
  parseMethod,
  parseTxnType,
  type EntryContext,
} from './entryRow'
import { formatAmountInput, parseSignedAmount } from './money'
import { PAYMENT_METHODS, pickerLabel, txnTypeLabel, type Txn, type TxnPatch } from './models'

export const EDITABLE_FIELDS = ['date', 'description', 'categoryId', 'amountPaise', 'type', 'accountId', 'toAccountId', 'paymentMethod'] as const
export type EditableField = (typeof EDITABLE_FIELDS)[number]

export function isEditableField(f: string): f is EditableField {
  return (EDITABLE_FIELDS as readonly string[]).includes(f)
}

/** The text a cell's editor starts with (an archived account or category as `Name (archived)`). */
export function editorText(t: Txn, field: EditableField, ctx: EntryContext): string {
  const named = (item: { name: string; archived: boolean } | undefined) => (item ? pickerLabel(item) : '')
  switch (field) {
    case 'date':
      return formatDateIndian(t.date)
    case 'description':
      return t.description
    case 'amountPaise':
      return formatAmountInput(t.amountPaise)
    case 'type':
      return txnTypeLabel(t.type)
    case 'categoryId':
      return t.categoryId ? named(ctx.categories.find((c) => c.id === t.categoryId)) : AUTO_CATEGORY
    case 'accountId':
      return named(ctx.accounts.find((a) => a.id === t.accountId))
    case 'toAccountId':
      return t.toAccountId ? named(ctx.accounts.find((a) => a.id === t.toAccountId)) : ''
    case 'paymentMethod':
      return t.paymentMethod ? PAYMENT_METHODS.find((m) => m.value === t.paymentMethod)!.label : ''
  }
}

function noAccount(value: string, ctx: EntryContext): string {
  const archived = archivedAccountNamed(value, ctx.accounts)
  return archived ? `"${archived.name}" is archived. Choose another account` : `No account called "${value}"`
}

export type CellEditResult =
  | { kind: 'unchanged' }
  | { kind: 'invalid'; message: string }
  /** Becoming a transfer needs a destination account first. */
  | { kind: 'needsTransferTarget' }
  | { kind: 'patch'; patch: TxnPatch }

/** What to save after `field` of `t` was edited to `text`. */
export function cellEdit(t: Txn, field: EditableField, text: string, ctx: EntryContext): CellEditResult {
  const unchanged = { kind: 'unchanged' } as const
  const invalid = (message: string) => ({ kind: 'invalid', message }) as const
  const patch = (p: TxnPatch) => ({ kind: 'patch', patch: p }) as const
  const value = text.trim()

  switch (field) {
    case 'date': {
      const d = parseDateInput(value, ctx.today, { allowExcelSerial: true })
      if (!d) return invalid('Enter a date')
      if (!d.ok) return invalid(d.error)
      return d.iso === t.date ? unchanged : patch({ date: d.iso })
    }
    case 'description':
      if ([...value].length > DESCRIPTION_MAX) return invalid(`Description is too long (${DESCRIPTION_MAX} characters at most)`)
      return value === t.description ? unchanged : patch({ description: value })
    case 'amountPaise': {
      const a = parseSignedAmount(value)
      if (!a) return invalid(value ? `"${value}" is not an amount` : 'Enter an amount')
      if (a.negative) return invalid('Enter the amount without a minus sign, and set Type to Expense or Income')
      if (a.paise <= 0) return invalid('Amount must be more than zero')
      return a.paise === t.amountPaise ? unchanged : patch({ amountPaise: a.paise })
    }
    case 'type': {
      const type = parseTxnType(value)
      if (!type) return invalid(`"${value}" is not a type. Use Expense, Income or Transfer`)
      if (type === t.type) return unchanged
      if (type === 'transfer') return { kind: 'needsTransferTarget' }
      // A category of the other kind can't stay: the database picks a new one.
      return patch({ type, categoryId: null, toAccountId: null })
    }
    case 'categoryId': {
      if (t.type === 'transfer') return unchanged
      if (isAutoCategory(value)) {
        // Back to automatic: the database categorizes it again.
        return t.categoryId === null ? unchanged : patch({ categoryId: null })
      }
      // Archived categories can't be picked, but the row's own one can stay.
      const c = matchCategory(value, t.type, ctx.categories, t.categoryId)
      if (!c) {
        const archived = ctx.categories.find((x) => x.kind === t.type && x.archived && x.name.trim().toLowerCase() === value.toLowerCase())
        return invalid(archived ? `"${archived.name}" is archived. Choose another category` : `No ${t.type} category called "${value}"`)
      }
      return c.id === t.categoryId ? unchanged : patch({ categoryId: c.id })
    }
    case 'accountId': {
      // Archived accounts can't be picked, but the row's own one can stay.
      const a = matchAccount(value, ctx.accounts, t.accountId)
      if (!a) return invalid(value ? noAccount(value, ctx) : 'Choose an account')
      if (a.id === t.accountId) return unchanged
      if (t.type === 'transfer' && a.id === t.toAccountId) return invalid('The "From" and "To" accounts must be different')
      return patch({ accountId: a.id })
    }
    case 'toAccountId': {
      if (t.type !== 'transfer') return unchanged
      const a = matchAccount(value, ctx.accounts, t.toAccountId)
      if (!a) return invalid(value ? noAccount(value, ctx) : 'Choose the account the money went to')
      if (a.id === t.toAccountId) return unchanged
      if (a.id === t.accountId) return invalid('The "From" and "To" accounts must be different')
      return patch({ toAccountId: a.id })
    }
    case 'paymentMethod': {
      const m = parseMethod(value)
      if (m === 'invalid') return invalid(`"${value}" is not a payment method. Use Cash, UPI, Debit or Card`)
      if (m === null && t.type === 'expense') return invalid('Expenses need a payment method: Cash, UPI, Debit or Card')
      return m === t.paymentMethod ? unchanged : patch({ paymentMethod: m })
    }
  }
}
