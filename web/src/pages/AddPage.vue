<script setup lang="ts">
// Batch entry, like a spreadsheet (PRD § 4.2): blank rows to fill in with
// Tab/Enter, today's date (India) and the last-used account and payment
// method pre-filled, rows pasted from Excel previewed before saving, and
// the category each saved row got shown right away.
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { useConfirm } from 'primevue/useconfirm'
import { useToast } from 'primevue/usetoast'
import { computed, onMounted, ref, watch } from 'vue'
import AppIcon from '@/components/AppIcon.vue'
import EntryGrid from '@/components/add/EntryGrid.vue'
import PasteDialog from '@/components/add/PasteDialog.vue'
import SavedPanel from '@/components/add/SavedPanel.vue'
import { newRowKey, type GridRow } from '@/components/add/gridRow'
import { useApp } from '@/data/appContext'
import { formatDateIndian } from '@/lib/dates'
import {
  AUTO_CATEGORY,
  ENTRY_FIELDS,
  FIELD_LABELS,
  emptyRow,
  isAutoCategory,
  matchCategory,
  parseEntryRow,
  parseTxnType,
  tidyCell,
  type EntryContext,
  type EntryField,
  type RawRow,
} from '@/lib/entryRow'
import { describeError } from '@/lib/errors'
import { methodLabel, type Txn } from '@/lib/models'

/** Blank rows on a fresh page, and blank rows kept below the last filled one. */
const INITIAL_ROWS = 8
const BLANK_TAIL = 3

const app = useApp()
const toast = useToast()
const confirm = useConfirm()

const accounts = computed(() => app.accounts.data.value ?? [])
const categories = computed(() => app.categories.data.value ?? [])
const context = computed<EntryContext>(() => ({ accounts: accounts.value, categories: categories.value, today: app.today.value }))

// The remembered account / method live in localStorage (not reactive), so
// this counter makes `defaults` re-read them after a save.
const prefsVersion = ref(0)
const defaults = computed(() => {
  void prefsVersion.value
  const list = accounts.value
  const account =
    list.find((a) => a.id === app.prefs.lastAccountId) ?? list.find((a) => a.type === 'cash') ?? list[0] ?? null
  const method = app.prefs.lastMethod
  return { account: account?.name ?? '', method: method ? methodLabel(method) : '' }
})

function blankRow(): GridRow {
  return {
    key: newRowKey(),
    raw: emptyRow({
      date: formatDateIndian(app.today.value),
      type: 'Expense',
      category: AUTO_CATEGORY,
      account: defaults.value.account,
      method: defaults.value.method,
    }),
  }
}

const rows = ref<GridRow[]>(Array.from({ length: INITIAL_ROWS }, blankRow))
/** Rows the user has typed in (their pre-filled values are no longer ours to update). */
const edited = new Set<string>()
/** Rows the user has left at least once: only these show their problems. */
const touched = ref(new Set<string>())
const parsed = computed(() => rows.value.map((r) => parseEntryRow(r.raw, context.value)))
const readyCount = computed(() => parsed.value.filter((p) => p.draft).length)
const problemRows = computed(() =>
  rows.value
    .map((row, i) => ({ row, i, p: parsed.value[i]! }))
    .filter((x) => touched.value.has(x.row.key) && !x.p.blank && !x.p.draft),
)

const saving = ref(false)
const failure = ref<string | null>(null)
const sessionSaved = ref<Txn[]>([])
const grid = ref<InstanceType<typeof EntryGrid> | null>(null)

// Untouched blank rows follow the defaults: accounts arrive after the page
// opens, a save changes the remembered ones, and the date turns over at midnight.
watch([defaults, () => app.today.value], () => {
  rows.value.forEach((r, i) => {
    if (edited.has(r.key) || !parsed.value[i]?.blank) return
    r.raw.date = formatDateIndian(app.today.value)
    r.raw.account = defaults.value.account
    r.raw.method = defaults.value.method
  })
})

