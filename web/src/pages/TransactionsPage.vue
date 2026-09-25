<script setup lang="ts">
// One month of transactions in a dense, editable table. Click a cell to edit
// it in place (Enter or Tab saves, Esc cancels); changing a category teaches
// the database's learning trigger. Filters by account, category and text;
// delete one row or several, always after confirming. Updates live.
import Button from 'primevue/button'
import Column from 'primevue/column'
import DataTable, { type DataTableCellEditCompleteEvent, type DataTableCellEditInitEvent } from 'primevue/datatable'
import Dialog from 'primevue/dialog'
import Select from 'primevue/select'
import { useConfirm } from 'primevue/useconfirm'
import { useToast } from 'primevue/usetoast'
import { computed, reactive, ref, watch } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import AccountAvatar from '@/components/AccountAvatar.vue'
import AppIcon from '@/components/AppIcon.vue'
import ComboInput from '@/components/ComboInput.vue'
import ExportDialog from '@/components/ExportDialog.vue'
import MerchantBadge from '@/components/MerchantBadge.vue'
import MonthSwitcher from '@/components/MonthSwitcher.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { useApp } from '@/data/appContext'
import { vFocus } from '@/directives'
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
import { ACCOUNT_TYPES, PAYMENT_METHODS, TXN_TYPES, sortByName, type Txn, type TxnPatch } from '@/lib/models'
import { METHOD_OPTIONS, TYPE_OPTIONS, accountOptions, categoryOptions } from '@/lib/options'

const app = useApp()
const route = useRoute()
const router = useRouter()
const toast = useToast()
const confirm = useConfirm()

// ------------------------------------------------------------ month & filters (kept in the URL)

const currentMonth = computed(() => monthOf(app.today.value))
const month = ref<YearMonth>(parseMonthKey(route.query.month) ?? currentMonth.value)
const accountFilter = ref<string>(typeof route.query.account === 'string' ? route.query.account : 'all')
const categoryFilter = ref<string>(typeof route.query.category === 'string' ? route.query.category : 'all')
const search = ref('')

watch([month, accountFilter, categoryFilter], () => {
  const query: Record<string, string> = { month: monthKey(month.value) }
  if (accountFilter.value !== 'all') query.account = accountFilter.value
  if (categoryFilter.value !== 'all') query.category = categoryFilter.value
  void router.replace({ query })
})

// Arriving again with other filters (the sidebar link, the Dashboard's
// "uncategorized" link) while this page is already open.
watch(
  () => route.query,
  (q) => {
    const m = parseMonthKey(q.month) ?? currentMonth.value
    if (compareMonths(m, month.value) !== 0) month.value = m
    const account = typeof q.account === 'string' ? q.account : 'all'
    if (account !== accountFilter.value) accountFilter.value = account
    const category = typeof q.category === 'string' ? q.category : 'all'
    if (category !== categoryFilter.value) categoryFilter.value = category
  },
)

// ------------------------------------------------------------ data

const txns = app.liveQuery(['transactions'], () => app.repo.fetchTransactions(month.value), () => monthKey(month.value))
const totals = app.liveQuery(['transactions'], () => app.repo.fetchMonthTotals(month.value), () => monthKey(month.value))

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
watch(
  () => txns.data.value,
  (list) => {
    const ids = new Set((list ?? []).map((t) => t.id))
    for (const id of hidden) if (!ids.has(id)) hidden.delete(id)
  },
)

interface Row extends Txn {
  categoryName: string
  accountName: string
  methodName: string
}

