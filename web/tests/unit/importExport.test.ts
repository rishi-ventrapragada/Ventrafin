// Phase 7: CSV import (reading files, the round trip from Ventrafin's own
// export), export ranges and file names, spotting rows already saved, and
// the passkey error wording.
import { afterEach, describe, expect, it } from 'vitest'
import { classifyPasskeyError, describePasskeyError, hasPasskeyHint, rememberPasskeyHint } from '@/data/passkeys'
import { decodeCsvBytes, detectSeparator, fileProblem, readCsv, stripFormulaGuard } from '@/lib/csvImport'
import { dateSpan, duplicateKey, findAlreadySaved } from '@/lib/duplicates'
import { parseEntryRow, type EntryContext } from '@/lib/entryRow'
import {
  exportFileName,
  financialYearLabel,
  financialYearStart,
  presetRange,
  rangeLabel,
  rangeProblem,
} from '@/lib/exportRange'
import { guessRoles, toGridRows } from '@/lib/paste'
import { ACCOUNTS, CATEGORIES } from '../support/fakeRepository'

const ctx: EntryContext = { accounts: ACCOUNTS, categories: CATEGORIES, today: '2026-09-25' }
const defaults = { account: 'Cash', method: 'UPI' }

function importText(text: string) {
  const table = readCsv(text, ctx.today)
  const roles = guessRoles(table, ctx)
  const rows = toGridRows(table, roles, ctx, defaults)
  return { table, roles, parsed: rows.map((r) => parseEntryRow(r.raw, ctx)) }
}

/**
 * export_transactions_csv() output, byte for byte as pinned by
 * supabase/tests/08_csv_export.test.sql.
 */
const EXPORTED =
  'Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n' +
  "2024-12-31,'-5 discount,200.00,Expense,Food,Bank,,Debit\r\n" +
  '2025-01-05,Swiggy dinner,450.00,Expense,Food,Bank,,UPI\r\n' +
  '2025-01-05,"Zqx ""odd"", item",0.05,Expense,Uncategorized,Bank,,Cash\r\n' +
  '2025-01-06,"\'=HYPERLINK(""x"")",1234.56,Expense,Groceries,Bank,,Card\r\n' +
  '2025-01-07,Pay,5000.00,Income,Salary,Bank,,\r\n' +
  '2025-01-08,ATM,1000.00,Transfer,,Bank,Cash,\r\n' +
  '2025-01-09,"Line1\nLine2",1.00,Expense,Food,Bank,,Cash\r\n'

