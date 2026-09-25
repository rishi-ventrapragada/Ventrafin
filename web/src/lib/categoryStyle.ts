// Curated category icons and colours (DECISIONS.md D13), read straight from
// /shared/category-style.json, the file the database constraint and the
// phone are checked against. Mirrors mobile/lib/core/category_style.dart.
import style from '../../../shared/category-style.json'

export interface CategoryIconDef {
  /** Material Symbols key, as stored in `categories.icon`. */
  key: string
  /** Short name for tooltips and screen readers. */
  label: string
}

export interface CategoryIconGroup {
  name: string
  icons: CategoryIconDef[]
}

export const DEFAULT_CATEGORY_ICON: string = style.defaultIcon
export const CATEGORY_ICON_GROUPS: readonly CategoryIconGroup[] = style.iconGroups
export const CATEGORY_ICON_KEYS: ReadonlySet<string> = new Set(
  style.iconGroups.flatMap((g) => g.icons.map((i) => i.key)),
)
export const CATEGORY_ICON_LABELS: Readonly<Record<string, string>> = Object.fromEntries(
  style.iconGroups.flatMap((g) => g.icons.map((i) => [i.key, i.label])),
)

/** Colour picker palette, in picker order; same as `private.category_palette()`. */
export const CATEGORY_PALETTE: readonly string[] = style.palette

/** Uncategorized has no row: an outlined amber question mark. */
export const UNCATEGORIZED_LOOK = style.uncategorized
/** Transfers are never categorized: an outlined grey arrow. */
export const TRANSFER_LOOK = style.transfer

export const MERCHANT_FILLER_WORDS: ReadonlySet<string> = new Set(style.merchantBadge.fillerWords)
export const MERCHANT_EXAMPLES = style.merchantBadge.examples

/** The icon key to draw: an unknown key (say, from a newer phone app) falls back to the tag. */
export function categoryIconKey(key: string | null | undefined): string {
  return key && CATEGORY_ICON_KEYS.has(key) ? key : DEFAULT_CATEGORY_ICON
}

// ---------------------------------------------------------------------------
// Colour maths (WCAG relative luminance, as Flutter's computeLuminance)
// ---------------------------------------------------------------------------

export function parseHex(hex: string | null | undefined, fallback = '#9E9E9E'): string {
  return hex && /^#[0-9a-f]{6}$/i.test(hex) ? hex.toUpperCase() : fallback
}

function channels(hex: string): [number, number, number] {
  const n = Number.parseInt(parseHex(hex).slice(1), 16)
  return [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]
}

function toHex([r, g, b]: [number, number, number]): string {
  return `#${[r, g, b].map((c) => Math.round(c).toString(16).padStart(2, '0')).join('')}`.toUpperCase()
}

export function luminance(hex: string): number {
  const [r, g, b] = channels(hex).map((c) => {
    const s = c / 255
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  }) as [number, number, number]
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

/**
 * White or near-black, whichever reads better on `background`. White wins
 * whenever it reaches the 3:1 contrast WCAG asks of icons, so most circles
 * get white glyphs; pale ones (yellow, peach, sky) get dark glyphs.
 */
export function foregroundOn(background: string): string {
  const whiteContrast = 1.05 / (luminance(background) + 0.05)
  return whiteContrast >= 3 ? '#FFFFFF' : 'rgba(0, 0, 0, 0.87)'
}

/**
 * A darker shade of `hex` for text written in a category's colour on a
 * light surface (pale palette colours are unreadable as text otherwise).
 */
export function readableTextColor(hex: string): string {
  let out = channels(hex)
  for (let i = 0; i < 6 && 1.05 / (luminance(toHex(out)) + 0.05) < 4.5; i++) {
    out = out.map((c) => c * 0.8) as [number, number, number]
  }
  return toHex(out)
}

/** `hex` at `alpha` opacity, for tinted backgrounds and borders. */
export function withAlpha(hex: string, alpha: number): string {
  const [r, g, b] = channels(hex)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}
