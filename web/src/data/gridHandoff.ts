// Rows handed from the CSV import (Settings) to the Add grid, where rows
// that can't be saved yet are fixed the same way as pasted ones. Kept in
// memory only, for the next time the Add page opens.
import type { RawRow } from '@/lib/entryRow'

let pending: RawRow[] = []

export function handOffToGrid(rows: readonly RawRow[]): void {
  pending = rows.map((r) => ({ ...r }))
}

/** The handed-off rows, once (the list is emptied). */
export function takeHandedOffRows(): RawRow[] {
  const rows = pending
  pending = []
  return rows
}
