<script setup lang="ts">
// One month of transactions in a dense, editable table. Click a cell, or Tab
// to it and press Enter or F2, to edit it in place (Enter or Tab saves, Esc
// cancels, and focus goes back to the cell); changing a category teaches the
// database's learning trigger. Filters by account, category, type and text;
// the search can cover every month. Delete one row or several after confirming,
// with a few seconds to undo it. Updates live.
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable, { type DataTableCellEditCompleteEvent, type DataTableCellEditInitEvent } from 'primevue/datatable'
import Dialog from 'primevue/dialog'
import Select from 'primevue/select'
import Toast from 'primevue/toast'
import { useConfirm } from 'primevue/useconfirm'
import { computed, nextTick, reactive, ref, shallowRef, useId, watch } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import AccountAvatar from '@/components/AccountAvatar.vue'
import AppIcon from '@/components/AppIcon.vue'
import ComboInput from '@/components/ComboInput.vue'
import ExportDialog from '@/components/ExportDialog.vue'
import LoadError from '@/components/LoadError.vue'
import MerchantBadge from '@/components/MerchantBadge.vue'
import MonthSwitcher from '@/components/MonthSwitcher.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { useNotify } from '@/components/useNotify'
import { useApp } from '@/data/appContext'
import { submitOnEnter, vFocus } from '@/directives'
import { cellEdit, editorText, isEditableField, type EditableField } from '@/lib/cellEdit'
import { readableTextColor } from '@/lib/categoryStyle'
import {
  addDays,
  compareMonths,
  formatDateIndian,
  monthKey,
  monthLabel,
  monthOf,
  monthStart,
  nextMonth,
  parseMonthKey,
  shortWeekday,
  type YearMonth,
} from '@/lib/dates'
import type { EntryContext } from '@/lib/entryRow'
import { AppError, describeError } from '@/lib/errors'
import { formatRupees, formatRupeesCompact } from '@/lib/money'
import { ACCOUNT_TYPES, PAYMENT_METHODS, TXN_TYPES, activeOnly, pickerLabel, sortByName, type Txn, type TxnPatch } from '@/lib/models'
import {
  METHOD_OPTIONS,
  TYPE_FILTER_OPTIONS,
  TYPE_OPTIONS,
  accountOptions,
  categoryOptions,
  typeFilterFromQuery,
  type TypeFilter,
} from '@/lib/options'

const app = useApp()
const route = useRoute()
const router = useRouter()
const notify = useNotify()
const confirm = useConfirm()

// ------------------------------------------------------------ month & filters (kept in the URL)

const currentMonth = computed(() => monthOf(app.today.value))
const month = ref<YearMonth>(parseMonthKey(route.query.month) ?? currentMonth.value)
const accountFilter = ref<string>(typeof route.query.account === 'string' ? route.query.account : 'all')
const categoryFilter = ref<string>(typeof route.query.category === 'string' ? route.query.category : 'all')
const typeFilter = ref<TypeFilter>(typeFilterFromQuery(route.query.type))
const search = ref('')

watch([month, accountFilter, categoryFilter, typeFilter], () => {
  const query: Record<string, string> = { month: monthKey(month.value) }
  if (accountFilter.value !== 'all') query.account = accountFilter.value
  if (categoryFilter.value !== 'all') query.category = categoryFilter.value
  if (typeFilter.value !== 'all') query.type = typeFilter.value
  void router.replace({ query })
})

// Arriving again with other filters (the sidebar link, the Dashboard's
// "uncategorized" link) while this page is already open.
watch(
  () => route.query,
  (q) => {
    const m = parseMonthKey(q.month) ?? currentMonth.value
    if (compareMonths(m, month.value) !== 0) {
      month.value = m
      // Sent to a particular month (e.g. from the Dashboard): show that month.
      allMonths.value = false
    }
    const account = typeof q.account === 'string' ? q.account : 'all'
    if (account !== accountFilter.value) accountFilter.value = account
    const category = typeof q.category === 'string' ? q.category : 'all'
    if (category !== categoryFilter.value) categoryFilter.value = category
    const type = typeFilterFromQuery(q.type)
    if (type !== typeFilter.value) typeFilter.value = type
  },
)

// ------------------------------------------------------------ data

const txns = app.liveQuery(['transactions'], () => app.repo.fetchTransactions(month.value), () => monthKey(month.value))
const totals = app.liveQuery(['transactions'], () => app.repo.fetchMonthTotals(month.value), () => monthKey(month.value))