describe('reading a CSV file', () => {
  it('re-imports a Ventrafin export exactly (every column recognised from its heading)', () => {
    const { table, roles, parsed } = importText(EXPORTED)
    expect(table.headings).not.toBeNull()
    expect(roles).toEqual(['date', 'description', 'amount', 'type', 'category', 'account', 'toAccount', 'method'])
    expect(parsed.every((p) => p.draft)).toBe(true)
    expect(parsed.map((p) => p.draft)).toEqual([
      { date: '2024-12-31', description: '-5 discount', amountPaise: 20000, type: 'expense', accountId: 'acc-bank', toAccountId: null, categoryId: 'cat-food', paymentMethod: 'debit' },
      { date: '2025-01-05', description: 'Swiggy dinner', amountPaise: 45000, type: 'expense', accountId: 'acc-bank', toAccountId: null, categoryId: 'cat-food', paymentMethod: 'upi' },
      // Uncategorized goes back to Auto: the database categorizes it again.
      { date: '2025-01-05', description: 'Zqx "odd", item', amountPaise: 5, type: 'expense', accountId: 'acc-bank', toAccountId: null, categoryId: null, paymentMethod: 'cash' },
      { date: '2025-01-06', description: '=HYPERLINK("x")', amountPaise: 123456, type: 'expense', accountId: 'acc-bank', toAccountId: null, categoryId: 'cat-groc', paymentMethod: 'card' },
      { date: '2025-01-07', description: 'Pay', amountPaise: 500000, type: 'income', accountId: 'acc-bank', toAccountId: null, categoryId: 'cat-salary', paymentMethod: null },
      { date: '2025-01-08', description: 'ATM', amountPaise: 100000, type: 'transfer', accountId: 'acc-bank', toAccountId: 'acc-cash', categoryId: null, paymentMethod: null },
      { date: '2025-01-09', description: 'Line1\nLine2', amountPaise: 100, type: 'expense', accountId: 'acc-bank', toAccountId: null, categoryId: 'cat-food', paymentMethod: 'cash' },
    ])
  })

  it('a bank statement saved from Excel: withdrawal/deposit columns, balance ignored, Indian dates', () => {
    const { roles, parsed } = importText(
      'Txn Date,Narration,Withdrawal Amt,Deposit Amt,Closing Balance\r\n' +
        '01/09/2026,UPI-SWIGGY-12345,"1,250.00",,"48,750.00"\r\n' +
        '02/09/2026,SALARY SEP,,"85,000.00","1,33,750.00"\r\n',
    )
    expect(roles).toEqual(['date', 'description', 'withdrawal', 'deposit', 'ignore'])
    expect(parsed.map((p) => [p.draft?.date, p.draft?.type, p.draft?.amountPaise, p.draft?.accountId])).toEqual([
      ['2026-09-01', 'expense', 125000, 'acc-cash'],
      ['2026-09-02', 'income', 8500000, 'acc-cash'],
    ])
  })

  it('semicolon files (Excel where the decimal mark is a comma) and tab files', () => {
    expect(detectSeparator('Date;Description;Amount\r\n25/09/2026;Tea;20\r\n')).toBe(';')
    expect(detectSeparator('Date\tDescription\tAmount\n')).toBe('\t')
    expect(detectSeparator('Date,"Desc; with, stuff",Amount\n')).toBe(',')
    expect(detectSeparator('just one column\n')).toBe(',')
    const { parsed } = importText('Date;Description;Amount;Paid by\r\n25/09/2026;Tea;20;Cash\r\n')
    expect(parsed[0]!.draft).toMatchObject({ description: 'Tea', amountPaise: 2000, paymentMethod: 'cash' })
  })

  it('rows with problems are marked, not dropped', () => {
    const { parsed } = importText('Date,Description,Amount\r\n25/09/2026,Tea,abc\r\n31/02/2026,Milk,40\r\n')
    expect(parsed.map((p) => p.draft === null)).toEqual([true, true])
    expect(parsed[0]!.issues[0]!.field).toBe('amount')
    expect(parsed[1]!.issues[0]!.field).toBe('date')
  })

  it('strips the formula guard only where it was added', () => {
    expect(stripFormulaGuard("'=SUM(A1)")).toBe('=SUM(A1)')
    expect(stripFormulaGuard("'-5")).toBe('-5')
    expect(stripFormulaGuard("'+91")).toBe('+91')
    expect(stripFormulaGuard("'@home")).toBe('@home')
    expect(stripFormulaGuard("'quoted'")).toBe("'quoted'")
    expect(stripFormulaGuard("Rishi's shop")).toBe("Rishi's shop")
  })

  it('decodes UTF-8 with or without a byte-order mark, and Excel\'s ANSI CSV as Windows-1252', () => {
    const utf8 = new TextEncoder().encode('﻿Amount (₹)\r\n')
    expect(decodeCsvBytes(utf8)).toBe('Amount (₹)\r\n')
    expect(decodeCsvBytes(new TextEncoder().encode('Café'))).toBe('Café')
    // "Café" as Windows-1252: 0xE9 alone is not valid UTF-8.
    expect(decodeCsvBytes(new Uint8Array([0x43, 0x61, 0x66, 0xe9]))).toBe('Café')
  })

  it('refuses spreadsheets, empty and oversized files with a way forward', () => {
    expect(fileProblem({ name: 'Statement.XLSX', size: 1000 })).toMatch(/CSV UTF-8/)
    expect(fileProblem({ name: 'a.csv', size: 0 })).toMatch(/empty/)
    expect(fileProblem({ name: 'a.csv', size: 6 * 1024 * 1024 })).toMatch(/5 MB/)
    expect(fileProblem({ name: 'a.csv', size: 1000 })).toBeNull()
  })
})

describe('export ranges', () => {
  it('Indian financial year: April to March', () => {
    expect(financialYearStart('2026-09-25')).toBe('2026-04-01')
    expect(financialYearStart('2026-04-01')).toBe('2026-04-01')
    expect(financialYearStart('2026-03-31')).toBe('2025-04-01')
    expect(financialYearLabel('2026-04-01')).toBe('FY 2026-27')
    expect(financialYearLabel('2099-04-01')).toBe('FY 2099-00')
  })

  it('presets from today (India)', () => {
    const today = '2026-09-25'
    expect(presetRange('thisMonth', today)).toEqual({ from: '2026-09-01', to: '2026-09-30' })
    expect(presetRange('lastMonth', today)).toEqual({ from: '2026-08-01', to: '2026-08-31' })
    expect(presetRange('thisFy', today)).toEqual({ from: '2026-04-01', to: '2027-03-31' })
    expect(presetRange('lastFy', today)).toEqual({ from: '2025-04-01', to: '2026-03-31' })
    expect(presetRange('all', today)).toEqual({ from: null, to: null })
    expect(presetRange('custom', today)).toBeNull()
    expect(presetRange('lastMonth', '2026-01-10')).toEqual({ from: '2025-12-01', to: '2025-12-31' })
    expect(presetRange('thisMonth', '2028-02-10')).toEqual({ from: '2028-02-01', to: '2028-02-29' })
    expect(presetRange('thisFy', '2027-02-01')).toEqual({ from: '2026-04-01', to: '2027-03-31' })
  })

  it('labels, problems and file names', () => {
    expect(rangeLabel({ from: '2026-04-01', to: '2027-03-31' })).toBe('01/04/2026 to 31/03/2027')
    expect(rangeLabel({ from: null, to: null })).toBe('All dates')
    expect(rangeLabel({ from: null, to: '2026-09-25' })).toBe('Up to 25/09/2026')
    expect(rangeProblem({ from: '2026-10-01', to: '2026-09-01' })).toMatch(/after/)
    expect(rangeProblem({ from: '2026-09-01', to: '2026-09-01' })).toBeNull()
    expect(exportFileName({ from: '2026-04-01', to: '2027-03-31' }, '2026-09-25')).toBe(
      'ventrafin-transactions-2026-04-01-to-2027-03-31.csv',
    )
    expect(exportFileName({ from: null, to: null }, '2026-09-25')).toBe('ventrafin-transactions-all-2026-09-25.csv')
    expect(exportFileName({ from: null, to: '2026-01-31' }, '2026-09-25')).toBe('ventrafin-transactions-start-to-2026-01-31.csv')
    expect(exportFileName({ from: '2026-09-01', to: '2026-09-30' }, '2026-09-25', { filtered: true })).toBe(
      'ventrafin-transactions-2026-09-01-to-2026-09-30-filtered.csv',
    )
  })
})

