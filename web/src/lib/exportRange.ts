// Which transactions a CSV export covers, and what the file is called.
// The CSV itself comes from Postgres (export_transactions_csv), so the phone
// and the web save identical files; the phone has the same presets
// (mobile/lib/features/settings/export_range.dart).
import { addDays, formatDateIndian, isoParts, monthOf, monthStart, nextMonth, previousMonth } from './dates'

/** Inclusive `yyyy-mm-dd` dates; null = no limit on that side. */
export interface DateRange {
  from: string | null
  to: string | null
}

export type RangePreset = 'thisMonth' | 'lastMonth' | 'thisFy' | 'lastFy' | 'all' | 'custom'

export const RANGE_PRESETS: readonly { value: RangePreset; label: string }[] = [
  { value: 'thisMonth', label: 'This month' },
  { value: 'lastMonth', label: 'Last month' },
  { value: 'thisFy', label: 'This financial year' },
  { value: 'lastFy', label: 'Last financial year' },
  { value: 'all', label: 'All time' },
  { value: 'custom', label: 'Choose dates' },
]

/** 1 April of the Indian financial year that `today` falls in. */
export function financialYearStart(today: string): string {
  const { year, month } = isoParts(today)
  return `${month >= 4 ? year : year - 1}-04-01`
}

/** `FY 2026-27` for the year starting 1 Apr 2026. */
export function financialYearLabel(start: string): string {
  const year = isoParts(start).year
  return `FY ${year}-${String((year + 1) % 100).padStart(2, '0')}`
}

/** The dates a preset covers (null for `custom`: the caller supplies them). */
export function presetRange(preset: RangePreset, today: string): DateRange | null {
  const month = monthOf(today)
  switch (preset) {
    case 'thisMonth':
      return { from: monthStart(month), to: addDays(monthStart(nextMonth(month)), -1) }
    case 'lastMonth':
      return { from: monthStart(previousMonth(month)), to: addDays(monthStart(month), -1) }
    case 'thisFy': {
      const start = financialYearStart(today)
      return { from: start, to: `${isoParts(start).year + 1}-03-31` }
    }
    case 'lastFy': {
      const start = `${isoParts(financialYearStart(today)).year - 1}-04-01`
      return { from: start, to: `${isoParts(start).year + 1}-03-31` }
    }
    case 'all':
      return { from: null, to: null }
    case 'custom':
      return null
  }
}

/** `1/4/2026 to 31/3/2027`, `All dates`, `From 1/4/2026`. */
export function rangeLabel(r: DateRange): string {
  if (r.from && r.to) return `${formatDateIndian(r.from)} to ${formatDateIndian(r.to)}`
  if (r.from) return `From ${formatDateIndian(r.from)}`
  if (r.to) return `Up to ${formatDateIndian(r.to)}`
  return 'All dates'
}

/** Why a chosen range can't be exported, or null. */
export function rangeProblem(r: DateRange): string | null {
  if (r.from && r.to && r.from > r.to) return 'The start date is after the end date.'
  return null
}

/**
 * `ventrafin-transactions-2026-04-01-to-2027-03-31.csv`,
 * `ventrafin-transactions-all-2026-09-25.csv`, `…-filtered.csv` for a filtered view.
 */
export function exportFileName(r: DateRange, today: string, { filtered = false } = {}): string {
  const part = r.from || r.to ? `${r.from ?? 'start'}-to-${r.to ?? today}` : `all-${today}`
  return `ventrafin-transactions-${part}${filtered ? '-filtered' : ''}.csv`
}
