// The "Ocean" theme (blue / teal), light mode only (PRD § 4.8). Same values
// as mobile/lib/core/theme.dart. The full set of six themes moves to
// /shared/theme-tokens.json in phase 7; until then these are the source.

export const OCEAN_PRIMARY = '#1565C0'
export const OCEAN_ACCENT = '#00897B'

/** Semantic colours for amounts and states (same as the phone). */
export const EXPENSE_COLOR = '#C62828'
export const INCOME_COLOR = '#2E7D32'
export const TRANSFER_COLOR = '#546E7A'
export const UNCATEGORIZED_COLOR = '#B26A00'

/** Material Blue, with 800 as the Ocean primary. Feeds the PrimeVue preset. */
export const OCEAN_PRIMARY_SCALE = {
  50: '#e3f2fd',
  100: '#bbdefb',
  200: '#90caf9',
  300: '#64b5f6',
  400: '#42a5f5',
  500: '#2196f3',
  600: '#1e88e5',
  700: '#1976d2',
  800: '#1565c0',
  900: '#0d47a1',
  950: '#0a2f6b',
} as const
