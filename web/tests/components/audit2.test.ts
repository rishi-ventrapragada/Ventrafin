// Audit round 2 on the fake repository: months in the URL (Dashboard,
// Reports), the icon rail and section order, signing out from the sidebar,
// the Dashboard's headline and bills, sticky error toasts, per-account
// totals, the Reports caption, Windows Hello wording, readable (not faded)
// states, and the Transactions type filter.
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Bill } from '@/lib/models'
import { FakeRepository, makeTxn } from '../support/fakeRepository'
import { byTestId, cell, confirmButton, mountApp, settle } from '../support/mountApp'
import type { PasskeyService } from '@/data/passkeys'

async function click(el: Element | null | undefined) {
  if (!el) throw new Error('nothing to click')
  ;(el as HTMLElement).click()
  await settle()
}

async function type(el: HTMLInputElement | null, text: string) {
  if (!el) throw new Error('no input')
  el.focus()
  el.value = text
  el.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
}

async function press(el: Element | null, key: string) {
  if (!el) throw new Error('nothing to press a key in')
  el.dispatchEvent(new KeyboardEvent('keydown', { key, code: key, bubbles: true, cancelable: true }))
  await settle()
}

afterEach(() => vi.useRealTimers())

const monthLabel = () => byTestId('month-label')!.textContent?.trim()
const OFFLINE_TEXT = "Couldn't reach the server. Check your internet connection and try again."

function failOnce<K extends 'fetchBills' | 'fetchAccountTotals'>(repo: FakeRepository, name: K) {
  const original = repo[name].bind(repo) as () => Promise<unknown>
  let failed = false
  ;(repo as unknown as Record<string, unknown>)[name] = async (...args: unknown[]) => {
    if (!failed) {
      failed = true
      throw new TypeError('Failed to fetch')
    }
    return (original as (...a: unknown[]) => Promise<unknown>)(...args)
  }
}

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

// ============================================================================
// NAV-4: the month (and the Reports span) survive Back and F5
// ============================================================================

describe('NAV-4: Dashboard month in the URL', () => {
  it('opens on the month in the URL (F5), writes a changed month back, and Back returns to it', async () => {
    const repo = new FakeRepository()
    const calls: string[] = []
    const original = repo.fetchMonthTotals.bind(repo)
    repo.fetchMonthTotals = async (m) => (calls.push(`${m.year}-${m.month}`), original(m))
    const { router } = await mountApp({ path: '/dashboard?month=2026-07', repo })
    expect(monthLabel()).toContain('July 2026')
    expect(calls.at(-1)).toBe('2026-7')

    await click(document.querySelector('[aria-label="Previous month"]'))
    expect(router.currentRoute.value.query).toEqual({ month: '2026-06' })

    await router.push('/reports')
    await settle()
    router.back()
    await vi.waitFor(() => expect(router.currentRoute.value.path).toBe('/dashboard'))
    await settle()
    expect(router.currentRoute.value.query).toEqual({ month: '2026-06' })
    expect(monthLabel()).toContain('June 2026')
  })

  it('this month keeps a clean URL; a bad or future month shows this month', async () => {
    const { router } = await mountApp({ path: '/dashboard?month=2026-06' })
    await click(document.querySelector('[aria-label="Next month"]'))
    await click(document.querySelector('[aria-label="Next month"]'))
    await click(document.querySelector('[aria-label="Next month"]'))
    expect(monthLabel()).toContain('September 2026')
    expect(router.currentRoute.value.query).toEqual({})
    for (const bad of ['2026-10', '2026-13', 'soon']) {
      await mountApp({ path: `/dashboard?month=${bad}` })
      expect(monthLabel(), bad).toContain('September 2026')
    }
  })

  it('the sidebar link goes back to this month', async () => {
    const { router } = await mountApp({ path: '/dashboard?month=2026-03' })
    expect(monthLabel()).toContain('March 2026')
    await click(document.querySelector('nav a[href="/dashboard"]'))
    expect(router.currentRoute.value.fullPath).toBe('/dashboard')
    expect(monthLabel()).toContain('September 2026')
  })

  it("leaving for another page's link leaves that page's URL alone", async () => {
    const { router } = await mountApp({ path: '/dashboard?month=2026-07' })
    await router.push({ path: '/transactions', query: { month: '2026-05', category: 'uncategorized' } })
    await settle()
    expect(router.currentRoute.value.query).toEqual({ month: '2026-05', category: 'uncategorized' })
    await router.push({ path: '/reports', query: { month: '2026-03', span: '12' } })
    await settle()
    expect(router.currentRoute.value.query).toEqual({ month: '2026-03', span: '12' })
    expect(monthLabel()).toContain('March 2026')
  })
})