const allRows = computed<Row[]>(() =>
  (txns.data.value ?? [])
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

const rows = computed(() => {
  const q = search.value.trim().toLowerCase()
  return allRows.value.filter((t) => {
    if (accountFilter.value !== 'all' && t.accountId !== accountFilter.value && t.toAccountId !== accountFilter.value) return false
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

const accountFilterOptions = computed(() => [
  { value: 'all', label: 'All accounts', type: null },
  ...accounts.value.map((a) => ({ value: a.id, label: a.name, type: a.type })),
])
const categoryFilterOptions = computed(() => [
  { value: 'all', label: 'All categories', kind: 'all' as const, category: null },
  { value: 'uncategorized', label: 'Uncategorized', kind: 'uncategorized' as const, category: null },
  { value: 'transfers', label: 'Transfers', kind: 'transfer' as const, category: null },
  ...sortByName(categories.value).map((c) => ({ value: c.id, label: c.name, kind: 'category' as const, category: c })),
])

// ------------------------------------------------------------ export (CSV)

const exportVisible = ref(false)
/** The export dialog's first choice: this month, only the rows shown when filtered. */
const shownForExport = computed(() => {
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
  search.value = ''
}

// ------------------------------------------------------------ editing

const edit = reactive<{ id: string; field: EditableField | null; text: string }>({ id: '', field: null, text: '' })

function onEditInit(e: DataTableCellEditInitEvent) {
  const t = e.data as Row
  if (!isEditableField(e.field)) return
  edit.id = t.id
  edit.field = e.field
  edit.text = editorText(t, e.field, context.value)
}

function onEditComplete(e: DataTableCellEditCompleteEvent) {
  const t = e.data as Row
  if (edit.id !== t.id || edit.field !== e.field || !isEditableField(e.field)) return
  const field = e.field
  const text = edit.text
  edit.field = null
  const result = cellEdit(t, field, text, context.value)
  switch (result.kind) {
    case 'unchanged':
      return
    case 'invalid':
      toast.add({ severity: 'warn', summary: 'Not changed', detail: result.message, life: 6000 })
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
    toast.add({ severity: 'error', summary: 'Not saved', detail: describeError(e) })
    return
  }
  pending.set(t.id, { ...pending.get(t.id), ...patch })
  savingIds.add(t.id)
  try {
    const updated = await app.repo.updateTransaction(t.id, patch)
    if (txns.data.value) txns.data.value = txns.data.value.map((x) => (x.id === updated.id ? updated : x))
    pending.delete(t.id)
    app.bump(['transactions'])
    if (updated.categoryId && !categoriesById.value.has(updated.categoryId)) app.bump(['categories'])
    if (patch.categoryId) {
      toast.add({
        severity: 'success',
        summary: 'Category saved',
        detail: 'Ventrafin will use it for similar descriptions from now on, on the phone too.',
        life: 4000,
      })
    }
    if (patch.date && compareMonths(monthOf(patch.date), month.value) !== 0) {
      toast.add({ severity: 'info', summary: `Moved to ${monthLabel(monthOf(patch.date))}`, life: 4000 })
    }
  } catch (e) {
    pending.delete(t.id)
    toast.add({ severity: 'error', summary: 'Not saved', detail: `${describeError(e)} The previous value is back.` })
    if (e instanceof AppError && e.code === 'PGRST116') app.bump(['transactions'])
  } finally {
    savingIds.delete(t.id)
  }
}

// Changing a row to a transfer: which account did the money go to?
const transfer = reactive<{ txn: Txn | null; to: string | null }>({ txn: null, to: null })
const transferTargets = computed(() => accounts.value.filter((a) => a.id !== transfer.txn?.accountId))

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
watch([month, accountFilter, categoryFilter, search], () => (selected.value = []))

function describeTxn(t: Txn) {
  return `${formatRupees(t.amountPaise)} · ${t.description || '(no description)'} · ${formatDateIndian(t.date)}`
}

function confirmDelete(list: Txn[]) {
  if (list.length === 0) return
  confirm.require({
    header: list.length === 1 ? 'Delete this transaction?' : `Delete ${list.length} transactions?`,
    message:
      list.length === 1
        ? `${describeTxn(list[0]!)}. This can't be undone.`
        : `${list.length} transactions, ${formatRupees(list.reduce((s, t) => s + t.amountPaise, 0))} in total. This can't be undone.`,
    acceptLabel: 'Delete',
    rejectLabel: 'Keep',
    acceptProps: { severity: 'danger' },
    rejectProps: { severity: 'secondary', outlined: true },
    accept: () => void deleteTxns(list.map((t) => t.id)),
  })
}

async function deleteTxns(ids: string[]) {
  try {
    app.requireOnline()
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Not deleted', detail: describeError(e) })
    return
  }
  ids.forEach((id) => hidden.add(id))
  try {
    const n = await app.repo.deleteTransactions(ids)
    selected.value = selected.value.filter((t) => !ids.includes(t.id))
    app.bump(['transactions'])
    toast.add({ severity: 'success', summary: `Deleted ${n} transaction${n === 1 ? '' : 's'}`, life: 3000 })
    if (n < ids.length) {
      toast.add({ severity: 'info', summary: `${ids.length - n} had already been deleted (perhaps on the phone).`, life: 5000 })
    }
  } catch (e) {
    ids.forEach((id) => hidden.delete(id))
    toast.add({ severity: 'error', summary: 'Not deleted', detail: describeError(e) })
  }
}

function amountClass(t: Txn) {
  return t.type === 'expense' ? 'text-expense' : t.type === 'income' ? 'text-income' : 'text-transfer'
}

function rowClass(t: Row) {
  return savingIds.has(t.id) ? 'opacity-60' : ''
}
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-2">
    <div class="flex flex-wrap items-center gap-2">
      <h1 class="mr-1 text-xl font-semibold text-slate-800">Transactions</h1>
      <MonthSwitcher v-model="month" :max="currentMonth" />
      <span class="relative">
        <AppIcon name="search" :size="20" class="pointer-events-none absolute top-1/2 left-2 -translate-y-1/2 text-slate-500" />
        <input
          v-model="search"
          type="search"
          placeholder="Search descriptions"
          aria-label="Search descriptions"
          class="h-[2.35rem] w-52 rounded-md border border-slate-300 bg-white pr-2 pl-8 outline-none placeholder:text-slate-500 focus:border-primary"
          data-testid="search"
        />
      </span>
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
            <AppIcon v-else name="account_balance_wallet" :size="22" class="text-slate-500" />{{ option.label }}
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
            <AppIcon v-else name="category" :size="22" class="text-slate-500" />
            {{ option.label }}
            <span v-if="option.category" class="ml-auto pl-2 text-sm text-slate-600">{{ option.category.kind }}</span>
          </span>
        </template>
      </Select>
      <Button v-if="filtered || search" label="Clear filters" severity="secondary" text size="small" @click="clearFilters">
        <template #icon><AppIcon name="filter_alt_off" :size="19" /></template>
      </Button>
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

    <div class="card flex flex-wrap items-center gap-x-6 gap-y-1 px-3 py-2" data-testid="month-summary">
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
        · click a cell to edit it
      </span>
    </div>

    <div v-if="txns.error.value && !txns.data.value" class="card flex items-center gap-3 p-4" role="alert">
      <AppIcon name="cloud_off" :size="30" class="text-expense" />
      <span>{{ describeError(txns.error.value) }}</span>
      <Button label="Retry" size="small" @click="txns.refresh()" />
    </div>

    <div v-else class="card min-h-0 flex-1 overflow-hidden">
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
        :loading="txns.loading.value && !txns.data.value"
        :row-class="rowClass"
        class="txn-table h-full"
        data-testid="txn-table"
        @cell-edit-init="onEditInit"
        @cell-edit-complete="onEditComplete"
      >
        <template #empty>
          <div class="py-8 text-center text-slate-600">
            <template v-if="filtered || search">
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

        <Column field="date" header="Date" sortable style="width: 8.2rem" body-class="whitespace-nowrap">
          <template #body="{ data }">
            <span class="tabular-nums">{{ formatDateIndian(data.date) }}</span>
            <span class="ml-1 text-sm text-slate-600">{{ shortWeekday(data.date) }}</span>
          </template>
          <template #editor>
            <input v-model="edit.text" v-focus class="cell-editor" aria-label="Date (dd/mm/yyyy)" placeholder="dd/mm/yyyy" />
          </template>
        </Column>

        <Column field="description" header="Description" sortable style="width: 100%; min-width: 13.5rem">
          <template #body="{ data }">
            <!-- w-0 + min-w-full: the text truncates instead of widening the table. -->
            <span class="flex w-0 min-w-full items-center gap-2">
              <TxnAvatar v-if="data.type === 'transfer'" kind="transfer" :size="28" />
              <TxnAvatar v-else-if="!data.categoryId" kind="uncategorized" :size="28" />
              <TxnAvatar v-else :category="categoriesById.get(data.categoryId) ?? null" :size="28" />
              <MerchantBadge :description="data.description" :size="18" />
              <span class="truncate" :class="data.description ? '' : 'italic text-slate-500'">{{ data.description || '(no description)' }}</span>
            </span>
          </template>
          <template #editor>
            <input v-model="edit.text" v-focus maxlength="500" class="cell-editor" aria-label="Description" />
          </template>
        </Column>

        <Column field="categoryId" sort-field="categoryName" header="Category" sortable style="width: 12rem">
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
          style="width: 9rem"
          body-class="text-right whitespace-nowrap"
          :pt="{ columnHeaderContent: { class: 'justify-end' } }"
        >
          <template #body="{ data }">
            <span class="font-semibold tabular-nums" :class="amountClass(data)">{{ data.type === 'income' ? '+' : '' }}{{ formatRupees(data.amountPaise) }}</span>
          </template>
          <template #editor>
            <input v-model="edit.text" v-focus inputmode="decimal" class="cell-editor text-right" aria-label="Amount" />
          </template>
        </Column>

        <Column field="type" header="Type" sortable style="width: 7.5rem" body-class="whitespace-nowrap">
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

        <Column field="accountId" sort-field="accountName" header="Account" sortable style="width: 10rem" body-class="whitespace-nowrap">
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
          <template #editor>
            <ComboInput v-model="edit.text" :options="accountOptions(accounts)" autofocus aria-label="Account">
              <template #option="{ option }"><AccountAvatar :type="option.account.type" :size="24" />{{ option.label }}</template>
            </ComboInput>
          </template>
        </Column>

        <Column field="toAccountId" header="To" style="width: 9rem" body-class="whitespace-nowrap">
          <template #body="{ data }">
            <span v-if="data.toAccountId" class="inline-flex items-center gap-1 text-slate-700">
              <AppIcon name="arrow_forward" :size="17" class="text-slate-500" />{{ accountsById.get(data.toAccountId)?.name ?? '…' }}
            </span>
          </template>
          <template #editor="{ data }">
            <input v-if="data.type !== 'transfer'" v-focus readonly class="cell-editor" placeholder="Only for transfers" />
            <ComboInput v-else v-model="edit.text" :options="accountOptions(accounts)" autofocus aria-label="To account">
              <template #option="{ option }"><AccountAvatar :type="option.account.type" :size="24" />{{ option.label }}</template>
            </ComboInput>
          </template>
        </Column>

        <Column field="paymentMethod" sort-field="methodName" header="Paid by" sortable style="width: 7.5rem" body-class="whitespace-nowrap">
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
              class="flex rounded p-1 text-slate-500 hover:bg-red-50 hover:text-expense"
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
      <p class="mb-3 text-slate-600">
        A transfer moves money between your own accounts, from
        <strong>{{ accountsById.get(transfer.txn?.accountId ?? '')?.name }}</strong> to:
      </p>
      <Select
        v-model="transfer.to"
        :options="transferTargets"
        option-label="name"
        option-value="id"
        class="w-full"
        aria-label="To account"
      />
      <p class="mt-3 text-sm text-slate-600">Transfers have no category and don't count as spending.</p>
      <template #footer>
        <Button label="Cancel" severity="secondary" text @click="transfer.txn = null" />
        <Button label="Make it a transfer" :disabled="!transfer.to" @click="confirmTransfer" />
      </template>
    </Dialog>

    <ExportDialog v-if="exportVisible" v-model:visible="exportVisible" :shown="shownForExport" />
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
.txn-table :deep(td[data-p-cell-editing='true']) {
  outline: 2px solid var(--p-primary-color);
  outline-offset: -2px;
  background: #f5f9ff;
}
.txn-table :deep(.p-datatable-tbody > tr > td:not([data-p-selection-column]):not(:last-child)) {
  cursor: text;
}
.cell-editor {
  width: 100%;
  background: transparent;
  outline: none;
}
</style>
