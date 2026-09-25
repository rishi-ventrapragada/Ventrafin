// Audit round 2, the rules without a page: the sidebar's width breakpoint and
// what fits at 1280 px, one toast rule, URL values, the sidebar and "Other"
// colours in every theme, per-account totals, and Windows Hello wording.
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { TOAST_LIFE, toastMessage } from '@/components/useNotify'
import { describePasskeyError } from '@/data/passkeys'
import { blend, contrastRatio } from '@/lib/categoryStyle'
import { monthFromQuery } from '@/lib/dates'
import { NAV, RAIL_QUERY, SIDEBAR_RAIL_BELOW, sidebarIsRail } from '@/lib/layout'
import { accountTotalsFromRow } from '@/lib/models'
import { TYPE_FILTER_OPTIONS, typeFilterFromQuery } from '@/lib/options'
import { OTHER_SERIES_COLOR, SUMMARY_CAPTION, spanFromQuery } from '@/lib/reports'
import { THEMES, themeSurfaces } from '@/lib/theme'

const src = (path: string) => readFileSync(resolve(process.cwd(), 'src', path), 'utf8')

describe('NAV-5: the sidebar becomes an icon rail below 1400 px', () => {
  it('breakpoint', () => {
    expect(SIDEBAR_RAIL_BELOW).toBe(1400)
    expect(RAIL_QUERY).toBe('(max-width: 1399.98px)')
    for (const w of [1024, 1280, 1366, 1399]) expect(sidebarIsRail(w), `${w}`).toBe(true)
    for (const w of [1400, 1440, 1536, 1920]) expect(sidebarIsRail(w), `${w}`).toBe(false)
  })

  // What the page has to spare, in rem: the window, less the sidebar, the
  // main area's padding (px-5), the card border and a vertical scrollbar.
  // The root font is 16px below 1500px and 17px from there (style.css).
  const RAIL_REM = 3.5 // w-14
  const SIDEBAR_REM = 13 // w-52
  const spare = (width: number) => {
    const root = width >= 1500 ? 17 : 16
    const sidebar = (sidebarIsRail(width) ? RAIL_REM : SIDEBAR_REM) * root
    return (width - sidebar - 2 * 20 - 2 - 17) / root
  }

  it('the Transactions table fits 1280 px (1080p at 150 %) and every width above it without scrolling sideways', () => {
    const page = src('pages/TransactionsPage.vue')
    const table = page.slice(page.indexOf('<DataTable'), page.indexOf('</DataTable>'))
    const fixed = [...table.matchAll(/(?:header-)?style="width: ([\d.]+)rem"/g)].map((m) => Number(m[1]))
    const description = Number(/width: 100%; min-width: ([\d.]+)rem/.exec(table)![1])
    expect(fixed).toHaveLength(9)
    expect(description).toBeLessThanOrEqual(8)
    const needed = fixed.reduce((s, w) => s + w, 0) + description
    for (const w of [1280, 1366, 1399, 1400, 1440, 1500, 1920]) expect(needed, `${w} px`).toBeLessThanOrEqual(spare(w))
  })

  it('so does the Add grid', () => {
    const grid = src('components/add/EntryGrid.vue')
    const min = Number(/min-width: ([\d.]+)rem;/.exec(grid.slice(grid.indexOf('.entry-grid {')))![1])
    for (const w of [1280, 1366, 1400, 1440, 1920]) expect(min, `${w} px`).toBeLessThanOrEqual(spare(w))
  })
})

describe('NAV-6: sections in the same order as the phone', () => {
  it('Dashboard, Transactions, Add, Bills, Categories, Accounts, Reports, Settings', () => {
    expect(NAV.map((n) => n.label)).toEqual(['Dashboard', 'Transactions', 'Add', 'Bills', 'Categories', 'Accounts', 'Reports', 'Settings'])
  })
})

