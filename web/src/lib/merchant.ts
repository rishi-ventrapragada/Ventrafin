// Merchant letter badges (DECISIONS.md D14): a small letter derived from the
// description, coloured consistently per merchant. No logos and no logo
// service; computed in the browser from text it already has. The rule is
// written down in /shared/category-style.json ("merchantBadge") and matches
// mobile/lib/core/merchant.dart, so a merchant gets the same badge on both.
import { CATEGORY_PALETTE, MERCHANT_FILLER_WORDS } from './categoryStyle'

/** Anything that isn't a letter, combining mark or digit separates words. */
const SEPARATORS = /[^\p{L}\p{M}\p{N}]+/u
const DIGITS_ONLY = /^\d+$/

/**
 * The merchant word of a description, or null if there isn't one.
 *   'UPI/SWIGGY/4471023@icici'    -> 'swiggy'
 *   'Paid to Ramesh Kirana Store' -> 'ramesh'
 */
export function merchantKey(description: string): string | null {
  for (const word of description.toLowerCase().split(SEPARATORS)) {
    if (!word || DIGITS_ONLY.test(word) || MERCHANT_FILLER_WORDS.has(word)) continue
    return word
  }
  return null
}

/** FNV-1a (32-bit) over the UTF-8 bytes: stable across devices and languages. */
export function fnv1a32(s: string): number {
  let hash = 0x811c9dc5
  for (const byte of new TextEncoder().encode(s)) {
    hash ^= byte
    hash = Math.imul(hash, 0x01000193) >>> 0
  }
  return hash >>> 0
}

export interface MerchantBadge {
  letter: string
  color: string
}

/** Letter and palette colour for a description's merchant, or null when it names none. */
export function merchantBadgeFor(description: string): MerchantBadge | null {
  const key = merchantKey(description)
  if (key === null) return null
  const first = [...key][0]!
  return {
    letter: first.toUpperCase(),
    color: CATEGORY_PALETTE[fnv1a32(key) % CATEGORY_PALETTE.length]!,
  }
}
