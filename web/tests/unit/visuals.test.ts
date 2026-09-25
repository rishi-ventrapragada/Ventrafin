// The web app draws the same icons, colours and merchant badges as the phone.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import shared from '../../../shared/category-style.json'
import {
  CATEGORY_ICON_KEYS,
  CATEGORY_PALETTE,
  categoryIconKey,
  foregroundOn,
  luminance,
  readableTextColor,
} from '@/lib/categoryStyle'
import { FILLED_ICONS, OUTLINED_ICONS } from '@/lib/icons.generated'
import { fnv1a32, merchantBadgeFor, merchantKey } from '@/lib/merchant'
import { ACCOUNT_TYPES, PAYMENT_METHODS, TXN_TYPES } from '@/lib/models'

const contrast = (a: string, b: string) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number]
  return (hi + 0.05) / (lo + 0.05)
}

describe('category icons', () => {
  it('every curated key (the database constraint) has a glyph, filled like Flutter Icons.*', () => {
    for (const key of CATEGORY_ICON_KEYS) expect(FILLED_ICONS[key], key).toBeTruthy()
    expect(CATEGORY_ICON_KEYS.size).toBe(shared.iconGroups.flatMap((g) => g.icons).length)
  })

  it('the icon list matches the latest migration that defines categories_icon_check', () => {
    const sql = readFileSync(resolve(process.cwd(), '../supabase/migrations/20260925040030_category_icons.sql'), 'utf8')
    const check = /categories_icon_check check \(icon in \(([\s\S]*?)\)\);/.exec(sql)![1]!
    const keys = [...check.matchAll(/'([a-z0-9_]+)'/g)].map((m) => m[1])
    expect(new Set(keys)).toEqual(CATEGORY_ICON_KEYS)
  })

  it('unknown keys fall back to the tag', () => {
    expect(categoryIconKey('swiggy_logo')).toBe('label')
    expect(categoryIconKey(null)).toBe('label')
  })

  it('every icon the UI names exists in the registry', () => {
    const named = [
      ...TXN_TYPES.map((t) => t.icon),
      ...PAYMENT_METHODS.map((m) => m.icon),
      ...Object.values(ACCOUNT_TYPES).map((a) => a.icon),
    ]
    for (const icon of named) expect((icon.filled ? FILLED_ICONS : OUTLINED_ICONS)[icon.name], icon.name).toBeTruthy()
    expect(FILLED_ICONS[shared.uncategorized.icon]).toBeTruthy()
    expect(FILLED_ICONS[shared.transfer.icon]).toBeTruthy()
  })
})

describe('colours', () => {
  it('palette is the shared one (same order as private.category_palette())', () => {
    expect(CATEGORY_PALETTE).toEqual(shared.palette)
  })

  it('glyphs on category circles are readable: white at 3:1 or better, else dark', () => {
    expect(foregroundOn('#1565C0')).toBe('#FFFFFF')
    expect(foregroundOn('#FDD835')).toBe('rgba(0, 0, 0, 0.87)')
    for (const hex of CATEGORY_PALETTE) {
      if (foregroundOn(hex) === '#FFFFFF') expect(contrast(hex, '#FFFFFF'), hex).toBeGreaterThanOrEqual(3)
    }
  })

  it('category names written in their colour are readable on white (4.5:1)', () => {
    for (const hex of CATEGORY_PALETTE) expect(contrast(readableTextColor(hex), '#FFFFFF'), hex).toBeGreaterThanOrEqual(4.5)
  })
})

describe('merchant letter badges (same as the phone)', () => {
  it('examples in the shared file', () => {
    for (const e of shared.merchantBadge.examples) {
      expect(merchantKey(e.description), e.description).toBe(e.key)
      expect(merchantBadgeFor(e.description)?.letter ?? null, e.description).toBe(e.letter)
    }
  })

  it('identical letter and colour to mobile/lib/core/merchant.dart (vectors printed by the Dart code)', () => {
    const dart: [string, string, string, string, number][] = [
      ['Swiggy dinner', 'swiggy', 'S', '#FB8C00', 4290119955],
      ['UPI/ZOMATO/4471023@paytm', 'zomato', 'Z', '#EC407A', 3582236729],
      ['D-Mart Andheri', 'd', 'D', '#A1887F', 3775669363],
      ['Paid to Ramesh Kirana Store', 'ramesh', 'R', '#EC407A', 1352794913],
      ['Apollo Pharmacy', 'apollo', 'A', '#4FC3F7', 2211952042],
      ['दूध वाला', 'दूध', 'द', '#78909C', 2939276493],
      ['Café Coffee Day', 'café', 'C', '#BF360C', 2821410889],
    ]
    for (const [description, key, letter, color, hash] of dart) {
      expect(merchantKey(description)).toBe(key)
      expect(fnv1a32(key)).toBe(hash)
      expect(merchantBadgeFor(description)).toEqual({ letter, color })
    }
    expect(merchantBadgeFor('4471023')).toBeNull()
  })

  it('same merchant, same badge, however the bank writes it', () => {
    const a = merchantBadgeFor('Swiggy dinner')
    expect(merchantBadgeFor('UPI/SWIGGY/4471023@icici')).toEqual(a)
    expect(merchantBadgeFor('Paid to swiggy order #88')).toEqual(a)
  })
})
