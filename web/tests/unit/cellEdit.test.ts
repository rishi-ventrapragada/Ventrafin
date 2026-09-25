// Editing one cell in the Transactions table: what gets saved.
import { describe, expect, it } from 'vitest'
import { cellEdit, editorText } from '@/lib/cellEdit'
import type { EntryContext } from '@/lib/entryRow'
import { ACCOUNTS, CATEGORIES, makeTxn } from '../support/fakeRepository'

const ctx: EntryContext = { accounts: ACCOUNTS, categories: CATEGORIES, today: '2026-09-25' }
const t = makeTxn('t1', { categoryId: 'cat-food', autoCategorized: true })

describe('cellEdit', () => {
  it('editor text is the cell as the user reads it', () => {
    expect(editorText(t, 'date', ctx)).toBe('20/09/2026')
    expect(editorText(t, 'amountPaise', ctx)).toBe('123.45')
    expect(editorText(t, 'categoryId', ctx)).toBe('Food')
    expect(editorText(makeTxn('u', { categoryId: null }), 'categoryId', ctx)).toBe('Auto')
    expect(editorText(t, 'paymentMethod', ctx)).toBe('UPI')
  })

  it('unchanged text saves nothing', () => {
    for (const field of ['date', 'description', 'amountPaise', 'type', 'categoryId', 'accountId', 'paymentMethod'] as const) {
      expect(cellEdit(t, field, editorText(t, field, ctx), ctx), field).toEqual({ kind: 'unchanged' })
    }
  })

  it('changing the category sends only category_id (the database learns from it)', () => {
    expect(cellEdit(t, 'categoryId', 'groceries', ctx)).toEqual({ kind: 'patch', patch: { categoryId: 'cat-groc' } })
  })

  it('"Auto" hands the category back to the database', () => {
    expect(cellEdit(t, 'categoryId', 'Auto', ctx)).toEqual({ kind: 'patch', patch: { categoryId: null } })
  })

  it('a category of the wrong kind is refused', () => {
    expect(cellEdit(t, 'categoryId', 'Salary', ctx)).toEqual({ kind: 'invalid', message: 'No expense category called "Salary"' })
  })

  it('dates and amounts are parsed like the Add grid', () => {
    expect(cellEdit(t, 'date', '21/9', ctx)).toEqual({ kind: 'patch', patch: { date: '2026-09-21' } })
    expect(cellEdit(t, 'amountPaise', '₹1,500', ctx)).toEqual({ kind: 'patch', patch: { amountPaise: 150000 } })
    expect(cellEdit(t, 'amountPaise', '0', ctx).kind).toBe('invalid')
  })

  it('expense <-> income clears the category so the database picks one of the right kind', () => {
    expect(cellEdit(t, 'type', 'Income', ctx)).toEqual({ kind: 'patch', patch: { type: 'income', categoryId: null, toAccountId: null } })
  })

  it('becoming a transfer first asks where the money went', () => {
    expect(cellEdit(t, 'type', 'transfer', ctx)).toEqual({ kind: 'needsTransferTarget' })
  })

  it('a transfer\'s accounts must differ', () => {
    const tr = makeTxn('t2', { type: 'transfer', accountId: 'acc-bank', toAccountId: 'acc-cash', categoryId: null })
    expect(cellEdit(tr, 'toAccountId', 'Bank', ctx).kind).toBe('invalid')
    expect(cellEdit(tr, 'toAccountId', 'Credit Card', ctx)).toEqual({ kind: 'patch', patch: { toAccountId: 'acc-cc' } })
  })

  it('expenses keep a payment method', () => {
    expect(cellEdit(t, 'paymentMethod', '', ctx).kind).toBe('invalid')
    expect(cellEdit(t, 'paymentMethod', 'phonepe', ctx)).toEqual({ kind: 'unchanged' }) // already UPI
    expect(cellEdit(t, 'paymentMethod', 'debit card', ctx)).toEqual({ kind: 'patch', patch: { paymentMethod: 'debit' } })
  })
})
