// Same cases as mobile/test/money_test.dart: both apps format and parse
// money identically.
import { describe, expect, it } from 'vitest'
import {
  MAX_PAISE_EXCLUSIVE,
  formatAmountInput,
  formatRupees,
  formatRupeesCompact,
  groupIndian,
  parseRupeesToPaise,
  parseSignedAmount,
} from '@/lib/money'

describe('formatRupees (Indian grouping, paise -> ₹)', () => {
  it('formats the canonical example', () => {
    expect(formatRupees(12345600)).toBe('₹1,23,456.00')
  })

  it('small values and paise', () => {
    expect(formatRupees(0)).toBe('₹0.00')
    expect(formatRupees(5)).toBe('₹0.05')
    expect(formatRupees(99)).toBe('₹0.99')
    expect(formatRupees(100)).toBe('₹1.00')
    expect(formatRupees(25050)).toBe('₹250.50')
  })

  it('grouping boundaries: 3 digits, then pairs', () => {
    expect(formatRupees(99900)).toBe('₹999.00')
    expect(formatRupees(100000)).toBe('₹1,000.00')
    expect(formatRupees(9999900)).toBe('₹99,999.00')
    expect(formatRupees(10000000)).toBe('₹1,00,000.00')
    expect(formatRupees(1000000000)).toBe('₹1,00,00,000.00') // 1 crore
    expect(formatRupees(123456789012)).toBe('₹1,23,45,67,890.12')
  })

  it('largest amount the database allows, exactly (no float drift)', () => {
    expect(formatRupees(MAX_PAISE_EXCLUSIVE - 1)).toBe('₹99,99,99,99,99,999.99')
  })

  it('negative values and the no-symbol form', () => {
    expect(formatRupees(-500000)).toBe('-₹5,000.00')
    expect(formatRupees(12345600, { symbol: false })).toBe('1,23,456.00')
  })

  it('compact form drops .00 only for whole rupees', () => {
    expect(formatRupeesCompact(125000)).toBe('₹1,250')
    expect(formatRupeesCompact(125050)).toBe('₹1,250.50')
    expect(formatRupeesCompact(-10000000)).toBe('-₹1,00,000')
  })

  it('grid cell form has no symbol', () => {
    expect(formatAmountInput(125000)).toBe('1,250')
    expect(formatAmountInput(12345650)).toBe('1,23,456.50')
  })

  it('refuses anything that is not integer paise', () => {
    expect(() => formatRupees(12.5)).toThrow(RangeError)
    expect(() => formatRupees(Number.NaN)).toThrow(RangeError)
  })

  it('groupIndian', () => {
    expect(groupIndian('1')).toBe('1')
    expect(groupIndian('123')).toBe('123')
    expect(groupIndian('1234')).toBe('1,234')
    expect(groupIndian('1234567')).toBe('12,34,567')
  })
})

describe('parseRupeesToPaise', () => {
  it('plain and decimal amounts', () => {
    expect(parseRupeesToPaise('250')).toBe(25000)
    expect(parseRupeesToPaise('250.5')).toBe(25050)
    expect(parseRupeesToPaise('250.05')).toBe(25005)
    expect(parseRupeesToPaise('.75')).toBe(75)
    expect(parseRupeesToPaise('0.01')).toBe(1)
    expect(parseRupeesToPaise('0')).toBe(0)
  })

  it('accepts ₹ / Rs / INR, spaces and Indian or Western commas', () => {
    expect(parseRupeesToPaise('₹1,23,456.00')).toBe(12345600)
    expect(parseRupeesToPaise(' ₹ 1,234 ')).toBe(123400)
    expect(parseRupeesToPaise('Rs. 99')).toBe(9900)
    expect(parseRupeesToPaise('rs 99')).toBe(9900)
    expect(parseRupeesToPaise('INR 5')).toBe(500)
    expect(parseRupeesToPaise('123,456.78')).toBe(12345678)
    expect(parseRupeesToPaise('007')).toBe(700)
    expect(parseRupeesToPaise('1 250')).toBe(125000) // Excel's non-breaking space
  })

  it('rejects invalid input', () => {
    for (const bad of ['', ' ', '.', 'abc', '12a', '1.234', '1.2.3', '-5', '+5', '1e5', '₹']) {
      expect(parseRupeesToPaise(bad), `"${bad}" should be rejected`).toBeNull()
    }
  })

  it('enforces the database upper bound', () => {
    expect(parseRupeesToPaise('9999999999999.99')).toBe(MAX_PAISE_EXCLUSIVE - 1)
    expect(parseRupeesToPaise('10000000000000')).toBeNull()
    expect(parseRupeesToPaise('99999999999999')).toBeNull()
  })

  it('never goes through floating point (no rounding drift)', () => {
    expect(parseRupeesToPaise('0.29')).toBe(29)
    expect(parseRupeesToPaise('1.13')).toBe(113)
    expect(parseRupeesToPaise('4.35')).toBe(435)
    expect(parseRupeesToPaise('1234567890.99')).toBe(123456789099)
  })

  it('format -> parse round-trips', () => {
    for (const p of [0, 1, 99, 100, 12345600, 987654321, MAX_PAISE_EXCLUSIVE - 1]) {
      expect(parseRupeesToPaise(formatRupees(p))).toBe(p)
    }
  })
})

describe('parseSignedAmount (bank-export conventions)', () => {
  it('plain amounts are unsigned', () => {
    expect(parseSignedAmount('₹1,250.50')).toEqual({ paise: 125050, negative: false, credit: false })
  })

  it('minus, brackets and Dr mean money going out', () => {
    for (const s of ['-500', '500-', '(500)', '500 Dr', '500Dr', '₹ -500', '(₹500.00)', '500 DR.']) {
      expect(parseSignedAmount(s), s).toEqual({ paise: 50000, negative: true, credit: false })
    }
  })

  it('Cr means money coming in', () => {
    expect(parseSignedAmount('1,00,000.00 Cr')).toEqual({ paise: 10000000, negative: false, credit: true })
  })

  it('rejects text', () => {
    expect(parseSignedAmount('abc')).toBeNull()
    expect(parseSignedAmount('')).toBeNull()
    expect(parseSignedAmount('12.345')).toBeNull()
  })
})
