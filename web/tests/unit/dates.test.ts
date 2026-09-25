import { describe, expect, it } from 'vitest'
import {
  addDays,
  formatDateIndian,
  indiaToday,
  monthKey,
  monthLabel,
  nextMonth,
  parseDateInput,
  parseMonthKey,
  previousMonth,
} from '@/lib/dates'

const TODAY = '2026-09-25'
const parse = (s: string, today = TODAY) => parseDateInput(s, today)
const iso = (s: string, today = TODAY) => {
  const r = parseDateInput(s, today, { allowExcelSerial: true })
  return r?.ok ? r.iso : r
}

describe('indiaToday (Asia/Kolkata, whatever the computer is set to)', () => {
  it('00:30 IST is already the next day even though UTC is still yesterday', () => {
    expect(indiaToday(() => new Date('2026-09-24T19:00:00Z'))).toBe('2026-09-25')
  })

  it('23:59 IST is still today', () => {
    expect(indiaToday(() => new Date('2026-09-25T18:29:59Z'))).toBe('2026-09-25')
  })

  it('crosses month and year ends', () => {
    expect(indiaToday(() => new Date('2026-12-31T18:30:00Z'))).toBe('2027-01-01')
  })
})

describe('parseDateInput: Indian day/month/year', () => {
  it('dd/mm/yyyy and its separators', () => {
    expect(iso('25/09/2026')).toBe('2026-09-25')
    expect(iso('25-09-2026')).toBe('2026-09-25')
    expect(iso('25.09.2026')).toBe('2026-09-25')
    expect(iso('5/9/2026')).toBe('2026-09-05')
  })

  it('day always comes first (05/09 is 5 September, not 9 May)', () => {
    expect(iso('05/09/2026')).toBe('2026-09-05')
    expect(iso('01/02/2026')).toBe('2026-02-01')
  })

  it('two-digit years', () => {
    expect(iso('25/09/26')).toBe('2026-09-25')
    expect(iso('01/01/99')).toBe('1999-01-01')
  })

  it('day and month only: the latest such date that is not in the future', () => {
    expect(iso('20/09')).toBe('2026-09-20')
    expect(iso('28/12')).toBe('2025-12-28')
  })

  it('month names, as Excel shows them', () => {
    expect(iso('25-Sep-26')).toBe('2026-09-25')
    expect(iso('25 Sep 2026')).toBe('2026-09-25')
    expect(iso('25 September 2026')).toBe('2026-09-25')
    expect(iso('5th Sept 2026')).toBe('2026-09-05')
    expect(iso('Sep 25, 2026')).toBe('2026-09-25')
    expect(iso('3 Jan')).toBe('2026-01-03')
  })

  it('ISO dates and date-times copied with a time', () => {
    expect(iso('2026-09-25')).toBe('2026-09-25')
    expect(iso('25/09/2026 14:30')).toBe('2026-09-25')
    expect(iso('25/09/2026 2:30 PM')).toBe('2026-09-25')
  })

  it('today / yesterday shortcuts', () => {
    expect(iso('today')).toBe('2026-09-25')
    expect(iso('Yesterday')).toBe('2026-09-24')
  })

  it('Excel day numbers (a date cell formatted as General)', () => {
    expect(iso('46290')).toBe('2026-09-25')
    expect(parse('46290')?.ok).toBe(false) // only when asked for
  })

  it('rejects impossible and out-of-range dates', () => {
    expect(parse('31/02/2026')).toEqual({ ok: false, error: '"31/02/2026" is not a real date' })
    expect(parse('29/02/2025')?.ok).toBe(false)
    expect(iso('29/02/2024')).toBe('2024-02-29')
    expect(parse('01/01/1989')).toEqual({ ok: false, error: 'Dates must be between 1990 and 2099' })
    expect(parse('hello')?.ok).toBe(false)
  })

  it('explains US-style month/day instead of guessing', () => {
    const r = parse('09/25/2026')
    expect(r?.ok).toBe(false)
    expect(r && !r.ok && r.error).toContain('looks like month/day')
  })

  it('empty is "no date", not an error', () => {
    expect(parse('  ')).toBeNull()
  })
})

describe('formatting', () => {
  it('dd/mm/yyyy', () => {
    expect(formatDateIndian('2026-09-05')).toBe('05/09/2026')
  })

  it('addDays across month ends', () => {
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28')
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
  })
})

describe('months', () => {
  it('next / previous across years', () => {
    expect(nextMonth({ year: 2026, month: 12 })).toEqual({ year: 2027, month: 1 })
    expect(previousMonth({ year: 2026, month: 1 })).toEqual({ year: 2025, month: 12 })
  })

  it('labels and URL keys', () => {
    expect(monthLabel({ year: 2026, month: 9 })).toBe('September 2026')
    expect(monthKey({ year: 2026, month: 9 })).toBe('2026-09')
    expect(parseMonthKey('2026-09')).toEqual({ year: 2026, month: 9 })
    expect(parseMonthKey('2026-13')).toBeNull()
    expect(parseMonthKey(['2026-09'])).toBeNull()
  })
})
