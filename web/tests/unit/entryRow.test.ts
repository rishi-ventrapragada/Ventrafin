// A grid row's validation: the same rules as the phone's entry form.
import { describe, expect, it } from 'vitest'
import { emptyRow, isBlankRow, parseEntryRow, tidyCell, type EntryContext, type RawRow } from '@/lib/entryRow'
import { ACCOUNTS, CATEGORIES } from '../support/fakeRepository'

const ctx: EntryContext = { accounts: ACCOUNTS, categories: CATEGORIES, today: '2026-09-25' }

const row = (over: Partial<RawRow>) =>
  emptyRow({ date: '25/09/2026', type: 'Expense', account: 'Cash', method: 'UPI', category: 'Auto', ...over })

const errors = (raw: RawRow) =>
  parseEntryRow(raw, ctx)
    .issues.filter((i) => i.level === 'error')
    .map((i) => `${i.field}: ${i.message}`)

describe('parseEntryRow', () => {
  it('a pre-filled row with nothing typed is blank and ignored', () => {
    expect(isBlankRow(row({}))).toBe(true)
    expect(parseEntryRow(row({}), ctx)).toEqual({ blank: true, draft: null, issues: [] })
  })

  it('a complete expense becomes a draft in paise with an ISO date', () => {
    expect(parseEntryRow(row({ description: ' Swiggy dinner ', amount: '1,250.50' }), ctx)).toEqual({
      blank: false,
      issues: [],
      draft: {
        date: '2026-09-25',
        amountPaise: 125050,
        description: 'Swiggy dinner',
        type: 'expense',
        accountId: 'acc-cash',
        toAccountId: null,
        categoryId: null,
        paymentMethod: 'upi',
      },
    })
  })

  it('amount is required and must be positive', () => {
    expect(errors(row({ description: 'Milk' }))).toEqual(['amount: Enter an amount'])
    expect(errors(row({ amount: '0' }))).toEqual(['amount: Amount must be more than zero'])
    expect(errors(row({ amount: '-50' }))).toEqual([
      'amount: Enter the amount without a minus sign, and set Type to Expense or Income',
    ])
    expect(errors(row({ amount: '12.345' }))).toEqual(['amount: "12.345" is not an amount'])
  })

  it('payment method is required for expenses only (as on the phone)', () => {
    expect(errors(row({ amount: '100', method: '' }))).toEqual(['method: Choose how you paid: Cash, UPI, Debit or Card'])
    expect(errors(row({ amount: '100', method: 'cheque' }))).toEqual([
      'method: "cheque" is not a payment method. Use Cash, UPI, Debit or Card',
    ])
    expect(parseEntryRow(row({ amount: '50000', type: 'Income', method: '' }), ctx).draft?.paymentMethod).toBeNull()
  })

  it('a chosen category is used; the other kind or an unknown name falls back to Auto with a note', () => {
    expect(parseEntryRow(row({ amount: '100', category: 'food' }), ctx).draft?.categoryId).toBe('cat-food')
    const other = parseEntryRow(row({ amount: '100', category: 'Salary' }), ctx)
    expect(other.draft?.categoryId).toBeNull()
    expect(other.issues[0]?.message).toBe('"Salary" is an income category. Ventrafin will pick one for this expense')
  })

  it('transfers: need a different To account; category and method optional', () => {
    const t = row({ amount: '2000', type: 'Transfer', account: 'Bank', toAccount: 'Cash', method: '' })
    expect(parseEntryRow(t, ctx).draft).toMatchObject({ type: 'transfer', accountId: 'acc-bank', toAccountId: 'acc-cash', categoryId: null })
    expect(errors(row({ amount: '2000', type: 'Transfer', toAccount: '' }))).toEqual(['toAccount: Choose the account the money went to'])
  })

  it('accounts by name, or by type word when only one account has that type', () => {
    expect(parseEntryRow(row({ amount: '1', account: 'credit card' }), ctx).draft?.accountId).toBe('acc-cc')
    expect(parseEntryRow(row({ amount: '1', account: 'cc' }), ctx).draft?.accountId).toBe('acc-cc')
    expect(errors(row({ amount: '1', account: 'HDFC' }))).toEqual(['account: No account called "HDFC"'])
  })

  it('type words', () => {
    for (const [text, type] of [['e', 'expense'], ['Dr', 'expense'], ['income', 'income'], ['cr', 'income'], ['T', 'transfer']] as const) {
      expect(parseEntryRow(row({ amount: '1', type: text, toAccount: 'Bank', method: 'Cash' }), ctx).draft?.type, text).toBe(type)
    }
    expect(errors(row({ amount: '1', type: 'gift' }))).toEqual(['type: "gift" is not a type. Use Expense, Income or Transfer'])
  })

  it('descriptions longer than the database allows are refused', () => {
    expect(errors(row({ amount: '1', description: 'x'.repeat(501) }))).toEqual([
      'description: Description is too long (500 characters at most)',
    ])
  })
})

describe('tidyCell (what a cell shows after you leave it)', () => {
  it('normalises dates, amounts and names', () => {
    expect(tidyCell('date', '24-9-26', ctx)).toBe('24/09/2026')
    expect(tidyCell('date', 'ctrl', ctx)).toBe('ctrl')
    expect(tidyCell('amount', '₹1250.5', ctx)).toBe('1,250.50')
    expect(tidyCell('method', 'gpay', ctx)).toBe('UPI')
    expect(tidyCell('type', 'cr', ctx)).toBe('Income')
    expect(tidyCell('account', 'cash', ctx)).toBe('Cash')
    expect(tidyCell('category', 'GROCERIES', ctx, 'expense')).toBe('Groceries')
    expect(tidyCell('category', '', ctx)).toBe('Auto')
  })
})
