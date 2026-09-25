// Transactions (inline editing, delete, filters), Categories (rename),
// Dashboard, live updates from the phone, and the sign-in guard.
import { describe, expect, it } from 'vitest'
import { FakeRepository, makeTxn } from '../support/fakeRepository'
import { buttonByText, byTestId, mountApp, settle } from '../support/mountApp'

async function click(el: Element | null | undefined) {
  if (!el) throw new Error('nothing to click')
  ;(el as HTMLElement).click()
  await settle()
}

async function type(el: HTMLInputElement, text: string) {
  el.focus()
  el.value = text
  el.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
}

/** PrimeVue's table reads event.code, the grid cells read event.key: send both. */
async function press(el: Element, key: string) {
  el.dispatchEvent(new KeyboardEvent('keydown', { key, code: key, bubbles: true, cancelable: true }))
  await settle()
}

function repoWithSeptember() {
  const repo = new FakeRepository()
  repo.txns = [
    makeTxn('t1', { date: '2026-09-24', description: 'Swiggy dinner', amountPaise: 45000, categoryId: 'cat-food', autoCategorized: true }),
    makeTxn('t2', { date: '2026-09-23', description: 'Apollo Tyres', amountPaise: 320000, categoryId: 'cat-med', autoCategorized: true, accountId: 'acc-bank', paymentMethod: 'card' }),
    makeTxn('t3', { date: '2026-09-22', description: 'Gift for Meena', amountPaise: 150000, categoryId: null }),
    makeTxn('t4', { date: '2026-09-21', description: 'ATM withdrawal', amountPaise: 200000, type: 'transfer', accountId: 'acc-bank', toAccountId: 'acc-cash', categoryId: null, paymentMethod: null }),
    makeTxn('t5', { date: '2026-08-30', description: 'Last month', amountPaise: 100 }),
  ]
  repo.totals = { expensePaise: 515000, lastExpensePaise: 100, incomePaise: 0, lastIncomePaise: 0, uncategorizedCount: 1 }
  return repo
}

const tableRows = () => [...document.querySelectorAll<HTMLTableRowElement>('[data-testid="txn-table"] tbody tr')]
const rowOf = (text: string) => tableRows().find((tr) => tr.textContent?.includes(text))
/** Columns: 0 select, 1 date, 2 description, 3 category, 4 amount, 5 type, 6 account, 7 to, 8 paid by, 9 delete. */
const CATEGORY_COL = 3

