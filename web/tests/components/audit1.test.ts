// Audit round 1 on the fake repository: unsaved changes, the all-months
// search, load errors with Retry, keyboard editing and undo in
// Transactions, dialogs (first field focused, Enter saves), and adding,
// archiving and restoring accounts and categories.
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Account, Bill } from '@/lib/models'
import { FakeRepository, makeTxn } from '../support/fakeRepository'
import { createMemoryEntryPrefs } from '../support/memoryEntryPrefs'
import { buttonByText, byTestId, cell, confirmButton, mountApp, nextFrames, settle } from '../support/mountApp'

async function click(el: Element | null | undefined) {
  if (!el) throw new Error('nothing to click')
  ;(el as HTMLElement).click()
  await settle()
}

async function type(el: HTMLInputElement | HTMLTextAreaElement | null, text: string) {
  if (!el) throw new Error('no input')
  el.focus()
  el.value = text
  el.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
}

/** PrimeVue reads event.code, the app reads event.key: send both. */
async function press(el: Element | null, key: string, opts: KeyboardEventInit = {}) {
  if (!el) throw new Error('nothing to press a key in')
  const e = new KeyboardEvent('keydown', { key, code: key, bubbles: true, cancelable: true, ...opts })
  el.dispatchEvent(e)
  await settle()
  return e
}

const input = (id: string) => byTestId<HTMLInputElement>(id)
const dialogTitles = () => [...document.querySelectorAll('.p-dialog-title')].map((t) => t.textContent?.trim())

afterEach(() => vi.useRealTimers())

/** Makes `repo[name]` fail once with a network error, then work again. */
function failOnce(repo: FakeRepository, name: 'fetchMonthTotals' | 'fetchMonthComparison' | 'fetchMonthlyTotals' | 'fetchMonthlyCategoryTotals' | 'fetchCategories' | 'fetchAccounts') {
  const original = repo[name].bind(repo) as (...args: unknown[]) => Promise<unknown>
  let failed = false
  ;(repo as unknown as Record<string, unknown>)[name] = async (...args: unknown[]) => {
    if (!failed) {
      failed = true
      throw new TypeError('Failed to fetch')
    }
    return original(...args)
  }
}

const OFFLINE_TEXT = "Couldn't reach the server. Check your internet connection and try again."

// ============================================================================
// 1. Unsaved changes
// ============================================================================

describe('Unsaved changes on Add', () => {
  const DESC = 1
  const AMOUNT = 2

  it('an untouched grid leaves without asking', async () => {
    const { router } = await mountApp({ path: '/add' })
    await router.push('/transactions')
    await settle()
    expect(router.currentRoute.value.path).toBe('/transactions')
    expect(document.body.textContent).not.toContain('Discard changes?')
  })

  it('typed rows: leaving asks "Discard changes?" with Keep editing focused; Keep editing stays, Discard leaves', async () => {
    const { router } = await mountApp({ path: '/add' })
    await type(cell(0, DESC), 'Swiggy dinner')
    await type(cell(0, AMOUNT), '450')

    void router.push('/transactions')
    await settle()
    expect(document.body.textContent).toContain('Discard changes?')
    expect(document.body.textContent).toContain("What you typed hasn't been saved.")
    expect(confirmButton('reject').textContent?.trim()).toBe('Keep editing')
    expect(document.activeElement).toBe(confirmButton('reject'))

    await click(confirmButton('reject'))
    expect(router.currentRoute.value.path).toBe('/add')
    expect(cell(0, DESC).value).toBe('Swiggy dinner')

    void router.push('/transactions')
    await settle()
    expect(confirmButton('accept').textContent?.trim()).toBe('Discard')
    await click(confirmButton('accept'))
    expect(router.currentRoute.value.path).toBe('/transactions')
  })

  it('closing the tab or F5: the browser asks while rows are unsaved, not before', async () => {
    await mountApp({ path: '/add' })
    const unload = () => {
      const e = new Event('beforeunload', { cancelable: true })
      window.dispatchEvent(e)
      return e.defaultPrevented
    }
    expect(unload()).toBe(false)
    await type(cell(0, DESC), 'Swiggy dinner')
    expect(unload()).toBe(true)
  })

  it('after saving, nothing is left to lose', async () => {
    const { router } = await mountApp({ path: '/add', prefs: createMemoryEntryPrefs({ method: 'upi' }) })
    await type(cell(0, DESC), 'Swiggy dinner')
    await type(cell(0, AMOUNT), '450')
    await click(byTestId('save-rows'))
    await router.push('/dashboard')
    await settle()
    expect(router.currentRoute.value.path).toBe('/dashboard')
  })
})