describe('rows already saved', () => {
  const base = { date: '2026-09-01', amountPaise: 125000, type: 'expense' as const, accountId: 'acc-bank', description: 'UPI-SWIGGY-12345' }

  it('same date, amount, type, account and description (case and spacing ignored)', () => {
    expect(duplicateKey(base)).toBe(duplicateKey({ ...base, description: '  upi-swiggy-12345 ' }))
    expect(duplicateKey(base)).not.toBe(duplicateKey({ ...base, accountId: 'acc-cash' }))
    expect(duplicateKey(base)).not.toBe(duplicateKey({ ...base, amountPaise: 125001 }))
    expect(duplicateKey(base)).not.toBe(duplicateKey({ ...base, type: 'income' }))
  })

  it('each saved transaction matches one row: repeats inside the file stay', () => {
    const rows = [
      { key: 1, draft: base },
      { key: 2, draft: base },
      { key: 3, draft: { ...base, description: 'Tea' } },
    ]
    expect([...findAlreadySaved(rows, [base])]).toEqual([1])
    expect([...findAlreadySaved(rows, [base, base])]).toEqual([1, 2])
    expect(findAlreadySaved(rows, []).size).toBe(0)
  })

  it('date span of the rows', () => {
    expect(dateSpan([{ date: '2026-09-02' }, { date: '2025-12-31' }, { date: '2026-01-05' }])).toEqual({
      from: '2025-12-31',
      to: '2026-09-02',
    })
    expect(dateSpan([])).toBeNull()
  })
})

describe('passkey errors in plain words', () => {
  afterEach(() => localStorage.clear())

  const err = (name: string, code?: string) => Object.assign(new Error('x'), { name, code })

  it('classifies browser and server errors', () => {
    expect(classifyPasskeyError(err('NotAllowedError', 'ERROR_PASSTHROUGH_SEE_CAUSE_PROPERTY'))).toBe('cancelled')
    expect(classifyPasskeyError(err('Error', 'ERROR_CEREMONY_ABORTED'))).toBe('cancelled')
    expect(classifyPasskeyError(err('AuthApiError', 'passkey_disabled'))).toBe('disabled')
    expect(classifyPasskeyError(err('InvalidStateError', 'ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED'))).toBe('already-registered')
    expect(classifyPasskeyError(err('AuthApiError', 'webauthn_credential_exists'))).toBe('already-registered')
    expect(classifyPasskeyError(err('AuthApiError', 'webauthn_credential_not_found'))).toBe('not-registered')
    expect(classifyPasskeyError(err('AuthApiError', 'webauthn_challenge_expired'))).toBe('expired')
    expect(classifyPasskeyError(err('AuthApiError', 'too_many_passkeys'))).toBe('too-many')
    expect(classifyPasskeyError(err('SecurityError', 'ERROR_INVALID_DOMAIN'))).toBe('wrong-site')
    expect(classifyPasskeyError(new TypeError('Failed to fetch'))).toBe('network')
    expect(classifyPasskeyError(err('Error'))).toBe('other')
  })

  it('never shows a raw error', () => {
    expect(describePasskeyError(err('NotAllowedError'), 'sign-in')).toBe('Windows Hello was cancelled. Nothing changed.')
    expect(describePasskeyError(err('X', 'passkey_disabled'), 'register')).toMatch(/switched off/)
    expect(describePasskeyError(err('X', 'weird'), 'sign-in')).toMatch(/Use Google instead/)
  })

  it('remembers per browser whether the account has a passkey', () => {
    expect(hasPasskeyHint()).toBe(false)
    rememberPasskeyHint(true)
    expect(hasPasskeyHint()).toBe(true)
    rememberPasskeyHint(false)
    expect(hasPasskeyHint()).toBe(false)
  })
})
