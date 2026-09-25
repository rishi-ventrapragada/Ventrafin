// Spotting rows in an imported file that are already saved, so importing the
// same bank statement (or Ventrafin export) twice doesn't double the
// spending. A row counts as already saved when a transaction has the same
// date, amount, type, account and description (ignoring case and spacing).
// Rows repeated inside the file are kept: two ₹20 teas on one day are real.
import type { TxnDraft } from './models'

type Keyed = Pick<TxnDraft, 'date' | 'amountPaise' | 'type' | 'accountId' | 'description'>

export function duplicateKey(t: Keyed): string {
  const description = t.description.trim().toLowerCase().replace(/\s+/g, ' ')
  return [t.date, t.amountPaise, t.type, t.accountId, description].join('|')
}

/**
 * Which of `rows` are already among `existing`. Each saved transaction
 * matches at most one row, so a file with two identical rows where one is
 * saved marks only one.
 */
export function findAlreadySaved<K>(rows: readonly { key: K; draft: Keyed }[], existing: readonly Keyed[]): Set<K> {
  const available = new Map<string, number>()
  for (const t of existing) {
    const k = duplicateKey(t)
    available.set(k, (available.get(k) ?? 0) + 1)
  }
  const found = new Set<K>()
  for (const row of rows) {
    const k = duplicateKey(row.draft)
    const left = available.get(k) ?? 0
    if (left > 0) {
      found.add(row.key)
      available.set(k, left - 1)
    }
  }
  return found
}

/** The earliest and latest dates among `drafts`, or null when there are none. */
export function dateSpan(drafts: readonly { date: string }[]): { from: string; to: string } | null {
  if (drafts.length === 0) return null
  let from = drafts[0]!.date
  let to = from
  for (const d of drafts) {
    if (d.date < from) from = d.date
    if (d.date > to) to = d.date
  }
  return { from, to }
}