function bill(over: Partial<Bill> = {}): Bill {
  return {
    id: 'bill-1',
    name: 'BESCOM',
    kind: 'utility',
    amountPaise: 145000,
    dueDay: 28,
    accountId: 'acc-bank',
    categoryId: 'cat-elec',
    reminderEnabled: true,
    paidThroughMonth: { year: 2026, month: 8 },
    nextDueDate: '2026-09-28',
    daysUntil: 3,
    status: 'due_soon',
    overdueCount: 0,
    ...over,
  }
}

describe('Unsaved changes in form dialogs (X and Escape)', () => {
  // Real transitions: PrimeVue's Dialog starts listening for Escape as it shows.
  const open = async (el: Element | null) => {
    await click(el)
    await nextFrames()
  }
  const escape = async () => {
    await press(document.activeElement ?? document.body, 'Escape')
    await nextFrames()
  }

  it('Bill: untouched closes at once; typed asks, and Keep editing keeps it', async () => {
    await mountApp({ path: '/bills', transitions: true })
    await open(byTestId('add-bill'))
    await escape()
    expect(byTestId('bill-form')).toBeNull()
    expect(document.body.textContent).not.toContain('Discard changes?')

    await open(byTestId('add-bill'))
    await type(input('bill-name'), 'Water')
    await escape()
    expect(document.body.textContent).toContain('Discard changes?')
    expect(document.activeElement).toBe(confirmButton('reject'))
    // Escape again closes only the question.
    await escape()
    expect(input('bill-name')!.value).toBe('Water')

    await click(document.querySelector('.p-dialog-close-button'))
    await nextFrames()
    await click(confirmButton('reject'))
    await nextFrames()
    expect(input('bill-name')!.value).toBe('Water')

    await click(document.querySelector('.p-dialog-close-button'))
    await nextFrames()
    await click(confirmButton('accept'))
    await nextFrames()
    expect(byTestId('bill-form')).toBeNull()
  })

  it('Category edit: a changed name asks before closing', async () => {
    await mountApp({ path: '/categories', transitions: true })
    await open(document.querySelector('[data-category-id="cat-food"]'))
    await type(input('category-name'), 'Khana')
    await escape()
    expect(document.body.textContent).toContain('Discard changes?')
    await click(confirmButton('accept'))
    await nextFrames()
    expect(input('category-name')).toBeNull()
  })

  it('Add account asks when something was typed', async () => {
    await mountApp({ path: '/accounts', transitions: true })
    await open(byTestId('add-account'))
    await type(input('account-name'), 'HDFC')
    await escape()
    expect(document.body.textContent).toContain('Discard changes?')
    await click(confirmButton('reject'))
    await nextFrames()
    expect(input('account-name')!.value).toBe('HDFC')
  })

  it('Add category asks when something was typed', async () => {
    await mountApp({ path: '/categories', transitions: true })
    await open(byTestId('add-category'))
    await type(input('category-add-name'), 'Pets')
    await escape()
    expect(document.body.textContent).toContain('Discard changes?')
  })
})

// ============================================================================
// 2. Search every month
// ============================================================================

describe('Transactions: search all months', () => {
  function repo() {
    const r = new FakeRepository()
    r.txns = [
      makeTxn('t1', { date: '2026-09-24', description: 'Swiggy dinner' }),
      makeTxn('t2', { date: '2026-08-10', description: 'Tea stall August' }),
      makeTxn('t3', { date: '2025-03-02', description: 'Tea estate trip' }),
      makeTxn('t4', { date: '2026-09-02', description: 'Chai and tea' }),
    ]
    return r
  }
  const shown = () => [...document.querySelectorAll('[data-testid="txn-table"] tbody tr')].map((tr) => tr.textContent ?? '')

  it('the same search runs over every month; turning it off goes back to the month', async () => {
    const { router } = await mountApp({ path: '/transactions?month=2026-09', repo: repo() })
    await type(input('search'), 'tea')
    expect(shown()).toHaveLength(1) // only September's
    expect(shown()[0]).toContain('Chai and tea')

    await click(input('all-months'))
    expect(byTestId('month-label')!.textContent).toContain('All months')
    expect(byTestId('month-summary')!.textContent).toContain('Searching all months')
    expect(shown().map((t) => t.match(/Chai and tea|Tea stall August|Tea estate trip/)?.[0])).toEqual([
      'Chai and tea',
      'Tea stall August',
      'Tea estate trip',
    ])
    expect(byTestId('month-summary')!.textContent).toContain('3 matches')
    expect(router.currentRoute.value.query).toEqual({ month: '2026-09' }) // no new URL parameter

    await click(input('all-months'))
    expect(byTestId('month-label')!.textContent).toContain('September 2026')
    expect(shown()).toHaveLength(1)
  })

  it('with nothing to search for, it asks for a search instead of listing everything', async () => {
    await mountApp({ path: '/transactions?month=2026-09', repo: repo() })
    await click(input('all-months'))
    expect(document.querySelector('[data-testid="txn-table"]')!.textContent).toContain('to search every month')
  })
})