describe('Transactions', () => {
  it('lists the month with its visuals: category circles, merchant letters, Uncategorized and transfers', async () => {
    await mountApp({ path: '/transactions?month=2026-09', repo: repoWithSeptember() })
    expect(tableRows()).toHaveLength(4) // August's row is not in September
    const swiggy = rowOf('Swiggy dinner')!
    expect(swiggy.querySelector('[data-icon="restaurant"]')).not.toBeNull()
    expect(swiggy.querySelector('[data-merchant-letter="S"]')).not.toBeNull()
    expect(swiggy.textContent).toContain('auto')
    expect(swiggy.textContent).toContain('₹450.00')
    expect(rowOf('Gift for Meena')!.querySelector('[data-testid="uncategorized-chip"]')).not.toBeNull()
    expect(rowOf('ATM withdrawal')!.querySelector('[data-circle="outlined"] [data-icon="swap_horiz"]')).not.toBeNull()
    expect(byTestId('month-summary')?.textContent).toContain('Uncategorized 1')
  })

  it('edit a category in place: only category_id is sent (so the database learns), and the row updates', async () => {
    const { repo } = await mountApp({ path: '/transactions?month=2026-09', repo: repoWithSeptember() })
    await click(rowOf('Apollo Tyres')!.cells[CATEGORY_COL])
    const input = rowOf('Apollo Tyres')!.cells[CATEGORY_COL]!.querySelector<HTMLInputElement>('input')!
    expect(document.activeElement).toBe(input)
    expect(input.value).toBe('Medical')

    await type(input, 'foo')
    await press(input, 'Enter')

    expect(repo.updates).toEqual([{ id: 't2', patch: { categoryId: 'cat-food' } }])
    expect(rowOf('Apollo Tyres')!.cells[CATEGORY_COL]!.textContent).toContain('Food')
    expect(rowOf('Apollo Tyres')!.cells[CATEGORY_COL]!.textContent).not.toContain('auto')
    expect(document.body.textContent).toContain('Category saved')
  })

  it('an invalid edit changes nothing and says why', async () => {
    const { repo } = await mountApp({ path: '/transactions?month=2026-09', repo: repoWithSeptember() })
    await click(rowOf('Swiggy dinner')!.cells[4])
    const input = rowOf('Swiggy dinner')!.cells[4]!.querySelector<HTMLInputElement>('input')!
    await type(input, '-50')
    await press(input, 'Enter')
    expect(repo.updates).toHaveLength(0)
    expect(document.body.textContent).toContain('Not changed')
  })

  it('a failed edit puts the old value back and says so', async () => {
    const repo = repoWithSeptember()
    repo.failNextUpdateWith = new TypeError('Failed to fetch')
    await mountApp({ path: '/transactions?month=2026-09', repo })
    const row = rowOf('Swiggy dinner')!
    await click(row.cells[2])
    const input = row.cells[2]!.querySelector<HTMLInputElement>('input')!
    await type(input, 'Swiggy lunch')
    await press(input, 'Enter')
    expect(document.body.textContent).toContain('Not saved')
    expect(rowOf('Swiggy dinner')).toBeDefined()
    expect(rowOf('Swiggy lunch')).toBeUndefined()
  })

  it('delete asks first, then removes the row', async () => {
    const { repo } = await mountApp({ path: '/transactions?month=2026-09', repo: repoWithSeptember() })
    await click(rowOf('Gift for Meena')!.querySelector('[data-testid="delete-row"]'))
    expect(document.body.textContent).toContain('Delete this transaction?')
    expect(repo.deletes).toHaveLength(0)
    await click(buttonByText('Delete'))
    expect(repo.deletes).toEqual([['t3']])
    expect(rowOf('Gift for Meena')).toBeUndefined()
  })

  it('filters: Uncategorized from the URL, and the account filter', async () => {
    await mountApp({ path: '/transactions?month=2026-09&category=uncategorized', repo: repoWithSeptember() })
    expect(tableRows().map((r) => r.textContent?.includes('Gift for Meena'))).toEqual([true])
    expect(byTestId('row-count')?.textContent).toContain('Showing 1 of 4')
  })

  it('a change made on the phone appears without a refresh (Realtime)', async () => {
    const repo = repoWithSeptember()
    await mountApp({ path: '/transactions?month=2026-09', repo, realtime: true })
    repo.txns.push(makeTxn('phone-1', { date: '2026-09-25', description: 'Entered on the phone' }))
    repo.emit({ table: 'transactions' })
    await new Promise((r) => setTimeout(r, 400)) // Realtime events are debounced (300 ms)
    await settle()
    expect(rowOf('Entered on the phone')).toBeDefined()
  })
})

