// Pasting rows copied from Excel: reading the clipboard, recognising the
// columns, and turning the rows into validated grid rows.
import { describe, expect, it } from 'vitest'
import { parseEntryRow, type EntryContext } from '@/lib/entryRow'
import { guessRoles, isHeadingRow, looksLikeRows, readPaste, splitClipboard, toGridRows } from '@/lib/paste'
import { ACCOUNTS, CATEGORIES } from '../support/fakeRepository'

const ctx: EntryContext = { accounts: ACCOUNTS, categories: CATEGORIES, today: '2026-09-25' }
const defaults = { account: 'Cash', method: 'UPI' }

/** Clipboard text as Excel writes it: tabs between cells, CRLF after each row. */
const excel = (...rows: string[][]) => rows.map((r) => r.join('\t')).join('\r\n') + '\r\n'

function pasteToDrafts(text: string) {
  const table = readPaste(text, ctx.today)
  const roles = guessRoles(table, ctx)
  const rows = toGridRows(table, roles, ctx, defaults)
  return { table, roles, rows, parsed: rows.map((r) => parseEntryRow(r.raw, ctx)) }
}

describe('splitClipboard', () => {
  it('tabs and CRLF, trailing newline ignored', () => {
    expect(splitClipboard('a\tb\r\nc\td\r\n')).toEqual([
      ['a', 'b'],
      ['c', 'd'],
    ])
  })

  it('quoted cells may contain tabs, line breaks and doubled quotes', () => {
    expect(splitClipboard('"Milk\tand eggs"\t"line1\nline2"\t"say ""hi"""\r\n')).toEqual([
      ['Milk\tand eggs', 'line1\nline2', 'say "hi"'],
    ])
  })

  it('drops blank lines and trims cells (including non-breaking spaces)', () => {
    expect(splitClipboard('\r\n a \t b \r\n\t\r\n')).toEqual([['a', 'b']])
  })

  it('LF-only (Google Sheets, Mac) works too', () => {
    expect(splitClipboard('a\tb\nc\td')).toHaveLength(2)
  })
})

describe('looksLikeRows: when a paste opens the preview', () => {
  it('one value pastes into the cell', () => {
    expect(looksLikeRows('Swiggy')).toBe(false)
    expect(looksLikeRows('Swiggy\r\n')).toBe(false) // Excel adds a newline even to one cell
  })

  it('several cells or rows open the preview', () => {
    expect(looksLikeRows('Swiggy\t250')).toBe(true)
    expect(looksLikeRows('Swiggy\r\nDMart')).toBe(true)
  })
})

describe('headings', () => {
  it('recognises a heading row and ignores it', () => {
    expect(isHeadingRow(['Date', 'Particulars', 'Amount (₹)'], ctx.today)).toBe(true)
    expect(isHeadingRow(['25/09/2026', 'Swiggy', '250'], ctx.today)).toBe(false)
    expect(isHeadingRow(['Swiggy', 'Groceries'], ctx.today)).toBe(false)
  })

  it('maps headings to columns, whatever their order', () => {
    const { roles, table } = pasteToDrafts(
      excel(['Paid by', 'Amount', 'Details', 'Dt', 'Category'], ['UPI', '250', 'Swiggy dinner', '24/09/2026', 'Food']),
    )
    expect(table.headings).not.toBeNull()
    expect(roles).toEqual(['method', 'amount', 'description', 'date', 'category'])
  })

  it('a heading only counts if its values agree ("Expense" over words is a description)', () => {
    const { roles } = pasteToDrafts(excel(['Date', 'Expense', 'Amount'], ['24/09/2026', 'Milk', '60'], ['24/09/2026', 'Petrol', '500']))
    expect(roles).toEqual(['date', 'description', 'amount'])
  })
})

describe('guessing columns without headings', () => {
  it('date, description, amount in any order', () => {
    const { roles } = pasteToDrafts(excel(['Swiggy dinner', '₹1,250', '24/09/2026'], ['DMart', '899.50', '23/09/2026']))
    expect(roles).toEqual(['description', 'amount', 'date'])
  })

  it('type, category, account and payment method columns', () => {
    const { roles } = pasteToDrafts(
      excel(
        ['24/09/2026', 'Swiggy', '250', 'Expense', 'Food', 'Cash', 'UPI'],
        ['24/09/2026', 'Salary Sept', '85000', 'Income', 'Salary', 'Bank', ''],
      ),
    )
    expect(roles).toEqual(['date', 'description', 'amount', 'type', 'category', 'account', 'method'])
  })

  it("bank statement: Withdrawal and Deposit columns (never both filled); Balance ignored", () => {
    const { roles, parsed } = pasteToDrafts(
      excel(
        ['Date', 'Narration', 'Chq./Ref.No.', 'Withdrawal Amt.', 'Deposit Amt.', 'Closing Balance'],
        ['24/09/26', 'UPI-SWIGGY-4471023', '000123', '1,250.00', '', '52,340.10'],
        ['25/09/26', 'SALARY SEP', '000124', '', '85,000.00', '1,37,340.10'],
      ),
    )
    expect(roles).toEqual(['date', 'description', 'ignore', 'withdrawal', 'deposit', 'ignore'])
    expect(parsed.map((p) => [p.draft?.type, p.draft?.amountPaise])).toEqual([
      ['expense', 125000],
      ['income', 8500000],
    ])
  })

  it('two amount columns without headings are told apart by being complementary', () => {
    const { roles } = pasteToDrafts(excel(['24/09/2026', 'Swiggy', '250', ''], ['24/09/2026', 'Refund', '', '100']))
    expect(roles).toEqual(['date', 'description', 'withdrawal', 'deposit'])
  })
})

