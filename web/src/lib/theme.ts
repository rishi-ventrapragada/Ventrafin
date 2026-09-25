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
export const UNCATEGORIZED_COLOR = tokens.semantic.uncategorized
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

/** Aura with the theme's primary as PrimeVue's primary colour. */
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
