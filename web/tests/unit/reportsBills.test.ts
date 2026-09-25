// Report shaping and bill wording: the same rules as the phone
// (report_data.dart, bill_visuals.dart, reminder_plan_test.dart vectors).
import { describe, expect, it } from 'vitest'
import { billNameError, billStatusLabel, defaultMethodFor, dueDayLabel } from '@/lib/bills'
import type { MonthlyCategoryTotal } from '@/lib/models'
import { formatTimeOfDay } from '@/lib/models'
import {
  OTHER_SERIES_COLOR,
  buildCategoryTrend,
  formatRupeesAxis,
  monthsEnding,
  niceAxisStep,
  percentChange,
  savedPercent,
  totalsFor,
} from '@/lib/reports'

const ct = (month: number, id: string | null, name: string, paise: number, kind: 'expense' | 'income' = 'expense'): MonthlyCategoryTotal => ({
  month: { year: 2026, month },
  kind,
  categoryId: id,
  categoryName: name,
  color: '#FB8C00',
  count: 2,
  totalPaise: paise,
})

describe('reports', () => {
  it('months ending with the chosen one, across a year boundary', () => {
    expect(monthsEnding({ year: 2026, month: 2 }, 4)).toEqual([
      { year: 2025, month: 11 },
      { year: 2025, month: 12 },
      { year: 2026, month: 1 },
      { year: 2026, month: 2 },
    ])
  })

  it('missing months are zeros', () => {
    const rows = totalsFor(monthsEnding({ year: 2026, month: 9 }, 2), [
      { month: { year: 2026, month: 9 }, expensePaise: 5, incomePaise: 9, expenseCount: 1, incomeCount: 1, uncategorizedCount: 0 },
    ])
    expect(rows.map((r) => r.expensePaise)).toEqual([0, 5])
  })

  it('trend: top 5 categories keep their colour, the rest fold into Other; income and other months ignored', () => {
    const months = monthsEnding({ year: 2026, month: 9 }, 3)
    const trend = buildCategoryTrend(
      [
        ...Array.from({ length: 7 }, (_, i) => ct(9, `c${i}`, `Cat ${i}`, (i + 1) * 1000)),
        ct(7, null, 'Uncategorized', 500),
        ct(3, 'c0', 'Cat 0', 99999),
        ct(9, 'sal', 'Salary', 5000000, 'income'),
      ],
      months,
      new Map(),
    )
    expect(trend.rows.map((r) => r.name).slice(0, 2)).toEqual(['Cat 6', 'Cat 5'])
    expect(trend.rows).toHaveLength(8)
    expect(trend.series).toHaveLength(6)
    const other = trend.series.at(-1)!
    expect(other.name).toBe('Other (3)')
    expect(other.color).toBe(OTHER_SERIES_COLOR)
    expect(other.perMonth).toEqual([500, 0, 3000])
    expect(trend.monthTotals.at(-1)).toBe(28000)
  })

  it('axis labels and steps match the phone', () => {
    expect(formatRupeesAxis(95000)).toBe('₹950')
    expect(formatRupeesAxis(950000)).toBe('₹9.5k')
    expect(formatRupeesAxis(1200000)).toBe('₹12k')
    expect(formatRupeesAxis(12000000)).toBe('₹1.2L')
    expect(formatRupeesAxis(3400000000)).toBe('₹3.4Cr')
    expect(niceAxisStep(0)).toBe(100)
    expect(niceAxisStep(4_000_000)).toBe(1_000_000)
    expect(niceAxisStep(4_500_000)).toBe(2_000_000)
  })

  it('percentages', () => {
    expect(savedPercent(10000, 2500)).toBe(75)
    expect(savedPercent(0, 2500)).toBeNull()
    expect(percentChange(150, 100)).toBe(50)
    expect(percentChange(5, 0)).toBeNull()
  })
})

describe('bills', () => {
  const base = { nextDueDate: '2026-10-10', overdueCount: 0 }
  it('status wording (same as the phone)', () => {
    expect(billStatusLabel({ ...base, status: 'overdue', daysUntil: -5 })).toBe('Overdue · 5 days')
    expect(billStatusLabel({ ...base, status: 'overdue', daysUntil: -1 })).toBe('Overdue · 1 day')
    expect(billStatusLabel({ ...base, status: 'overdue', daysUntil: -40, overdueCount: 2 })).toBe('Overdue · 2 months')
    expect(billStatusLabel({ ...base, status: 'due_today', daysUntil: 0 })).toBe('Due today')
    expect(billStatusLabel({ ...base, status: 'due_soon', daysUntil: 1 })).toBe('Due tomorrow')
    expect(billStatusLabel({ ...base, status: 'due_soon', daysUntil: 3 })).toBe('Due in 3 days')
    expect(billStatusLabel({ ...base, status: 'upcoming', daysUntil: 15 })).toBe('Due 10 Oct')
  })

  it('due day labels (same vectors as the phone)', () => {
    expect(dueDayLabel(1)).toBe('1st of every month')
    expect(dueDayLabel(2)).toBe('2nd of every month')
    expect(dueDayLabel(11)).toBe('11th of every month')
    expect(dueDayLabel(22)).toBe('22nd of every month')
    expect(dueDayLabel(31)).toBe('last day of every month')
  })

  it('payment method follows the account; names are checked', () => {
    expect(defaultMethodFor('cash')).toBe('cash')
    expect(defaultMethodFor('credit')).toBe('card')
    expect(defaultMethodFor('bank')).toBe('upi')
    expect(billNameError('  ')).toMatch(/Enter a name/)
    expect(billNameError('x'.repeat(61))).toMatch(/60 characters/)
    expect(billNameError('BESCOM')).toBeNull()
  })

  it('reminder time wording', () => {
    expect(formatTimeOfDay('20:30')).toBe('8:30 pm')
    expect(formatTimeOfDay('00:05')).toBe('12:05 am')
    expect(formatTimeOfDay('12:00')).toBe('12:00 pm')
  })
})
