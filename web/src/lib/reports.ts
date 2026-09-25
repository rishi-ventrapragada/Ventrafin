// Shaping the report rows for tables and charts. The totals themselves come
// from Postgres; this only groups them for drawing, by the same rules as the
// phone (mobile/lib/features/reports/report_data.dart).
import { UNCATEGORIZED_LOOK } from './categoryStyle'
import { compareMonths, previousMonth, type YearMonth } from './dates'
import type { Category, MonthlyCategoryTotal, MonthlyTotal } from './models'

/** The `count` months ending with `to`, oldest first. */
export function monthsEnding(to: YearMonth, count: number): YearMonth[] {
  const out = [to]
  while (out.length < count) out.unshift(previousMonth(out[0]!))
  return out
}

const sameMonth = (a: YearMonth, b: YearMonth) => compareMonths(a, b) === 0

/** Monthly totals for exactly `months`, with zeros where a month is missing. */
export function totalsFor(months: readonly YearMonth[], rows: readonly MonthlyTotal[]): MonthlyTotal[] {
  return months.map(
    (m) =>
      rows.find((r) => sameMonth(r.month, m)) ?? {
        month: m,
        expensePaise: 0,
        incomePaise: 0,
        expenseCount: 0,
        incomeCount: 0,
        uncategorizedCount: 0,
      },
  )
}

/** Share of income not spent, whole percent; null without income. */
export function savedPercent(incomePaise: number, expensePaise: number): number | null {
  return incomePaise > 0 ? Math.round(((incomePaise - expensePaise) * 100) / incomePaise) : null
}

/** How many categories get their own colour in the trend chart; the rest fold into "Other". */
export const TREND_TOP_CATEGORIES = 5

/**
 * "Other" in the trend: a neutral grey that is not in the category palette,
 * dark enough (3:1 or more) to show on every surface in every theme. Same as the phone.
 */
export const OTHER_SERIES_COLOR = '#7F8C93'

/** Months the Reports trends can cover. */
export const TREND_SPANS = [6, 12] as const
export type TrendSpan = (typeof TREND_SPANS)[number]

/** `?span=` from the URL: 12, or the default 6 for anything else. */
export function spanFromQuery(value: unknown): TrendSpan {
  return value === '12' ? 12 : 6
}

/** The caption under the Reports month summary (same words as the phone). */
export const SUMMARY_CAPTION = 'Net = income minus spending. Saved = the part of income not spent, as a percentage.'

export interface TrendSeries {
  /** Category id, `uncategorized` or `other`. */
  key: string
  name: string
  color: string
  category: Category | null
  /** Paise per month, in the order of `months`. */
  perMonth: number[]
  total: number
}

export interface CategoryTrend {
  months: YearMonth[]
  /** For the chart: the top TREND_TOP_CATEGORIES over the range, then "Other". Largest first. */
  series: TrendSeries[]
  /** For the table: every category with spending in the range, largest first. */
  rows: TrendSeries[]
  monthTotals: number[]
}

/** Expense totals per category per month, for the trend chart and the pivot table. */
export function buildCategoryTrend(
  totals: readonly MonthlyCategoryTotal[],
  months: readonly YearMonth[],
  categoriesById: ReadonlyMap<string, Category>,
): CategoryTrend {
  const byKey = new Map<string, { meta: MonthlyCategoryTotal; perMonth: number[] }>()
  for (const t of totals) {
    if (t.kind !== 'expense') continue
    const i = months.findIndex((m) => sameMonth(m, t.month))
    if (i < 0) continue
    const key = t.categoryId ?? 'uncategorized'
    const entry = byKey.get(key) ?? { meta: t, perMonth: months.map(() => 0) }
    entry.perMonth[i]! += t.totalPaise
    byKey.set(key, entry)
  }
  const rows: TrendSeries[] = [...byKey.entries()]
    .map(([key, { meta, perMonth }]) => {
      const c = meta.categoryId ? (categoriesById.get(meta.categoryId) ?? null) : null
      return {
        key,
        name: meta.categoryId ? (c?.name ?? meta.categoryName) : 'Uncategorized',
        color: meta.categoryId ? (c?.color ?? meta.color) : UNCATEGORIZED_LOOK.color,
        category: c,
        perMonth,
        total: perMonth.reduce((s, v) => s + v, 0),
      }
    })
    .sort((a, b) => b.total - a.total || a.name.localeCompare(b.name, 'en-IN', { sensitivity: 'base' }))

  const top = rows.slice(0, TREND_TOP_CATEGORIES)
  const rest = rows.slice(TREND_TOP_CATEGORIES)
  const series = [...top]
  if (rest.length > 0) {
    const perMonth = months.map((_, i) => rest.reduce((s, r) => s + r.perMonth[i]!, 0))
    series.push({
      key: 'other',
      name: `Other (${rest.length})`,
      color: OTHER_SERIES_COLOR,
      category: null,
      perMonth,
      total: perMonth.reduce((s, v) => s + v, 0),
    })
  }
  return {
    months: [...months],
    series,
    rows,
    monthTotals: months.map((_, i) => rows.reduce((s, r) => s + r.perMonth[i]!, 0)),
  }
}

/** Short axis labels: `₹950`, `₹9.5k`, `₹12k`, `₹1.2L`, `₹3.4Cr` (same as the phone). */
export function formatRupeesAxis(paise: number): string {
  const rupees = Math.trunc(paise / 100)
  const sign = rupees < 0 ? '-' : ''
  const r = Math.abs(rupees)
  const one = (v: number) => {
    const s = v.toFixed(v < 10 ? 1 : 0)
    return s.endsWith('.0') ? s.slice(0, -2) : s
  }
  if (r < 1000) return `${sign}₹${r}`
  if (r < 100000) return `${sign}₹${one(r / 1000)}k`
  if (r < 10000000) return `${sign}₹${one(r / 100000)}L`
  return `${sign}₹${one(r / 10000000)}Cr`
}

/** A round gridline step for about `lines` lines up to `maxPaise` (1, 2 or 5 × a power of ten rupees). */
export function niceAxisStep(maxPaise: number, lines = 4): number {
  const raw = maxPaise / lines
  if (raw <= 100) return 100
  let magnitude = 100
  while (magnitude * 10 <= raw) magnitude *= 10
  for (const m of [1, 2, 5, 10]) if (magnitude * m >= raw) return magnitude * m
  return magnitude * 10
}