describe('Categories', () => {
  it('rename a category', async () => {
    const { repo } = await mountApp({ path: '/categories' })
    await click(document.querySelector('[data-category-id="cat-food"]'))
    const name = byTestId<HTMLInputElement>('category-name')!
    expect(name.value).toBe('Food')
    await type(name, 'Khana')
    await click(byTestId('category-save'))
    expect(repo.categoryEdits).toEqual([{ id: 'cat-food', edit: { name: 'Khana', icon: 'restaurant', color: '#FB8C00' } }])
    expect(document.querySelector('[data-category-id="cat-food"]')?.textContent).toContain('Khana')
  })

  it('empty, reserved and duplicate names are refused before saving', async () => {
    const { repo } = await mountApp({ path: '/categories' })
    await click(document.querySelector('[data-category-id="cat-food"]'))
    const name = byTestId<HTMLInputElement>('category-name')!
    const save = byTestId<HTMLButtonElement>('category-save')!

    await type(name, '  ')
    expect(byTestId('category-name-error')?.textContent).toBe('Enter a name')
    expect(save.disabled).toBe(true)
    await type(name, 'Uncategorized')
    expect(byTestId('category-name-error')?.textContent).toContain('is reserved')
    await type(name, 'groceries')
    expect(byTestId('category-name-error')?.textContent).toBe('You already have an expense category called "Groceries"')
    expect(save.disabled).toBe(true)
    await type(name, 'Salary') // an income category may share it
    expect(save.disabled).toBe(false)
    expect(repo.categoryEdits).toHaveLength(0)
  })

  it('change the icon and colour from the curated sets', async () => {
    const { repo } = await mountApp({ path: '/categories' })
    await click(document.querySelector('[data-category-id="cat-groc"]'))
    await click(byTestId('icon-house'))
    await click(byTestId('color-#AD1457'))
    await click(byTestId('category-save'))
    expect(repo.categoryEdits[0]?.edit).toEqual({ name: 'Groceries', icon: 'house', color: '#AD1457' })
  })
})

describe('Dashboard', () => {
  it('this month against last month, and spending by category', async () => {
    const repo = new FakeRepository()
    repo.totals = { expensePaise: 1234500, lastExpensePaise: 1000000, incomePaise: 8500000, lastIncomePaise: 8500000, uncategorizedCount: 2 }
    repo.comparison = [
      { kind: 'expense', categoryId: 'cat-food', categoryName: 'Food', color: '#FB8C00', thisMonthPaise: 800000, lastMonthPaise: 600000 },
      { kind: 'expense', categoryId: null, categoryName: 'Uncategorized', color: '#9E9E9E', thisMonthPaise: 434500, lastMonthPaise: 0 },
      { kind: 'expense', categoryId: 'cat-med', categoryName: 'Medical', color: '#E53935', thisMonthPaise: 0, lastMonthPaise: 400000 },
      { kind: 'income', categoryId: 'cat-salary', categoryName: 'Salary', color: '#2E7D32', thisMonthPaise: 8500000, lastMonthPaise: 8500000 },
    ]
    await mountApp({ path: '/dashboard', repo })

    expect(byTestId('spent-now')?.textContent).toBe('₹12,345.00')
    expect(byTestId('uncategorized-callout')?.textContent).toContain('2 uncategorized in September 2026')
    const breakdown = [...document.querySelectorAll('[data-breakdown]')].map((r) => r.getAttribute('data-breakdown'))
    expect(breakdown).toEqual(['cat-food', 'uncategorized', 'cat-med']) // expenses only, biggest first
    expect(document.querySelector('[data-breakdown="cat-food"]')?.textContent).toMatch(/₹8,000.*₹6,000.*₹2,000/s)
    expect(document.querySelector('[data-breakdown="uncategorized"]')?.textContent).toContain('new')
  })
})

describe('sign-in guard', () => {
  it('signed out: every section sends you to /login, and back afterwards', async () => {
    const { router } = await mountApp({ path: '/transactions?month=2026-09', signedIn: false })
    expect(router.currentRoute.value.name).toBe('login')
    expect(router.currentRoute.value.query.next).toBe('/transactions?month=2026-09')
    expect(byTestId('google-sign-in')).not.toBeNull()
  })

  it('every section has its own route', async () => {
    const { router } = await mountApp({ path: '/dashboard' })
    for (const path of ['/dashboard', '/transactions', '/add', '/categories', '/accounts', '/bills', '/reports', '/settings']) {
      await router.push(path)
      await settle()
      expect(router.currentRoute.value.path).toBe(path)
      expect(document.querySelector(`nav a[href="${path}"]`)?.getAttribute('aria-current')).toBe('page')
    }
  })

  it('signing out from anywhere returns to the login page', async () => {
    const { router, auth } = await mountApp({ path: '/accounts' })
    await auth.signOut()
    await settle()
    expect(router.currentRoute.value.name).toBe('login')
  })
})