describe('NAV-4: Reports month and span in the URL', () => {
  it('opens on them (F5), writes changes back, and keeps defaults out of the URL', async () => {
    const repo = new FakeRepository()
    const { router } = await mountApp({ path: '/reports?month=2026-07&span=12', repo })
    expect(monthLabel()).toContain('July 2026')
    expect(byTestId('span-12')!.getAttribute('aria-pressed')).toBe('true')
    expect(repo.monthlyRanges.at(-1)).toEqual({ from: { year: 2025, month: 8 }, to: { year: 2026, month: 7 } })

    await click(byTestId('span-6'))
    expect(router.currentRoute.value.query).toEqual({ month: '2026-07' })
    await click(byTestId('span-12'))
    await click(document.querySelector('[aria-label="Previous month"]'))
    expect(router.currentRoute.value.query).toEqual({ month: '2026-06', span: '12' })

    await router.push('/dashboard')
    await settle()
    router.back()
    await vi.waitFor(() => expect(router.currentRoute.value.path).toBe('/reports'))
    await settle()
    expect(monthLabel()).toContain('June 2026')
    expect(byTestId('span-12')!.getAttribute('aria-pressed')).toBe('true')
  })

  it('bad values fall back to this month and 6 months', async () => {
    const repo = new FakeRepository()
    await mountApp({ path: '/reports?month=2031-01&span=24', repo })
    expect(monthLabel()).toContain('September 2026')
    expect(byTestId('span-6')!.getAttribute('aria-pressed')).toBe('true')
    expect(repo.monthlyRanges.at(-1)).toEqual({ from: { year: 2026, month: 4 }, to: { year: 2026, month: 9 } })
  })
})

// ============================================================================
// NAV-5, NAV-6, NAV-7, UI-1: the sidebar
// ============================================================================

/** A window `width` CSS pixels wide, as far as matchMedia is concerned; `resize` changes it. */
function fakeWindowWidth(width: number) {
  const original = window.matchMedia
  const lists: { query: string; listeners: ((e: MediaQueryListEvent) => void)[] }[] = []
  const evaluate = (query: string) => {
    const max = /max-width:\s*([\d.]+)px/.exec(query)
    const min = /min-width:\s*([\d.]+)px/.exec(query)
    return (!max || width <= Number(max[1])) && (!min || width >= Number(min[1]))
  }
  window.matchMedia = (query: string) => {
    const entry = { query, listeners: [] as ((e: MediaQueryListEvent) => void)[] }
    lists.push(entry)
    return {
      get matches() {
        return evaluate(query)
      },
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: (_: string, l: (e: MediaQueryListEvent) => void) => entry.listeners.push(l),
      removeEventListener: (_: string, l: (e: MediaQueryListEvent) => void) => (entry.listeners = entry.listeners.filter((x) => x !== l)),
      dispatchEvent: () => false,
    } as unknown as MediaQueryList
  }
  return {
    resize(w: number) {
      width = w
      for (const l of lists) for (const fn of l.listeners) fn({ matches: evaluate(l.query), media: l.query } as MediaQueryListEvent)
    },
    restore: () => (window.matchMedia = original),
  }
}