// ============================================================================
// 3. Load errors with Retry
// ============================================================================

describe('Load errors: the reason and a Retry button', () => {
  it('Dashboard: totals and the breakdown', async () => {
    const repo = new FakeRepository()
    failOnce(repo, 'fetchMonthTotals')
    failOnce(repo, 'fetchMonthComparison')
    await mountApp({ path: '/dashboard', repo })
    const errors = document.querySelectorAll('[data-testid="load-error"]')
    expect(errors).toHaveLength(2)
    expect(errors[0]!.textContent).toContain(`Couldn't load totals. ${OFFLINE_TEXT}`)
    for (const retry of document.querySelectorAll('[data-testid="retry"]')) await click(retry)
    expect(document.querySelectorAll('[data-testid="load-error"]')).toHaveLength(0)
  })

  it('Reports: each section on its own', async () => {
    const repo = new FakeRepository()
    failOnce(repo, 'fetchMonthlyTotals')
    failOnce(repo, 'fetchMonthlyCategoryTotals')
    await mountApp({ path: '/reports', repo })
    expect(byTestId('report-income-vs-spending')!.textContent).toContain(`Couldn't load the months. ${OFFLINE_TEXT}`)
    expect(byTestId('report-category-trend')!.textContent).toContain(`Couldn't load the categories. ${OFFLINE_TEXT}`)
    await click(byTestId('report-income-vs-spending')!.querySelector('[data-testid="retry"]'))
    expect(byTestId('report-income-vs-spending')!.querySelector('[data-testid="load-error"]')).toBeNull()
    expect(byTestId('report-category-trend')!.querySelector('[data-testid="load-error"]')).not.toBeNull()
    await click(byTestId('report-category-trend')!.querySelector('[data-testid="retry"]'))
    expect(document.querySelector('[data-testid="load-error"]')).toBeNull()
  })

  it('Categories', async () => {
    const repo = new FakeRepository()
    failOnce(repo, 'fetchCategories')
    await mountApp({ path: '/categories', repo })
    expect(byTestId('load-error')!.textContent).toContain(`Couldn't load categories. ${OFFLINE_TEXT}`)
    await click(byTestId('retry'))
    expect(byTestId('categories-expense')).not.toBeNull()
  })

  it('Accounts', async () => {
    const repo = new FakeRepository()
    failOnce(repo, 'fetchAccounts')
    await mountApp({ path: '/accounts', repo })
    expect(byTestId('load-error')!.textContent).toContain(`Couldn't load accounts. ${OFFLINE_TEXT}`)
    await click(byTestId('retry'))
    expect(byTestId('accounts-table')).not.toBeNull()
  })
})

// ============================================================================
// 5 and 6. Transactions: keyboard editing, delete with Undo
// ============================================================================

function septemberRepo() {
  const repo = new FakeRepository()
  repo.txns = [
    makeTxn('t1', { date: '2026-09-24', description: 'Swiggy dinner', amountPaise: 45000, categoryId: 'cat-food', autoCategorized: true }),
    makeTxn('t2', { date: '2026-09-23', description: 'Apollo Tyres', amountPaise: 320000, categoryId: 'cat-med', accountId: 'acc-bank', paymentMethod: 'card' }),
    makeTxn('t3', { date: '2026-09-21', description: 'ATM withdrawal', amountPaise: 200000, type: 'transfer', accountId: 'acc-bank', toAccountId: 'acc-cash', categoryId: null, paymentMethod: null }),
  ]
  return repo
}
const tableRows = () => [...document.querySelectorAll<HTMLTableRowElement>('[data-testid="txn-table"] tbody tr')]
const rowOf = (text: string) => tableRows().find((tr) => tr.textContent?.includes(text))
/** Columns: 0 select, 1 date, 2 description, 3 category, 4 amount, 5 type, 6 account, 7 to, 8 paid by, 9 delete. */
const DESCRIPTION_COL = 2

