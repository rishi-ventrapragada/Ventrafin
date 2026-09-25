// The Add page's spreadsheet grid, mounted for real (PrimeVue, router,
// dialogs) on the in-memory repository with a fixed clock: 00:30 IST on
// 25 Sep 2026, when UTC is still the 24th.
import { describe, expect, it } from 'vitest'
import { createMemoryEntryPrefs } from '../support/memoryEntryPrefs'
import { AppError } from '@/lib/errors'
import { FakeRepository } from '../support/fakeRepository'
import { buttonByText, byTestId, cell, mountApp, settle } from '../support/mountApp'

// Grid columns
const DATE = 0
const DESC = 1
const AMOUNT = 2
const TYPE = 3
const CATEGORY = 4
const ACCOUNT = 5
const METHOD = 7

async function type(el: HTMLInputElement, text: string) {
  el.focus()
  el.value = text
  el.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
}

async function key(el: HTMLElement, k: string, opts: KeyboardEventInit = {}) {
  el.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true, ...opts }))
  await settle()
}

async function leave(el: HTMLInputElement) {
  el.blur()
  await settle()
}

async function click(el: Element | null) {
  if (!el) throw new Error('nothing to click')
  ;(el as HTMLElement).click()
  await settle()
}

const gridRows = () => document.querySelectorAll('tbody tr[data-row-key]')

async function fillRow(row: number, description: string, amount: string) {
  await type(cell(row, DESC), description)
  await type(cell(row, AMOUNT), amount)
  await leave(cell(row, AMOUNT))
}