function ensureRows() {
  let lastFilled = -1
  parsed.value.forEach((p, i) => {
    if (!p.blank) lastFilled = i
  })
  const wanted = Math.max(INITIAL_ROWS, lastFilled + 1 + BLANK_TAIL)
  while (rows.value.length < wanted) rows.value.push(blankRow())
}

function onEdit(i: number, field: EntryField, value: string) {
  const row = rows.value[i]
  if (!row) return
  edited.add(row.key)
  row.raw[field] = value
  if (field === 'type') {
    // A category of the other kind can't stay (the phone does the same).
    const type = parseTxnType(value) ?? 'expense'
    if (type === 'transfer') row.raw.category = AUTO_CATEGORY
    else if (!isAutoCategory(row.raw.category) && !matchCategory(row.raw.category, type, categories.value)) {
      const otherKind = type === 'income' ? 'expense' : 'income'
      if (matchCategory(row.raw.category, otherKind, categories.value)) row.raw.category = AUTO_CATEGORY
    }
    if (type !== 'transfer') row.raw.toAccount = ''
  }
  ensureRows()
}

function onTidy(i: number, field: EntryField) {
  const row = rows.value[i]
  if (!row) return
  const tidy = tidyCell(field, row.raw[field], context.value, parseTxnType(row.raw.type) ?? 'expense')
  if (tidy !== row.raw[field]) row.raw[field] = tidy
}

function onTouch(key: string) {
  const i = rows.value.findIndex((r) => r.key === key)
  if (i >= 0 && !parsed.value[i]!.blank) touched.value.add(key)
}

function removeRow(i: number) {
  const [row] = rows.value.splice(i, 1)
  if (row) {
    touched.value.delete(row.key)
    edited.delete(row.key)
  }
  ensureRows()
}

function addRows(n: number) {
  for (let k = 0; k < n; k++) rows.value.push(blankRow())
}

/**
 * Saves every ready row (or only those in `only`). Rows with problems stay
 * in the grid, highlighted. A failed save changes nothing and says why;
 * retrying reuses the same ids, so nothing can be saved twice.
 */
async function save(only?: ReadonlySet<string>): Promise<boolean> {
  if (saving.value) return false
  const candidates = rows.value
    .map((row, i) => ({ row, p: parsed.value[i]! }))
    .filter((x) => !x.p.blank && (!only || only.has(x.row.key)))
  candidates.forEach((x) => touched.value.add(x.row.key))
  const ready = candidates.filter((x) => x.p.draft)
  const broken = candidates.length - ready.length
  if (ready.length === 0) {
    toast.add(
      broken
        ? { severity: 'warn', summary: 'Nothing saved', detail: `${broken} row${broken === 1 ? ' needs' : 's need'} fixing first. The red cells say why.`, life: 6000 }
        : { severity: 'info', summary: 'Nothing to save yet', detail: 'Type or paste some rows first.', life: 4000 },
    )
    return false
  }

  saving.value = true
  let saved: Txn[]
  try {
    app.requireOnline()
    saved = await app.repo.insertTransactions(ready.map((x) => ({ id: x.row.key, ...x.p.draft! })))
  } catch (e) {
    failure.value = describeError(e)
    return false
  } finally {
    saving.value = false
  }

  const savedKeys = new Set(saved.map((t) => t.id))
  rows.value = rows.value.filter((r) => !savedKeys.has(r.key))
  savedKeys.forEach((k) => {
    touched.value.delete(k)
    edited.delete(k)
  })
  sessionSaved.value = [...saved, ...sessionSaved.value]

  // Remembered for the next entry (a device preference, not data).
  const last = saved[saved.length - 1]
  if (last) {
    app.prefs.remember(last.accountId, last.paymentMethod)
    prefsVersion.value++
  }
  app.bump(['transactions'])
  // A category the database just created for a keyword: fetch it to show its name.
  if (saved.some((t) => t.categoryId && !categories.value.some((c) => c.id === t.categoryId))) app.bump(['categories'])
  ensureRows()

  const auto = saved.filter((t) => t.autoCategorized).length
  toast.add({
    severity: 'success',
    summary: `Saved ${saved.length} transaction${saved.length === 1 ? '' : 's'}`,
    detail: [
      auto ? `${auto} categorized automatically.` : '',
      broken ? `${broken} row${broken === 1 ? '' : 's'} still need${broken === 1 ? 's' : ''} fixing.` : '',
    ]
      .filter(Boolean)
      .join(' ') || undefined,
    life: 4000,
  })
  if (!only && broken === 0) void grid.value?.focusFirstEmpty()
  return true
}