describe('Transactions: editing with the keyboard', () => {
  it('editable cells are Tab stops; the checkbox and delete columns are not', async () => {
    await mountApp({ path: '/transactions?month=2026-09', repo: septemberRepo() })
    const cells = [...rowOf('Swiggy dinner')!.cells]
    expect(cells.map((td) => td.getAttribute('tabindex'))).toEqual([null, '0', '0', '0', '0', '0', '0', '0', '0', null])
  })

  it('Enter starts editing, Escape cancels and focus returns to the cell; F2 then Enter saves and stays on the cell', async () => {
    const { repo } = await mountApp({ path: '/transactions?month=2026-09', repo: septemberRepo() })
    // By amount: while editing, the description is in the editor, not the row's text.
    const td = () => rowOf('₹450.00')!.cells[DESCRIPTION_COL]!
    td().focus()
    await press(td(), 'Enter')
    const editor = td().querySelector('input')!
    expect(document.activeElement).toBe(editor)
    expect(editor.value).toBe('Swiggy dinner')

    await type(editor, 'Swiggy lunch')
    await press(editor, 'Escape')
    expect(td().querySelector('input')).toBeNull()
    expect(document.activeElement).toBe(td())
    expect(repo.updates).toHaveLength(0)

    await press(td(), 'F2')
    const again = td().querySelector('input')!
    expect(document.activeElement).toBe(again)
    await type(again, 'Swiggy lunch')
    await press(again, 'Enter')
    expect(repo.updates).toEqual([{ id: 't1', patch: { description: 'Swiggy lunch' } }])
    expect(td().textContent).toContain('Swiggy lunch')
    expect(document.activeElement).toBe(td())
  })

  it('Tab on a cell that is not being edited just moves on (no editor opens)', async () => {
    await mountApp({ path: '/transactions?month=2026-09', repo: septemberRepo() })
    const td = rowOf('Swiggy')!.cells[1]!
    td.focus()
    const e = await press(td, 'Tab')
    expect(e.defaultPrevented).toBe(false) // the browser moves the focus
    expect(document.querySelector('[data-testid="txn-table"] tbody input:not([type="checkbox"])')).toBeNull()
  })

  it('changing Type to Transfer asks for the account with the first choice focused; Enter confirms', async () => {
    const { repo } = await mountApp({ path: '/transactions?month=2026-09', repo: septemberRepo() })
    const td = rowOf('Swiggy dinner')!.cells[5]!
    td.focus()
    await press(td, 'Enter')
    const editor = td.querySelector('input')!
    await type(editor, 'Transfer')
    await press(editor, 'Enter')
    expect(dialogTitles()).toContain('Change to a transfer')
    const radio = document.activeElement as HTMLInputElement
    expect(radio.type).toBe('radio')
    expect(radio.checked).toBe(true)
    await press(radio, 'Enter')
    expect(repo.updates).toEqual([{ id: 't1', patch: { type: 'transfer', toAccountId: 'acc-bank', categoryId: null } }])
  })
})

