// Phase 7 on the fake repository: CSV export (Transactions and Settings),
// CSV import (Settings), and Windows Hello (Settings and the sign-in page).
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { AppUser } from '@/data/auth'
import { rememberPasskeyHint, type PasskeyInfo, type PasskeyService, type PasskeySupport } from '@/data/passkeys'
import { FakeRepository, makeTxn } from '../support/fakeRepository'
import { buttonByText, byTestId, cell, mountApp, settle } from '../support/mountApp'

async function click(el: Element | null | undefined) {
  if (!el) throw new Error('nothing to click')
  ;(el as HTMLElement).click()
  await settle()
}

async function press(el: Element, key: string) {
  el.dispatchEvent(new KeyboardEvent('keydown', { key, code: key, bubbles: true, cancelable: true }))
  await settle()
}

async function type(el: HTMLInputElement | null, text: string) {
  if (!el) throw new Error('no input')
  el.value = text
  el.dispatchEvent(new Event('input', { bubbles: true }))
  await settle()
}

// ------------------------------------------------------------ downloads

let downloads: { name: string; text: string }[] = []
let pendingBlobs: Promise<void>[] = []

beforeEach(() => {
  downloads = []
  pendingBlobs = []
  let lastBlob: Blob | null = null
  URL.createObjectURL = vi.fn((b: Blob) => {
    lastBlob = b
    return 'blob:ventrafin-test'
  }) as typeof URL.createObjectURL
  URL.revokeObjectURL = vi.fn()
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
    const name = this.download
    const blob = lastBlob!
    // Blob.text() would drop the byte-order mark, so decode the bytes as they are.
    pendingBlobs.push(
      blob.arrayBuffer().then((b) => void downloads.push({ name, text: new TextDecoder('utf-8', { ignoreBOM: true }).decode(b) })),
    )
  })
})

afterEach(() => vi.restoreAllMocks())

async function downloaded() {
  await Promise.all(pendingBlobs)
  return downloads
}

function repoWithSeptember() {
  const repo = new FakeRepository()
  repo.txns = [
    makeTxn('t1', { date: '2026-09-20', description: 'Swiggy dinner', amountPaise: 45000, accountId: 'acc-cash' }),
    makeTxn('t2', { date: '2026-09-21', description: 'DMart', amountPaise: 120000, categoryId: 'cat-groc', accountId: 'acc-bank' }),
    makeTxn('t3', { date: '2026-08-02', description: 'August tea', amountPaise: 2000 }),
  ]
  return repo
}

