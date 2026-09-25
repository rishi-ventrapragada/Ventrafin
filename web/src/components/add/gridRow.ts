import type { RawRow } from '@/lib/entryRow'

export interface GridRow {
  /** Also the transaction id sent on save, so retrying a save can't create a duplicate. */
  key: string
  raw: RawRow
}

/** A random UUID v4 (the transaction's id once saved). */
export function newRowKey(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID()
  const b = crypto.getRandomValues(new Uint8Array(16))
  b[6] = (b[6]! & 0x0f) | 0x40
  b[8] = (b[8]! & 0x3f) | 0x80
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}