describe('Transactions: delete, with Undo', () => {
  it('the confirm focuses Cancel, so Enter never deletes', async () => {
    const { repo } = await mountApp({ path: '/transactions?month=2026-09', repo: septemberRepo() })
    await click(rowOf('Apollo Tyres')!.querySelector('[data-testid="delete-row"]'))
    expect(confirmButton('reject').textContent?.trim()).toBe('Cancel')
    expect(document.activeElement).toBe(confirmButton('reject'))
    await click(confirmButton('reject'))
    expect(repo.deletes).toHaveLength(0)
  })

  it('Undo puts a deleted row back with its id and every field', async () => {
    const repo = septemberRepo()
    const before = repo.txns.find((t) => t.id === 't2')!
    await mountApp({ path: '/transactions?month=2026-09', repo })
    await click(rowOf('Apollo Tyres')!.querySelector('[data-testid="delete-row"]'))
    await click(confirmButton('accept'))
    expect(rowOf('Apollo Tyres')).toBeUndefined()
    expect(byTestId('undo-toast')!.textContent).toContain('Deleted 1 transaction')

    await click(byTestId('undo-delete'))
    expect(repo.insertAttempts.at(-1)).toEqual(['t2'])
    const after = repo.txns.find((t) => t.id === 't2')!
    const fields = (t: typeof before) => [t.id, t.date, t.amountPaise, t.description, t.type, t.accountId, t.toAccountId, t.categoryId, t.paymentMethod]
    expect(fields(after)).toEqual(fields(before))
    expect(rowOf('Apollo Tyres')).toBeDefined()
    expect(document.body.textContent).toContain('Restored 1 transaction')
    expect(byTestId('undo-toast')).toBeNull()
  })

  it('several rows at once: all come back', async () => {
    const repo = septemberRepo()
    await mountApp({ path: '/transactions?month=2026-09', repo })
    for (const text of ['Swiggy dinner', 'ATM withdrawal']) await click(rowOf(text)!.querySelector('td[data-p-selection-column="true"] input'))
    await click(byTestId('delete-selected'))
    expect(document.body.textContent).toContain('Delete 2 transactions?')
    await click(confirmButton('accept'))
    expect(repo.deletes).toEqual([['t1', 't3']])
    expect(tableRows()).toHaveLength(1)

    await click(byTestId('undo-delete'))
    expect(repo.insertAttempts.at(-1)).toEqual(['t1', 't3'])
    expect(tableRows()).toHaveLength(3)
    expect(repo.txns.find((t) => t.id === 't3')).toMatchObject({ type: 'transfer', accountId: 'acc-bank', toAccountId: 'acc-cash' })
  })

  it('the Undo goes away after 5 seconds', async () => {
    const repo = septemberRepo()
    await mountApp({ path: '/transactions?month=2026-09', repo })
    await click(rowOf('Apollo Tyres')!.querySelector('[data-testid="delete-row"]'))
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    confirmButton('accept').click()
    await vi.advanceTimersByTimeAsync(100)
    expect(byTestId('undo-toast')).not.toBeNull()
    await vi.advanceTimersByTimeAsync(4800)
    expect(byTestId('undo-toast')).not.toBeNull()
    await vi.advanceTimersByTimeAsync(1000)
    vi.useRealTimers()
    await settle()
    expect(byTestId('undo-toast')).toBeNull()
    expect(repo.insertAttempts).toHaveLength(0)
  })
})

// ============================================================================
// 7. Dialogs: first field focused, Enter saves; destructive confirms focus Cancel
// ============================================================================