// "All months": the same search and filters over every transaction. The
// month stays as it was, so turning it off goes back to it. (Not kept in
// the URL.) Fetched only while it is on.
const allMonths = ref(false)
const everything = app.liveQuery(
  ['transactions'],
  async () => {
    if (!allMonths.value) return null
    const list = await app.repo.fetchTransactionsBetween('1900-01-01', '9999-12-31')
    // Newest first, like a month.
    return list.sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt))
  },
  () => allMonths.value,
)
/** What the table is built from: the month, or every transaction. */
const shownList = computed(() => (allMonths.value ? everything.data.value : txns.data.value) ?? undefined)
const shownError = computed(() => (allMonths.value ? everything.error.value : txns.error.value))
const shownLoading = computed(() => (allMonths.value ? everything.loading.value : txns.loading.value))
const reload = () => (allMonths.value ? everything.refresh() : txns.refresh())

const accounts = computed(() => app.accounts.data.value ?? [])
const categories = computed(() => app.categories.data.value ?? [])
const accountsById = computed(() => new Map(accounts.value.map((a) => [a.id, a])))
const categoriesById = computed(() => new Map(categories.value.map((c) => [c.id, c])))
const context = computed<EntryContext>(() => ({ accounts: accounts.value, categories: categories.value, today: app.today.value }))

/** Saved here but not yet back from the server: shown straight away. */
const pending = reactive(new Map<string, Partial<Txn>>())
/** Deleted here: hidden straight away. */
const hidden = reactive(new Set<string>())
const savingIds = reactive(new Set<string>())

// Once the server's list no longer has them, forget the hidden ids.
watch(shownList, (list) => {
  if (!list) return
  const ids = new Set(list.map((t) => t.id))
  for (const id of hidden) if (!ids.has(id)) hidden.delete(id)
})

interface Row extends Txn {
  categoryName: string
  accountName: string
  methodName: string
}

const allRows = computed<Row[]>(() =>
  (shownList.value ?? [])
    .filter((t) => !hidden.has(t.id))
    .map((t) => {
      const merged = { ...t, ...pending.get(t.id) }
      return {
        ...merged,
        categoryName:
          merged.type === 'transfer'
            ? 'Transfer'
            : merged.categoryId
              ? (categoriesById.value.get(merged.categoryId)?.name ?? '…')
              : 'Uncategorized',
        accountName: accountsById.value.get(merged.accountId)?.name ?? '…',
        methodName: merged.paymentMethod ? PAYMENT_METHODS.find((m) => m.value === merged.paymentMethod)!.label : '',
      }
    }),
)

/** A search or filter is narrowing the list down. */
const narrowing = computed(
  () => search.value.trim() !== '' || accountFilter.value !== 'all' || categoryFilter.value !== 'all' || typeFilter.value !== 'all',
)

const rows = computed(() => {
  const q = search.value.trim().toLowerCase()
  // Every month is only listed as a search: nothing until there is one.
  if (allMonths.value && !narrowing.value) return []
  return allRows.value.filter((t) => {
    if (accountFilter.value !== 'all' && t.accountId !== accountFilter.value && t.toAccountId !== accountFilter.value) return false
    if (typeFilter.value !== 'all' && t.type !== typeFilter.value) return false
    switch (categoryFilter.value) {
      case 'all':
        break
      case 'uncategorized':
        if (t.type === 'transfer' || t.categoryId !== null) return false
        break
      case 'transfers':
        if (t.type !== 'transfer') return false
        break
      default:
        if (t.categoryId !== categoryFilter.value) return false
    }
    return !q || t.description.toLowerCase().includes(q) || t.categoryName.toLowerCase().includes(q)
  })
})

const filtered = computed(() => rows.value.length !== allRows.value.length)
const viewSpent = computed(() => rows.value.filter((t) => t.type === 'expense').reduce((s, t) => s + t.amountPaise, 0))
const viewIncome = computed(() => rows.value.filter((t) => t.type === 'income').reduce((s, t) => s + t.amountPaise, 0))

// The filters list archived accounts and categories too: old entries use them.
const accountFilterOptions = computed(() => [
  { value: 'all', label: 'All accounts', type: null },
  ...accounts.value.map((a) => ({ value: a.id, label: pickerLabel(a), type: a.type })),
])
const categoryFilterOptions = computed(() => [
  { value: 'all', label: 'All categories', kind: 'all' as const, category: null },
  { value: 'uncategorized', label: 'Uncategorized', kind: 'uncategorized' as const, category: null },
  { value: 'transfers', label: 'Transfers', kind: 'transfer' as const, category: null },
  ...sortByName(categories.value).map((c) => ({ value: c.id, label: pickerLabel(c), kind: 'category' as const, category: c })),
])

// ------------------------------------------------------------ export (CSV)

const exportVisible = ref(false)
/** The export dialog's first choice: this month, only the rows shown when filtered. */
const shownForExport = computed(() => {
  if (allMonths.value) {
    const ids = rows.value.map((t) => t.id)
    return { range: { from: null, to: null }, ids, count: ids.length, label: 'All months, filtered as on screen' }
  }
  const narrowed = filtered.value || search.value.trim() !== ''
  return {
    range: { from: monthStart(month.value), to: addDays(monthStart(nextMonth(month.value)), -1) },
    ids: narrowed ? rows.value.map((t) => t.id) : null,
    count: rows.value.length,
    label: narrowed ? `${monthLabel(month.value)}, filtered as on screen` : monthLabel(month.value),
  }
})

