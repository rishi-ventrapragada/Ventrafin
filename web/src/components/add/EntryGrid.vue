<script setup lang="ts">
// The Add page's spreadsheet: every cell is always editable, like Excel.
//   Tab / Shift+Tab       next / previous cell
//   Enter, Down           same column, next row (Enter adds a row at the bottom)
//   Shift+Enter, Up       same column, previous row
//   Ctrl+D                copy the cell above (fill down)
//   Ctrl+;                today's date (date column)
//   Ctrl+S, Ctrl+Enter    save
// Pasting several cells (rows copied from Excel) opens the paste preview
// instead of dropping text into one cell.
import { computed, nextTick, ref } from 'vue'
import AccountAvatar from '@/components/AccountAvatar.vue'
import AppIcon from '@/components/AppIcon.vue'
import ComboInput from '@/components/ComboInput.vue'
import MerchantBadge from '@/components/MerchantBadge.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { formatDateIndian } from '@/lib/dates'
import {
  ENTRY_FIELDS,
  FIELD_LABELS,
  isAutoCategory,
  matchAccount,
  matchCategory,
  parseTxnType,
  type EntryContext,
  type EntryField,
  type ParsedRow,
} from '@/lib/entryRow'
import { ACCOUNT_TYPES } from '@/lib/models'
import { METHOD_OPTIONS, TYPE_OPTIONS, accountOptions, categoryOptions } from '@/lib/options'
import { looksLikeRows } from '@/lib/paste'
import type { GridRow } from './gridRow'

const props = defineProps<{
  rows: readonly GridRow[]
  parsed: readonly ParsedRow[]
  context: EntryContext
  /** Rows the user has left at least once: only these show their problems. */
  touched: ReadonlySet<string>
  disabled?: boolean
}>()

const emit = defineEmits<{
  edit: [index: number, field: EntryField, value: string]
  /** The user finished with a cell: tidy its text (25-9 -> 25/09/2026). */
  tidy: [index: number, field: EntryField]
  touch: [key: string]
  addRows: [count: number]
  removeRow: [index: number]
  paste: [text: string]
  save: []
}>()

const COLS = ENTRY_FIELDS
const table = ref<HTMLTableElement | null>(null)

const accountOpts = computed(() => accountOptions(props.context.accounts))

function typeOf(row: GridRow) {
  return parseTxnType(row.raw.type) ?? 'expense'
}

function categoryOpts(row: GridRow) {
  const t = typeOf(row)
  return categoryOptions(props.context.categories, t === 'income' ? 'income' : 'expense')
}

function issueFor(i: number, field: EntryField) {
  const key = props.rows[i]?.key
  if (!key || !props.touched.has(key)) return null
  return props.parsed[i]?.issues.find((x) => x.field === field) ?? null
}

function cellClass(i: number, field: EntryField) {
  const issue = issueFor(i, field)
  return { 'cell-error': issue?.level === 'error', 'cell-warn': issue?.level === 'warning' }
}

function cellTitle(i: number, field: EntryField) {
  return issueFor(i, field)?.message
}

type Status = 'blank' | 'ok' | 'warn' | 'error' | 'pending'
function statusOf(i: number): Status {
  const p = props.parsed[i]
  const key = props.rows[i]?.key
  if (!p || p.blank) return 'blank'
  if (!p.draft) return key && props.touched.has(key) ? 'error' : 'pending'
  return p.issues.length > 0 ? 'warn' : 'ok'
}

function statusText(i: number): string {
  const p = props.parsed[i]
  if (!p || p.blank) return ''
  if (p.issues.length === 0) return 'Ready to save'
  return p.issues.map((x) => `${FIELD_LABELS[x.field]}: ${x.message}`).join('\n')
}

// ------------------------------------------------------------ navigation

function cellInput(row: number, col: number): HTMLInputElement | null {
  return table.value?.querySelector<HTMLInputElement>(`input[data-row="${row}"][data-col="${col}"]`) ?? null
}

async function focusCell(row: number, col: number) {
  await nextTick()
  let c = col
  let el = cellInput(row, c)
  // A disabled cell (To account on a non-transfer): the nearest one to its left.
  while (el?.disabled && c > 0) el = cellInput(row, --c)
  el?.focus()
}

async function moveTo(row: number, col: number, grow: boolean) {
  if (row < 0) return
  if (row >= props.rows.length) {
    if (!grow) return
    emit('addRows', 1)
  }
  await focusCell(row, col)
}

function fillDown(row: number, col: number) {
  const field = COLS[col]
  const above = props.rows[row - 1]
  if (!field || !above) return
  emit('edit', row, field, above.raw[field])
  // Refresh what the (uncontrolled while focused) text input shows.
  const el = cellInput(row, col)
  if (el && el.getAttribute('role') !== 'combobox') el.value = above.raw[field]
}