describe('Dialogs open on their first field, and Enter saves', () => {
  it('Paste: the box has the focus; Enter there is a new line; Save is the form\'s submit button', async () => {
    await mountApp({ path: '/add' })
    await click(byTestId('open-paste'))
    const box = byTestId<HTMLTextAreaElement>('paste-box')!
    expect(document.activeElement).toBe(box)
    expect((await press(box, 'Enter')).defaultPrevented).toBe(false)
    const save = byTestId<HTMLButtonElement>('paste-save')!
    expect(save.type).toBe('submit')
    expect(save.form).toBe(box.form)
  })

  it('Bill: the name has the focus; Enter in the amount adds the bill', async () => {
    const { repo } = await mountApp({ path: '/bills' })
    await click(byTestId('add-bill'))
    expect(document.activeElement).toBe(input('bill-name'))
    await type(input('bill-name'), 'Water')
    await type(input('bill-amount'), '300')
    await press(input('bill-amount'), 'Enter')
    expect(repo.billInserts.map((b) => [b.draft.name, b.draft.amountPaise])).toEqual([['Water', 30000]])
  })

  it('Mark paid: the amount has the focus; Enter marks it paid', async () => {
    const repo = new FakeRepository()
    repo.bills = [bill()]
    await mountApp({ path: '/bills', repo })
    await click(byTestId('pay-bill-1'))
    expect(document.activeElement).toBe(input('paid-amount'))
    await press(input('paid-amount'), 'Enter')
    expect(repo.paidCalls).toHaveLength(1)
  })

  it('Category edit: the name has the focus; Enter saves', async () => {
    const { repo } = await mountApp({ path: '/categories' })
    await click(document.querySelector('[data-category-id="cat-food"]'))
    expect(document.activeElement).toBe(input('category-name'))
    await type(input('category-name'), 'Khana')
    await press(input('category-name'), 'Enter')
    expect(repo.categoryEdits.map((e) => e.edit.name)).toEqual(['Khana'])
  })

  it('Add category: the name has the focus; Enter adds', async () => {
    const { repo } = await mountApp({ path: '/categories' })
    await click(byTestId('add-category'))
    expect(document.activeElement).toBe(input('category-add-name'))
    await type(input('category-add-name'), 'Pets')
    await press(input('category-add-name'), 'Enter')
    expect(repo.categoryInserts).toEqual([{ name: 'Pets', kind: 'expense' }])
  })

  it('Add account: the name has the focus; Enter adds', async () => {
    const { repo } = await mountApp({ path: '/accounts' })
    await click(byTestId('add-account'))
    expect(document.activeElement).toBe(input('account-name'))
    await type(input('account-name'), 'HDFC Savings')
    await press(input('account-name'), 'Enter')
    expect(repo.accountWrites.map((w) => [w.op, w.name, w.type])).toEqual([['insert', 'HDFC Savings', 'bank']])
  })

  it('a radio button or checkbox takes Enter too, but a disabled Save is never pressed', async () => {
    const { repo } = await mountApp({ path: '/accounts' })
    await click(byTestId('add-account'))
    await press(input('account-type-cash'), 'Enter') // no name yet: says what's missing, saves nothing
    expect(repo.accountWrites).toHaveLength(0)
    expect(byTestId('account-name-error')!.textContent).toBe('Enter a name')
  })

  it('destructive confirms focus Cancel: clearing the Add grid', async () => {
    await mountApp({ path: '/add' })
    await type(cell(0, 1), 'Swiggy')
    await click(buttonByText('Clear'))
    expect(document.activeElement).toBe(confirmButton('reject'))
    expect(confirmButton('reject').textContent?.trim()).toBe('Cancel')
  })

  it('destructive confirms focus Cancel: deleting a bill', async () => {
    const repo = new FakeRepository()
    repo.bills = [bill()]
    await mountApp({ path: '/bills', repo })
    await click(byTestId('delete-bill-1'))
    expect(document.activeElement).toBe(confirmButton('reject'))
    expect(confirmButton('reject').textContent?.trim()).toBe('Cancel')
  })

  it('text boxes show a focus ring instead of hiding the outline', async () => {
    await mountApp({ path: '/transactions?month=2026-09', repo: septemberRepo() })
    expect(input('search')!.classList.contains('focus-ring')).toBe(true)
    expect(input('search')!.classList.contains('outline-none')).toBe(false)
  })
})

// ============================================================================
// 9. Categories and accounts: add, archive, restore; pickers hide archived
// ============================================================================

describe('Categories: add, archive, restore', () => {
  it('adds a category of the section it was added from; the database picks its look', async () => {
    const { repo } = await mountApp({ path: '/categories' })
    expect(document.body.textContent).not.toContain('later update')
    await click(byTestId('add-income-category'))
    expect(input('category-add-income')!.checked).toBe(true)
    expect(document.body.textContent).toContain('Ventrafin picks an icon and colour from the name. Change them afterwards by opening the category.')
    await type(input('category-add-name'), 'Rent received')
    await click(byTestId('category-add-save'))
    expect(repo.categoryInserts).toEqual([{ name: 'Rent received', kind: 'income' }])
    expect(document.body.textContent).toContain('Added Rent received')
    expect(byTestId('categories-income')!.textContent).toContain('Rent received')
  })

  it('names are checked before saving, archived ones included', async () => {
    const { repo } = await mountApp({ path: '/categories' })
    await click(byTestId('add-category'))
    await type(input('category-add-name'), 'old STUFF')
    expect(byTestId('category-add-error')!.textContent).toBe('You already have an expense category called "Old stuff" (archived)')
    await click(byTestId('category-add-save'))
    expect(repo.categoryInserts).toHaveLength(0)
  })

  it('archive asks first (Cancel focused), then the category moves to Archived; Restore brings it back', async () => {
    const { repo } = await mountApp({ path: '/categories' })
    await click(document.querySelector('[data-category-id="cat-food"]'))
    await click(byTestId('category-archive'))
    expect(document.body.textContent).toContain('Archive Food?')
    expect(document.body.textContent).toContain(
      'It disappears from the category pickers and auto-categorization stops using it. Its past transactions keep it, and you can restore it any time.',
    )
    expect(document.activeElement).toBe(confirmButton('reject'))
    await click(confirmButton('accept'))
    expect(repo.categoryArchives).toEqual([{ id: 'cat-food', archived: true }])
    expect(document.body.textContent).toContain('Archived Food')
    expect(byTestId('categories-expense')!.textContent).not.toContain('Food')
    expect(byTestId('categories-archived')!.textContent).toContain('Food')

    await click(byTestId('restore-cat-food'))
    expect(repo.categoryArchives.at(-1)).toEqual({ id: 'cat-food', archived: false })
    expect(document.body.textContent).toContain('Restored Food')
    expect(byTestId('categories-expense')!.textContent).toContain('Food')
  })
})

