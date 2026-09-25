// Reports, Bills and Settings (theme) pages on the fake repository.
import { describe, expect, it } from 'vitest'
import type { Bill } from '@/lib/models'
import { FakeRepository } from '../support/fakeRepository'
import { buttonByText, byTestId, confirmButton, mountApp, settle } from '../support/mountApp'

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

describe('Reports', () => {
  function repoWithReports() {
    const repo = new FakeRepository()
    repo.totals = { expensePaise: 3000000, lastExpensePaise: 2500000, incomePaise: 6000000, lastIncomePaise: 6000000, uncategorizedCount: 1 }
    repo.comparison = [
      { kind: 'expense', categoryId: 'cat-food', categoryName: 'Food', color: '#FB8C00', thisMonthPaise: 2000000, lastMonthPaise: 1000000 },
      { kind: 'expense', categoryId: null, categoryName: 'Uncategorized', color: '#9E9E9E', thisMonthPaise: 1000000, lastMonthPaise: 1500000 },
      { kind: 'income', categoryId: 'cat-salary', categoryName: 'Salary', color: '#2E7D32', thisMonthPaise: 6000000, lastMonthPaise: 6000000 },
    ]
    repo.monthlyTotals = [4, 5, 6, 7, 8, 9].map((m) => ({
      month: { year: 2026, month: m },
      expensePaise: m * 100000,
      incomePaise: 6000000,
      expenseCount: 3,
      incomeCount: 1,
      uncategorizedCount: 0,
    }))
    repo.monthlyCategoryTotals = [
      { month: { year: 2026, month: 8 }, kind: 'expense', categoryId: 'cat-food', categoryName: 'Food', color: '#FB8C00', count: 4, totalPaise: 1000000 },
      { month: { year: 2026, month: 9 }, kind: 'expense', categoryId: 'cat-food', categoryName: 'Food', color: '#FB8C00', count: 6, totalPaise: 2000000 },
      { month: { year: 2026, month: 9 }, kind: 'expense', categoryId: null, categoryName: 'Uncategorized', color: '#9E9E9E', count: 1, totalPaise: 1000000 },
    ]
    return repo
  }

  it('the chosen month, its categories, and both trends with their tables', async () => {
    const { repo } = await mountApp({ path: '/reports', repo: repoWithReports() })
    expect(repo.monthlyRanges.at(-1)).toEqual({ from: { year: 2026, month: 4 }, to: { year: 2026, month: 9 } })
    expect(byTestId('report-month-summary')?.textContent).toContain('September 2026')
    expect(byTestId('saved-now')?.textContent).toContain('50%')
    const food = document.querySelector('[data-report-row="expense-cat-food"]')!
    expect(food.textContent).toContain('₹20,000')
    expect(food.textContent).toContain('67%')
    expect(food.textContent).toContain('6') // entries
    expect(document.querySelector('[data-report-row="expense-uncategorized"]')).not.toBeNull()
    expect(document.querySelector('[data-report-row="income-cat-salary"]')).not.toBeNull()
    // Trends: two charts (SVG with an accessible summary) and their tables.
    expect(document.querySelectorAll('[data-testid="report-income-vs-spending"] svg[role="img"]')).toHaveLength(1)
    expect(document.querySelectorAll('[data-testid="income-vs-spending-table"] tbody tr')).toHaveLength(7) // 6 months + total
    const pivot = byTestId('category-pivot')!
    expect(pivot.querySelectorAll('thead th')).toHaveLength(1 + 6 + 2)
    expect(pivot.textContent).toContain('Food')
    expect(pivot.textContent).toContain('₹30,000') // Food over the range
    expect(byTestId('trend-legend')?.textContent).toContain('Uncategorized')
  })

  it('12 months fetches a longer range; a past month moves every section', async () => {
    const { repo } = await mountApp({ path: '/reports', repo: repoWithReports() })
    await click(byTestId('span-12'))
    expect(repo.monthlyRanges.at(-1)).toEqual({ from: { year: 2025, month: 10 }, to: { year: 2026, month: 9 } })
    await click(document.querySelector('[aria-label="Previous month"]'))
    expect(byTestId('report-month-summary')?.textContent).toContain('August 2026')
    expect(repo.monthlyRanges.at(-1)).toEqual({ from: { year: 2025, month: 9 }, to: { year: 2026, month: 8 } })
  })

  it('hovering a month shows its values', async () => {
    await mountApp({ path: '/reports', repo: repoWithReports() })
    const col = document.querySelector('[data-testid="report-income-vs-spending"] [data-month-col="5"]')!
    col.dispatchEvent(new MouseEvent('mouseenter'))
    await settle()
    const tip = document.querySelector('[data-testid="report-income-vs-spending"] [role="tooltip"]')!
    expect(tip.textContent).toContain('September 2026')
    expect(tip.textContent).toContain('₹60,000')
  })
})

