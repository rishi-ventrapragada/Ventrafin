<script setup lang="ts">
// Preview of rows pasted from Excel. Shows which column Ventrafin thinks is
// which (changeable), every row as it will be saved, and marks rows that
// can't be saved and why. Nothing is saved until the user confirms.
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Select from 'primevue/select'
import { computed, ref, watch } from 'vue'
import AppIcon from '@/components/AppIcon.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { formatDateIndian } from '@/lib/dates'
import { FIELD_LABELS, parseEntryRow, type EntryContext, type ParsedRow, type RawRow } from '@/lib/entryRow'
import { formatRupees } from '@/lib/money'
import { txnTypeLabel } from '@/lib/models'
import { COLUMN_ROLES, guessRoles, readPaste, toGridRows, type ColumnRole, type PasteDefaults } from '@/lib/paste'

const props = defineProps<{
  /** Text that was pasted into the grid ('' when opened from the button). */
  initialText: string
  context: EntryContext
  defaults: PasteDefaults
  saving: boolean
}>()

const visible = defineModel<boolean>('visible', { required: true })

const emit = defineEmits<{
  /** Save the ready rows; rows with problems go to the grid to be fixed. */
  save: [ready: RawRow[], problems: RawRow[]]
  /** Put every row into the grid without saving. */
  toGrid: [rows: RawRow[]]
}>()

const text = ref(props.initialText)
watch(
  () => props.initialText,
  (t) => (text.value = t),
)

const table = computed(() => readPaste(text.value, props.context.today))
const roles = ref<ColumnRole[]>([])
// New paste (or new column layout): guess the columns again.
watch(
  () => [text.value, props.context.accounts.length, props.context.categories.length] as const,
  () => (roles.value = guessRoles(table.value, props.context)),
  { immediate: true },
)

const rows = computed(() =>
  toGridRows(table.value, roles.value, props.context, props.defaults).map((r) => ({
    ...r,
    parsed: parseEntryRow(r.raw, props.context),
  })),
)
const nonBlank = computed(() => rows.value.filter((r) => !r.parsed.blank))
const ready = computed(() => nonBlank.value.filter((r) => r.parsed.draft))
const problems = computed(() => nonBlank.value.filter((r) => !r.parsed.draft))
const spent = computed(() =>
  ready.value.reduce((sum, r) => sum + (r.parsed.draft!.type === 'expense' ? r.parsed.draft!.amountPaise : 0), 0),
)

const noDateColumn = computed(() => table.value.rows.length > 0 && !roles.value.includes('date'))
const noAmountColumn = computed(
  () => table.value.rows.length > 0 && !roles.value.some((r) => r === 'amount' || r === 'withdrawal' || r === 'deposit'),
)

function columnName(c: number): string {
  const heading = table.value.headings?.[c]
  return heading ? heading : `Column ${String.fromCharCode(65 + (c % 26))}`
}

function sample(c: number): string {
  return table.value.rows.find((r) => r[c])?.[c] ?? ''
}

function categoryFor(p: ParsedRow) {
  const id = p.draft?.categoryId
  return id ? (props.context.categories.find((c) => c.id === id) ?? null) : null
}

function accountName(id: string | null | undefined) {
  return props.context.accounts.find((a) => a.id === id)?.name ?? ''
}

function problemText(p: ParsedRow) {
  return p.issues.map((x) => `${FIELD_LABELS[x.field]}: ${x.message}`).join(' · ')
}
</script>

<template>
  <Dialog
    v-model:visible="visible"
    modal
    header="Paste rows from Excel"
    :style="{ width: 'min(1200px, 96vw)' }"
    :content-style="{ maxHeight: '72vh' }"
    :close-on-escape="!saving"
    :closable="!saving"
  >
    <div class="flex flex-col gap-3">
      <div>
        <label for="paste-box" class="mb-1 block text-sm font-semibold text-slate-700">
          Copy the rows in Excel, click in the box and press <kbd>Ctrl</kbd>+<kbd>V</kbd>
        </label>
        <textarea
          id="paste-box"
          v-model="text"
          rows="3"
          class="w-full rounded-md border border-slate-300 bg-slate-50 px-2 py-1.5 font-mono text-sm outline-none focus:border-ocean focus:bg-white"
          placeholder="Date	Description	Amount	Category	Paid by"
          spellcheck="false"
          data-testid="paste-box"
        />
      </div>

      <template v-if="table.rows.length > 0">
        <div class="text-sm text-slate-600" data-testid="paste-summary">
          Found <strong>{{ nonBlank.length }}</strong> row{{ nonBlank.length === 1 ? '' : 's' }}.
          <span v-if="table.headings">The first line was read as column headings and is not saved.</span>
          Check the columns below; change any that Ventrafin guessed wrong.
        </div>

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
          <AppIcon name="info" :size="18" class="align-[-4px] text-ocean" /> No date column: every row gets today's date
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
                v-for="r in nonBlank"
                :key="r.line"
                :data-line="r.line"
                :data-valid="r.parsed.draft ? 'true' : 'false'"
                :class="r.parsed.draft ? '' : 'bg-red-50'"
              >
                <td class="num text-slate-600">{{ r.line }}</td>
                <td>
                  <AppIcon v-if="!r.parsed.draft" name="error" filled :size="19" class="text-expense" label="Can't be saved" />
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
                <td class="text-sm" :class="r.parsed.draft ? 'text-uncat-ink' : 'text-expense'">{{ problemText(r.parsed) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </div>

    <template #footer>
      <div class="flex w-full flex-wrap items-center gap-2">
        <div class="mr-auto text-sm" data-testid="paste-counts">
          <template v-if="nonBlank.length">
            <span class="font-semibold text-income">{{ ready.length }} ready</span>
            <span v-if="spent > 0" class="text-slate-600"> ({{ formatRupees(spent) }} spent)</span>
            <template v-if="problems.length">
              · <span class="font-semibold text-expense">{{ problems.length }} can't be saved yet</span>
              <span class="text-slate-600"> (they go into the grid for you to fix)</span>
            </template>
          </template>
        </div>
        <Button label="Cancel" severity="secondary" text :disabled="saving" @click="visible = false" />
        <Button
          label="Put in the grid to review"
          severity="secondary"
          outlined
          :disabled="saving || nonBlank.length === 0"
          data-testid="paste-to-grid"
          @click="emit('toGrid', nonBlank.map((r) => r.raw))"
        />
        <Button
          :label="`Save ${ready.length} row${ready.length === 1 ? '' : 's'}`"
          :loading="saving"
          :disabled="ready.length === 0"
          data-testid="paste-save"
          @click="emit('save', ready.map((r) => r.raw), problems.map((r) => r.raw))"
        />
      </div>
    </template>
  </Dialog>
</template>