describe('Accounts: add, edit, archive, restore', () => {
  const OLD: Account = { id: 'acc-old', name: 'Old Bank', type: 'bank', archived: true }

  it('adds an account with a name and type', async () => {
    const { repo } = await mountApp({ path: '/accounts' })
    expect(document.body.textContent).not.toContain('later update')
    await click(byTestId('add-account'))
    await type(input('account-name'), 'HDFC Credit')
    await click(input('account-type-credit'))
    await click(byTestId('account-save'))
    expect(repo.accountWrites).toMatchObject([{ op: 'insert', name: 'HDFC Credit', type: 'credit' }])
    expect(document.body.textContent).toContain('Added HDFC Credit')
    expect(byTestId('accounts-table')!.textContent).toContain('HDFC Credit')
  })

  it('checks the name as the database does: empty, too long, already used (archived too)', async () => {
    const repo = new FakeRepository()
    repo.accounts.push({ ...OLD })
    await mountApp({ path: '/accounts', repo })
    await click(byTestId('add-account'))
    await click(byTestId('account-save'))
    expect(byTestId('account-name-error')!.textContent).toBe('Enter a name')
    await type(input('account-name'), 'x'.repeat(61))
    expect(byTestId('account-name-error')!.textContent).toBe('Keep it to 60 characters or fewer')
    await type(input('account-name'), ' bank ')
    expect(byTestId('account-name-error')!.textContent).toBe('You already have an account called "Bank"')
    await type(input('account-name'), 'old bank')
    expect(byTestId('account-name-error')!.textContent).toBe('You already have an account called "Old Bank" (archived)')
    expect(repo.accountWrites).toHaveLength(0)
  })

  it('edits the name and type', async () => {
    const { repo } = await mountApp({ path: '/accounts' })
    await click(document.querySelector('[data-account-id="acc-cc"]'))
    expect(dialogTitles()).toContain('Edit account')
    await type(input('account-name'), 'SBI Card')
    await click(input('account-type-bank'))
    await click(byTestId('account-save'))
    expect(repo.accountWrites).toEqual([{ op: 'update', id: 'acc-cc', name: 'SBI Card', type: 'bank' }])
    expect(document.body.textContent).toContain('Saved SBI Card')
  })

  it('archive asks first, then the account moves to Archived; Restore needs no confirm', async () => {
    const { repo } = await mountApp({ path: '/accounts' })
    await click(document.querySelector('[data-account-id="acc-cash"]'))
    await click(byTestId('account-archive'))
    expect(document.body.textContent).toContain('Archive Cash?')
    expect(document.body.textContent).toContain(
      'It disappears from the account pickers. Its transactions and bills keep it, and you can restore it any time.',
    )
    expect(document.activeElement).toBe(confirmButton('reject'))
    await click(confirmButton('accept'))
    expect(repo.accountWrites).toEqual([{ op: 'archive', id: 'acc-cash' }])
    expect(document.body.textContent).toContain('Archived Cash')
    expect(byTestId('accounts-archived')!.textContent).toContain('Cash')

    await click(byTestId('restore-acc-cash'))
    expect(repo.accountWrites.at(-1)).toEqual({ op: 'restore', id: 'acc-cash' })
    expect(document.body.textContent).toContain('Restored Cash')
    expect(byTestId('accounts-archived')).toBeNull()
  })

  it('the last active account cannot be archived', async () => {
    const repo = new FakeRepository()
    repo.accounts = repo.accounts.map((a) => ({ ...a, archived: a.id !== 'acc-bank' }))
    await mountApp({ path: '/accounts', repo })
    await click(document.querySelector('[data-account-id="acc-bank"]'))
    expect(byTestId<HTMLButtonElement>('account-archive')!.disabled).toBe(true)
    expect(byTestId('account-last-active')!.textContent).toBe('Keep at least one active account.')
  })

  it("the database's refusal is shown in plain words", async () => {
    const repo = new FakeRepository()
    await mountApp({ path: '/accounts', repo })
    await click(document.querySelector('[data-account-id="acc-cash"]'))
    // The phone archived the other two meanwhile.
    repo.accounts = repo.accounts.map((a) => ({ ...a, archived: a.id !== 'acc-cash' }))
    await click(byTestId('account-archive'))
    await click(confirmButton('accept'))
    expect(document.body.textContent).toContain('Not archived. Keep at least one active account.')
  })
})