async function saveFromGrid() {
  await save()
}

// ------------------------------------------------------------ paste

const pasteVisible = ref(false)
const pasteText = ref('')

function openPaste(text = '') {
  pasteText.value = text
  pasteVisible.value = true
}

/** Adds rows to the grid in place of the unused blank ones. */
function placeInGrid(newRows: GridRow[]) {
  const kept = rows.value.filter((r, i) => !(parsed.value[i]?.blank && !edited.has(r.key)))
  rows.value = [...kept, ...newRows]
  newRows.forEach((r) => edited.add(r.key))
  ensureRows()
}

async function savePasted(ready: RawRow[], problems: RawRow[]) {
  const readyRows = ready.map((raw) => ({ key: newRowKey(), raw: { ...raw } }))
  const brokenRows = problems.map((raw) => ({ key: newRowKey(), raw: { ...raw } }))
  // Into the grid first, so nothing is lost if saving fails.
  placeInGrid([...readyRows, ...brokenRows])
  brokenRows.forEach((r) => touched.value.add(r.key))
  pasteVisible.value = false
  await save(new Set(readyRows.map((r) => r.key)))
}

function pastedToGrid(raws: RawRow[]) {
  const newRows = raws.map((raw) => ({ key: newRowKey(), raw: { ...raw } }))
  placeInGrid(newRows)
  newRows.forEach((r) => touched.value.add(r.key))
  pasteVisible.value = false
  toast.add({ severity: 'info', summary: `${newRows.length} rows added to the grid`, detail: 'Check them, then Save.', life: 4000 })
}

// ------------------------------------------------------------ misc

function clearUnsaved() {
  const filled = parsed.value.filter((p) => !p.blank).length
  const reset = () => {
    rows.value = Array.from({ length: INITIAL_ROWS }, blankRow)
    touched.value.clear()
    edited.clear()
  }
  if (filled === 0) return reset()
  confirm.require({
    header: 'Clear the grid?',
    message: `This removes ${filled} unsaved row${filled === 1 ? '' : 's'}. Saved transactions are not affected.`,
    acceptLabel: 'Clear',
    rejectLabel: 'Keep',
    acceptProps: { severity: 'danger' },
    rejectProps: { severity: 'secondary', outlined: true },
    accept: reset,
  })
}

function focusProblem(i: number, field: EntryField) {
  void grid.value?.focusCell(i, ENTRY_FIELDS.indexOf(field))
}

function onPageKeydown(e: KeyboardEvent) {
  if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S') && !e.defaultPrevented) {
    e.preventDefault()
    void save()
  }
}

onMounted(() => void grid.value?.focusCell(0, ENTRY_FIELDS.indexOf('description')))
</script>