function clearFilters() {
  accountFilter.value = 'all'
  categoryFilter.value = 'all'
  typeFilter.value = 'all'
  search.value = ''
}

// ------------------------------------------------------------ editing

const edit = reactive<{ id: string; field: EditableField | null; text: string }>({ id: '', field: null, text: '' })
/** The table cell being edited, to put the focus back on it afterwards. */
let editCell: HTMLElement | null = null

/** Editable cells are Tab stops (Column pt), so the table works without a mouse. */
const CELL_PT = { bodyCell: { tabindex: 0 } }
const AMOUNT_PT = { ...CELL_PT, columnHeaderContent: { class: 'justify-end' } }

/**
 * Keys on a focused cell that isn't being edited (capture phase, before
 * PrimeVue's own handler): Enter or F2 starts editing, as in Excel; Tab
 * just moves on to the next cell (PrimeVue would start editing it).
 */
function onTableKeydown(e: KeyboardEvent) {
  const cell = e.target
  if (!(cell instanceof HTMLTableCellElement)) return
  if (cell.getAttribute('data-p-editable-column') !== 'true' || cell.getAttribute('data-p-cell-editing') === 'true') return
  if (e.key === 'Enter' || e.key === 'F2') {
    e.preventDefault()
    e.stopPropagation()
    cell.click()
  } else if (e.key === 'Tab' || e.key === 'Escape') {
    e.stopPropagation()
  }
}

/** Back to the cell that was edited (Enter or Esc), unless something else has taken the focus. */
function refocusCell() {
  const cell = editCell
  // Two ticks: PrimeVue switches the cell back to view mode (removing the
  // editor, and the focus with it) in the render after this one.
  void nextTick()
    .then(() => nextTick())
    .then(() => {
      const lost = !document.activeElement || document.activeElement === document.body
      if (cell?.isConnected && lost && transfer.txn === null) cell.focus()
    })
}

function onEditInit(e: DataTableCellEditInitEvent) {
  const t = e.data as Row
  if (!isEditableField(e.field)) return
  edit.id = t.id
  edit.field = e.field
  edit.text = editorText(t, e.field, context.value)
  const target = e.originalEvent.target
  editCell = target instanceof Element ? target.closest('td') : null
}

function onEditCancel() {
  edit.field = null
  refocusCell()
}

function onEditComplete(e: DataTableCellEditCompleteEvent) {
  const t = e.data as Row
  if (edit.id !== t.id || edit.field !== e.field || !isEditableField(e.field)) return
  const field = e.field
  const text = edit.text
  edit.field = null
  // Enter: stay on the cell. Tab moves on to the next one; a click went elsewhere.
  if (e.type === 'enter') refocusCell()
  const result = cellEdit(t, field, text, context.value)
  switch (result.kind) {
    case 'unchanged':
      return
    case 'invalid':
      notify.warn('Not changed', { detail: result.message })
      return
    case 'needsTransferTarget':
      askTransferTarget(t)
      return
    case 'patch':
      void applyPatch(t, result.patch)
  }
}

async function applyPatch(t: Txn, patch: TxnPatch) {
  try {
    app.requireOnline()
  } catch (e) {
    notify.error('Not saved', describeError(e))
    return
  }
  pending.set(t.id, { ...pending.get(t.id), ...patch })
  savingIds.add(t.id)
  try {
    const updated = await app.repo.updateTransaction(t.id, patch)
    if (txns.data.value) txns.data.value = txns.data.value.map((x) => (x.id === updated.id ? updated : x))
    if (everything.data.value) everything.data.value = everything.data.value.map((x) => (x.id === updated.id ? updated : x))
    pending.delete(t.id)
    app.bump(['transactions'])
    if (updated.categoryId && !categoriesById.value.has(updated.categoryId)) app.bump(['categories'])
    if (patch.categoryId) {
      notify.success('Category saved', { detail: 'Ventrafin will use it for similar descriptions from now on, on the phone too.' })
    }
    if (patch.date && !allMonths.value && compareMonths(monthOf(patch.date), month.value) !== 0) {
      notify.info(`Moved to ${monthLabel(monthOf(patch.date))}`, { life: 4000 })
    }
  } catch (e) {
    pending.delete(t.id)
    notify.error('Not saved', `${describeError(e)} The previous value is back.`)
    if (e instanceof AppError && e.code === 'PGRST116') app.bump(['transactions'])
  } finally {
    savingIds.delete(t.id)
  }
}

// Changing a row to a transfer: which (active) account did the money go to?
const transfer = reactive<{ txn: Txn | null; to: string | null }>({ txn: null, to: null })
const transferTargets = computed(() => activeOnly(accounts.value).filter((a) => a.id !== transfer.txn?.accountId))
const transferFormId = useId()