describe('Export (Transactions page)', () => {
  it('downloads the month on screen, as a UTF-8 CSV Excel opens', async () => {
    const repo = repoWithSeptember()
    await mountApp({ repo, path: '/transactions?month=2026-09' })
    await click(byTestId('open-export'))
    const first = document.querySelector<HTMLInputElement>('[data-range="shown"] input')!
    expect(first.checked).toBe(true)
    expect(byTestId('export-ranges')!.textContent).toContain('September 2026 · 2 transactions')

    await click(byTestId('export-download'))
    expect(repo.exportCalls).toEqual([{ from: '2026-09-01', to: '2026-09-30' }])
    const [file] = await downloaded()
    expect(file!.name).toBe('ventrafin-transactions-2026-09-01-to-2026-09-30.csv')
    expect(file!.text.startsWith('﻿Date,Description,Amount (₹),Type,Category,Account,To account,Paid by\r\n')).toBe(true)
    expect(file!.text).toContain('Swiggy dinner')
    expect(file!.text).not.toContain('August tea')
    expect(document.body.textContent).toContain('Downloaded 2 transactions')
  })

  it('with filters on, only the rows shown are exported', async () => {
    const repo = repoWithSeptember()
    await mountApp({ repo, path: '/transactions?month=2026-09&account=acc-bank' })
    await click(byTestId('open-export'))
    expect(byTestId('export-ranges')!.textContent).toContain('filtered as on screen · 1 transaction')
    await click(byTestId('export-download'))
    expect(repo.exportCalls).toEqual([{ from: '2026-09-01', to: '2026-09-30', ids: ['t2'] }])
    const [file] = await downloaded()
    expect(file!.name).toBe('ventrafin-transactions-2026-09-01-to-2026-09-30-filtered.csv')
    expect(file!.text).toContain('DMart')
    expect(file!.text).not.toContain('Swiggy')
  })

  it('nothing in range: says so and downloads nothing', async () => {
    const repo = new FakeRepository()
    await mountApp({ repo, path: '/transactions?month=2026-09' })
    await click(byTestId('open-export'))
    await click(byTestId('export-download'))
    expect(byTestId('export-failure')!.textContent).toContain('no transactions in that range')
    expect(await downloaded()).toEqual([])
  })

  it('opens on the chosen range, and Enter downloads', async () => {
    const repo = repoWithSeptember()
    await mountApp({ repo, path: '/transactions?month=2026-09' })
    await click(byTestId('open-export'))
    const first = document.querySelector<HTMLInputElement>('[data-range="shown"] input')!
    expect(document.activeElement).toBe(first)
    expect(byTestId<HTMLButtonElement>('export-download')!.type).toBe('submit')
    await press(first, 'Enter')
    expect(repo.exportCalls).toEqual([{ from: '2026-09-01', to: '2026-09-30' }])
  })

  it('searching all months: exports the matches from every month', async () => {
    const repo = repoWithSeptember()
    await mountApp({ repo, path: '/transactions?month=2026-09' })
    await type(byTestId<HTMLInputElement>('search'), 'tea')
    await click(byTestId('all-months'))
    await click(byTestId('open-export'))
    expect(byTestId('export-ranges')!.textContent).toContain('All months, filtered as on screen · 1 transaction')
    await click(byTestId('export-download'))
    expect(repo.exportCalls).toEqual([{ from: null, to: null, ids: ['t3'] }])
  })

  it('a failed export explains why and keeps the dialog open', async () => {
    const repo = repoWithSeptember()
    repo.failNextExportWith = new TypeError('Failed to fetch')
    await mountApp({ repo, path: '/transactions?month=2026-09' })
    await click(byTestId('open-export'))
    await click(byTestId('export-download'))
    expect(byTestId('export-failure')!.textContent).toContain("Couldn't reach the server")
    expect(byTestId('export-download')).not.toBeNull()
  })
})

describe('Export (Settings)', () => {
  it('financial-year and custom ranges', async () => {
    const repo = repoWithSeptember()
    await mountApp({ repo, path: '/settings' })
    await click(byTestId('settings-export'))
    expect(document.querySelector('[data-range="shown"]')).toBeNull()
    expect(byTestId('export-ranges')!.textContent).toContain('FY 2026-27: 01/04/2026 to 31/03/2027')

    await click(document.querySelector('[data-range="thisFy"] input'))
    await click(byTestId('export-download'))
    expect(repo.exportCalls.at(-1)).toEqual({ from: '2026-04-01', to: '2027-03-31' })

    await click(byTestId('settings-export'))
    await click(document.querySelector('[data-range="custom"] input'))
    await type(byTestId<HTMLInputElement>('export-from'), '2026-09-21')
    await type(byTestId<HTMLInputElement>('export-to'), '2026-09-01')
    expect(document.body.textContent).toContain('The start date is after the end date.')
    expect(byTestId<HTMLButtonElement>('export-download')!.disabled).toBe(true)
    await type(byTestId<HTMLInputElement>('export-to'), '2026-09-30')
    await click(byTestId('export-download'))
    expect(repo.exportCalls.at(-1)).toEqual({ from: '2026-09-21', to: '2026-09-30' })
    const files = await downloaded()
    expect(files.at(-1)!.text).toContain('DMart')
    expect(files.at(-1)!.text).not.toContain('Swiggy')
  })
})

// ------------------------------------------------------------ import

async function chooseFile(name: string, content: string | Uint8Array) {
  const input = byTestId<HTMLInputElement>('import-file')!
  const file = new File([content as BlobPart], name, { type: 'text/csv' })
  Object.defineProperty(input, 'files', { value: [file], configurable: true })
  input.dispatchEvent(new Event('change'))
  await settle()
}