describe('TX-5: one toast rule for the whole app', () => {
  it('errors stay until closed; everything else is timed', () => {
    expect(toastMessage('error', 'Not saved', { detail: 'Offline.', life: 3000 })).toEqual({ severity: 'error', summary: 'Not saved', detail: 'Offline.' })
    expect(toastMessage('success', 'Saved')).toEqual({ severity: 'success', summary: 'Saved', life: TOAST_LIFE.success })
    expect(toastMessage('info', 'Moved')).toMatchObject({ life: TOAST_LIFE.info })
    expect(toastMessage('warn', 'Not changed')).toMatchObject({ life: TOAST_LIFE.warn })
    expect(toastMessage('success', 'Deleted', { group: 'undo', life: 5000 })).toMatchObject({ group: 'undo', life: 5000 })
  })

  it('no page or component shows a toast any other way', () => {
    const files: string[] = []
    const walk = (dir: string) => {
      for (const f of readdirSync(dir)) {
        const p = join(dir, f)
        if (statSync(p).isDirectory()) walk(p)
        else if (/\.(vue|ts)$/.test(f)) files.push(p)
      }
    }
    walk(resolve(process.cwd(), 'src'))
    const offenders = files.filter(
      (f) => !f.endsWith('useNotify.ts') && /primevue\/usetoast|toast\.add\(/.test(readFileSync(f, 'utf8')),
    )
    expect(offenders).toEqual([])
  })
})

describe('NAV-4 and PRD-3: values read from the URL', () => {
  const sep = { year: 2026, month: 9 }

  it('month: a valid month up to this one; anything else is the default', () => {
    expect(monthFromQuery('2026-07', sep)).toEqual({ year: 2026, month: 7 })
    expect(monthFromQuery('2026-09', sep)).toEqual(sep)
    expect(monthFromQuery('2026-10', sep)).toBeNull() // the future
    for (const bad of [undefined, null, '', '2026-13', '2026-7', 'july', ['2026-07']]) expect(monthFromQuery(bad, sep)).toBeNull()
  })

  it('span: 12, or 6', () => {
    expect(spanFromQuery('12')).toBe(12)
    for (const v of ['6', undefined, '24', '', null]) expect(spanFromQuery(v)).toBe(6)
  })

  it('type: expense, income or transfer, or all', () => {
    expect(typeFilterFromQuery('expense')).toBe('expense')
    expect(typeFilterFromQuery('income')).toBe('income')
    expect(typeFilterFromQuery('transfer')).toBe('transfer')
    for (const v of ['all', 'Expense', undefined, '']) expect(typeFilterFromQuery(v)).toBe('all')
    expect(TYPE_FILTER_OPTIONS.map((o) => o.label)).toEqual(['All types', 'Expenses', 'Income', 'Transfers'])
  })
})

describe.each(THEMES.map((t) => [t.name, t] as const))('UI-1 and REP-3 in %s', (_name, t) => {
  it('sidebar text reads at 4.5:1 on the sidebar, on a hovered row and on the current (darkened) row', () => {
    const inactive = t.brand
    const hovered = blend('#000000', 0.1, t.brand) // hover:bg-black/10
    const active = blend('#000000', 0.15, t.brand) // bg-black/15
    for (const [what, bg] of [['inactive', inactive], ['hovered', hovered], ['current', active]] as const) {
      expect(contrastRatio(t.onBrand, bg), `${what} ${bg}`).toBeGreaterThanOrEqual(4.5)
    }
  })

  it('"Other" in the category trend stands out (3:1) from every surface', () => {
    for (const s of themeSurfaces(t)) expect(contrastRatio(OTHER_SERIES_COLOR, s), s).toBeGreaterThanOrEqual(3)
  })
})

describe('UI-1: the sidebar uses those backgrounds, at full opacity', () => {
  it('AppShell', () => {
    const shell = src('components/AppShell.vue')
    expect(shell).toContain("'bg-black/15 font-semibold")
    expect(shell).toContain('hover:bg-black/10')
    expect(shell).not.toMatch(/on-brand\/90|bg-on-brand\/1[05]/)
  })
})

describe('REP-3 and REP-4: shared with the phone', () => {
  it('values', () => {
    expect(OTHER_SERIES_COLOR).toBe('#7F8C93')
    expect(SUMMARY_CAPTION).toBe('Net = income minus spending. Saved = the part of income not spent, as a percentage.')
  })
})

describe('CAT-1: get_account_totals rows', () => {
  it('bigint strings become numbers; the month is the month', () => {
    expect(
      accountTotalsFromRow({
        account_id: 'acc-bank',
        month: '2026-09-01',
        expense_paise: '1234500' as unknown as number,
        income_paise: 0,
        transfer_out_paise: '200000' as unknown as number,
        transfer_in_paise: 50000,
        entry_count: '7' as unknown as number,
      }),
    ).toEqual({
      accountId: 'acc-bank',
      month: { year: 2026, month: 9 },
      expensePaise: 1234500,
      incomePaise: 0,
      transferOutPaise: 200000,
      transferInPaise: 50000,
      entryCount: 7,
    })
  })
})

describe('SET-1: the feature is "Windows Hello sign-in", never "passkey"', () => {
  it('every error message', () => {
    const errors = [
      Object.assign(new Error('x'), { name: 'NotAllowedError' }),
      { code: 'passkey_disabled' },
      { code: 'webauthn_credential_exists' },
      { code: 'webauthn_credential_not_found' },
      { code: 'webauthn_challenge_expired' },
      { code: 'too_many_passkeys' },
      { code: 'ERROR_INVALID_DOMAIN' },
      Object.assign(new Error('x'), { name: 'NotSupportedError' }),
      new TypeError('Failed to fetch'),
      new Error('something else'),
    ]
    for (const e of errors) {
      for (const step of ['sign-in', 'register'] as const) expect(describePasskeyError(e, step)).not.toMatch(/passkey/i)
    }
    expect(describePasskeyError({ code: 'too_many_passkeys' }, 'register')).toBe(
      'Your account has the most Windows Hello sign-ins allowed. Remove one in Settings first.',
    )
  })
})