<template>
  <div class="flex flex-col gap-3" @keydown="onPageKeydown">
    <div class="flex items-start gap-4">
      <div class="min-w-0 flex-1">
        <h1 class="text-xl font-semibold text-slate-800">Add transactions</h1>
        <p class="text-sm text-slate-500">
          Fill in the rows like a spreadsheet, or paste rows copied from Excel. Category is optional: leave it on
          <strong>Auto</strong> and Ventrafin picks one from the description.
        </p>
      </div>
      <div class="flex shrink-0 flex-wrap justify-end gap-2">
      <Button label="Paste from Excel" severity="secondary" outlined data-testid="open-paste" @click="openPaste()">
        <template #icon><AppIcon name="content_paste" :size="17" /></template>
      </Button>
      <Button label="Add 5 rows" severity="secondary" outlined @click="addRows(5)">
        <template #icon><AppIcon name="playlist_add" :size="17" /></template>
      </Button>
      <Button label="Clear" severity="secondary" text @click="clearUnsaved">
        <template #icon><AppIcon name="clear_all" :size="17" /></template>
      </Button>
      <Button
        :label="readyCount ? `Save ${readyCount} row${readyCount === 1 ? '' : 's'}` : 'Save'"
        :loading="saving"
        data-testid="save-rows"
        @click="save()"
      >
        <template #icon><AppIcon name="check" :size="17" /></template>
      </Button>
      </div>
    </div>

    <div
      v-if="app.accounts.error.value && accounts.length === 0"
      class="card flex items-center gap-3 p-4 text-slate-700"
      role="alert"
    >
      <AppIcon name="cloud_off" :size="28" class="text-expense" />
      <span>Couldn't load your accounts. {{ describeError(app.accounts.error.value) }}</span>
      <Button label="Retry" size="small" @click="app.accounts.refresh()" />
    </div>

    <EntryGrid
      ref="grid"
      :rows="rows"
      :parsed="parsed"
      :context="context"
      :touched="touched"
      :disabled="saving"
      @edit="onEdit"
      @tidy="onTidy"
      @touch="onTouch"
      @add-rows="addRows"
      @remove-row="removeRow"
      @paste="openPaste"
      @save="saveFromGrid"
    />

    <div class="flex flex-wrap items-start gap-x-6 gap-y-1 text-xs text-slate-500">
      <span><kbd>Tab</kbd> next cell</span>
      <span><kbd>Enter</kbd> next row</span>
      <span><kbd>Ctrl</kbd>+<kbd>D</kbd> copy from the row above</span>
      <span><kbd>Ctrl</kbd>+<kbd>;</kbd> today</span>
      <span><kbd>Alt</kbd>+<kbd>↓</kbd> open a list</span>
      <span><kbd>Ctrl</kbd>+<kbd>S</kbd> save</span>
      <span>Dates are day/month/year. Amounts can have commas or ₹.</span>
    </div>

    <div v-if="problemRows.length" class="card border-red-200 bg-red-50/60 p-3 text-sm" role="status" data-testid="problems">
      <div class="mb-1 font-semibold text-expense">
        {{ problemRows.length }} row{{ problemRows.length === 1 ? '' : 's' }} can't be saved yet
      </div>
      <ul class="space-y-0.5">
        <li v-for="x in problemRows.slice(0, 8)" :key="x.row.key">
          <button type="button" class="text-left hover:underline" @click="focusProblem(x.i, x.p.issues.find((q) => q.level === 'error')!.field)">
            Row {{ x.i + 1 }}:
            {{
              x.p.issues
                .filter((q) => q.level === 'error')
                .map((q) => `${FIELD_LABELS[q.field]}: ${q.message}`)
                .join(' · ')
            }}
          </button>
        </li>
        <li v-if="problemRows.length > 8" class="text-slate-500">…and {{ problemRows.length - 8 }} more</li>
      </ul>
    </div>

    <SavedPanel v-if="sessionSaved.length" :saved="sessionSaved" :accounts="accounts" :categories="categories" />

    <PasteDialog
      v-if="pasteVisible"
      v-model:visible="pasteVisible"
      :initial-text="pasteText"
      :context="context"
      :defaults="defaults"
      :saving="saving"
      @save="savePasted"
      @to-grid="pastedToGrid"
    />

    <Dialog
      :visible="failure !== null"
      modal
      header="Not saved"
      :closable="false"
      :style="{ width: '28rem' }"
      data-testid="save-failed"
    >
      <div class="flex gap-3">
        <AppIcon name="error" filled :size="28" class="text-expense" />
        <div>
          <p>{{ failure }}</p>
          <p class="mt-2 text-slate-600">Your rows are still in the grid. Nothing was lost; try saving again.</p>
        </div>
      </div>
      <template #footer>
        <Button label="OK" autofocus @click="failure = null" />
      </template>
    </Dialog>

    <p v-if="sessionSaved.length === 0" class="text-xs text-slate-400">
      Saved rows leave the grid and appear here, with the category each one got.
    </p>
  </div>
</template>
