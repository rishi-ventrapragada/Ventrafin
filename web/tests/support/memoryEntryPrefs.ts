import type { EntryPrefs } from '@/data/entryPrefs'
import type { PaymentMethod } from '@/lib/models'

/** In-memory prefs for the component tests and the demo page. */
export function createMemoryEntryPrefs(initial: { accountId?: string; method?: PaymentMethod } = {}): EntryPrefs {
  let accountId = initial.accountId ?? null
  let method = initial.method ?? null
  return {
    get lastAccountId() {
      return accountId
    },
    get lastMethod() {
      return method
    },
    remember(a, m) {
      accountId = a
      if (m) method = m
    },
  }
}