const navLinks = () => [...document.querySelectorAll<HTMLAnchorElement>('nav[aria-label="Sections"] a')]

describe('NAV-5: an icon rail below 1400 px', () => {
  it('at 1280 px: icons only, each named for screen readers and tooltips, still links, the current one marked', async () => {
    const win = fakeWindowWidth(1280)
    try {
      await mountApp({ path: '/bills' })
      expect(byTestId('sidebar')!.dataset.rail).toBe('true')
      const links = navLinks()
      expect(links.map((a) => a.getAttribute('aria-label'))).toEqual([
        'Dashboard',
        'Transactions',
        'Add',
        'Bills',
        'Categories',
        'Accounts',
        'Reports',
        'Settings',
      ])
      expect(links.every((a) => a.textContent?.trim() === '' && a.getAttribute('href'))).toBe(true)
      const current = links.filter((a) => a.getAttribute('aria-current') === 'page')
      expect(current.map((a) => a.getAttribute('aria-label'))).toEqual(['Bills'])
      expect(current[0]!.className).toContain('bg-black/15')
      expect(byTestId('sidebar-sign-out')!.getAttribute('aria-label')).toBe('Sign out')
      expect(byTestId('sidebar')!.textContent).not.toContain('dad@example.com')

      // Wider window: the names come back.
      win.resize(1440)
      await settle()
      expect(byTestId('sidebar')!.dataset.rail).toBeUndefined()
      expect(navLinks().map((a) => a.textContent?.trim())).toContain('Transactions')
      expect(navLinks()[0]!.getAttribute('aria-label')).toBeNull()
      expect(byTestId('sidebar')!.textContent).toContain('dad@example.com')
    } finally {
      win.restore()
    }
  })

  it('at 1400 px and wider: the full sidebar', async () => {
    const win = fakeWindowWidth(1400)
    try {
      await mountApp({ path: '/dashboard' })
      expect(byTestId('sidebar')!.dataset.rail).toBeUndefined()
      expect(navLinks()[0]!.textContent?.trim()).toBe('Dashboard')
    } finally {
      win.restore()
    }
  })
})

describe('NAV-6 and UI-1: sidebar order and looks', () => {
  it('the same order as the phone; the current row is darkened, the others at full opacity', async () => {
    await mountApp({ path: '/accounts' })
    expect(navLinks().map((a) => a.textContent?.trim())).toEqual([
      'Dashboard',
      'Transactions',
      'Add',
      'Bills',
      'Categories',
      'Accounts',
      'Reports',
      'Settings',
    ])
    const current = navLinks().find((a) => a.getAttribute('aria-current') === 'page')!
    expect(current.textContent?.trim()).toBe('Accounts')
    expect(current.className).toContain('bg-black/15')
    for (const a of navLinks()) expect(a.className).not.toMatch(/\/90|on-brand\/1/)
  })
})

describe('NAV-7: signing out from the sidebar asks first', () => {
  it('the same question as Settings, with Cancel focused; Cancel stays, Sign out signs out', async () => {
    const { router, auth } = await mountApp({ path: '/transactions' })
    await click(byTestId('sidebar-sign-out'))
    expect(document.body.textContent).toContain('Sign out?')
    expect(document.body.textContent).toContain(
      'Your data stays in your account. Sign in with Google to come back. The phone stays signed in.',
    )
    expect(document.activeElement).toBe(confirmButton('reject'))
    expect(confirmButton('reject').textContent?.trim()).toBe('Cancel')
    await click(confirmButton('reject'))
    expect(auth.user.value).not.toBeNull()
    expect(router.currentRoute.value.path).toBe('/transactions')

    await click(byTestId('sidebar-sign-out'))
    await click(confirmButton('accept'))
    await vi.waitFor(() => expect(router.currentRoute.value.name).toBe('login'))
  })

  it('Settings asks the same, with Cancel focused too', async () => {
    await mountApp({ path: '/settings' })
    await click([...document.querySelectorAll('main button')].find((b) => b.textContent?.trim() === 'Sign out'))
    expect(document.body.textContent).toContain('Sign out?')
    expect(document.activeElement).toBe(confirmButton('reject'))
  })
})

