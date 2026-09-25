// The six themes from /shared/theme-tokens.json: in step with the database,
// readable (WCAG AA), and every category colour legible on every theme's
// surfaces. Same checks as mobile/test/theme_test.dart.
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import style from '../../../shared/category-style.json'
import tokens from '../../../shared/theme-tokens.json'
import {
  CATEGORY_PALETTE,
  CIRCLE_EDGE_MIN_CONTRAST,
  UNCATEGORIZED_LOOK,
  TRANSFER_LOOK,
  blend,
  circleEdgeFor,
  contrastRatio,
  foregroundOn,
  outlinedInkFor,
  readableTextColor,
} from '@/lib/categoryStyle'
import {
  CARD_COLOR,
  EXPENSE_COLOR,
  INCOME_COLOR,
  THEMES,
  TRANSFER_COLOR,
  UNCATEGORIZED_INK,
  activeTheme,
  applyTheme,
  cssVarsFor,
  presetFor,
  themeById,
  themeSurfaces,
} from '@/lib/theme'

/** The glyph actually drawn: white, or 87 % black over the circle. */
const glyph = (bg: string) => (foregroundOn(bg) === '#FFFFFF' ? '#FFFFFF' : blend('#000000', 0.87, bg))

describe('theme tokens', () => {
  it('ids equal the profiles_theme_check constraint, Ocean first and the default', () => {
    const sql = readFileSync(resolve(process.cwd(), '../supabase/migrations/20260924154739_core_schema.sql'), 'utf8')
    const check = /check \(theme in \(([^)]*)\)\)/.exec(sql)![1]!
    expect(THEMES.map((t) => t.id)).toEqual([...check.matchAll(/'([a-z]+)'/g)].map((m) => m[1]))
    expect(tokens.defaultTheme).toBe('ocean')
    expect(themeById('nope').id).toBe('ocean')
  })

  it('style.css starts in Ocean with the same values', () => {
    const css = readFileSync(resolve(process.cwd(), 'src/style.css'), 'utf8').toLowerCase()
    for (const [k, v] of Object.entries(cssVarsFor(themeById('ocean')))) expect(css, k).toContain(`${k}: ${v.toLowerCase()};`)
    expect(css).toContain(`--color-expense: ${EXPENSE_COLOR.toLowerCase()}`)
    expect(css).toContain(`--color-income: ${INCOME_COLOR.toLowerCase()}`)
    expect(css).toContain(`--color-uncat-ink: ${UNCATEGORIZED_INK.toLowerCase()}`)
  })

  it('applyTheme sets the CSS variables and the active theme', () => {
    applyTheme(themeById('sunflower'))
    expect(document.documentElement.dataset.theme).toBe('sunflower')
    expect(document.documentElement.style.getPropertyValue('--vf-brand')).toBe('#FBC02D')
    expect(activeTheme.value.id).toBe('sunflower')
    applyTheme(themeById('ocean'))
  })
})

describe.each(THEMES.map((t) => [t.name, t] as const))('%s is readable (WCAG 2.1 AA)', (_name, t) => {
  const surfaces = themeSurfaces(t)

  it('sidebar text and marker, buttons and links, amounts', () => {
    expect(contrastRatio(t.onBrand, t.brand)).toBeGreaterThanOrEqual(4.5)
    expect(contrastRatio(t.brandIndicator, t.brand)).toBeGreaterThanOrEqual(3)
    expect(contrastRatio('#FFFFFF', t.primary)).toBeGreaterThanOrEqual(4.5)
    expect(contrastRatio('#FFFFFF', t.primaryHover)).toBeGreaterThanOrEqual(4.5)
    expect(contrastRatio(t.onAccent, t.accent)).toBeGreaterThanOrEqual(4.5)
    for (const s of surfaces) {
      expect(contrastRatio(t.primary, s), `primary on ${s}`).toBeGreaterThanOrEqual(4.5)
      for (const c of [EXPENSE_COLOR, INCOME_COLOR, UNCATEGORIZED_INK, TRANSFER_COLOR]) {
        expect(contrastRatio(c, s), `${c} on ${s}`).toBeGreaterThanOrEqual(4.5)
      }
    }
  })

  it('category circles stand out from every surface, or get an outline that does', () => {
    for (const c of CATEGORY_PALETTE) {
      const edge = circleEdgeFor(c, surfaces)
      for (const s of surfaces) {
        if (edge) expect(contrastRatio(edge, s), `outline of ${c} on ${s}`).toBeGreaterThanOrEqual(3)
        else expect(contrastRatio(c, s), `${c} on ${s}`).toBeGreaterThanOrEqual(CIRCLE_EDGE_MIN_CONTRAST)
      }
    }
  })

  it('names in their category colour, and outlined looks, read at 4.5:1', () => {
    for (const s of surfaces) {
      for (const c of CATEGORY_PALETTE) expect(contrastRatio(readableTextColor(c, s), s), `${c} on ${s}`).toBeGreaterThanOrEqual(4.5)
      for (const c of [UNCATEGORIZED_LOOK.color, TRANSFER_LOOK.color, t.primary]) {
        const tint = blend(c, 0.1, s)
        expect(contrastRatio(outlinedInkFor(c, surfaces), tint), `outlined ${c} on ${s}`).toBeGreaterThanOrEqual(4.5)
      }
    }
  })
})

describe('category glyphs (the same on both apps)', () => {
  it('match the shared table for every palette colour, so every built-in category', () => {
    const expected = style.glyph.onPalette as Record<string, string>
    expect(Object.keys(expected)).toEqual([...CATEGORY_PALETTE])
    for (const hex of CATEGORY_PALETTE) expect(foregroundOn(hex) === '#FFFFFF' ? 'white' : 'dark', hex).toBe(expected[hex])
  })

  it('reach 4.2:1 on every palette colour (the circle is the same in every theme)', () => {
    for (const hex of CATEGORY_PALETTE) expect(contrastRatio(glyph(hex), hex), hex).toBeGreaterThanOrEqual(4.2)
  })

  it('only pale colours get an outline', () => {
    const ocean = themeSurfaces(themeById('ocean'))
    expect(circleEdgeFor('#FDD835', ocean)).not.toBeNull()
    expect(circleEdgeFor('#1565C0', ocean)).toBeNull()
    expect(CARD_COLOR).toBe('#FFFFFF')
  })
})

describe('toasts (save confirmations and errors)', () => {
  it('every severity reads at 4.5:1 or better on its own background, in all six themes', () => {
    const severities = ['info', 'success', 'warn', 'error', 'secondary', 'contrast']
    for (const theme of THEMES) {
      // The values PrimeVue actually uses: the toast tokens of the theme's preset.
      const preset = presetFor(theme) as { components: { toast: { colorScheme: { light: Record<string, Record<string, string>> } } } }
      const toast = preset.components.toast.colorScheme.light
      for (const sev of severities) {
        const t = toast[sev]!
        // Solid backgrounds, so the ratio is what is on screen (Aura's are see-through).
        expect(t.background, `${theme.id} ${sev}`).toMatch(/^#[0-9a-f]{6}$/i)
        expect(contrastRatio(t.color!, t.background!), `${theme.id} ${sev} title and icon`).toBeGreaterThanOrEqual(4.5)
        expect(contrastRatio(t.detailColor!, t.background!), `${theme.id} ${sev} detail`).toBeGreaterThanOrEqual(4.5)
      }
    }
  })
})
