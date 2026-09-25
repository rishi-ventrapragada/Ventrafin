// Dates. Asia/Kolkata is the app's single timezone (ARCHITECTURE.md § 1);
// India has no daylight saving, so a fixed +05:30 offset is exact and
// matches the database's private.local_today(). Calendar dates travel as
// ISO strings (`yyyy-mm-dd`), the format of Postgres `date` columns, so no
// Date object (and no browser timezone) is involved in storing them.

export type Clock = () => Date
export const systemClock: Clock = () => new Date()

const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000

export const MONTH_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const
export const MONTH_LONG = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
] as const
const WEEKDAY_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const

/** The database accepts 1990-01-01 up to 2099-12-31 (`transactions_date_check`). */
export const MIN_YEAR = 1990
export const MAX_YEAR = 2099

const pad2 = (n: number) => String(n).padStart(2, '0')

export function isoDate(year: number, month: number, day: number): string {
  return `${String(year).padStart(4, '0')}-${pad2(month)}-${pad2(day)}`
}

export function isoParts(iso: string): { year: number; month: number; day: number } {
  const [y, m, d] = iso.split('-').map(Number)
  return { year: y!, month: m!, day: d! }
}

export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate()
}

export function isValidDate(year: number, month: number, day: number): boolean {
  return (
    Number.isInteger(year) && Number.isInteger(month) && Number.isInteger(day) &&
    month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth(year, month)
  )
}

/** Today's calendar date in India, whatever timezone the computer is set to. */
export function indiaToday(clock: Clock = systemClock): string {
  const ist = new Date(clock().getTime() + IST_OFFSET_MS)
  return isoDate(ist.getUTCFullYear(), ist.getUTCMonth() + 1, ist.getUTCDate())
}

export function addDays(iso: string, days: number): string {
  const { year, month, day } = isoParts(iso)
  const d = new Date(Date.UTC(year, month - 1, day + days))
  return isoDate(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate())
}

function weekday(iso: string): string {
  const { year, month, day } = isoParts(iso)
  return WEEKDAY_SHORT[new Date(Date.UTC(year, month - 1, day)).getUTCDay()]!
}

/** `25/09/2026`: how dates are typed and shown in the grids. */
export function formatDateIndian(iso: string): string {
  const { year, month, day } = isoParts(iso)
  return `${pad2(day)}/${pad2(month)}/${year}`
}

/** `25 Sep`. */
export function formatDayMonth(iso: string): string {
  const { month, day } = isoParts(iso)
  return `${day} ${MONTH_SHORT[month - 1]}`
}

/** `Thu, 24 Sep 2026`, or "Today, 25 Sep" / "Yesterday, 24 Sep" relative to India time. */
export function friendlyDate(iso: string, today: string): string {
  if (iso === today) return `Today, ${formatDayMonth(iso)}`
  if (iso === addDays(today, -1)) return `Yesterday, ${formatDayMonth(iso)}`
  const { year } = isoParts(iso)
  return `${weekday(iso)}, ${formatDayMonth(iso)} ${year}`
}

/** `Thu 24/09` for dense table cells. */
export function shortWeekday(iso: string): string {
  return weekday(iso)
}

// ---------------------------------------------------------------------------
// Parsing what people type or paste
// ---------------------------------------------------------------------------

export type DateParse = { ok: true; iso: string } | { ok: false; error: string }

const MONTH_BY_NAME: Record<string, number> = Object.fromEntries(
  MONTH_LONG.flatMap((name, i) => [
    [name.toLowerCase(), i + 1],
    [name.slice(0, 3).toLowerCase(), i + 1],
  ]).concat([['sept', 9]]),
)

function fullYear(y: string): number {
  if (y.length === 4) return Number(y)
  const n = Number(y)
  // Two-digit years: 90–99 are the 1990s, everything else this century.
  return n >= 90 ? 1900 + n : 2000 + n
}

function checked(year: number, month: number, day: number, source: string, note?: string): DateParse {
  if (!isValidDate(year, month, day)) {
    return { ok: false, error: note ?? `"${source}" is not a real date` }
  }
  if (year < MIN_YEAR || year > MAX_YEAR) {
    return { ok: false, error: `Dates must be between ${MIN_YEAR} and ${MAX_YEAR}` }
  }
  return { ok: true, iso: isoDate(year, month, day) }
}

/**
 * Parses a date the way an Indian Excel user writes it. Day comes before
 * month, always (`05/09/2026` is 5 September):
 *   25/09/2026, 25-09-2026, 25.09.2026, 25/9/26, 25/09 (this year, or last
 *   year if that would be in the future), 25 Sep 2026, 25-Sep-26, Sep 25 2026,
 *   2026-09-25 (ISO), "today", "yesterday", and, when `allowExcelSerial` is
 *   set, Excel day numbers such as 46290.
 * Returns null for empty input.
 */
