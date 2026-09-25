// Screen-width rules for the app shell. Dad's PC may be a 1080p screen at
// 150 % Windows scaling: 1280 CSS pixels across. Below SIDEBAR_RAIL_BELOW the
// sidebar shrinks to a rail of icons, so the Add grid and the Transactions
// table fit without scrolling sideways.

/** Narrower than this (CSS pixels), the sidebar is an icon rail. */
export const SIDEBAR_RAIL_BELOW = 1400

/** The media query that is true while the sidebar is a rail. */
export const RAIL_QUERY = `(max-width: ${SIDEBAR_RAIL_BELOW - 0.02}px)`

/** Whether a window `width` CSS pixels wide gets the icon rail. */
export function sidebarIsRail(width: number): boolean {
  return width < SIDEBAR_RAIL_BELOW
}

/** The sidebar's sections, in the same order as the phone's. */
export const NAV = [
  { to: '/dashboard', label: 'Dashboard', icon: 'dashboard' },
  { to: '/transactions', label: 'Transactions', icon: 'receipt_long' },
  { to: '/add', label: 'Add', icon: 'add_circle' },
  { to: '/bills', label: 'Bills', icon: 'event_note' },
  { to: '/categories', label: 'Categories', icon: 'category' },
  { to: '/accounts', label: 'Accounts', icon: 'account_balance_wallet' },
  { to: '/reports', label: 'Reports', icon: 'bar_chart' },
  { to: '/settings', label: 'Settings', icon: 'settings' },
] as const