const STATEMENT =
  'Txn Date,Narration,Withdrawal Amt,Deposit Amt,Closing Balance\r\n' +
  '01/09/2026,UPI-SWIGGY-12345,"1,250.00",,"48,750.00"\r\n' +
  '02/09/2026,SALARY SEP,,"85,000.00","1,33,750.00"\r\n' +
  '03/09/2026,DMART,500.00,,"1,33,250.00"\r\n' +
  '31/02/2026,BROKEN DATE,10.00,,"1,33,240.00"\r\n'

describe('Import (Settings)', () => {
  it('previews a bank statement, skips a row already saved, saves the rest and sends problems to the Add grid', async () => {
    const repo = new FakeRepository()
    // DMART on 3 Sep from Bank is already in Transactions.
    repo.txns = [makeTxn('old', { date: '2026-09-03', description: 'DMart', amountPaise: 50000, accountId: 'acc-bank', categoryId: 'cat-groc' })]
    const { router } = await mountApp({ repo, path: '/settings' })
    await click(byTestId('settings-import'))
    await chooseFile('statement.csv', STATEMENT)

    expect(byTestId('import-file-name')!.textContent).toBe('statement.csv')
    expect(byTestId('import-summary')!.textContent).toContain('Found 4 rows')
    // A bank statement has no Account column: the dialog's default is Bank (no account used yet).
    expect(byTestId('import-default-account')!.textContent).toContain('Bank')
    const preview = byTestId('paste-preview')!
    expect(preview.querySelectorAll('tr[data-valid="true"]')).toHaveLength(3)
    expect(preview.querySelector('tr[data-line="5"]')!.getAttribute('data-valid')).toBe('false')
    expect(preview.querySelector('tr[data-line="4"]')!.getAttribute('data-skipped')).toBe('true')
    expect(byTestId('import-duplicates')!.textContent).toContain('1 row is already in Transactions')
    expect(byTestId('import-counts')!.textContent).toContain('2 to save')
    expect(byTestId('import-counts')!.textContent).toContain("1 can't be saved yet")

    await click(byTestId('import-save'))
    expect(repo.insertAttempts).toHaveLength(1)
    const saved = repo.txns.filter((t) => t.id !== 'old')
    expect(saved.map((t) => [t.date, t.description, t.type, t.amountPaise, t.accountId])).toEqual([
      ['2026-09-01', 'UPI-SWIGGY-12345', 'expense', 125000, 'acc-bank'],
      ['2026-09-02', 'SALARY SEP', 'income', 8500000, 'acc-bank'],
    ])
    expect(document.body.textContent).toContain('Imported 2 transactions')
    // The broken row is waiting in the Add grid, highlighted.
    await vi.waitFor(() => expect(router.currentRoute.value.path).toBe('/add'))
    await settle()
    expect(cell(0, 1).value).toBe('BROKEN DATE')
    expect(document.body.textContent).toContain('1 imported row to fix')
  })

  it('opens on "Choose a CSV file"; Enter in the form saves', async () => {
    const repo = new FakeRepository()
    repo.txns = [makeTxn('old', { date: '2026-09-03', description: 'DMart', amountPaise: 50000, accountId: 'acc-bank', categoryId: 'cat-groc' })]
    await mountApp({ repo, path: '/settings' })
    await click(byTestId('settings-import'))
    expect(document.activeElement).toBe(byTestId('import-choose'))
    await chooseFile('statement.csv', STATEMENT)
    const anyway = byTestId<HTMLInputElement>('import-include-duplicates')!
    anyway.focus()
    await press(anyway, 'Enter')
    expect(repo.insertAttempts).toHaveLength(1)
    expect(document.body.textContent).toContain('Imported 2 transactions')
  })

  it('"Save them anyway" includes rows already saved', async () => {
    const repo = new FakeRepository()
    repo.txns = [makeTxn('old', { date: '2026-09-03', description: 'DMART', amountPaise: 50000, accountId: 'acc-bank' })]
    await mountApp({ repo, path: '/settings' })
    await click(byTestId('settings-import'))
    await chooseFile('statement.csv', STATEMENT)
    expect(byTestId('import-counts')!.textContent).toContain('2 to save')
    await click(byTestId('import-include-duplicates'))
    expect(byTestId('import-counts')!.textContent).toContain('3 to save')
  })

  it('the default account can be changed for rows that don\'t say', async () => {
    const repo = new FakeRepository()
    const { ctx } = await mountApp({ repo, path: '/settings' })
    ctx.prefs.remember('acc-cash', 'cash')
    await click(byTestId('settings-import'))
    await chooseFile('cash.csv', 'Date,Description,Amount\r\n25/09/2026,Tea,20\r\n')
    expect(byTestId('import-default-account')!.textContent).toContain('Cash')
    await click(byTestId('import-save'))
    expect(repo.txns[0]).toMatchObject({ accountId: 'acc-cash', paymentMethod: 'cash', amountPaise: 2000 })
  })

  it('a failed save keeps everything and retrying reuses the same ids', async () => {
    const repo = new FakeRepository()
    repo.failNextInsertWith = new TypeError('Failed to fetch')
    await mountApp({ repo, path: '/settings' })
    await click(byTestId('settings-import'))
    await chooseFile('a.csv', 'Date,Description,Amount,Paid by\r\n25/09/2026,Tea,20,Cash\r\n24/09/2026,Milk,40,UPI\r\n')
    await click(byTestId('import-save'))
    expect(byTestId('import-failure')!.textContent).toContain('Nothing was saved')
    expect(repo.txns).toHaveLength(0)
    await click(byTestId('import-save'))
    expect(repo.txns).toHaveLength(2)
    expect(repo.insertAttempts[1]).toEqual(repo.insertAttempts[0])
  })

  it('an Excel workbook is refused with how to save it as CSV', async () => {
    await mountApp({ path: '/settings' })
    await click(byTestId('settings-import'))
    await chooseFile('Statement.xlsx', 'PK...')
    expect(byTestId('import-file-error')!.textContent).toContain('CSV UTF-8')
    expect(byTestId<HTMLButtonElement>('import-save')!.disabled).toBe(true)
  })

  it('re-importing a Ventrafin export: every row is already saved', async () => {
    const repo = repoWithSeptember()
    await mountApp({ repo, path: '/settings' })
    const csv = await repo.exportTransactionsCsv({ from: null, to: null })
    await click(byTestId('settings-import'))
    await chooseFile('ventrafin-transactions-all-2026-09-25.csv', '﻿' + csv)
    expect(byTestId('import-summary')!.textContent).toContain('Found 3 rows')
    expect(byTestId('import-duplicates')!.textContent).toContain('3 rows are already in Transactions')
    expect(byTestId('import-counts')!.textContent).toContain('0 to save')
  })
})