/** Leaves the focused cell so typed-but-unconfirmed text is committed. */
function commitFocusedCell() {
  const el = document.activeElement
  if (el instanceof HTMLInputElement && table.value?.contains(el)) {
    el.blur()
    return el
  }
  return null
}

function onKeydown(e: KeyboardEvent) {
  const target = e.target as HTMLElement
  const row = Number(target.dataset.row)
  const col = Number(target.dataset.col)
  if (!Number.isInteger(row) || !Number.isInteger(col)) return
  const mod = e.ctrlKey || e.metaKey

  if (mod && (e.key === 's' || e.key === 'S' || e.key === 'Enter')) {
    e.preventDefault()
    commitFocusedCell()
    emit('save')
    return
  }
  if (mod && (e.key === 'd' || e.key === 'D')) {
    e.preventDefault()
    fillDown(row, col)
    return
  }
  if (mod && e.key === ';' && COLS[col] === 'date') {
    e.preventDefault()
    emit('edit', row, 'date', formatDateIndian(props.context.today))
    ;(target as HTMLInputElement).value = formatDateIndian(props.context.today)
    return
  }
  if (e.altKey || mod) return
  if (e.key === 'Enter') {
    e.preventDefault()
    void moveTo(e.shiftKey ? row - 1 : row + 1, col, !e.shiftKey)
  } else if (e.key === 'ArrowDown') {
    e.preventDefault()
    void moveTo(row + 1, col, false)
  } else if (e.key === 'ArrowUp') {
    e.preventDefault()
    void moveTo(row - 1, col, false)
  }
}

function onPaste(e: ClipboardEvent) {
  const text = e.clipboardData?.getData('text/plain') ?? ''
  if (!looksLikeRows(text)) return // one value: a normal paste into the cell
  e.preventDefault()
  emit('paste', text)
}

function onRowFocusOut(e: FocusEvent, key: string) {
  const next = e.relatedTarget as Node | null
  const tr = e.currentTarget as HTMLElement
  if (!next || !tr.contains(next)) emit('touch', key)
}

function onText(i: number, field: EntryField, e: Event) {
  emit('edit', i, field, (e.target as HTMLInputElement).value)
}

defineExpose({
  focusCell,
  commitFocusedCell,
  focusFirstEmpty: () => {
    const i = props.parsed.findIndex((p) => p.blank)
    return focusCell(i >= 0 ? i : 0, COLS.indexOf('description'))
  },
})
</script>