// ============================================================================
// DASH-1, DASH-4: the Dashboard
// ============================================================================

describe('DASH-1: this month\'s spending is the headline', () => {
  it('a large figure above the table (the table stays)', async () => {
    const repo = new FakeRepository()
    repo.totals = { expensePaise: 1234500, lastExpensePaise: 1000000, incomePaise: 8500000, lastIncomePaise: 8500000, uncategorizedCount: 0 }
    await mountApp({ path: '/dashboard', repo })
    const headline = byTestId('spent-headline')!
    expect(headline.textContent?.trim()).toBe('₹12,345.00')
    expect(headline.className).toContain('text-4xl')
    expect(byTestId('month-totals')!.textContent).toContain('Spent this month')
    expect(byTestId('spent-now')!.textContent).toBe('₹12,345.00')

    await click(document.querySelector('[aria-label="Previous month"]'))
    expect(byTestId('month-totals')!.textContent).toContain('Spent in August 2026')
  })
})

describe('DASH-4: bills to pay on the Dashboard', () => {
  it('overdue and due within 7 days, soonest first, linking to Bills; later bills left out', async () => {
    const repo = new FakeRepository()
    repo.bills = [
      bill({ id: 'b-over', name: 'Home loan EMI', kind: 'emi', status: 'overdue', daysUntil: -2, nextDueDate: '2026-09-23', amountPaise: 2500000 }),
      bill({ id: 'b-today', name: 'Water', status: 'due_today', daysUntil: 0, nextDueDate: '2026-09-25' }),
      bill({ id: 'b-soon', name: 'BESCOM' }),
      bill({ id: 'b-later', name: 'Internet', status: 'upcoming', daysUntil: 15, nextDueDate: '2026-10-10' }),
    ]
    const { router } = await mountApp({ path: '/dashboard', repo })
    const tile = byTestId('bills-due')!
    expect([...tile.querySelectorAll('[data-bill-due]')].map((r) => r.getAttribute('data-bill-due'))).toEqual(['b-over', 'b-today', 'b-soon'])
    expect(tile.textContent).toContain('Overdue · 2 days')
    expect(tile.textContent).toContain('Due today')
    expect(tile.textContent).toContain('Due in 3 days')
    expect(tile.textContent).toContain('₹25,000')
    expect(tile.textContent).not.toContain('Internet')
    await click(byTestId('bills-due-link'))
    expect(router.currentRoute.value.path).toBe('/bills')
  })

  it('hidden when nothing is due soon', async () => {
    const repo = new FakeRepository()
    repo.bills = [bill({ status: 'upcoming', daysUntil: 20, nextDueDate: '2026-10-15' })]
    await mountApp({ path: '/dashboard', repo })
    expect(byTestId('month-totals')).not.toBeNull()
    expect(byTestId('bills-due')).toBeNull()
  })

  it('a load error says why, with Retry', async () => {
    const repo = new FakeRepository()
    repo.bills = [bill()]
    failOnce(repo, 'fetchBills')
    await mountApp({ path: '/dashboard', repo })
    expect(byTestId('bills-due')!.textContent).toContain(`Couldn't load bills. ${OFFLINE_TEXT}`)
    await click(byTestId('bills-due')!.querySelector('[data-testid="retry"]'))
    expect(byTestId('bills-due')!.querySelector('[data-bill-due="bill-1"]')).not.toBeNull()
  })
})

// ============================================================================
// TX-5: error toasts stay; the others go
// ============================================================================