describe('Bills', () => {
  it('table with status, amounts, account and reminder; overdue in its own tile', async () => {
    const repo = new FakeRepository()
    repo.bills = [
      bill({ id: 'b-over', name: 'Home loan', kind: 'emi', status: 'overdue', daysUntil: -4, categoryId: null, amountPaise: 2500000 }),
      bill(),
    ]
    await mountApp({ path: '/bills', repo })
    const rows = document.querySelectorAll('[data-testid="bills-table"] tbody tr')
    expect(rows).toHaveLength(2)
    expect(rows[0]!.getAttribute('data-status')).toBe('overdue')
    expect(rows[0]!.textContent).toContain('Overdue · 4 days')
    expect(rows[1]!.textContent).toContain('Due in 3 days')
    expect(rows[1]!.textContent).toContain('Bank')
    expect(byTestId('overdue-total')?.textContent).toContain('₹25,000')
    expect(byTestId('reminder-note')?.textContent).toContain('3 days before')
  })

  it('mark paid: logs the payment with the chosen amount and method, once, with a client id', async () => {
    const repo = new FakeRepository()
    repo.bills = [bill()]
    await mountApp({ path: '/bills', repo })
    await click(byTestId('pay-bill-1'))
    expect(document.body.textContent).toContain('Mark BESCOM paid for September 2026')
    await type(byTestId<HTMLInputElement>('paid-amount'), '1,512.50')
    await click(byTestId('paid-method-card'))
    await click(byTestId('paid-confirm'))
    const call = repo.paidCalls[0]!
    expect(repo.paidCalls).toHaveLength(1)
    expect(call.month).toEqual({ year: 2026, month: 9 })
    expect(call.txnId).toMatch(/^[0-9a-f-]{36}$/)
    expect(call.amountPaise).toBe(151250)
    expect(call.paymentMethod).toBe('card')
    expect(call.paidOn).toBe('2026-09-25')
  })

  it('mark paid without logging sends no transaction', async () => {
    const repo = new FakeRepository()
    repo.bills = [bill()]
    await mountApp({ path: '/bills', repo })
    await click(byTestId('pay-bill-1'))
    await click(byTestId('paid-log'))
    await click(byTestId('paid-confirm'))
    expect(repo.paidCalls[0]!.txnId).toBeNull()
  })

  it('add a bill: validated first, then saved', async () => {
    const repo = new FakeRepository()
    await mountApp({ path: '/bills', repo })
    expect(byTestId('bills-empty')).not.toBeNull()
    await click(byTestId('add-bill'))
    await click(byTestId('bill-save'))
    expect(repo.billInserts).toHaveLength(0)
    expect(document.body.textContent).toContain('Enter a name')
    await type(byTestId<HTMLInputElement>('bill-name'), ' Home loan ')
    await click(byTestId('bill-kind-emi'))
    await type(byTestId<HTMLInputElement>('bill-amount'), '25000')
    await click(byTestId('bill-save'))
    expect(repo.billInserts).toHaveLength(1)
    expect(repo.billInserts[0]!.draft).toEqual({
      name: ' Home loan ',
      kind: 'emi',
      amountPaise: 2500000,
      dueDay: 10,
      accountId: 'acc-bank',
      categoryId: null,
      reminderEnabled: true,
    })
  })

  it('the bell toggles the reminder; "Mark unpaid" moves the paid month back after confirming', async () => {
    const repo = new FakeRepository()
    repo.bills = [bill()]
    await mountApp({ path: '/bills', repo })
    await click(byTestId('reminder-bill-1'))
    expect(repo.reminderToggles).toEqual([{ id: 'bill-1', enabled: false }])
    expect(byTestId('unpay-bill-1')?.textContent?.trim()).toBe('Mark unpaid')
    await click(byTestId('unpay-bill-1'))
    expect(document.body.textContent).toContain('Mark August 2026 unpaid?')
    expect(document.activeElement).toBe(confirmButton('reject')) // Cancel, so Enter changes nothing
    await click(confirmButton('accept'))
    expect(repo.paidThroughSets).toEqual([{ id: 'bill-1', month: { year: 2026, month: 7 } }])
    // It only marks the month unpaid: nothing is deleted from Transactions.
    expect(repo.deletes).toHaveLength(0)
    expect(document.body.textContent).toContain('Marked August 2026 unpaid for BESCOM')
  })

  it('offline: nothing is sent', async () => {
    const repo = new FakeRepository()
    repo.bills = [bill()]
    await mountApp({ path: '/bills', repo, online: false })
    await click(byTestId('pay-bill-1'))
    await click(byTestId('paid-confirm'))
    expect(repo.paidCalls).toHaveLength(0)
    expect(document.body.textContent).toContain('Not marked paid')
  })
})

describe('Settings: theme', () => {
  it('picking a theme applies it at once and saves it to the profile', async () => {
    const { repo } = await mountApp({ path: '/settings' })
    expect(document.querySelector('[data-theme-option="ocean"]')?.getAttribute('aria-checked')).toBe('true')
    await click(document.querySelector('[data-theme-option="forest"]'))
    expect(repo.themeUpdates).toEqual(['forest'])
    expect(document.documentElement.dataset.theme).toBe('forest')
    expect(document.documentElement.style.getPropertyValue('--vf-brand')).toBe('#1B5E20')
    expect(document.querySelector('[data-theme-option="forest"]')?.getAttribute('aria-checked')).toBe('true')
  })

  it('a failed save goes back to the previous theme and says so', async () => {
    const repo = new FakeRepository()
    repo.failNextThemeUpdateWith = new Error('boom')
    await mountApp({ path: '/settings', repo })
    await click(document.querySelector('[data-theme-option="garden"]'))
    expect(document.documentElement.dataset.theme).toBe('ocean')
    expect(document.body.textContent).toContain('Theme not saved')
  })

  it('a theme changed on the phone arrives via Realtime', async () => {
    const repo = new FakeRepository()
    await mountApp({ path: '/dashboard', repo, realtime: true })
    repo.profile = { ...repo.profile, theme: 'marigold' }
    repo.emit({ table: 'profiles' })
    await new Promise((r) => setTimeout(r, 350)) // Realtime debounce
    await settle()
    expect(document.documentElement.dataset.theme).toBe('marigold')
  })

  it('shows the phone reminder settings read-only', async () => {
    await mountApp({ path: '/settings' })
    const summary = byTestId('reminders-summary')!.textContent!
    expect(summary).toContain('on, at 8:30 pm')
    expect(summary).toContain('3 days before and on the due date')
  })
})