<template>
  <!-- The scroll container both ways, no taller than the window: the header row
       (position: sticky) stays in view after pasting a long list. -->
  <div class="grid-scroller overflow-auto rounded-md border border-slate-300 bg-white" data-testid="grid-scroller">
    <table ref="table" class="entry-grid" aria-label="New transactions">
      <colgroup>
        <col style="width: 2.2rem" />
        <col style="width: 6.2rem" />
        <col />
        <col style="width: 6.4rem" />
        <col style="width: 7.6rem" />
        <col style="width: 10.2rem" />
        <col style="width: 8.8rem" />
        <col style="width: 6.8rem" />
        <col style="width: 6.2rem" />
        <col style="width: 2rem" />
        <col style="width: 2rem" />
      </colgroup>
      <thead>
        <tr>
          <th class="text-center">#</th>
          <th>Date</th>
          <th>Description</th>
          <th class="text-right">Amount (₹)</th>
          <th>Type</th>
          <th>Category <span class="font-normal text-slate-600">(optional)</span></th>
          <th>Account</th>
          <th>To account</th>
          <th>Paid by</th>
          <th><span class="sr-only">Status</span></th>
          <th><span class="sr-only">Remove</span></th>
        </tr>
      </thead>
      <tbody @keydown="onKeydown" @paste="onPaste">
        <tr
          v-for="(row, i) in rows"
          :key="row.key"
          :data-row-key="row.key"
          :data-status="statusOf(i)"
          @focusout="onRowFocusOut($event, row.key)"
        >
          <td class="rownum">{{ i + 1 }}</td>

          <td :class="cellClass(i, 'date')" :title="cellTitle(i, 'date')">
            <input
              :value="row.raw.date"
              :data-row="i"
              data-col="0"
              placeholder="dd/mm/yyyy"
              :aria-label="`Row ${i + 1} date`"
              :disabled="disabled"
              @input="onText(i, 'date', $event)"
              @focus="($event.target as HTMLInputElement).select()"
              @blur="emit('tidy', i, 'date')"
            />
          </td>

          <td :class="cellClass(i, 'description')" :title="cellTitle(i, 'description')">
            <div class="flex h-full items-center gap-1.5">
              <MerchantBadge :description="row.raw.description" :size="18" />
              <input
                :value="row.raw.description"
                :data-row="i"
                data-col="1"
                maxlength="500"
                :placeholder="i === 0 ? 'e.g. Swiggy dinner, DMart, Electricity bill' : ''"
                :aria-label="`Row ${i + 1} description`"
                :disabled="disabled"
                @input="onText(i, 'description', $event)"
                @blur="emit('tidy', i, 'description')"
              />
            </div>
          </td>

          <td :class="cellClass(i, 'amount')" :title="cellTitle(i, 'amount')">
            <input
              :value="row.raw.amount"
              :data-row="i"
              data-col="2"
              inputmode="decimal"
              class="text-right tabular-nums"
              :aria-label="`Row ${i + 1} amount`"
              :disabled="disabled"
              @input="onText(i, 'amount', $event)"
              @focus="($event.target as HTMLInputElement).select()"
              @blur="emit('tidy', i, 'amount')"
            />
          </td>

          <td :class="cellClass(i, 'type')" :title="cellTitle(i, 'type')">
            <ComboInput
              :model-value="row.raw.type"
              :options="TYPE_OPTIONS"
              :disabled="disabled"
              :aria-label="`Row ${i + 1} type`"
              :input-attrs="{ 'data-row': i, 'data-col': 3 }"
              @update:model-value="emit('edit', i, 'type', $event)"
            >
              <template #prefix>
                <AppIcon :name="TYPE_OPTIONS.find((o) => o.value === typeOf(row))!.icon.name" :size="19" class="text-slate-600" />
              </template>
              <template #option="{ option }">
                <AppIcon :name="option.icon.name" :size="19" class="text-slate-600" />{{ option.label }}
              </template>
            </ComboInput>
          </td>

          <td :class="[cellClass(i, 'category'), { 'cell-na': typeOf(row) === 'transfer' }]" :title="cellTitle(i, 'category')">
            <ComboInput
              :model-value="typeOf(row) === 'transfer' ? '' : row.raw.category"
              :options="categoryOpts(row)"
              :disabled="disabled || typeOf(row) === 'transfer'"
              :placeholder="typeOf(row) === 'transfer' ? '—' : 'Auto'"
              :aria-label="`Row ${i + 1} category`"
              :input-attrs="{ 'data-row': i, 'data-col': 4 }"
              @update:model-value="emit('edit', i, 'category', $event)"
            >
              <template #prefix>
                <TxnAvatar v-if="typeOf(row) === 'transfer'" kind="transfer" :size="24" />
                <TxnAvatar v-else-if="isAutoCategory(row.raw.category)" kind="auto" :size="24" />
                <TxnAvatar
                  v-else-if="matchCategory(row.raw.category, typeOf(row) === 'income' ? 'income' : 'expense', context.categories)"
                  :category="matchCategory(row.raw.category, typeOf(row) === 'income' ? 'income' : 'expense', context.categories)"
                  :size="24"
                />
                <TxnAvatar v-else kind="uncategorized" :size="24" />
              </template>
              <template #option="{ option }">
                <TxnAvatar v-if="option.category" :category="option.category" :size="24" />
                <TxnAvatar v-else kind="auto" :size="24" />
                {{ option.label }}
              </template>
            </ComboInput>
          </td>

          <td :class="cellClass(i, 'account')" :title="cellTitle(i, 'account')">
            <ComboInput
              :model-value="row.raw.account"
              :options="accountOpts"
              :disabled="disabled"
              :aria-label="`Row ${i + 1} account`"
              :input-attrs="{ 'data-row': i, 'data-col': 5 }"
              @update:model-value="emit('edit', i, 'account', $event)"
            >
              <template #prefix>
                <AppIcon
                  v-if="matchAccount(row.raw.account, context.accounts)"
                  :name="ACCOUNT_TYPES[matchAccount(row.raw.account, context.accounts)!.type].icon.name"
                  :filled="ACCOUNT_TYPES[matchAccount(row.raw.account, context.accounts)!.type].icon.filled"
                  :size="19"
                  :style="{ color: ACCOUNT_TYPES[matchAccount(row.raw.account, context.accounts)!.type].color }"
                />
              </template>
              <template #option="{ option }">
                <AccountAvatar :type="option.account.type" :size="24" />{{ option.label }}
              </template>
            </ComboInput>
          </td>

          <td :class="[cellClass(i, 'toAccount'), { 'cell-na': typeOf(row) !== 'transfer' }]" :title="cellTitle(i, 'toAccount')">
            <ComboInput
              :model-value="typeOf(row) === 'transfer' ? row.raw.toAccount : ''"
              :options="accountOpts"
              :disabled="disabled || typeOf(row) !== 'transfer'"
              :placeholder="typeOf(row) === 'transfer' ? 'Choose…' : '—'"
              :aria-label="`Row ${i + 1} to account`"
              :input-attrs="{ 'data-row': i, 'data-col': 6 }"
              @update:model-value="emit('edit', i, 'toAccount', $event)"
            >
              <template #option="{ option }">
                <AccountAvatar :type="option.account.type" :size="24" />{{ option.label }}
              </template>
            </ComboInput>
          </td>

          <td :class="cellClass(i, 'method')" :title="cellTitle(i, 'method')">
            <ComboInput
              :model-value="row.raw.method"
              :options="METHOD_OPTIONS"
              :disabled="disabled"
              :placeholder="typeOf(row) === 'expense' ? 'Choose…' : '—'"
              :aria-label="`Row ${i + 1} paid by`"
              :input-attrs="{ 'data-row': i, 'data-col': 7 }"
              @update:model-value="emit('edit', i, 'method', $event)"
            >
              <template #prefix>
                <AppIcon
                  v-if="METHOD_OPTIONS.find((o) => o.label === row.raw.method)"
                  :name="METHOD_OPTIONS.find((o) => o.label === row.raw.method)!.icon.name"
                  :filled="METHOD_OPTIONS.find((o) => o.label === row.raw.method)!.icon.filled"
                  :size="19"
                  class="text-slate-600"
                />
              </template>
              <template #option="{ option }">
                <AppIcon :name="option.icon.name" :filled="option.icon.filled" :size="19" class="text-slate-600" />{{ option.label }}
              </template>
            </ComboInput>
          </td>

          <td class="text-center" :title="statusText(i)">
            <AppIcon v-if="statusOf(i) === 'ok'" name="check_circle" :size="21" class="text-income" label="Ready" />
            <AppIcon v-else-if="statusOf(i) === 'warn'" name="warning" filled :size="21" class="text-uncat" label="Ready, with a note" />
            <AppIcon v-else-if="statusOf(i) === 'error'" name="error" filled :size="21" class="text-expense" label="Needs fixing" />
            <span v-else-if="statusOf(i) === 'pending'" class="text-slate-600">•</span>
          </td>

          <td class="text-center">
            <button
              type="button"
              tabindex="-1"
              class="rounded p-0.5 text-slate-600 hover:bg-red-50 hover:text-expense"
              :aria-label="`Remove row ${i + 1}`"
              :disabled="disabled"
              @click="emit('removeRow', i)"
            >
              <AppIcon name="close" :size="18" />
            </button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped>