describe('TX-5: one rule for toasts', () => {
  it('Bills: an error stays until closed, a confirmation goes away by itself', async () => {
    const repo = new FakeRepository()
    repo.bills = [bill()]
    await mountApp({ path: '/bills', repo })
    repo.setBillReminder = async () => {
      throw new TypeError('Failed to fetch')
    }
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    byTestId('reminder-bill-1')!.click()
    await vi.advanceTimersByTimeAsync(100)
    await vi.advanceTimersByTimeAsync(30000)
    const toasts = () => [...document.querySelectorAll('.p-toast-message')].map((t) => t.textContent ?? '')
    expect(toasts().some((t) => t.includes('Not changed') && t.includes(OFFLINE_TEXT))).toBe(true)

    // Closing it is up to Dad.
    ;(document.querySelector('.p-toast-message .p-toast-close-button') as HTMLElement).click()
    await vi.advanceTimersByTimeAsync(1000)
    expect(toasts().some((t) => t.includes('Not changed'))).toBe(false)
    vi.useRealTimers()
  })

  it('Transactions: a success toast is timed', async () => {
    const repo = new FakeRepository()
    repo.txns = [makeTxn('t1', { date: '2026-09-24', description: 'Swiggy dinner' })]
    await mountApp({ path: '/transactions?month=2026-09', repo })
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
    const row = document.querySelector('[data-testid="txn-table"] tbody tr')!
    ;(row.querySelector('[data-testid="delete-row"]') as HTMLElement).click()
    await vi.advanceTimersByTimeAsync(100)
    confirmButton('accept').click()
    await vi.advanceTimersByTimeAsync(100)
    expect(byTestId('undo-toast')).not.toBeNull()
    await vi.advanceTimersByTimeAsync(6000)
    vi.useRealTimers()
    await settle()
    expect(byTestId('undo-toast')).toBeNull()
  })
})

// ============================================================================
// CAT-1: the Accounts page
// ============================================================================