describe('pasted rows -> grid rows -> drafts', () => {
  it('a typical sheet: Indian dates, ₹ and commas, category optional', () => {
    const { parsed, rows } = pasteToDrafts(
      excel(
        ['Date', 'Description', 'Amount', 'Category'],
        ['24/09/2026', 'Swiggy dinner', '₹1,250.50', ''],
        ['23-Sep-26', 'DMart', '2,340', 'groceries'],
      ),
    )
    expect(parsed.map((p) => p.draft)).toEqual([
      {
        date: '2026-09-24',
        amountPaise: 125050,
        description: 'Swiggy dinner',
        type: 'expense',
        accountId: 'acc-cash',
        toAccountId: null,
        categoryId: null, // Auto: the database will categorize it
        paymentMethod: 'upi',
      },
      {
        date: '2026-09-23',
        amountPaise: 234000,
        description: 'DMart',
        type: 'expense',
        accountId: 'acc-cash',
        toAccountId: null,
        categoryId: 'cat-groc',
        paymentMethod: 'upi',
      },
    ])
    // Tidied for the grid, with line numbers from the paste (heading = line 1).
    expect(rows[1]!.raw).toMatchObject({ date: '23/09/2026', amount: '2,340', category: 'Groceries', account: 'Cash', method: 'UPI' })
    expect(rows.map((r) => r.line)).toEqual([2, 3])
  })

  it('no date column: today; no account or method: the Add page defaults', () => {
    const { parsed } = pasteToDrafts(excel(['Chai', '20'], ['Auto rickshaw', '80']))
    expect(parsed.every((p) => p.draft?.date === '2026-09-25')).toBe(true)
    expect(parsed.every((p) => p.draft?.accountId === 'acc-cash' && p.draft?.paymentMethod === 'upi')).toBe(true)
  })

  it('a minus sign or Dr/Cr decides the type when there is no Type column', () => {
    const { parsed } = pasteToDrafts(excel(['Refund', '500 Cr'], ['Swiggy', '-250'], ['Milk', '(60)']))
    expect(parsed.map((p) => [p.draft?.type, p.draft?.amountPaise])).toEqual([
      ['income', 50000],
      ['expense', 25000],
      ['expense', 6000],
    ])
  })

  it('payment method words: GPay, PhonePe -> UPI; credit card -> Card', () => {
    const { parsed } = pasteToDrafts(
      excel(['Description', 'Amount', 'Mode'], ['Swiggy', '250', 'GPay'], ['Amazon', '999', 'Credit Card'], ['Milk', '60', 'cash']),
    )
    expect(parsed.map((p) => p.draft?.paymentMethod)).toEqual(['upi', 'card', 'cash'])
  })

  it('marks rows that cannot be saved, with the reason', () => {
    const { parsed } = pasteToDrafts(
      excel(
        ['Date', 'Description', 'Amount', 'Account'],
        ['31/02/2026', 'Bad date', '100', 'Cash'],
        ['24/09/2026', 'No amount', '', 'Cash'],
        ['24/09/2026', 'Zero', '0', 'Cash'],
        ['24/09/2026', 'Unknown account', '100', 'HDFC'],
        ['24/09/2026', 'Fine', '100', 'Bank'],
      ),
    )
    const problems = parsed.map((p) => (p.draft ? null : p.issues.filter((i) => i.level === 'error').map((i) => i.message)))
    expect(problems).toEqual([
      ['"31/02/2026" is not a real date'],
      ['Enter an amount'],
      ['Amount must be more than zero'],
      ['No account called "HDFC"'],
      null,
    ])
  })

  it('an unknown category is not an error: the row saves and Ventrafin picks one', () => {
    const { parsed } = pasteToDrafts(excel(['Description', 'Amount', 'Category'], ['Ramesh kirana', '450', 'Kirana']))
    expect(parsed[0]!.draft?.categoryId).toBeNull()
    expect(parsed[0]!.issues).toEqual([
      { field: 'category', level: 'warning', message: 'No expense category called "Kirana". Ventrafin will pick one' },
    ])
  })

  it('an archived category is not used', () => {
    const { parsed } = pasteToDrafts(excel(['Description', 'Amount', 'Category'], ['Junk', '10', 'Old stuff']))
    expect(parsed[0]!.draft?.categoryId).toBeNull()
    expect(parsed[0]!.issues[0]?.message).toContain('archived')
  })

  it('transfers need a different "To" account and never get a category', () => {
    const { parsed } = pasteToDrafts(
      excel(
        ['Description', 'Amount', 'Type', 'Account', 'To account'],
        ['ATM', '2000', 'Transfer', 'Bank', 'Cash'],
        ['Oops', '100', 'Transfer', 'Cash', 'Cash'],
      ),
    )
    expect(parsed[0]!.draft).toMatchObject({ type: 'transfer', accountId: 'acc-bank', toAccountId: 'acc-cash', categoryId: null })
    expect(parsed[1]!.issues.find((i) => i.level === 'error')?.message).toBe('Must be different from the "From" account')
  })
})