function askTransferTarget(t: Txn) {
  transfer.txn = t
  transfer.to = transferTargets.value[0]?.id ?? null
}

function confirmTransfer() {
  const t = transfer.txn
  if (!t || !transfer.to) return
  transfer.txn = null
  void applyPatch(t, { type: 'transfer', toAccountId: transfer.to, categoryId: null })
}

// ------------------------------------------------------------ deleting

const selected = ref<Row[]>([])
// Only ever delete what is on screen.
watch([month, accountFilter, categoryFilter, typeFilter, search, allMonths], () => (selected.value = []))

function describeTxn(t: Txn) {
  return `${formatRupees(t.amountPaise)} · ${t.description || '(no description)'} · ${formatDateIndian(t.date)}`
}

function confirmDelete(list: Txn[]) {
  if (list.length === 0) return
  confirm.require({
    header: list.length === 1 ? 'Delete this transaction?' : `Delete ${list.length} transactions?`,
    message:
      list.length === 1
        ? `${describeTxn(list[0]!)}.`
        : `${list.length} transactions, ${formatRupees(list.reduce((s, t) => s + t.amountPaise, 0))} in total.`,
    acceptLabel: 'Delete',
    rejectLabel: 'Cancel',
    // Enter or a stray key doesn't delete.
    defaultFocus: 'reject',
    acceptProps: { severity: 'danger' },
    rejectProps: { severity: 'secondary', outlined: true },
    accept: () => void deleteTxns(list),
  })
}

/** How long "Deleted … Undo" stays up. */
const UNDO_MS = 5000
/** The rows of the last delete, as they were, while its Undo is offered. */
const undoable = shallowRef<Txn[] | null>(null)

async function deleteTxns(list: Txn[]) {
  const ids = list.map((t) => t.id)
  try {
    app.requireOnline()
  } catch (e) {
    notify.error('Not deleted', describeError(e))
    return
  }
  ids.forEach((id) => hidden.add(id))
  try {
    const n = await app.repo.deleteTransactions(ids)
    selected.value = selected.value.filter((t) => !ids.includes(t.id))
    app.bump(['transactions'])
    // One Undo at a time: the latest delete's.
    notify.removeGroup('undo')
    undoable.value = list.map(plainTxn)
    notify.success(`Deleted ${n} transaction${n === 1 ? '' : 's'}`, { group: 'undo', life: UNDO_MS })
    if (n < ids.length) notify.info(`${ids.length - n} had already been deleted (perhaps on the phone).`)
  } catch (e) {
    ids.forEach((id) => hidden.delete(id))
    notify.error('Not deleted', describeError(e))
  }
}

/** A Txn without the table's display fields. */
function plainTxn(t: Txn): Txn {
  return {
    id: t.id,
    date: t.date,
    amountPaise: t.amountPaise,
    description: t.description,
    type: t.type,
    accountId: t.accountId,
    toAccountId: t.toAccountId,
    categoryId: t.categoryId,
    paymentMethod: t.paymentMethod,
    autoCategorized: t.autoCategorized,
    createdAt: t.createdAt,
    updatedAt: t.updatedAt,
  }
}

/** Undo: the deleted rows go back with their ids and every field they had. */
async function undoDelete() {
  const list = undoable.value
  undoable.value = null
  notify.removeGroup('undo')
  if (!list) return
  try {
    app.requireOnline()
    // A restored row's category counts as chosen by Dad (auto_categorized
    // is only ever set by the database's own guess), so it stays exactly as
    // it was and is not guessed again.
    await app.repo.insertTransactions(
      list.map((t) => ({
        id: t.id,
        date: t.date,
        amountPaise: t.amountPaise,
        description: t.description,
        type: t.type,
        accountId: t.accountId,
        toAccountId: t.toAccountId,
        categoryId: t.categoryId,
        paymentMethod: t.paymentMethod,
      })),
    )
    list.forEach((t) => hidden.delete(t.id))
    app.bump(['transactions'])
    notify.success(`Restored ${list.length} transaction${list.length === 1 ? '' : 's'}`)
  } catch (e) {
    notify.error('Not restored', describeError(e))
  }
}

function amountClass(t: Txn) {
  return t.type === 'expense' ? 'text-expense' : t.type === 'income' ? 'text-income' : 'text-transfer'
}