describe('CAT-1: this month per account', () => {
  function repoWithMonth() {
    const repo = new FakeRepository()
    repo.txns = [
      makeTxn('t1', { date: '2026-09-24', amountPaise: 45000, accountId: 'acc-cash' }),
      makeTxn('t2', { date: '2026-09-23', amountPaise: 320000, accountId: 'acc-bank', paymentMethod: 'card' }),
      makeTxn('t3', { date: '2026-09-01', amountPaise: 8500000, type: 'income', categoryId: 'cat-salary', accountId: 'acc-bank' }),
      makeTxn('t4', { date: '2026-09-21', amountPaise: 200000, type: 'transfer', accountId: 'acc-bank', toAccountId: 'acc-cash', categoryId: null }),
      makeTxn('t5', { date: '2026-08-30', amountPaise: 999900, accountId: 'acc-bank' }),
    ]
    return repo
  }
  const row = (id: string) => document.querySelector(`[data-testid="accounts-table"] [data-account-id="${id}"]`)!
  const cellText = (id: string, testId: string) => row(id).querySelector(`[data-testid="${testId}"]`)!.textContent?.trim()

  it('spent, income, transfers out and in, and entries, for this month', async () => {
    const repo = repoWithMonth()
    await mountApp({ path: '/accounts', repo })
    expect(repo.accountTotalsMonths.at(-1)).toEqual({ year: 2026, month: 9 })
    expect(cellText('acc-bank', 'account-spent')).toBe('₹3,200')
    expect(cellText('acc-bank', 'account-income')).toBe('₹85,000')
    expect(cellText('acc-bank', 'account-out')).toBe('₹2,000')
    expect(cellText('acc-bank', 'account-in')).toBe('₹0')
    expect(cellText('acc-bank', 'account-entries')).toBe('3')
    expect(cellText('acc-cash', 'account-spent')).toBe('₹450')
    expect(cellText('acc-cash', 'account-in')).toBe('₹2,000')
    expect(cellText('acc-cash', 'account-entries')).toBe('2')
    expect(cellText('acc-cc', 'account-entries')).toBe('0')
    expect(byTestId('accounts-total')!.textContent).toContain('₹3,650')
    expect(document.body.textContent).toContain('Totals for September 2026')
  })

  it('an account opens its transactions for this month, filtered to it', async () => {
    const { router } = await mountApp({ path: '/accounts', repo: repoWithMonth() })
    await click(byTestId('account-txns-acc-bank'))
    expect(router.currentRoute.value.path).toBe('/transactions')
    expect(router.currentRoute.value.query).toEqual({ month: '2026-09', account: 'acc-bank' })
    const rows = [...document.querySelectorAll('[data-testid="txn-table"] tbody tr')]
    expect(rows).toHaveLength(3)

    // The whole row does the same; Edit still edits.
    await router.push('/accounts')
    await settle()
    await click(row('acc-cash').querySelector('td:nth-child(3)'))
    expect(router.currentRoute.value.query).toEqual({ month: '2026-09', account: 'acc-cash' })
    await router.push('/accounts')
    await settle()
    await click(byTestId('edit-account-acc-cc'))
    expect(router.currentRoute.value.path).toBe('/accounts')
    expect([...document.querySelectorAll('.p-dialog-title')].map((t) => t.textContent?.trim())).toContain('Edit account')
  })

  it('a new entry updates the totals', async () => {
    const repo = repoWithMonth()
    await mountApp({ path: '/accounts', repo, realtime: true })
    repo.txns.push(makeTxn('phone-1', { date: '2026-09-25', amountPaise: 10000, accountId: 'acc-cc', paymentMethod: 'card' }))
    repo.emit({ table: 'transactions' }) // Realtime events are debounced (300 ms)
    await vi.waitFor(() => expect(cellText('acc-cc', 'account-spent')).toBe('₹100'), { timeout: 3000 })
  })

  it('a load error says why, with Retry; the accounts still show', async () => {
    const repo = repoWithMonth()
    failOnce(repo, 'fetchAccountTotals')
    await mountApp({ path: '/accounts', repo })
    expect(byTestId('load-error')!.textContent).toContain(`Couldn't load this month's totals. ${OFFLINE_TEXT}`)
    expect(row('acc-bank').textContent).toContain('Bank')
    await click(byTestId('retry'))
    expect(cellText('acc-bank', 'account-spent')).toBe('₹3,200')
  })
})

// ============================================================================
// REP-4, SET-1
// ============================================================================

describe('REP-4: what Net and Saved mean', () => {
  it('a caption under the month summary', async () => {
    await mountApp({ path: '/reports' })
    expect(byTestId('report-month-summary')!.querySelector('[data-testid="summary-caption"]')!.textContent).toBe(
      'Net = income minus spending. Saved = the part of income not spent, as a percentage.',
    )
  })
})

