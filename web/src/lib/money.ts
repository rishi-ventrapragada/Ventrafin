// Money helpers. Amounts are ALWAYS integer paise in app state and in the
// database (CLAUDE.md); rupees exist only as display strings. No floats: the
// database caps amounts below 10^15 paise, which is inside JavaScript's
// safe-integer range, so plain numbers hold every value exactly.
// Mirrors mobile/lib/core/money.dart.

/** Exclusive upper bound enforced by the database (`amount_paise < 10^15`). */
export const MAX_PAISE_EXCLUSIVE = 1_000_000_000_000_000

/** Most whole-rupee digits that can stay below MAX_PAISE_EXCLUSIVE. */
export const MAX_RUPEE_DIGITS = 13

/** Indian grouping of a string of digits: last 3, then groups of 2. `1234567` -> `12,34,567`. */
export function groupIndian(digits: string): string {
  if (digits.length <= 3) return digits
  const last3 = digits.slice(-3)
  let rest = digits.slice(0, -3)
  const groups: string[] = []
  while (rest.length > 2) {
    groups.unshift(rest.slice(-2))
    rest = rest.slice(0, -2)
  }
  if (rest) groups.unshift(rest)
  return `${groups.join(',')},${last3}`
}

function splitPaise(paise: number): { negative: boolean; rupees: string; fraction: string } {
  if (!Number.isSafeInteger(paise)) throw new RangeError(`Not an integer paise amount: ${paise}`)
  const abs = Math.abs(paise)
  return {
    negative: paise < 0,
    rupees: String(Math.floor(abs / 100)),
    fraction: String(abs % 100).padStart(2, '0'),
  }
}

/** `12345600` -> `₹1,23,456.00`, `-5000` -> `-₹50.00`. */
export function formatRupees(paise: number, { symbol = true }: { symbol?: boolean } = {}): string {
  const { negative, rupees, fraction } = splitPaise(paise)
  return `${negative ? '-' : ''}${symbol ? '₹' : ''}${groupIndian(rupees)}.${fraction}`
}

/** Dense variant: drops `.00` for whole rupees (`₹1,250` / `₹1,250.50`). */
export function formatRupeesCompact(paise: number): string {
  const { negative, rupees, fraction } = splitPaise(paise)
  const body = fraction === '00' ? groupIndian(rupees) : `${groupIndian(rupees)}.${fraction}`
  return `${negative ? '-' : ''}₹${body}`
}

/** How an amount is shown inside an editable grid cell: `1,250` or `1,250.50`, no symbol. */
export function formatAmountInput(paise: number): string {
  const { negative, rupees, fraction } = splitPaise(paise)
  const body = fraction === '00' ? groupIndian(rupees) : `${groupIndian(rupees)}.${fraction}`
  return `${negative ? '-' : ''}${body}`
}

/**
 * Parses user text into paise, or returns null if it isn't a valid amount.
 *
 * Accepts an optional `₹` / `Rs` / `Rs.` / `INR`, spaces and grouping commas
 * (Indian or Western) and at most two decimals: `"1,23,456.5"` -> `12345650`,
 * `"₹ 250"` -> `25000`, `".75"` -> `75`. Rejects negatives, more than two
 * decimals, anything non-numeric and values at or above the database limit.
 * Zero parses to 0; "must be more than zero" is a validation concern.
 */
export function parseRupeesToPaise(input: string): number | null {
  let s = input.trim()
  if (!s) return null
  s = s.replace(/^(₹|rs\.?|inr)\s*/i, '')
  s = s.replace(/[\s, ]/g, '')
  const match = /^(\d*)(?:\.(\d{0,2}))?$/.exec(s)
  if (!match) return null
  const whole = match[1] ?? ''
  const frac = match[2] ?? ''
  if (!whole && !frac) return null
  const wholeDigits = whole.replace(/^0+(?=\d)/, '')
  if (wholeDigits.length > MAX_RUPEE_DIGITS) return null
  const paise = Number(wholeDigits || '0') * 100 + Number(frac.padEnd(2, '0'))
  return paise < MAX_PAISE_EXCLUSIVE ? paise : null
}

/** An amount as it appears in a spreadsheet or bank statement. */
export interface SignedAmount {
  paise: number
  /** `-500`, `(500)`, `500 Dr`: money going out. */
  negative: boolean
  /** `500 Cr`: explicitly money coming in. */
  credit: boolean
}

/**
 * Like parseRupeesToPaise, but also understands the sign conventions of
 * bank exports: a leading or trailing minus, accounting brackets `(500)`,
 * and `Dr` / `Cr` suffixes. The caller decides what the sign means.
 */
export function parseSignedAmount(input: string): SignedAmount | null {
  let s = input.trim()
  if (!s) return null
  let negative = false
  let credit = false
  const suffix = /\s*(?<![a-z])(dr|cr)\.?$/i.exec(s)
  if (suffix) {
    if (suffix[1]!.toLowerCase() === 'dr') negative = true
    else credit = true
    s = s.slice(0, suffix.index).trim()
  }
  if (/^\(.*\)$/.test(s)) {
    negative = true
    s = s.slice(1, -1).trim()
  }
  s = s.replace(/^(₹|rs\.?|inr)\s*/i, '')
  if (s.startsWith('-')) {
    negative = true
    s = s.slice(1).trim()
  } else if (s.endsWith('-')) {
    negative = true
    s = s.slice(0, -1).trim()
  } else if (s.startsWith('+')) {
    s = s.slice(1).trim()
  }
  const paise = parseRupeesToPaise(s)
  if (paise === null) return null
  return { paise, negative, credit }
}