// ------------------------------------------------------------ Windows Hello

function fakePasskeys(opts: { support?: PasskeySupport; enabled?: boolean; list?: PasskeyInfo[] } = {}) {
  const state = {
    list: [...(opts.list ?? [])],
    signIns: 0,
    registers: 0,
    removed: [] as string[],
    failNext: null as unknown,
    onSignIn: () => {},
  }
  const service: PasskeyService = {
    serverEnabled: async () => opts.enabled ?? true,
    deviceSupport: async () => opts.support ?? 'platform',
    async signIn() {
      state.signIns++
      if (state.failNext) {
        const e = state.failNext
        state.failNext = null
        throw e
      }
      state.onSignIn()
    },
    async register() {
      state.registers++
      if (state.failNext) {
        const e = state.failNext
        state.failNext = null
        throw e
      }
      const p = { id: `pk-${state.registers}`, name: 'Windows Hello', createdAt: '2026-09-25T10:00:00Z', lastUsedAt: null }
      state.list.push(p)
      return p
    },
    list: async () => state.list.map((p) => ({ ...p })),
    async remove(id) {
      state.removed.push(id)
      state.list = state.list.filter((p) => p.id !== id)
    },
  }
  return { service, state }
}

describe('Windows Hello in Settings', () => {
  it('sets up a passkey on this PC and lists it', async () => {
    const { service, state } = fakePasskeys()
    await mountApp({ path: '/settings', passkeys: service })
    expect(byTestId('passkey-none')!.textContent).toContain('Not set up yet')
    await click(byTestId('passkey-register'))
    expect(state.registers).toBe(1)
    expect(byTestId('passkey-list')!.textContent).toContain('Windows Hello')
    expect(byTestId('passkey-list')!.textContent).toContain('25/09/2026')
    expect(document.body.textContent).toContain('Windows Hello sign-in is set up')
  })

  it('cancelling the Windows prompt is not an error', async () => {
    const { service, state } = fakePasskeys()
    state.failNext = Object.assign(new Error('The operation either timed out or was not allowed.'), { name: 'NotAllowedError' })
    await mountApp({ path: '/settings', passkeys: service })
    await click(byTestId('passkey-register'))
    expect(document.body.textContent).toContain('Setup was cancelled. Nothing was saved.')
  })

  it('removing asks first', async () => {
    const { service, state } = fakePasskeys({
      list: [{ id: 'pk-a', name: 'Windows Hello', createdAt: '2026-09-01T10:00:00Z', lastUsedAt: '2026-09-20T03:00:00Z' }],
    })
    await mountApp({ path: '/settings', passkeys: service })
    expect(byTestId('passkey-list')!.textContent).toContain('20/09/2026')
    await click(buttonByText('Remove'))
    expect(state.removed).toEqual([])
    await click(document.querySelector('.p-confirmdialog-accept-button'))
    expect(state.removed).toEqual(['pk-a'])
    expect(byTestId('passkey-none')).not.toBeNull()
  })

  it('hidden with a reason when the browser or the server can\'t do it', async () => {
    await mountApp({ path: '/settings', passkeys: fakePasskeys({ support: 'none' }).service })
    expect(byTestId('passkey-unsupported')!.textContent).toContain("can't use Windows Hello")
    expect(byTestId('passkey-register')).toBeNull()
  })

  it('server switched off: says not available yet', async () => {
    await mountApp({ path: '/settings', passkeys: fakePasskeys({ enabled: false }).service })
    expect(byTestId('passkey-server-off')!.textContent).toContain('Not available yet')
    expect(byTestId('passkey-register')).toBeNull()
  })
})

