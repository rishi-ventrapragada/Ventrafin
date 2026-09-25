<script setup lang="ts">
// Column pickers and the row-by-row preview shared by "Paste from Excel"
// (Add page) and "Import a CSV file" (Settings): which column Ventrafin
// thinks is which, every row as it will be saved, and why a row can't be.
import Select from 'primevue/select'
import { computed } from 'vue'
import AppIcon from '@/components/AppIcon.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { formatDateIndian } from '@/lib/dates'
import { FIELD_LABELS, type EntryContext, type ParsedRow } from '@/lib/entryRow'
import { formatRupees } from '@/lib/money'
import { txnTypeLabel } from '@/lib/models'
import { COLUMN_ROLES, type ColumnRole, type PasteTable } from '@/lib/paste'
import type { PreviewRow } from './previewRows'

const props = defineProps<{
  table: PasteTable
  rows: readonly PreviewRow[]
  context: EntryContext
  /** Lines that are fine but won't be saved (with the reason), e.g. already in Transactions. */
  skipped?: ReadonlyMap<number, string>
}>()

const roles = defineModel<ColumnRole[]>('roles', { required: true })

const noDateColumn = computed(() => props.table.rows.length > 0 && !roles.value.includes('date'))
const noAmountColumn = computed(
  () => props.table.rows.length > 0 && !roles.value.some((r) => r === 'amount' || r === 'withdrawal' || r === 'deposit'),
)

function columnName(c: number): string {
  const heading = props.table.headings?.[c]
  return heading ? heading : `Column ${String.fromCharCode(65 + (c % 26))}`
}

function sample(c: number): string {
  return props.table.rows.find((r) => r[c])?.[c] ?? ''
}

function categoryFor(p: ParsedRow) {
  const id = p.draft?.categoryId
  return id ? (props.context.categories.find((c) => c.id === id) ?? null) : null
}

function accountName(id: string | null | undefined) {
  return props.context.accounts.find((a) => a.id === id)?.name ?? ''
}

function problemText(r: PreviewRow) {
  const notes = r.parsed.issues.map((x) => `${FIELD_LABELS[x.field]}: ${x.message}`)
  const skip = props.skipped?.get(r.line)
  return (skip ? [skip, ...notes] : notes).join(' · ')
}
</script>

<template>
  <div class="grid gap-2" :style="{ gridTemplateColumns: `repeat(${Math.min(table.columnCount, 6)}, minmax(0, 1fr))` }">
    <div v-for="c in table.columnCount" :key="c" class="rounded-md border border-slate-200 bg-slate-50 p-2">
      <div class="truncate text-sm font-semibold text-slate-700" :title="columnName(c - 1)">{{ columnName(c - 1) }}</div>
      <div class="mb-1 truncate text-sm text-slate-600" :title="sample(c - 1)">e.g. {{ sample(c - 1) || '(empty)' }}</div>
      <Select
        v-model="roles[c - 1]"
        :options="[...COLUMN_ROLES]"
        option-label="label"
        option-value="value"
        size="small"
        class="w-full"
        :aria-label="`What is ${columnName(c - 1)}?`"
        :data-testid="`role-${c - 1}`"
      />
    </div>
  </div>

  <div v-if="noDateColumn" class="text-sm text-slate-600">
    <AppIcon name="info" :size="18" class="align-[-4px] text-primary" /> No date column: every row gets today's date
    ({{ formatDateIndian(context.today) }}).
  </div>
  <div v-if="noAmountColumn" class="text-sm text-expense">
    <AppIcon name="error" filled :size="18" class="align-[-4px]" /> Choose which column holds the amount.
  </div>

  <div class="overflow-auto rounded-md border border-slate-200">
    <table class="dense-table" data-testid="paste-preview">
      <thead>
        <tr>
          <th class="w-10 text-right">Line</th>
          <th class="w-8"></th>
          <th>Date</th>
          <th>Description</th>
          <th class="text-right">Amount</th>
          <th>Type</th>
          <th>Category</th>
          <th>Account</th>
          <th>Paid by</th>
          <th>Problems</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="r in rows"
          :key="r.line"
          :data-line="r.line"
          :data-valid="r.parsed.draft ? 'true' : 'false'"
          :data-skipped="skipped?.has(r.line) ? 'true' : undefined"
          :class="!r.parsed.draft ? 'bg-red-50' : skipped?.has(r.line) ? 'text-slate-500' : ''"
        >
          <td class="num text-slate-600">{{ r.line }}</td>
          <td>
            <AppIcon v-if="!r.parsed.draft" name="error" filled :size="19" class="text-expense" label="Can't be saved" />
            <AppIcon v-else-if="skipped?.has(r.line)" name="content_copy" :size="19" class="text-slate-500" label="Already saved" />
            <AppIcon v-else-if="r.parsed.issues.length" name="warning" filled :size="19" class="text-uncat" label="Note" />
            <AppIcon v-else name="check_circle" :size="19" class="text-income" label="Ready" />
          </td>
          <td class="whitespace-nowrap">{{ r.parsed.draft ? formatDateIndian(r.parsed.draft.date) : r.raw.date }}</td>
          <td class="max-w-[18rem] truncate" :title="r.raw.description">{{ r.raw.description }}</td>
          <td class="num">{{ r.parsed.draft ? formatRupees(r.parsed.draft.amountPaise) : r.raw.amount }}</td>
          <td>{{ r.parsed.draft ? txnTypeLabel(r.parsed.draft.type) : r.raw.type || 'Expense' }}</td>
          <td class="whitespace-nowrap">
            <template v-if="r.parsed.draft && r.parsed.draft.type === 'transfer'">
              <TxnAvatar kind="transfer" :size="22" class="mr-1 align-middle" />Transfer
            </template>
            <template v-else-if="r.parsed.draft && categoryFor(r.parsed)">
              <TxnAvatar :category="categoryFor(r.parsed)" :size="22" class="mr-1 align-middle" />{{ categoryFor(r.parsed)!.name }}
            </template>
            <template v-else><TxnAvatar kind="auto" :size="22" class="mr-1 align-middle" />Auto</template>
          </td>
          <td class="whitespace-nowrap">
            {{ r.parsed.draft ? accountName(r.parsed.draft.accountId) : r.raw.account }}
            <template v-if="r.parsed.draft?.toAccountId"> → {{ accountName(r.parsed.draft.toAccountId) }}</template>
          </td>
          <td>{{ r.raw.method || '—' }}</td>
          <td class="text-sm" :class="!r.parsed.draft ? 'text-expense' : skipped?.has(r.line) ? 'text-slate-600' : 'text-uncat-ink'">
            {{ problemText(r) }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
