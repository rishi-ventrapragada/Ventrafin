import type { PaymentMethod } from '@/lib/models'

/**
 * The last-used account and payment method, remembered in this browser so
 * the next entry starts with them (like the phone's EntryPrefs). These are
 * UI conveniences, not financial data, so localStorage is fine; this is not
 * a local database or cache.
 */
export interface EntryPrefs {
  readonly lastAccountId: string | null
  readonly lastMethod: PaymentMethod | null
  remember(accountId: string, method: PaymentMethod | null): void
}

const ACCOUNT_KEY = 'ventrafin.entry.lastAccountId'
const METHOD_KEY = 'ventrafin.entry.lastPaymentMethod'

function read(key: string): string | null {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}

function write(key: string, value: string): void {
  try {
    localStorage.setItem(key, value)
  } catch {
    // Storage blocked (private window): the defaults just aren't remembered.
  }
}

export function createLocalEntryPrefs(): EntryPrefs {
  return {
    get lastAccountId() {
      return read(ACCOUNT_KEY)
    },
    get lastMethod() {
      const m = read(METHOD_KEY)
      return m === 'cash' || m === 'upi' || m === 'debit' || m === 'card' ? m : null
    },
    remember(accountId, method) {
      write(ACCOUNT_KEY, accountId)
      if (method) write(METHOD_KEY, method)
    },
  }
}