.grid-scroller {
  /* The Add page's title and buttons above, the keyboard hints below. */
  max-height: calc(100vh - 11rem);
  min-height: 12rem;
}
.entry-grid {
  width: 100%;
  /* Below this the description column would be crushed: scroll instead. */
  min-width: 67rem;
  border-collapse: collapse;
  table-layout: fixed;
  font-size: var(--text-dense);
}
.entry-grid th {
  position: sticky;
  top: 0;
  z-index: 1;
  background: #eef2f7;
  color: #334155;
  font-weight: 600;
  font-size: 0.88rem;
  text-align: left;
  padding: 0.35rem 0.45rem;
  border-bottom: 1px solid #cbd5e1;
  border-right: 1px solid #dde3ea;
  white-space: nowrap;
}
.entry-grid td {
  height: 2.1rem;
  padding: 0 0.45rem;
  border-bottom: 1px solid #e5eaf0;
  border-right: 1px solid #e5eaf0;
  background: #fff;
}
.entry-grid td:focus-within {
  outline: 2px solid var(--p-primary-color);
  outline-offset: -2px;
  background: #f5f9ff;
}
.entry-grid td.rownum {
  text-align: center;
  color: #475569;
  background: #f8fafc;
  font-size: 0.88rem;
}
.entry-grid input {
  width: 100%;
  height: 100%;
  min-width: 0;
  background: transparent;
  outline: none;
}
/* Lighter than typed text, but readable (slate-500, 4.8:1). */
.entry-grid input::placeholder {
  color: #64748b;
}
/* Not used for this row's type (Category on a transfer, To account otherwise):
   grey, and its "—" is slate-600 (ComboInput), 6.9:1 on it; not faded. */
.entry-grid td.cell-na {
  background: #f1f5f9;
}
.entry-grid .cell-error {
  background: #fdecea;
  box-shadow: inset 3px 0 0 var(--color-expense);
}
.entry-grid .cell-warn {
  background: #fff6e5;
  box-shadow: inset 3px 0 0 var(--color-uncat);
}
.entry-grid tr[data-status='ok'] td.rownum {
  color: var(--color-income);
  font-weight: 600;
}
</style>