export function parseDateInput(
  input: string,
  today: string,
  { allowExcelSerial = false }: { allowExcelSerial?: boolean } = {},
): DateParse | null {
  const s = input.trim().toLowerCase().replace(/\s+/g, ' ')
  if (!s) return null
  if (s === 'today' || s === 't') return { ok: true, iso: today }
  if (s === 'yesterday' || s === 'y') return { ok: true, iso: addDays(today, -1) }

  let m: RegExpExecArray | null

  // ISO: 2026-09-25 (also 2026/09/25)
  if ((m = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/.exec(s))) {
    return checked(Number(m[1]), Number(m[2]), Number(m[3]), input.trim())
  }

  // Day first: 25/09/2026, 25-9-26, 25.09.2026, optionally followed by a time
  if ((m = /^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})(?:[ t]\d{1,2}:\d{2}(?::\d{2})?(?: ?[ap]m)?)?$/.exec(s))) {
    const day = Number(m[1])
    const month = Number(m[2])
    const year = fullYear(m[3]!)
    if (month > 12 && day <= 12 && isValidDate(year, day, month)) {
      return {
        ok: false,
        error: `"${input.trim()}" looks like month/day. Ventrafin reads dates as day/month/year (${pad2(month)}/${pad2(day)}/${year}).`,
      }
    }
    return checked(year, month, day, input.trim())
  }

  // Day and month only: 25/09 -> the most recent 25 Sep that isn't in the future
  if ((m = /^(\d{1,2})[/.\-](\d{1,2})$/.exec(s))) {
    return dayMonthOnly(Number(m[1]), Number(m[2]), today, input.trim())
  }

  // 25 Sep 2026, 25-Sep-26, 25 September, 25th Sep 2026
  if ((m = /^(\d{1,2})(?:st|nd|rd|th)?[ \-/.]?([a-z]{3,9})\.?(?:[ \-/.,]+(\d{4}|\d{2}))?$/.exec(s))) {
    const month = MONTH_BY_NAME[m[2]!]
    if (!month) return { ok: false, error: `"${input.trim()}" is not a date Ventrafin understands` }
    if (!m[3]) return dayMonthOnly(Number(m[1]), month, today, input.trim())
    return checked(fullYear(m[3]), month, Number(m[1]), input.trim())
  }

  // Sep 25, 2026 / September 25 2026
  if ((m = /^([a-z]{3,9})\.? (\d{1,2})(?:st|nd|rd|th)?,? (\d{4})$/.exec(s))) {
    const month = MONTH_BY_NAME[m[1]!]
    if (!month) return { ok: false, error: `"${input.trim()}" is not a date Ventrafin understands` }
    return checked(Number(m[3]), month, Number(m[2]), input.trim())
  }

  if (allowExcelSerial && /^\d{5}$/.test(s)) {
    // An Excel day number (a date cell formatted as General). Excel counts
    // days from 30 Dec 1899; its 1900 leap-year bug only affects earlier dates.
    const d = new Date(Date.UTC(1899, 11, 30 + Number(s)))
    return checked(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate(), input.trim())
  }

  return { ok: false, error: `"${input.trim()}" is not a date. Use day/month/year, e.g. 25/09/2026` }
}

function dayMonthOnly(day: number, month: number, today: string, source: string): DateParse {
  const { year } = isoParts(today)
  const thisYear = checked(year, month, day, source)
  if (thisYear.ok && thisYear.iso > today) return checked(year - 1, month, day, source)
  return thisYear
}

// ---------------------------------------------------------------------------
// Months
// ---------------------------------------------------------------------------

/** A calendar month: the Transactions filter, and the reports' `p_month`. */
export interface YearMonth {
  readonly year: number
  readonly month: number
}

export function monthOf(iso: string): YearMonth {
  const { year, month } = isoParts(iso)
  return { year, month }
}

/** First day of the month, `yyyy-mm-01`. */
export function monthStart(m: YearMonth): string {
  return isoDate(m.year, m.month, 1)
}

export function nextMonth(m: YearMonth): YearMonth {
  return m.month === 12 ? { year: m.year + 1, month: 1 } : { year: m.year, month: m.month + 1 }
}

export function previousMonth(m: YearMonth): YearMonth {
  return m.month === 1 ? { year: m.year - 1, month: 12 } : { year: m.year, month: m.month - 1 }
}

export function compareMonths(a: YearMonth, b: YearMonth): number {
  return a.year !== b.year ? a.year - b.year : a.month - b.month
}

/** `September 2026`. */
export function monthLabel(m: YearMonth): string {
  return `${MONTH_LONG[m.month - 1]} ${m.year}`
}

/** `Sep 2026`. */
export function monthShortLabel(m: YearMonth): string {
  return `${MONTH_SHORT[m.month - 1]} ${m.year}`
}

/** `2026-09`, used in URLs. */
export function monthKey(m: YearMonth): string {
  return `${m.year}-${pad2(m.month)}`
}

export function parseMonthKey(key: unknown): YearMonth | null {
  if (typeof key !== 'string') return null
  const m = /^(\d{4})-(\d{2})$/.exec(key)
  if (!m) return null
  const year = Number(m[1])
  const month = Number(m[2])
  if (month < 1 || month > 12 || year < MIN_YEAR || year > MAX_YEAR) return null
  return { year, month }
}
