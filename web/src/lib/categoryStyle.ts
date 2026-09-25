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

/** WCAG contrast ratio between two opaque colours (1 to 21). */
export function contrastRatio(a: string, b: string): number {
  const la = luminance(a)
  const lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

/**
 * White or near-black, whichever has more contrast on `background`; white
 * keeps near-ties (within 10 %, e.g. red #E53935, where both are about
 * 4.4:1). Every palette colour gets a glyph at 4.2:1 or better. The phone
 * uses the same rule, and /shared/category-style.json lists the result for
 * every palette colour, which both apps' tests check (DECISIONS.md D20).
 */
export function foregroundOn(background: string): string {
  const l = luminance(background)
  const whiteContrast = 1.05 / (l + 0.05)
  // The dark glyph is 87 % black over the circle's colour.
  const dark = luminance(toHex(channels(background).map((c) => c * 0.13) as [number, number, number]))
  const darkContrast = (l + 0.05) / (dark + 0.05)
  return whiteContrast * 1.1 >= darkContrast ? '#FFFFFF' : 'rgba(0, 0, 0, 0.87)'
}

/**
 * A darker shade of `hex` for text written in a category's colour on a
 * light surface (pale palette colours are unreadable as text otherwise):
 * 4.5:1 or better on `surface` (white unless given).
 */
export function readableTextColor(hex: string, surface = '#FFFFFF'): string {
  const onSurface = luminance(surface) + 0.05
  let out = channels(hex)
  for (let i = 0; i < 6 && onSurface / (luminance(toHex(out)) + 0.05) < 4.5; i++) {
    out = out.map((c) => c * 0.8) as [number, number, number]
  }
  return toHex(out)
}

/** `hex` at `alpha` opacity over white, as a solid colour. */
export function tintOnWhite(hex: string, alpha: number): string {
  return toHex(channels(hex).map((c) => c * alpha + 255 * (1 - alpha)) as [number, number, number])
}

/** `hex` at `alpha` opacity, for tinted backgrounds and borders. */
export function withAlpha(hex: string, alpha: number): string {
  const [r, g, b] = channels(hex)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

/** `hex` darkened 20 % at a time until `ok` holds (at most `steps` times). */
function darkenUntil(hex: string, ok: (c: string) => boolean, steps: number): string {
  let out = parseHex(hex)
  for (let i = 0; i < steps && !ok(out); i++) out = toHex(channels(out).map((c) => c * 0.8) as [number, number, number])
  return out
}

/** Below this contrast against a surface it sits on, a filled circle's edge gets lost (yellow on white is 1.4:1). */
export const CIRCLE_EDGE_MIN_CONTRAST = 1.5

/**
 * The outline for a filled category circle of `fill` shown on any of
 * `surfaces` (the theme's white cards, page and highlighted rows), or null
 * when it stands out from all of them: a darker shade at 3:1 or better
 * against every surface (DECISIONS.md D20). Same as the phone.
 */
export function circleEdgeFor(fill: string, surfaces: readonly string[]): string | null {
  if (surfaces.every((s) => contrastRatio(fill, s) >= CIRCLE_EDGE_MIN_CONTRAST)) return null
  return darkenUntil(fill, (c) => surfaces.every((s) => contrastRatio(c, s) >= 3), 8)
}

/**
 * Glyph and ring colour of an outlined circle (Uncategorized, Transfer,
 * Auto): a shade of `color` at 4.5:1 on the circle's 10 % tint over each of
 * `surfaces`. Same as the phone.
 */
export function outlinedInkFor(color: string, surfaces: readonly string[]): string {
  const tints = surfaces.map((s) => blend(color, 0.1, s))
  return darkenUntil(color, (c) => tints.every((t) => contrastRatio(c, t) >= 4.5), 8)
}

/** `hex` at `alpha` opacity over `under`, as a solid colour. */
export function blend(hex: string, alpha: number, under: string): string {
  const top = channels(hex)
  const bottom = channels(under)
  return toHex(top.map((c, i) => c * alpha + bottom[i]! * (1 - alpha)) as [number, number, number])
}