describe('Add grid', () => {
  it('starts with blank rows dated today in India, with the last-used account and payment method', async () => {
    await mountApp({ path: '/add', prefs: createMemoryEntryPrefs({ accountId: 'acc-bank', method: 'card' }) })

    expect(gridRows()).toHaveLength(8)
    expect(cell(0, DATE).value).toBe('25/09/2026') // India's date, though UTC is still the 24th
    expect(cell(0, TYPE).value).toBe('Expense')
    expect(cell(0, CATEGORY).value).toBe('Auto')
    expect(cell(0, ACCOUNT).value).toBe('Bank')
    expect(cell(0, METHOD).value).toBe('Card')
    expect(document.activeElement).toBe(cell(0, DESC)) // ready to type
  })

  it('with nothing remembered yet: the Cash account, and Paid by to choose', async () => {
    await mountApp({ path: '/add' })
    expect(cell(0, ACCOUNT).value).toBe('Cash')
    expect(cell(0, METHOD).value).toBe('')
  })

  it('Enter moves down the same column (adding a row at the bottom); Up moves back', async () => {
    await mountApp({ path: '/add' })
    await type(cell(0, AMOUNT), '100')
    await key(cell(0, AMOUNT), 'Enter')
    expect(document.activeElement).toBe(cell(1, AMOUNT))
    await key(cell(1, AMOUNT), 'ArrowUp')
    expect(document.activeElement).toBe(cell(0, AMOUNT))

    await key(cell(7, DESC), 'Enter')
    expect(gridRows().length).toBeGreaterThan(8)
    expect(document.activeElement).toBe(cell(8, DESC))
  })

  it('cells are tabbed in spreadsheet order; row buttons are skipped', async () => {
    await mountApp({ path: '/add' })
    const tabbable = [...document.querySelectorAll<HTMLElement>('table input, table button')].filter(
      (el) => el.tabIndex >= 0 && !(el as HTMLInputElement).disabled,
    )
    const order = tabbable.slice(0, 7).map((el) => `${el.dataset.row},${el.dataset.col}`)
    // Row 0: date, description, amount, type, category, account, (to account is disabled), paid by.
    expect(order).toEqual(['0,0', '0,1', '0,2', '0,3', '0,4', '0,5', '0,7'])
    expect(tabbable[7]?.dataset.row).toBe('1')
  })

  it('saves integer paise with the India date; the database picks the category; the result is shown', async () => {
    const prefs = createMemoryEntryPrefs({ method: 'upi' })
    const { repo } = await mountApp({ path: '/add', prefs })

    await fillRow(0, 'Swiggy dinner', '₹1,250.50')
    expect(cell(0, AMOUNT).value).toBe('1,250.50') // tidied when leaving the cell
    await click(byTestId('save-rows'))

    expect(repo.insertAttempts).toHaveLength(1)
    const saved = repo.txns[0]!
    expect(saved).toMatchObject({
      date: '2026-09-25',
      amountPaise: 125050,
      description: 'Swiggy dinner',
      type: 'expense',
      accountId: 'acc-cash',
      paymentMethod: 'upi',
    })
    expect(Number.isInteger(saved.amountPaise)).toBe(true)
    // Category left on Auto -> none sent; the (fake) database chose Food.
    expect(saved.categoryId).toBe('cat-food')
    expect(saved.autoCategorized).toBe(true)

    expect(byTestId('saved-summary')?.textContent).toContain('1 saved this session · ₹1,250.50 spent')
    expect(byTestId('saved-category')?.textContent).toMatch(/Food\s*auto/)
    // The row left the grid; a fresh blank one is at the top.
    expect(cell(0, DESC).value).toBe('')
    expect(prefs.lastAccountId).toBe('acc-cash')
    expect(prefs.lastMethod).toBe('upi')
  })

  it('picking a category from the list by typing its first letters', async () => {
    const { repo } = await mountApp({ path: '/add', prefs: createMemoryEntryPrefs({ method: 'cash' }) })
    await fillRow(0, 'Weekly vegetables', '420')
    await type(cell(0, CATEGORY), 'gro')
    expect(document.querySelector('[role="listbox"]')?.textContent).toContain('Groceries')
    await key(cell(0, CATEGORY), 'Enter')
    expect(cell(0, CATEGORY).value).toBe('Groceries')

    await click(byTestId('save-rows'))
    expect(repo.txns[0]?.categoryId).toBe('cat-groc')
    expect(repo.txns[0]?.autoCategorized).toBe(false)
  })

  it('rows with problems are not saved; they stay, marked, while the good rows save', async () => {
    const { repo } = await mountApp({ path: '/add', prefs: createMemoryEntryPrefs({ method: 'cash' }) })
    await fillRow(0, 'DMart', '899')
    await type(cell(1, DESC), 'Milk') // no amount
    await leave(cell(1, DESC))
    await click(byTestId('save-rows'))

    expect(repo.insertAttempts).toHaveLength(1)
    expect(repo.txns.map((t) => t.description)).toEqual(['DMart'])
    expect(cell(0, DESC).value).toBe('Milk')
    expect(gridRows()[0]?.getAttribute('data-status')).toBe('error')
    expect(byTestId('problems')?.textContent).toContain('Row 1: Amount: Enter an amount')
  })

  it('a failed save is never silent: it says why, keeps the rows, and the retry reuses the same ids', async () => {
    const repo = new FakeRepository()
    repo.failNextInsertWith = new AppError('TypeError: Failed to fetch', null, true)
    await mountApp({ path: '/add', repo, prefs: createMemoryEntryPrefs({ method: 'cash' }) })
    await fillRow(0, 'Chai', '20')
    await click(byTestId('save-rows'))

    const dialog = byTestId('save-failed') ?? document.querySelector('[role="dialog"]')
    expect(dialog?.textContent).toContain('Not saved')
    expect(dialog?.textContent).toContain("Couldn't reach the server")
    expect(dialog?.textContent).toContain('Your rows are still in the grid')
    expect(repo.txns).toHaveLength(0)
    expect(cell(0, DESC).value).toBe('Chai')

    await click(buttonByText('OK'))
    await click(byTestId('save-rows'))
    expect(repo.txns).toHaveLength(1)
    expect(repo.insertAttempts).toHaveLength(2)
    expect(repo.insertAttempts[1]).toEqual(repo.insertAttempts[0])
  })

  it('offline: nothing is sent, and the page says why', async () => {
    const { repo } = await mountApp({ path: '/add', online: false, prefs: createMemoryEntryPrefs({ method: 'cash' }) })
    expect(byTestId('offline-banner')?.textContent).toContain(
      "No internet connection. Entries can't be saved or loaded until you're back online.",
    )
    await fillRow(0, 'Chai', '20')
    await click(byTestId('save-rows'))
    expect(document.querySelector('[role="dialog"]')?.textContent).toContain("There's no internet connection.")
    expect(repo.insertAttempts).toHaveLength(0)
    expect(cell(0, DESC).value).toBe('Chai')
  })

  it('Ctrl+D copies the cell above; Ctrl+; puts today in a date cell', async () => {
    await mountApp({ path: '/add' })
    await type(cell(0, DESC), 'Auto rickshaw')
    cell(1, DESC).focus()
    await key(cell(1, DESC), 'd', { ctrlKey: true })
    expect(cell(1, DESC).value).toBe('Auto rickshaw')

    await type(cell(1, DATE), '')
    await key(cell(1, DATE), ';', { ctrlKey: true })
    expect(cell(1, DATE).value).toBe('25/09/2026')
  })

  it('paste from Excel: a preview marks the bad rows, and nothing is saved until confirmed', async () => {
    const { repo } = await mountApp({ path: '/add', prefs: createMemoryEntryPrefs({ method: 'upi' }) })
    const clipboard = [
      'Date\tDescription\tAmount\tCategory',
      '24/09/2026\tSwiggy dinner\t₹1,250\t',
      '23-Sep-26\tDMart\t2,340.50\tGroceries',
      '31/02/2026\tBad date\t100\t',
    ].join('\r\n')
    const paste = new Event('paste', { bubbles: true, cancelable: true })
    Object.defineProperty(paste, 'clipboardData', { value: { getData: () => clipboard } })
    cell(0, DESC).dispatchEvent(paste)
    await settle()

    expect(paste.defaultPrevented).toBe(true) // not dumped into one cell
    const preview = byTestId('paste-preview')!
    const lines = [...preview.querySelectorAll('tbody tr')].map((tr) => [tr.getAttribute('data-line'), tr.getAttribute('data-valid')])
    expect(lines).toEqual([
      ['2', 'true'],
      ['3', 'true'],
      ['4', 'false'],
    ])
    expect(preview.textContent).toContain('"31/02/2026" is not a real date')
    expect(byTestId('paste-counts')?.textContent).toMatch(/2 ready.*1 can't be saved yet/s)
    expect(repo.insertAttempts).toHaveLength(0)

    await click(byTestId('paste-save'))
    expect(repo.txns.map((t) => [t.date, t.description, t.amountPaise, t.categoryId])).toEqual([
      ['2026-09-24', 'Swiggy dinner', 125000, 'cat-food'],
      ['2026-09-23', 'DMart', 234050, 'cat-groc'],
    ])
    // The bad row went into the grid to be fixed, marked.
    expect(cell(0, DESC).value).toBe('Bad date')
    expect(cell(0, DATE).value).toBe('31/02/2026')
    expect(gridRows()[0]?.getAttribute('data-status')).toBe('error')
    expect(byTestId('saved-summary')?.textContent).toContain('2 saved this session')
  })

  it('pasting a single value just goes into the cell', async () => {
    await mountApp({ path: '/add' })
    const paste = new Event('paste', { bubbles: true, cancelable: true })
    Object.defineProperty(paste, 'clipboardData', { value: { getData: () => 'Swiggy\r\n' } })
    cell(0, DESC).dispatchEvent(paste)
    await settle()
    expect(paste.defaultPrevented).toBe(false)
    expect(byTestId('paste-preview')).toBeNull()
  })
})