describe('SET-1: "Windows Hello sign-in", not "passkey"', () => {
  function passkeys(support: 'platform' | 'roaming'): PasskeyService {
    const list = [{ id: 'pk-a', name: 'Windows Hello sign-in', createdAt: '2026-09-01T10:00:00Z', lastUsedAt: null }]
    return {
      serverEnabled: async () => true,
      deviceSupport: async () => support,
      signIn: async () => {},
      register: async () => list[0]!,
      list: async () => list,
      remove: async () => {},
    }
  }

  it('Settings, on a PC with and without Windows Hello, and the remove question', async () => {
    for (const support of ['platform', 'roaming'] as const) {
      await mountApp({ path: '/settings', passkeys: passkeys(support) })
      const section = byTestId('passkey-section')!
      expect(section.textContent, support).not.toMatch(/passkey/i)
      expect(byTestId('passkey-register')!.textContent).toContain('Set up Windows Hello sign-in')
    }
    await click([...document.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Remove'))
    expect(document.querySelector('.p-confirmdialog')!.textContent).toContain('Remove Windows Hello sign-in?')
    expect(document.querySelector('.p-confirmdialog')!.textContent).not.toMatch(/passkey/i)
  })

  it('the sign-in page', async () => {
    localStorage.clear()
    const { rememberPasskeyHint } = await import('@/data/passkeys')
    rememberPasskeyHint(true)
    await mountApp({ path: '/login', signedIn: false, passkeys: passkeys('roaming') })
    expect(byTestId('passkey-sign-in')!.textContent).toContain('Sign in with Windows Hello')
    expect(document.body.textContent).not.toMatch(/passkey/i)
  })
})

// ============================================================================
// UI-4: readable states, not faded ones
// ============================================================================

describe('UI-4: states use colour and words, not opacity', () => {
  it('Transactions: "(no description)" in slate-600; a row being saved is tinted and says Saving…', async () => {
    const repo = new FakeRepository()
    repo.txns = [makeTxn('t1', { date: '2026-09-24', description: '' }), makeTxn('t2', { date: '2026-09-23', description: 'Swiggy dinner' })]
    await mountApp({ path: '/transactions?month=2026-09', repo })
    const empty = [...document.querySelectorAll('[data-testid="txn-table"] span')].find(
      (s) => s.children.length === 0 && s.textContent === '(no description)',
    )!
    expect(empty.className).toContain('text-slate-600')
    expect(empty.className).not.toContain('slate-500')

    // The save waits until the test lets it finish.
    let finish = () => {}
    const update = repo.updateTransaction.bind(repo)
    repo.updateTransaction = async (id, patch) => {
      await new Promise<void>((r) => (finish = r))
      return update(id, patch)
    }
    const row = [...document.querySelectorAll<HTMLTableRowElement>('[data-testid="txn-table"] tbody tr')].find((r) =>
      r.textContent?.includes('Swiggy dinner'),
    )!
    const amount = row.querySelectorAll('td')[4]!
    amount.click()
    await settle()
    const editor = amount.querySelector('input')!
    editor.value = '999'
    editor.dispatchEvent(new Event('input', { bubbles: true }))
    await press(editor, 'Enter')
    const saving = document.querySelector('[data-testid="txn-table"] tbody tr.row-saving')!
    expect(saving).not.toBeNull()
    expect(saving.className).not.toMatch(/opacity/)
    expect(saving.querySelector('[data-testid="row-saving"]')!.textContent).toBe('Saving…')
    finish()
    await settle()
    expect(document.querySelector('tr.row-saving')).toBeNull()
    expect(repo.updates.at(-1)).toEqual({ id: 't2', patch: { amountPaise: 99900 } })
  })

  it('Add grid: cells not used by the row are grey, not faded, and the grid is its own scroller', async () => {
    await mountApp({ path: '/add' })
    const typeCell = cell(0, 3)
    await type(typeCell, 'Transfer')
    typeCell.blur()
    await settle()
    const category = cell(0, 4)
    expect(category.disabled).toBe(true)
    expect(category.closest('td')!.className).toContain('cell-na')
    expect(category.closest('[data-combo]')!.className).not.toMatch(/opacity/)
    expect(category.className).toContain('disabled:text-slate-600')
    expect(category.className).toContain('disabled:placeholder:text-slate-600')
    expect(cell(0, 6).closest('td')!.className).not.toContain('cell-na') // To account: used by a transfer

    const scroller = byTestId('grid-scroller')!
    expect(scroller.className).toContain('overflow-auto')
    expect(scroller.className).not.toContain('overflow-x-auto')
    expect(scroller.querySelector('table.entry-grid thead th')).not.toBeNull()
  })

  it('Import preview: rows already saved are slate-600 on grey', async () => {
    const { readFileSync } = await import('node:fs')
    const { resolve } = await import('node:path')
    const preview = readFileSync(resolve(process.cwd(), 'src/components/import/RowsPreview.vue'), 'utf8')
    expect(preview).toContain("'bg-slate-50 text-slate-600'")
    expect(preview).not.toContain('text-slate-500')
  })
})

// ============================================================================
// PRD-3: Expenses / Income / Transfers filter on Transactions
// ============================================================================

describe('PRD-3: the type filter', () => {
  function repoWithTypes() {
    const repo = new FakeRepository()
    repo.txns = [
      makeTxn('t1', { date: '2026-09-24', description: 'Swiggy dinner', amountPaise: 45000 }),
      makeTxn('t2', { date: '2026-09-01', description: 'Salary September', amountPaise: 8500000, type: 'income', categoryId: 'cat-salary', accountId: 'acc-bank' }),
      makeTxn('t3', { date: '2026-09-21', description: 'ATM withdrawal', amountPaise: 200000, type: 'transfer', accountId: 'acc-bank', toAccountId: 'acc-cash', categoryId: null }),
      makeTxn('t4', { date: '2026-07-01', description: 'Salary July', amountPaise: 8500000, type: 'income', categoryId: 'cat-salary', accountId: 'acc-bank' }),
    ]
    return repo
  }
  const shown = () => [...document.querySelectorAll('[data-testid="txn-table"] tbody tr')].map((tr) => tr.textContent ?? '')

  it('from the URL; picking one writes it back; Clear filters removes it', async () => {
    const { router } = await mountApp({ path: '/transactions?month=2026-09&type=income', repo: repoWithTypes() })
    expect(shown()).toHaveLength(1)
    expect(shown()[0]).toContain('Salary September')
    expect(byTestId('type-filter')!.textContent).toContain('Income')
    expect(byTestId('row-count')!.textContent).toContain('Showing 1 of 3')

    await router.push({ path: '/transactions', query: { month: '2026-09', type: 'transfer' } })
    await settle()
    expect(shown().map((t) => t.includes('ATM withdrawal'))).toEqual([true])

    await click([...document.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Clear filters'))
    expect(shown()).toHaveLength(3)
    expect(router.currentRoute.value.query).toEqual({ month: '2026-09' })
  })

  it('choosing from the list', async () => {
    const { router } = await mountApp({ path: '/transactions?month=2026-09', repo: repoWithTypes() })
    await click(byTestId('type-filter'))
    const option = [...document.querySelectorAll('[role="option"]')].find((o) => o.textContent?.trim() === 'Expenses')!
    // PrimeVue picks an option on mousedown.
    option.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }))
    await settle()
    expect(router.currentRoute.value.query).toEqual({ month: '2026-09', type: 'expense' })
    expect(shown().map((t) => t.includes('Swiggy dinner'))).toEqual([true])
  })

  it('an unknown type is ignored', async () => {
    await mountApp({ path: '/transactions?month=2026-09&type=refund', repo: repoWithTypes() })
    expect(shown()).toHaveLength(3)
  })

  it('works with All months, and export takes what is shown', async () => {
    const repo = repoWithTypes()
    await mountApp({ path: '/transactions?month=2026-09&type=income', repo })
    await click(byTestId('all-months'))
    // A type alone is enough to search every month.
    expect(shown().map((t) => t.match(/Salary (September|July)/)?.[0])).toEqual(['Salary September', 'Salary July'])
    await click(byTestId('open-export'))
    expect(byTestId('export-ranges')!.textContent).toContain('All months, filtered as on screen · 2 transactions')
  })

  it('export of a month with a type filter keeps just those rows', async () => {
    const repo = repoWithTypes()
    await mountApp({ path: '/transactions?month=2026-09&type=expense', repo })
    await click(byTestId('open-export'))
    expect(byTestId('export-ranges')!.textContent).toContain('September 2026, filtered as on screen · 1 transaction')
  })
})
