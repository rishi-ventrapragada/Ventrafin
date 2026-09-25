<script setup lang="ts">
// This month against last month (get_month_totals), spending by category
// (get_month_comparison) and the bills that are overdue or due within a week
// (get_bill_schedule): the phone's Dashboard, laid out for a wide screen.
// Numbers come from Postgres; the browser only draws them. The month is kept
// in the URL (?month=yyyy-mm), so Back and F5 come back to it.
import Button from 'primevue/button'
import { computed, ref, watch } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import AppIcon from '@/components/AppIcon.vue'
import ChangeCell from '@/components/ChangeCell.vue'
import DonutChart from '@/components/DonutChart.vue'
import LoadError from '@/components/LoadError.vue'
import MonthSwitcher from '@/components/MonthSwitcher.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { useApp } from '@/data/appContext'
import { billStatusLabel, billStatusLook } from '@/lib/bills'
import { UNCATEGORIZED_LOOK, categoryIconKey, readableTextColor } from '@/lib/categoryStyle'
import { compareMonths, formatDateIndian, monthFromQuery, monthKey, monthLabel, monthOf, type YearMonth } from '@/lib/dates'
import { formatRupees, formatRupeesCompact } from '@/lib/money'
import type { Category } from '@/lib/models'
import { EXPENSE_COLOR, INCOME_COLOR } from '@/lib/theme'

const app = useApp()
const route = useRoute()
const router = useRouter()

const currentMonth = computed(() => monthOf(app.today.value))
const month = ref<YearMonth>(monthFromQuery(route.query.month, currentMonth.value) ?? currentMonth.value)
// Midnight on the last day of the month: follow along if showing "this month".
watch(currentMonth, (now, before) => {
  if (compareMonths(month.value, before) === 0) month.value = now
})
// In the URL only when it isn't this month, so /dashboard is always "now".
watch(month, (m) => {
  const query = compareMonths(m, currentMonth.value) === 0 ? {} : { month: monthKey(m) }
  void router.replace({ query })
})
// The sidebar link (no month) while a past month is open: back to this month.
watch(
  () => route.query.month,
  (q) => {
    const m = monthFromQuery(q, currentMonth.value) ?? currentMonth.value
    if (compareMonths(m, month.value) !== 0) month.value = m
  },
)

const totals = app.liveQuery(['transactions'], () => app.repo.fetchMonthTotals(month.value), () => monthKey(month.value))
// Category names and colours are joined in the SQL, so a rename re-fetches too.
const comparison = app.liveQuery(
  ['transactions', 'categories'],
  () => app.repo.fetchMonthComparison(month.value),
  () => monthKey(month.value),
)

const categoriesById = computed(() => new Map((app.categories.data.value ?? []).map((c) => [c.id, c])))

// Bills that need attention now (whatever month is shown): overdue, due
// today or within 7 days. Status depends on today, so re-fetch when it changes.
const bills = app.liveQuery(['recurring_bills'], () => app.repo.fetchBills(), () => app.today.value)
const billsDue = computed(() => (bills.data.value ?? []).filter((b) => b.status !== 'upcoming'))

interface BreakdownRow {
  key: string
  name: string
  color: string
  icon: string
  category: Category | null
  uncategorized: boolean
  now: number
  before: number
}

const rows = computed<BreakdownRow[]>(() =>
  (comparison.data.value ?? [])
    .filter((r) => r.kind === 'expense' && (r.thisMonthPaise > 0 || r.lastMonthPaise > 0))
    .map((r) => {
      const category = r.categoryId ? (categoriesById.value.get(r.categoryId) ?? null) : null
      const uncategorized = r.categoryId === null
      return {
        key: r.categoryId ?? 'uncategorized',
        name: category?.name ?? r.categoryName,
        color: uncategorized ? UNCATEGORIZED_LOOK.color : (category?.color ?? r.color),
        icon: uncategorized ? UNCATEGORIZED_LOOK.icon : categoryIconKey(category?.icon),
        category,
        uncategorized,
        now: r.thisMonthPaise,
        before: r.lastMonthPaise,
      }
    })
    .sort((a, b) => b.now - a.now || b.before - a.before),
)
const spentTotal = computed(() => rows.value.reduce((s, r) => s + r.now, 0))
const lastTotal = computed(() => rows.value.reduce((s, r) => s + r.before, 0))
const segments = computed(() =>
  rows.value.filter((r) => r.now > 0).map((r) => ({ value: r.now, color: r.color, icon: r.icon, label: r.name })),
)

function share(paise: number) {
  return spentTotal.value > 0 ? `${Math.round((paise * 100) / spentTotal.value)}%` : ''
}

