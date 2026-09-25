// Archived accounts and categories (PRD § 4.1, § 4.3): names checked the
// way the database checks them, pickers for new entries without archived
// ones, existing values kept as "Name (archived)", and the database's
// "keep one active account" refusal in plain words.
import { describe, expect, it } from 'vitest'
import { cellEdit, editorText } from '@/lib/cellEdit'
import { matchAccount, matchCategory, parseEntryRow, emptyRow, type EntryContext } from '@/lib/entryRow'
import { AppError, describeError } from '@/lib/errors'
import { accountFromRow, accountNameError, activeOnly, pickerLabel, type Account } from '@/lib/models'
import { accountOptions, categoryOptions } from '@/lib/options'
import { ACCOUNTS, CATEGORIES, makeTxn } from '../support/fakeRepository'

const OLD_BANK: Account = { id: 'acc-old', name: 'Old Bank', type: 'bank', archived: true }
const accounts = [...ACCOUNTS, OLD_BANK]
const ctx: EntryContext = { accounts, categories: CATEGORIES, today: '2026-09-25' }

describe('account names', () => {
  it('mirror the database: 1–60 characters, unique ignoring case and spaces, archived ones included', () => {
    expect(accountNameError('  ', { existing: accounts })).toBe('Enter a name')
    expect(accountNameError('x'.repeat(61), { existing: accounts })).toBe('Keep it to 60 characters or fewer')
    expect(accountNameError('x'.repeat(60), { existing: accounts })).toBeNull()
    expect(accountNameError(' cash ', { existing: accounts })).toBe('You already have an account called "Cash"')
    expect(accountNameError('OLD BANK', { existing: accounts })).toBe('You already have an account called "Old Bank" (archived)')
    expect(accountNameError('HDFC', { existing: accounts })).toBeNull()
  })

  it('renaming an account to its own name (or a new case of it) is fine', () => {
    expect(accountNameError('CASH', { existing: accounts, exceptId: 'acc-cash' })).toBeNull()
  })
})

describe('rows from the server', () => {
  it('an account row without `archived` (before the migration) counts as active', () => {
    expect(accountFromRow({ id: 'a', name: 'Cash', type: 'cash' })).toEqual({ id: 'a', name: 'Cash', type: 'cash', archived: false })
    expect(accountFromRow({ id: 'a', name: 'Cash', type: 'cash', archived: true }).archived).toBe(true)
  })
})

describe('pickers for new entries', () => {
  it('leave archived accounts and categories out, except the value a row already has', () => {
    expect(activeOnly(accounts).map((a) => a.id)).toEqual(['acc-bank', 'acc-cash', 'acc-cc'])
    expect(activeOnly(accounts, 'acc-old').map((a) => a.id)).toContain('acc-old')
    expect(accountOptions(accounts).map((o) => o.label)).toEqual(['Bank', 'Cash', 'Credit Card'])
    expect(accountOptions(accounts, 'acc-old').map((o) => o.label)).toContain('Old Bank (archived)')
    expect(categoryOptions(CATEGORIES, 'expense').map((o) => o.label)).not.toContain('Old stuff')
    expect(categoryOptions(CATEGORIES, 'expense', 'cat-old').map((o) => o.label)).toContain('Old stuff (archived)')
    expect(pickerLabel({ name: 'Cash', archived: false })).toBe('Cash')
  })

  it('typed names match active accounts only; the kept value also by its "(archived)" label', () => {
    expect(matchAccount('old bank', accounts)).toBeNull()
    expect(matchAccount('Old Bank (archived)', accounts, 'acc-old')?.id).toBe('acc-old')
    // A type word picks the only *active* account of that type.
    expect(matchAccount('bank', accounts)?.id).toBe('acc-bank')
    expect(matchCategory('old stuff', 'expense', CATEGORIES)).toBeNull()
    expect(matchCategory('Old stuff (archived)', 'expense', CATEGORIES, 'cat-old')?.id).toBe('cat-old')
  })

  it('a new row on an archived account says so', () => {
    const p = parseEntryRow(emptyRow({ date: '25/09/2026', amount: '100', account: 'Old Bank', method: 'Cash' }), ctx)
    expect(p.draft).toBeNull()
    expect(p.issues).toContainEqual({ field: 'account', message: '"Old Bank" is archived. Choose another account', level: 'error' })
  })
})

describe('editing a row that uses an archived account or category', () => {
  const t = makeTxn('t1', { accountId: 'acc-old', categoryId: 'cat-old' })

  it('shows it as "(archived)", and leaving it as it is changes nothing', () => {
    expect(editorText(t, 'accountId', ctx)).toBe('Old Bank (archived)')
    expect(editorText(t, 'categoryId', ctx)).toBe('Old stuff (archived)')
    expect(cellEdit(t, 'accountId', 'Old Bank (archived)', ctx)).toEqual({ kind: 'unchanged' })
    expect(cellEdit(t, 'categoryId', 'Old stuff (archived)', ctx)).toEqual({ kind: 'unchanged' })
    expect(cellEdit(t, 'accountId', 'Cash', ctx)).toEqual({ kind: 'patch', patch: { accountId: 'acc-cash' } })
  })

  it('another row cannot be moved onto an archived one', () => {
    const other = makeTxn('t2')
    expect(cellEdit(other, 'accountId', 'Old Bank', ctx)).toEqual({ kind: 'invalid', message: '"Old Bank" is archived. Choose another account' })
    expect(cellEdit(other, 'categoryId', 'Old stuff', ctx)).toEqual({ kind: 'invalid', message: '"Old stuff" is archived. Choose another category' })
  })
})

describe('describeError', () => {
  it('the last active account: the database says exactly what to do', () => {
    expect(describeError(new AppError('Keep at least one active account.', '23514'))).toBe('Keep at least one active account.')
    // Other check violations keep the general wording.
    expect(describeError(new AppError('new row violates check constraint "transactions_amount_check"', '23514'))).toMatch(/^Some values were not accepted/)
  })
})