describe('Pickers for new entries hide archived accounts and categories', () => {
  function repoWithArchived() {
    const repo = new FakeRepository()
    repo.accounts.push({ id: 'acc-old', name: 'Old Bank', type: 'bank', archived: true })
    repo.txns = [
      makeTxn('t-old', { date: '2026-09-20', description: 'Old habits', accountId: 'acc-old', categoryId: 'cat-old', paymentMethod: 'debit' }),
      makeTxn('t-new', { date: '2026-09-21', description: 'Swiggy dinner' }),
    ]
    return repo
  }
  const listed = () => [...document.querySelectorAll('ul[role="listbox"] li')].map((li) => li.textContent?.trim() ?? '')

  it('Add grid: no archived account in the list; a remembered archived account falls back to an active one', async () => {
    await mountApp({ path: '/add', repo: repoWithArchived(), prefs: createMemoryEntryPrefs({ accountId: 'acc-old', method: 'upi' }) })
    expect(cell(0, 5).value).toBe('Cash')
    cell(0, 5).focus()
    await press(cell(0, 5), 'ArrowDown', { altKey: true })
    expect(listed().some((t) => t.includes('Old Bank'))).toBe(false)
    expect(listed().some((t) => t.startsWith('Bank'))).toBe(true)
  })

  it('Add grid: typing an archived account says so', async () => {
    await mountApp({ path: '/add', repo: repoWithArchived() })
    await type(cell(0, 1), 'Tea')
    await type(cell(0, 2), '20')
    await type(cell(0, 5), 'Old Bank')
    cell(0, 5).blur()
    await settle()
    expect(byTestId('problems')!.textContent).toContain('"Old Bank" is archived. Choose another account')
  })

  it("Transactions: a row's archived account and category show as (archived) and can stay; other rows can't pick them", async () => {
    const { repo } = await mountApp({ path: '/transactions?month=2026-09', repo: repoWithArchived() })
    const old = () => rowOf('Old habits')!
    await click(old().cells[6])
    const account = old().cells[6]!.querySelector('input')!
    expect(account.value).toBe('Old Bank (archived)')
    await press(account, 'F4')
    expect(listed().some((t) => t.startsWith('Old Bank (archived)'))).toBe(true)
    await press(account, 'Escape')
    await press(account, 'Enter')
    expect(repo.updates).toHaveLength(0) // unchanged, not "no account called"
    expect(document.body.textContent).not.toContain('Not changed')

    await click(old().cells[3])
    const category = old().cells[3]!.querySelector('input')!
    expect(category.value).toBe('Old stuff (archived)')
    await press(category, 'Enter')
    expect(repo.updates).toHaveLength(0)

    await click(rowOf('Swiggy dinner')!.cells[6])
    await press(rowOf('Swiggy dinner')!.cells[6]!.querySelector('input'), 'F4')
    expect(listed().some((t) => t.includes('Old Bank'))).toBe(false)
  })

  it('Bill dialog: a new bill offers active accounts only; a bill on an archived account keeps it, marked', async () => {
    const repo = repoWithArchived()
    repo.bills = [bill({ accountId: 'acc-old' })]
    await mountApp({ path: '/bills', repo })
    await click(byTestId('add-bill'))
    const options = () => [...byTestId<HTMLSelectElement>('bill-account')!.options].map((o) => o.textContent?.trim())
    expect(options()).toEqual(['Bank', 'Cash', 'Credit Card'])
    await click(document.querySelector('.p-dialog-close-button'))

    await click(byTestId('edit-bill-1'))
    expect(options()).toContain('Old Bank (archived)')
    expect(byTestId<HTMLSelectElement>('bill-account')!.value).toBe('acc-old')
  })
})