const t = computed(() => totals.data.value)
const isThisMonth = computed(() => compareMonths(month.value, currentMonth.value) === 0)

function openUncategorized() {
  void router.push({ path: '/transactions', query: { month: monthKey(month.value), category: 'uncategorized' } })
}
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-2">
      <h1 class="mr-2 text-xl font-semibold text-slate-800">Dashboard</h1>
      <MonthSwitcher v-model="month" :max="currentMonth" />
      <div class="ml-auto flex gap-2">
        <RouterLink v-slot="{ navigate }" to="/add" custom>
          <Button label="Add today's expenses" @click="navigate">
            <template #icon><AppIcon name="add" :size="21" /></template>
          </Button>
        </RouterLink>
        <RouterLink v-slot="{ navigate }" :to="{ path: '/transactions', query: { month: monthKey(month) } }" custom>
          <Button label="Transactions" severity="secondary" outlined @click="navigate">
            <template #icon><AppIcon name="receipt_long" :size="21" /></template>
          </Button>
        </RouterLink>
      </div>
    </div>

    <div class="grid items-start gap-3 xl:grid-cols-[minmax(22rem,30rem)_1fr]">
      <div class="flex flex-col gap-3">
        <section class="card p-3" data-testid="month-totals">
          <div class="mb-2 flex flex-wrap items-end gap-x-4 gap-y-1">
            <div>
              <h2 class="text-sm font-semibold text-slate-700">Spent {{ isThisMonth ? 'this month' : `in ${monthLabel(month)}` }}</h2>
              <div class="text-4xl leading-tight font-bold tabular-nums" :style="{ color: EXPENSE_COLOR }" data-testid="spent-headline">
                {{ t ? formatRupees(t.expensePaise) : '…' }}
              </div>
            </div>
            <div v-if="t" class="pb-1 text-sm text-slate-700">
              <ChangeCell :now="t.expensePaise" :before="t.lastExpensePaise" /> against last month
              ({{ formatRupeesCompact(t.lastExpensePaise) }})
            </div>
          </div>
          <LoadError v-if="totals.error.value && !t" compact :error="totals.error.value" what="Couldn't load totals." @retry="totals.refresh()" />
          <table class="dense-table">
            <thead>
              <tr>
                <th></th>
                <th class="text-right">This month</th>
                <th class="text-right">Last month</th>
                <th class="text-right">Change</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td class="font-medium">Spent</td>
                <td class="num font-semibold" :style="{ color: EXPENSE_COLOR }" data-testid="spent-now">{{ t ? formatRupees(t.expensePaise) : '…' }}</td>
                <td class="num text-slate-600">{{ t ? formatRupeesCompact(t.lastExpensePaise) : '' }}</td>
                <td class="num"><ChangeCell v-if="t" :now="t.expensePaise" :before="t.lastExpensePaise" /></td>
              </tr>
              <tr>
                <td class="font-medium">Income</td>
                <td class="num font-semibold" :style="{ color: INCOME_COLOR }">{{ t ? formatRupees(t.incomePaise) : '…' }}</td>
                <td class="num text-slate-600">{{ t ? formatRupeesCompact(t.lastIncomePaise) : '' }}</td>
                <td class="num"><ChangeCell v-if="t" :now="t.incomePaise" :before="t.lastIncomePaise" up-is-good /></td>
              </tr>
              <tr>
                <td class="font-semibold">Net</td>
                <td class="num font-semibold">{{ t ? formatRupees(t.incomePaise - t.expensePaise) : '…' }}</td>
                <td class="num text-slate-600">{{ t ? formatRupeesCompact(t.lastIncomePaise - t.lastExpensePaise) : '' }}</td>
                <td></td>
              </tr>
            </tbody>
          </table>
        </section>

        <button
          v-if="t && t.uncategorizedCount > 0"
          type="button"
          class="card flex items-center gap-3 border-amber-300 bg-amber-50 p-3 text-left hover:bg-amber-100"
          data-testid="uncategorized-callout"
          @click="openUncategorized"
        >
          <TxnAvatar kind="uncategorized" :size="36" />
          <span>
            <span class="block font-semibold text-slate-800">{{ t.uncategorizedCount }} uncategorized in {{ monthLabel(month) }}</span>
            <span class="text-sm text-slate-700">Open them and pick a category. Ventrafin learns from it.</span>
          </span>
          <AppIcon name="chevron_right" :size="24" class="ml-auto text-slate-600" />
        </button>

        <section v-if="bills.error.value && !bills.data.value" class="card p-3" data-testid="bills-due">
          <h2 class="card-title mb-2">Bills</h2>
          <LoadError compact :error="bills.error.value" what="Couldn't load bills." @retry="bills.refresh()" />
        </section>
        <section v-else-if="billsDue.length" class="card p-3" data-testid="bills-due">
          <div class="mb-1 flex items-baseline gap-2">
            <h2 class="card-title">Bills to pay</h2>
            <span class="text-sm text-slate-600">overdue or due within 7 days</span>
            <RouterLink to="/bills" class="ml-auto text-sm font-medium text-primary hover:underline" data-testid="bills-due-link">
              All bills
            </RouterLink>
          </div>
          <table class="dense-table">
            <tbody>
              <tr v-for="b in billsDue" :key="b.id" :data-bill-due="b.id">
                <td>
                  <span
                    class="inline-flex items-center gap-1 rounded-md px-2 py-0.5 font-semibold whitespace-nowrap"
                    :style="{ color: billStatusLook(b.status).fg, background: billStatusLook(b.status).bg }"
                  >
                    <AppIcon :name="billStatusLook(b.status).icon" :size="17" /> {{ billStatusLabel(b) }}
                  </span>
                </td>
                <td class="w-full">
                  <RouterLink to="/bills" class="font-medium hover:underline">{{ b.name }}</RouterLink>
                </td>
                <td class="whitespace-nowrap text-slate-700">{{ formatDateIndian(b.nextDueDate) }}</td>
                <td class="num font-semibold">{{ formatRupeesCompact(b.amountPaise) }}</td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>

      <section class="card p-3" data-testid="category-breakdown">
        <div class="mb-2 flex items-baseline gap-2">
          <h2 class="card-title">Spending by category</h2>
          <span class="text-sm text-slate-600">{{ monthLabel(month) }} against the month before</span>
        </div>
        <LoadError
          v-if="comparison.error.value && !comparison.data.value"
          compact
          :error="comparison.error.value"
          what="Couldn't load the breakdown."
          @retry="comparison.refresh()"
        />
        <p v-else-if="!comparison.data.value" class="muted py-6">Loading…</p>
        <p v-else-if="rows.length === 0" class="py-4 text-slate-600">Nothing spent yet in {{ monthLabel(month) }}.</p>
        <div v-else class="flex flex-col gap-4 min-[110rem]:flex-row min-[110rem]:items-start">
          <div class="flex items-center gap-4">
            <DonutChart
              v-if="spentTotal > 0"
              :segments="segments"
              center-label="Spent"
              :center-value="formatRupeesCompact(spentTotal)"
            />
            <ul class="flex min-w-[11rem] flex-col gap-1.5 text-dense">
              <li v-for="r in rows.filter((x) => x.now > 0).slice(0, 6)" :key="r.key" class="flex items-center gap-2">
                <TxnAvatar v-if="r.uncategorized" kind="uncategorized" :size="24" />
                <TxnAvatar v-else :category="r.category" :size="24" />
                <span class="flex-1 truncate">{{ r.name }}</span>
                <span class="font-bold tabular-nums">{{ share(r.now) }}</span>
              </li>
            </ul>
          </div>
          <table class="dense-table flex-1" data-testid="breakdown-table">
            <thead>
              <tr>
                <th>Category</th>
                <th class="text-right">This month</th>
                <th class="text-right">Last month</th>
                <th class="text-right">Change</th>
                <th class="text-right">Share</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in rows" :key="r.key" :data-breakdown="r.key">
                <td>
                  <span class="flex items-center gap-2">
                    <TxnAvatar v-if="r.uncategorized" kind="uncategorized" :size="28" />
                    <TxnAvatar v-else :category="r.category" :size="28" />
                    <span :style="{ color: r.uncategorized ? undefined : readableTextColor(r.color) }" class="font-medium">{{ r.name }}</span>
                  </span>
                </td>
                <td class="num font-semibold">{{ formatRupeesCompact(r.now) }}</td>
                <td class="num text-slate-600">{{ formatRupeesCompact(r.before) }}</td>
                <td class="num"><ChangeCell :now="r.now" :before="r.before" /></td>
                <td class="num text-slate-600">{{ share(r.now) }}</td>
              </tr>
              <tr class="font-semibold">
                <td>Total</td>
                <td class="num">{{ formatRupeesCompact(spentTotal) }}</td>
                <td class="num text-slate-600">{{ formatRupeesCompact(lastTotal) }}</td>
                <td class="num"><ChangeCell :now="spentTotal" :before="lastTotal" /></td>
                <td></td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </div>
</template>