/** A row being saved: tinted and marked "Saving…" (not faded, so it stays readable). */
function rowClass(t: Row) {
  return savingIds.has(t.id) ? 'row-saving' : ''
}
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-2">
    <!-- Two rows, so it fits 1280 px (1080p at 150 %) without wrapping: the month and actions, then search and filters. -->
    <div class="flex flex-wrap items-center gap-2">
      <h1 class="mr-1 text-xl font-semibold text-slate-800">Transactions</h1>
      <MonthSwitcher v-model="month" :max="currentMonth" :all-label="allMonths ? 'All months' : null" />
      <div class="ml-auto flex gap-2">
        <Button
          v-if="selected.length"
          :label="`Delete ${selected.length} selected`"
          severity="danger"
          outlined
          data-testid="delete-selected"
          @click="confirmDelete(selected)"
        >
          <template #icon><AppIcon name="delete" :size="20" /></template>
        </Button>
        <Button label="Export" severity="secondary" outlined data-testid="open-export" @click="exportVisible = true">
          <template #icon><AppIcon name="download" :size="20" /></template>
        </Button>
        <RouterLink v-slot="{ navigate }" to="/add" custom>
          <Button label="Add" @click="navigate">
            <template #icon><AppIcon name="add" :size="20" /></template>
          </Button>
        </RouterLink>
      </div>
    </div>
    <div class="flex flex-wrap items-center gap-2" data-testid="txn-filters">
      <span class="relative">
        <AppIcon name="search" :size="20" class="pointer-events-none absolute top-1/2 left-2 -translate-y-1/2 text-slate-600" />
        <input
          v-model="search"
          type="search"
          :placeholder="allMonths ? 'Search every month' : 'Search descriptions'"
          aria-label="Search descriptions"
          class="focus-ring h-[2.35rem] w-52 rounded-md border border-slate-300 bg-white pr-2 pl-8 placeholder:text-slate-500 focus:border-primary"
          data-testid="search"
        />
      </span>
      <label
        class="inline-flex h-[2.35rem] cursor-pointer items-center gap-1.5 rounded-md border px-2.5 select-none"
        :class="allMonths ? 'border-primary bg-primary-soft font-semibold text-primary' : 'border-slate-300 bg-white text-slate-700 hover:bg-slate-50'"
        title="Search and filter every month, not just the one shown"
      >
        <input v-model="allMonths" type="checkbox" class="h-4 w-4 accent-[var(--vf-primary)]" data-testid="all-months" />
        All months
      </label>
      <Select
        v-model="accountFilter"
        :options="accountFilterOptions"
        option-label="label"
        option-value="value"
        aria-label="Account"
        class="w-44"
        data-testid="account-filter"
      >
        <template #option="{ option }">
          <span class="flex items-center gap-2">
            <AccountAvatar v-if="option.type" :type="option.type" :size="24" />
            <AppIcon v-else name="account_balance_wallet" :size="22" class="text-slate-600" />{{ option.label }}
          </span>
        </template>
      </Select>
      <Select
        v-model="categoryFilter"
        :options="categoryFilterOptions"
        option-label="label"
        option-value="value"
        filter
        filter-placeholder="Find a category"
        aria-label="Category"
        class="w-52"
        data-testid="category-filter"
      >
        <template #option="{ option }">
          <span class="flex items-center gap-2">
            <TxnAvatar v-if="option.kind === 'category'" :category="option.category" :size="24" />
            <TxnAvatar v-else-if="option.kind === 'uncategorized'" kind="uncategorized" :size="24" />
            <TxnAvatar v-else-if="option.kind === 'transfer'" kind="transfer" :size="24" />
            <AppIcon v-else name="category" :size="22" class="text-slate-600" />
            {{ option.label }}
            <span v-if="option.category" class="ml-auto pl-2 text-sm text-slate-600">{{ option.category.kind }}</span>
          </span>
        </template>
      </Select>
      <Select
        v-model="typeFilter"
        :options="TYPE_FILTER_OPTIONS"
        option-label="label"
        option-value="value"
        aria-label="Type"
        class="w-40"
        data-testid="type-filter"
      >
        <template #option="{ option }">
          <span class="flex items-center gap-2"><AppIcon :name="option.icon" :size="20" class="text-slate-600" />{{ option.label }}</span>
        </template>
      </Select>
      <Button v-if="filtered || search || typeFilter !== 'all'" label="Clear filters" severity="secondary" text size="small" @click="clearFilters">
        <template #icon><AppIcon name="filter_alt_off" :size="19" /></template>
      </Button>
    </div>

    <div v-if="allMonths" class="card flex flex-wrap items-center gap-x-6 gap-y-1 px-3 py-2" data-testid="month-summary">
      <span class="font-semibold">Searching all months</span>
      <span v-if="narrowing && everything.data.value" class="text-slate-700">
        {{ rows.length }} match{{ rows.length === 1 ? '' : 'es' }} · spent
        <strong class="text-expense tabular-nums">{{ formatRupeesCompact(viewSpent) }}</strong>
        <template v-if="viewIncome"> · income <strong class="text-income tabular-nums">{{ formatRupeesCompact(viewIncome) }}</strong></template>
      </span>
      <button type="button" class="ml-auto text-sm text-primary hover:underline" @click="allMonths = false">
        Back to {{ monthLabel(month) }}
      </button>
    </div>
    <div v-else class="card flex flex-wrap items-center gap-x-6 gap-y-1 px-3 py-2" data-testid="month-summary">
      <span>Spent <strong class="text-expense tabular-nums">{{ totals.data.value ? formatRupeesCompact(totals.data.value.expensePaise) : '…' }}</strong></span>
      <span>Income <strong class="text-income tabular-nums">{{ totals.data.value ? formatRupeesCompact(totals.data.value.incomePaise) : '…' }}</strong></span>
      <span>
        Net
        <strong class="tabular-nums">{{
          totals.data.value ? formatRupeesCompact(totals.data.value.incomePaise - totals.data.value.expensePaise) : '…'
        }}</strong>
      </span>
      <button
        type="button"
        class="hover:underline"
        :class="(totals.data.value?.uncategorizedCount ?? 0) > 0 ? 'font-semibold text-uncat-ink' : 'text-slate-600'"
        @click="categoryFilter = 'uncategorized'"
      >
        Uncategorized {{ totals.data.value?.uncategorizedCount ?? '…' }}
      </button>
      <span class="ml-auto text-sm text-slate-600" data-testid="row-count">
        <template v-if="filtered">
          Showing {{ rows.length }} of {{ allRows.length }} · spent {{ formatRupeesCompact(viewSpent) }}
          <template v-if="viewIncome"> · income {{ formatRupeesCompact(viewIncome) }}</template>
        </template>
        <template v-else>{{ allRows.length }} transaction{{ allRows.length === 1 ? '' : 's' }}</template>
        · click a cell, or Tab to it and press Enter, to edit it
      </span>
    </div>

    <LoadError
      v-if="shownError && !shownList"
      :error="shownError"
      :what="allMonths ? `Couldn't search all months.` : `Couldn't load ${monthLabel(month)}.`"
      @retry="reload()"
    />

    <div v-else class="card min-h-0 flex-1 overflow-hidden" @keydown.capture="onTableKeydown">
      <DataTable
        v-model:selection="selected"
        :value="rows"
        data-key="id"
        edit-mode="cell"
        size="small"
        scrollable
        scroll-height="flex"
        striped-rows
        removable-sort
        :loading="shownLoading && !shownList"
        :row-class="rowClass"
        class="txn-table h-full"
        data-testid="txn-table"
        @cell-edit-init="onEditInit"
        @cell-edit-complete="onEditComplete"
        @cell-edit-cancel="onEditCancel"
      >
        <template #empty>
          <div class="py-8 text-center text-slate-600">
            <template v-if="allMonths && !narrowing">
              Type in the search box, or pick an account or category, to search every month.
            </template>
            <template v-else-if="filtered || search">
              No transactions match the filters.
              <button type="button" class="text-primary hover:underline" @click="clearFilters">Clear filters</button>
            </template>
            <template v-else>
              No transactions in {{ monthLabel(month) }}.
              <RouterLink to="/add" class="text-primary hover:underline">Add some</RouterLink>
            </template>
          </div>
        </template>

        <Column selection-mode="multiple" header-style="width: 2.4rem" />

        <Column field="date" header="Date" sortable style="width: 7.8rem" body-class="whitespace-nowrap" :pt="CELL_PT">
          <template #body="{ data }">
            <span class="tabular-nums">{{ formatDateIndian(data.date) }}</span>
            <span class="ml-1 text-sm text-slate-600">{{ shortWeekday(data.date) }}</span>
          </template>
          <template #editor>
            <input v-model="edit.text" v-focus class="cell-editor" aria-label="Date (dd/mm/yyyy)" placeholder="dd/mm/yyyy" />
          </template>
        </Column>

        <Column field="description" header="Description" sortable style="width: 100%; min-width: 8rem" :pt="CELL_PT">
          <template #body="{ data }">
            <!-- w-0 + min-w-full: the text truncates instead of widening the table. -->
            <span class="flex w-0 min-w-full items-center gap-2">
              <TxnAvatar v-if="data.type === 'transfer'" kind="transfer" :size="28" />
              <TxnAvatar v-else-if="!data.categoryId" kind="uncategorized" :size="28" />
              <TxnAvatar v-else :category="categoriesById.get(data.categoryId) ?? null" :size="28" />
              <MerchantBadge :description="data.description" :size="18" />
              <span class="truncate" :class="data.description ? '' : 'italic text-slate-600'">{{ data.description || '(no description)' }}</span>
              <span v-if="savingIds.has(data.id)" class="ml-auto shrink-0 text-sm font-semibold text-primary" data-testid="row-saving">Saving…</span>
            </span>
          </template>
          <template #editor>
            <input v-model="edit.text" v-focus maxlength="500" class="cell-editor" aria-label="Description" />
          </template>
        </Column>

        <Column field="categoryId" sort-field="categoryName" header="Category" sortable style="width: 10rem" :pt="CELL_PT">
          <template #body="{ data }">
            <span v-if="data.type === 'transfer'" class="font-medium text-transfer">Transfer</span>
            <span
              v-else-if="!data.categoryId"
              class="rounded border border-amber-400/70 bg-amber-50 px-1.5 py-px text-sm text-uncat-ink"
              data-testid="uncategorized-chip"
              >Uncategorized</span
            >
            <span v-else class="inline-flex items-center gap-1.5">
              <span
                class="font-semibold"
                :style="{ color: readableTextColor(categoriesById.get(data.categoryId)?.color ?? '#546E7A') }"
                >{{ data.categoryName }}</span
              >
              <span v-if="data.autoCategorized" class="text-sm text-slate-600" title="Chosen automatically">auto</span>
            </span>
          </template>
          <template #editor="{ data }">
            <!-- Read-only but focusable, so Tab carries on through the row. -->
            <input v-if="data.type === 'transfer'" v-focus readonly class="cell-editor" placeholder="Transfers have no category" />
            <ComboInput
              v-else
              v-model="edit.text"
              :options="categoryOptions(categories, data.type === 'income' ? 'income' : 'expense', data.categoryId)"
              placeholder="Auto"
              autofocus
              aria-label="Category"
            >
              <template #option="{ option }">
                <TxnAvatar v-if="option.category" :category="option.category" :size="24" />
                <TxnAvatar v-else kind="auto" :size="24" />
                {{ option.label }}
              </template>
            </ComboInput>
          </template>
        </Column>

        <Column
          field="amountPaise"
          header="Amount (₹)"
          sortable
          style="width: 8.5rem"
          body-class="text-right whitespace-nowrap"
          :pt="AMOUNT_PT"
        >
          <template #body="{ data }">
            <span class="font-semibold tabular-nums" :class="amountClass(data)">{{ data.type === 'income' ? '+' : '' }}{{ formatRupees(data.amountPaise) }}</span>
          </template>
          <template #editor>
            <input v-model="edit.text" v-focus inputmode="decimal" class="cell-editor text-right" aria-label="Amount" />
          </template>
        </Column>

        <Column field="type" header="Type" sortable style="width: 7rem" body-class="whitespace-nowrap" :pt="CELL_PT">
          <template #body="{ data }">
            <span class="inline-flex items-center gap-1 text-slate-600">
              <AppIcon :name="TXN_TYPES.find((x) => x.value === data.type)!.icon.name" :size="18" />
              {{ TXN_TYPES.find((x) => x.value === data.type)!.label }}
            </span>
          </template>
          <template #editor>
            <ComboInput v-model="edit.text" :options="TYPE_OPTIONS" autofocus aria-label="Type">
              <template #option="{ option }"><AppIcon :name="option.icon.name" :size="19" />{{ option.label }}</template>
            </ComboInput>
          </template>
        </Column>

        <Column
          field="accountId"
          sort-field="accountName"
          header="Account"
          sortable
          style="width: 9rem"
          body-class="whitespace-nowrap"
          :pt="CELL_PT"
        >
          <template #body="{ data }">
            <span class="inline-flex items-center gap-1.5 text-slate-700">
              <AppIcon
                v-if="accountsById.get(data.accountId)"
                :name="ACCOUNT_TYPES[accountsById.get(data.accountId)!.type].icon.name"
                :filled="ACCOUNT_TYPES[accountsById.get(data.accountId)!.type].icon.filled"
                :size="18"
                :style="{ color: ACCOUNT_TYPES[accountsById.get(data.accountId)!.type].color }"
              />
              {{ data.accountName }}
            </span>
          </template>
          <template #editor="{ data }">
            <!-- Active accounts, plus this row's own even if it has been archived. -->
            <ComboInput v-model="edit.text" :options="accountOptions(accounts, data.accountId)" autofocus aria-label="Account">
              <template #option="{ option }"><AccountAvatar :type="option.account.type" :size="24" />{{ option.label }}</template>
            </ComboInput>
          </template>
        </Column>

        <Column field="toAccountId" header="To" style="width: 8rem" body-class="whitespace-nowrap" :pt="CELL_PT">
          <template #body="{ data }">
            <span v-if="data.toAccountId" class="inline-flex items-center gap-1 text-slate-700">
              <AppIcon name="arrow_forward" :size="17" class="text-slate-600" />{{ accountsById.get(data.toAccountId)?.name ?? '…' }}
            </span>
          </template>
          <template #editor="{ data }">
            <input v-if="data.type !== 'transfer'" v-focus readonly class="cell-editor" placeholder="Only for transfers" />
            <ComboInput v-else v-model="edit.text" :options="accountOptions(accounts, data.toAccountId)" autofocus aria-label="To account">
              <template #option="{ option }"><AccountAvatar :type="option.account.type" :size="24" />{{ option.label }}</template>
            </ComboInput>
          </template>
        </Column>

        <Column
          field="paymentMethod"
          sort-field="methodName"
          header="Paid by"
          sortable
          style="width: 7rem"
          body-class="whitespace-nowrap"
          :pt="CELL_PT"
        >
          <template #body="{ data }">
            <span v-if="data.paymentMethod" class="inline-flex items-center gap-1 text-slate-600">
              <AppIcon
                :name="PAYMENT_METHODS.find((m) => m.value === data.paymentMethod)!.icon.name"
                :filled="PAYMENT_METHODS.find((m) => m.value === data.paymentMethod)!.icon.filled"
                :size="18"
              />{{ data.methodName }}
            </span>
          </template>
          <template #editor>
            <ComboInput v-model="edit.text" :options="METHOD_OPTIONS" autofocus aria-label="Paid by">
              <template #option="{ option }">
                <AppIcon :name="option.icon.name" :filled="option.icon.filled" :size="19" />{{ option.label }}
              </template>
            </ComboInput>
          </template>
        </Column>

        <Column header="" style="width: 2.6rem">
          <template #body="{ data }">
            <button
              type="button"
              class="flex rounded p-1 text-slate-600 hover:bg-red-50 hover:text-expense"
              :aria-label="`Delete ${describeTxn(data)}`"
              data-testid="delete-row"
              @click="confirmDelete([data])"
            >
              <AppIcon name="delete" :size="20" />
            </button>
          </template>
        </Column>
      </DataTable>
    </div>

    <Dialog
      :visible="transfer.txn !== null"
      modal
      header="Change to a transfer"
      :style="{ width: '26rem' }"
      @update:visible="(v: boolean) => !v && (transfer.txn = null)"
    >
      <form :id="transferFormId" @submit.prevent="confirmTransfer" @keydown="submitOnEnter">
        <p class="mb-3 text-slate-600">
          A transfer moves money between your own accounts, from
          <strong>{{ accountsById.get(transfer.txn?.accountId ?? '')?.name }}</strong> to:
        </p>
        <div role="radiogroup" aria-label="To account" class="flex flex-col gap-1" data-testid="transfer-targets">
          <label
            v-for="a in transferTargets"
            :key="a.id"
            class="flex cursor-pointer items-center gap-2 rounded-md border px-3 py-1.5"
            :class="transfer.to === a.id ? 'border-primary bg-primary-soft' : 'border-slate-200 hover:bg-slate-50'"
          >
            <input
              v-model="transfer.to"
              type="radio"
              name="transfer-to"
              :value="a.id"
              :autofocus="transfer.to === a.id"
              class="accent-[var(--vf-primary)]"
            />
            <AccountAvatar :type="a.type" :size="24" />
            {{ a.name }}
          </label>
        </div>
        <p class="mt-3 text-sm text-slate-600">Transfers have no category and don't count as spending.</p>
      </form>
      <template #footer>
        <Button label="Cancel" severity="secondary" text @click="transfer.txn = null" />
        <Button type="submit" :form="transferFormId" label="Make it a transfer" :disabled="!transfer.to" />
      </template>
    </Dialog>

    <ExportDialog v-if="exportVisible" v-model:visible="exportVisible" :shown="shownForExport" />

    <!-- "Deleted … Undo", bottom right, apart from the other messages. -->
    <Toast group="undo" position="bottom-right" @life-end="undoable = null" @close="undoable = null">
      <template #message="{ message }">
        <div class="flex flex-1 items-center gap-3" data-testid="undo-toast">
          <AppIcon name="check_circle" :size="22" class="shrink-0" />
          <span class="flex-1 font-semibold">{{ message.summary }}</span>
          <Button label="Undo" size="small" severity="secondary" outlined data-testid="undo-delete" @click="undoDelete">
            <template #icon><AppIcon name="undo" :size="18" /></template>
          </Button>
        </div>
      </template>
    </Toast>
  </div>
</template>

<style scoped>
.txn-table {
  font-size: var(--text-dense);
  line-height: var(--text-dense--line-height);
}
.txn-table :deep(.p-datatable-thead > tr > th) {
  white-space: nowrap;
}
.txn-table :deep(.p-datatable-tbody > tr > td) {
  padding-top: 0.25rem;
  padding-bottom: 0.25rem;
}
/* A row being saved: the theme's highlight tint (every amount colour reads at 4.5:1 on it). */
.txn-table :deep(tr.row-saving > td) {
  background: var(--vf-primary-soft);
}
.txn-table :deep(td[data-p-cell-editing='true']) {
  outline: 2px solid var(--p-primary-color);
  outline-offset: -2px;
  background: #f5f9ff;
}
.txn-table :deep(.p-datatable-tbody > tr > td:not([data-p-selection-column]):not(:last-child)) {
  cursor: text;
}
/* A cell reached with Tab (not being edited): the same 2px ring as an editing cell. */
.txn-table :deep(td[tabindex]:focus-visible) {
  outline: 2px solid var(--p-primary-color);
  outline-offset: -2px;
}
.cell-editor {
  width: 100%;
  background: transparent;
  outline: none;
}
</style>
