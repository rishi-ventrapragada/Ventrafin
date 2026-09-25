// The rows of a paste or an imported CSV file, as they will be saved: the
// columns Ventrafin guessed (changeable), each row parsed by the same
// parser as a typed grid row, and the counts the dialogs show.
import { computed, ref, watch, type Ref } from 'vue'
import { parseEntryRow, type EntryContext } from '@/lib/entryRow'
import { guessRoles, toGridRows, type ColumnRole, type PasteDefaults, type PasteTable } from '@/lib/paste'

export function usePreviewRows(table: Readonly<Ref<PasteTable>>, context: Readonly<Ref<EntryContext>>, defaults: Readonly<Ref<PasteDefaults>>) {
  const roles = ref<ColumnRole[]>([])
  // New rows (or a new column layout): guess the columns again.
  watch(
    () => [table.value, context.value.accounts.length, context.value.categories.length] as const,
    () => (roles.value = guessRoles(table.value, context.value)),
    { immediate: true },
  )

  const rows = computed(() =>
    toGridRows(table.value, roles.value, context.value, defaults.value).map((r) => ({
      ...r,
      parsed: parseEntryRow(r.raw, context.value),
    })),
  )
  const nonBlank = computed(() => rows.value.filter((r) => !r.parsed.blank))
  const ready = computed(() => nonBlank.value.filter((r) => r.parsed.draft))
  const problems = computed(() => nonBlank.value.filter((r) => !r.parsed.draft))

  return { roles, nonBlank, ready, problems }
}

export type PreviewRow = ReturnType<typeof usePreviewRows>['nonBlank']['value'][number]

/** Money spent in `rows` (expenses only), for the footer. */
export function spentIn(rows: readonly PreviewRow[]): number {
  return rows.reduce((sum, r) => sum + (r.parsed.draft?.type === 'expense' ? r.parsed.draft.amountPaise : 0), 0)
}