describe('Windows Hello on the sign-in page', () => {
  it('offered only where it was set up, next to Google', async () => {
    const { service } = fakePasskeys()
    await mountApp({ path: '/login', signedIn: false, passkeys: service })
    expect(byTestId('google-sign-in')).not.toBeNull()
    expect(byTestId('passkey-sign-in')).toBeNull()
  })

  it('signs in and opens the page that was asked for', async () => {
    rememberPasskeyHint(true)
    const { service, state } = fakePasskeys()
    const { auth, router } = await mountApp({ path: '/login?next=/reports', signedIn: false, passkeys: service })
    state.onSignIn = () => {
      ;(auth.user as { value: AppUser | null }).value = { id: 'user-1', email: 'dad@example.com', name: 'Dad' }
    }
    expect(byTestId('passkey-sign-in')!.textContent).toContain('Sign in with Windows Hello')
    await click(byTestId('passkey-sign-in'))
    expect(state.signIns).toBe(1)
    await vi.waitFor(() => expect(router.currentRoute.value.path).toBe('/reports'))
  })

  it('a passkey removed from the account: explains, and stops offering it here', async () => {
    rememberPasskeyHint(true)
    const { service, state } = fakePasskeys()
    state.failNext = Object.assign(new Error('not found'), { name: 'AuthApiError', code: 'webauthn_credential_not_found' })
    await mountApp({ path: '/login', signedIn: false, passkeys: service })
    await click(byTestId('passkey-sign-in'))
    expect(document.body.textContent).toContain('Sign in with Google, then set it up again in Settings')
    expect(byTestId('passkey-sign-in')).toBeNull()
  })

  it('hidden when the server has passkeys switched off', async () => {
    rememberPasskeyHint(true)
    await mountApp({ path: '/login', signedIn: false, passkeys: fakePasskeys({ enabled: false }).service })
    expect(byTestId('passkey-sign-in')).toBeNull()
  })
})
