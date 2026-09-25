// The six colour themes (PRD § 4.8), light mode only, read straight from
// /shared/theme-tokens.json, the file the phone's theme_tokens.g.dart is
// generated from (DECISIONS.md D22). Applying a theme sets CSS variables
// (sidebar, page, highlights) and swaps PrimeVue's preset (buttons, links,
// focus rings), so the whole app follows without a reload.
import { definePreset, usePreset } from '@primeuix/themes'
import Aura from '@primeuix/themes/aura'
import { shallowRef } from 'vue'
import tokens from '../../../shared/theme-tokens.json'

export type ThemeId = 'ocean' | 'sunset' | 'forest' | 'garden' | 'sunflower' | 'marigold'

export interface ThemeTokens {
  id: ThemeId
  name: string
  /** "Blue and teal". */
  description: string
  /** The sidebar, with `onBrand` text; `brandIndicator` marks the current section. */
  brand: string
  onBrand: string
  brandIndicator: string
  /** Buttons, links, switches, selections: 4.5:1 as text on white and page, and under white text. */
  primary: string
  primaryHover: string
  /** Selected and highlighted rows. */
  primarySoft: string
  accent: string
  onAccent: string
  accentSoft: string
  /** Behind the cards (cards are white). */
  page: string
  primaryScale: Record<'50' | '100' | '200' | '300' | '400' | '500' | '600' | '700' | '800' | '900' | '950', string>
}

export const THEMES: readonly ThemeTokens[] = tokens.themes as ThemeTokens[]
export const DEFAULT_THEME_ID = tokens.defaultTheme as ThemeId

/** Semantic colours for amounts and states, the same in every theme and on the phone. */
export const EXPENSE_COLOR = tokens.semantic.expense
export const INCOME_COLOR = tokens.semantic.income
export const TRANSFER_COLOR = tokens.semantic.transfer
export const UNCATEGORIZED_INK = tokens.semantic.uncategorizedInk
export const CARD_COLOR = tokens.semantic.card

/** The theme stored under `id`; the default for an unknown id (say, from a newer phone app). */
export function themeById(id: string | null | undefined): ThemeTokens {
  return THEMES.find((t) => t.id === id) ?? THEMES.find((t) => t.id === DEFAULT_THEME_ID)!
}

/** Every surface a category circle can sit on in `theme`. */
export function themeSurfaces(theme: ThemeTokens): string[] {
  return [CARD_COLOR, theme.page, theme.primarySoft]
}

export type ToastSeverity = 'info' | 'success' | 'warn' | 'error' | 'secondary' | 'contrast'

/**
 * Toast colours. Aura's own put green-600 on green-50 (3.1:1) and
 * yellow-600 on yellow-50 (2.8:1), over a see-through background; these
 * are solid, and the title, icon and detail all read at 4.5:1 or better
 * (tests/unit/themes.test.ts). The same in every theme: a toast floats over
 * whatever is on the page.
 */
export const TOAST_COLORS: Readonly<Record<ToastSeverity, { background: string; border: string; color: string; detail: string; hover: string }>> = {
  info: { background: '#eff6ff', border: '#bfdbfe', color: '#1e40af', detail: '#334155', hover: '#dbeafe' },
  success: { background: '#f0fdf4', border: '#bbf7d0', color: '#166534', detail: '#334155', hover: '#dcfce7' },
  warn: { background: '#fefce8', border: '#fde68a', color: '#854d0e', detail: '#334155', hover: '#fef9c3' },
  error: { background: '#fef2f2', border: '#fecaca', color: '#991b1b', detail: '#334155', hover: '#fee2e2' },
  secondary: { background: '#f1f5f9', border: '#e2e8f0', color: '#334155', detail: '#334155', hover: '#e2e8f0' },
  contrast: { background: '#0f172a', border: '#020617', color: '#f8fafc', detail: '#f8fafc', hover: '#1e293b' },
}

function toastTokens() {
  return Object.fromEntries(
    Object.entries(TOAST_COLORS).map(([severity, c]) => [
      severity,
      {
        background: c.background,
        borderColor: c.border,
        color: c.color,
        detailColor: c.detail,
        closeButton: { hoverBackground: c.hover, focusRing: { color: c.color, shadow: 'none' } },
      },
    ]),
  )
}

/** Aura with the theme's primary as PrimeVue's primary colour, and readable toasts. */
export function presetFor(theme: ThemeTokens) {
  return definePreset(Aura, {
    semantic: {
      primary: Object.fromEntries(Object.entries(theme.primaryScale).map(([k, v]) => [k, v.toLowerCase()])),
      colorScheme: {
        light: {
          primary: {
            color: theme.primary,
            contrastColor: '#ffffff',
            hoverColor: theme.primaryHover,
            activeColor: theme.primaryHover,
          },
          highlight: {
            background: theme.primarySoft,
            focusBackground: theme.primaryScale['100'],
            color: theme.primary,
            focusColor: theme.primaryHover,
          },
        },
      },
    },
    components: {
      toast: { colorScheme: { light: toastTokens() } },
    },
  })
}

/** CSS variables behind the Tailwind colours `brand`, `on-brand`, `page`, `primary-soft` … (style.css). */
export function cssVarsFor(theme: ThemeTokens): Record<string, string> {
  return {
    '--vf-brand': theme.brand,
    '--vf-on-brand': theme.onBrand,
    '--vf-brand-indicator': theme.brandIndicator,
    '--vf-primary': theme.primary,
    '--vf-primary-soft': theme.primarySoft,
    '--vf-accent': theme.accent,
    '--vf-page': theme.page,
  }
}

const STORAGE_KEY = 'ventrafin.theme'

/** The theme last shown in this browser (a per-browser convenience, so the page opens in it). */
export function rememberedThemeId(): string | null {
  try {
    return localStorage.getItem(STORAGE_KEY)
  } catch {
    return null
  }
}

let applied: string | null = null

/** The theme on screen now, for components that draw with its colours (category circles, the Auto look). */
export const activeTheme = shallowRef<ThemeTokens>(themeById(null))

/** Applies `theme` to the page and remembers it in this browser. */
export function applyTheme(theme: ThemeTokens, { preset = true }: { preset?: boolean } = {}): void {
  if (typeof document !== 'undefined') {
    const root = document.documentElement
    for (const [k, v] of Object.entries(cssVarsFor(theme))) root.style.setProperty(k, v)
    root.dataset.theme = theme.id
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme.brand)
  }
  if (preset && applied !== theme.id) usePreset(presetFor(theme))
  applied = theme.id
  activeTheme.value = theme
  try {
    localStorage.setItem(STORAGE_KEY, theme.id)
  } catch {
    // Private window or storage blocked: the theme still applies, it just isn't remembered.
  }
}

/** For installUi(): the preset to start with. */
export function initialTheme(): ThemeTokens {
  const theme = themeById(rememberedThemeId())
  applied = theme.id
  activeTheme.value = theme
  return theme
}
