<script setup lang="ts">
// Reports (PRD § 4.6): any month's totals and categories against the month
// before, then 6- or 12-month trends of income against spending and of
// spending by category, as charts with the same numbers in tables beside
// them. Every total is computed in Postgres (get_month_totals,
// get_month_comparison, get_monthly_totals, get_monthly_category_totals);
// the browser only lays them out. Same sections as the phone's Reports.
import { computed, ref, watch } from 'vue'
import { RouterLink } from 'vue-router'
import BarChart from '@/components/BarChart.vue'
import ChangeCell from '@/components/ChangeCell.vue'
import MonthSwitcher from '@/components/MonthSwitcher.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { useApp } from '@/data/appContext'
import { UNCATEGORIZED_LOOK, readableTextColor } from '@/lib/categoryStyle'
import { MONTH_SHORT, compareMonths, monthKey, monthLabel, monthOf, monthShortLabel, type YearMonth } from '@/lib/dates'
import { describeError } from '@/lib/errors'
import { formatRupeesCompact } from '@/lib/money'
import type { CategoryKind } from '@/lib/models'
import { buildCategoryTrend, monthsEnding, savedPercent, totalsFor } from '@/lib/reports'
import { EXPENSE_COLOR, INCOME_COLOR } from '@/lib/theme'

const app = useApp()

const currentMonth = computed(() => monthOf(app.today.value))
const month = ref(currentMonth.value)
watch(currentMonth, (now, before) => {
  if (compareMonths(month.value, before) === 0) month.value = now
})
const span = ref<6 | 12>(6)
const months = computed(() => monthsEnding(month.value, span.value))
const rangeKey = () => `${monthKey(months.value[0]!)}..${monthKey(month.value)}`

const totals = app.liveQuery(['transactions'], () => app.repo.fetchMonthTotals(month.value), () => monthKey(month.value))
const comparison = app.liveQuery(
  ['transactions', 'categories'],
  () => app.repo.fetchMonthComparison(month.value),
  () => monthKey(month.value),
)
const monthly = app.liveQuery(
  ['transactions'],
  () => app.repo.fetchMonthlyTotals(months.value[0]!, month.value),
  rangeKey,
)
const monthlyCategories = app.liveQuery(
  ['transactions', 'categories'],
  () => app.repo.fetchMonthlyCategoryTotals(months.value[0]!, month.value),
  rangeKey,
)

const categoriesById = computed(() => new Map((app.categories.data.value ?? []).map((c) => [c.id, c])))
const sameMonth = (a: YearMonth, b: YearMonth) => compareMonths(a, b) === 0

// ---- the chosen month -------------------------------------------------------
const t = computed(() => totals.data.value)
const counts = computed(() => monthly.data.value?.find((m) => sameMonth(m.month, month.value)))

function categoryRows(kind: CategoryKind) {
  const entryCounts = new Map(
    (monthlyCategories.data.value ?? [])
      .filter((r) => r.kind === kind && sameMonth(r.month, month.value))
      .map((r) => [r.categoryId ?? 'uncategorized', r.count]),
  )
  const rows = (comparison.data.value ?? [])
    .filter((r) => r.kind === kind && (r.thisMonthPaise > 0 || r.lastMonthPaise > 0))
    .map((r) => {
      const category = r.categoryId ? (categoriesById.value.get(r.categoryId) ?? null) : null
      const key = r.categoryId ?? 'uncategorized'
      return {
        key,
        category,
        uncategorized: r.categoryId === null,
        name: r.categoryId ? (category?.name ?? r.categoryName) : 'Uncategorized',
        color: r.categoryId ? (category?.color ?? r.color) : UNCATEGORIZED_LOOK.color,
        now: r.thisMonthPaise,
        before: r.lastMonthPaise,
        count: entryCounts.get(key) ?? 0,
      }
    })
    .sort((a, b) => b.now - a.now || b.before - a.before)
  const total = rows.reduce((s, r) => s + r.now, 0)
  const lastTotal = rows.reduce((s, r) => s + r.before, 0)
  return { rows, total, lastTotal }
}
const expense = computed(() => categoryRows('expense'))
const income = computed(() => categoryRows('income'))
const share = (paise: number, total: number) => (total > 0 ? `${Math.round((paise * 100) / total)}%` : '')

// ---- trends -------------------------------------------------------------------
const tick = (m: YearMonth, i: number) => (m.month === 1 || i === 0 ? `${MONTH_SHORT[m.month - 1]} ’${String(m.year).slice(2)}` : MONTH_SHORT[m.month - 1]!)
const labels = computed(() => months.value.map(tick))
const titles = computed(() => months.value.map(monthLabel))
const trendMonths = computed(() => totalsFor(months.value, monthly.data.value ?? []))
const trendTotals = computed(() => ({
  income: trendMonths.value.reduce((s, m) => s + m.incomePaise, 0),
  spent: trendMonths.value.reduce((s, m) => s + m.expensePaise, 0),
}))
const incomeSeries = computed(() => [
  { key: 'income', name: 'Income', color: INCOME_COLOR, values: trendMonths.value.map((m) => m.incomePaise) },
  { key: 'spent', name: 'Spent', color: EXPENSE_COLOR, values: trendMonths.value.map((m) => m.expensePaise) },
])
const trend = computed(() => buildCategoryTrend(monthlyCategories.data.value ?? [], months.value, categoriesById.value))
const trendSeries = computed(() => trend.value.series.map((s) => ({ key: s.key, name: s.name, color: s.color, values: s.perMonth })))
const grand = computed(() => trend.value.monthTotals.reduce((s, v) => s + v, 0))
const last = computed(() => months.value.length - 1)
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-2">
      <h1 class="mr-2 text-xl font-semibold text-slate-800">Reports</h1>
      <MonthSwitcher v-model="month" :max="currentMonth" />
      <RouterLink
        :to="{ path: '/transactions', query: { month: monthKey(month) } }"
        class="ml-auto text-sm font-medium text-primary hover:underline"
      >
        Transactions in {{ monthLabel(month) }}
      </RouterLink>
    </div>

    <!-- The chosen month -->
    <div class="grid items-start gap-3 xl:grid-cols-[minmax(22rem,30rem)_1fr]">
      <div class="flex flex-col gap-3">
        <section class="card p-3" data-testid="report-month-summary">
          <h2 class="card-title mb-2">{{ monthLabel(month) }}</h2>
          <p v-if="totals.error.value && !t" class="text-sm text-expense" role="alert">
            Couldn't load totals. {{ describeError(totals.error.value) }}
          </p>
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
                <td class="num font-semibold" :style="{ color: EXPENSE_COLOR }">{{ t ? formatRupeesCompact(t.expensePaise) : '…' }}</td>
                <td class="num text-slate-600">{{ t ? formatRupeesCompact(t.lastExpensePaise) : '' }}</td>
                <td class="num"><ChangeCell v-if="t" :now="t.expensePaise" :before="t.lastExpensePaise" /></td>
              </tr>
              <tr>
                <td class="font-medium">Income</td>
                <td class="num font-semibold" :style="{ color: INCOME_COLOR }">{{ t ? formatRupeesCompact(t.incomePaise) : '…' }}</td>
                <td class="num text-slate-600">{{ t ? formatRupeesCompact(t.lastIncomePaise) : '' }}</td>
                <td class="num"><ChangeCell v-if="t" :now="t.incomePaise" :before="t.lastIncomePaise" up-is-good /></td>
              </tr>
              <tr>
                <td class="font-semibold">Net</td>
                <td class="num font-semibold">{{ t ? formatRupeesCompact(t.incomePaise - t.expensePaise) : '…' }}</td>
                <td class="num text-slate-600">{{ t ? formatRupeesCompact(t.lastIncomePaise - t.lastExpensePaise) : '' }}</td>
                <td></td>
              </tr>
              <tr>
                <td class="font-medium">Saved</td>
                <td class="num font-semibold" data-testid="saved-now">
                  {{ t ? (savedPercent(t.incomePaise, t.expensePaise) ?? '–') + (savedPercent(t.incomePaise, t.expensePaise) === null ? '' : '%') : '…' }}
                </td>
                <td class="num text-slate-600">
                  {{ t ? (savedPercent(t.lastIncomePaise, t.lastExpensePaise) ?? '–') + (savedPercent(t.lastIncomePaise, t.lastExpensePaise) === null ? '' : '%') : '' }}
                </td>
                <td></td>
              </tr>
            </tbody>
          </table>
          <p v-if="counts" class="mt-2 text-sm text-slate-600">
            {{ counts.expenseCount }} expenses and {{ counts.incomeCount }} income entries<template v-if="counts.uncategorizedCount > 0">,
              {{ counts.uncategorizedCount }} uncategorized</template>. Transfers between your accounts are not counted.
          </p>
        </section>

        <section v-if="income.rows.length > 0" class="card p-3" data-testid="report-income-categories">
          <h2 class="card-title mb-2">Income by category</h2>
          <table class="dense-table">
            <thead>
              <tr>
                <th>Category</th>
                <th class="text-right">Entries</th>
                <th class="text-right">Amount</th>
                <th class="text-right">vs last month</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="r in income.rows" :key="r.key" :data-report-row="`income-${r.key}`">
                <td>
                  <span class="flex items-center gap-2">
                    <TxnAvatar v-if="r.uncategorized" kind="uncategorized" :size="26" />
                    <TxnAvatar v-else :category="r.category" :size="26" />
                    <span class="font-medium">{{ r.name }}</span>
                  </span>
                </td>
                <td class="num text-slate-600">{{ r.count }}</td>
                <td class="num font-semibold">{{ formatRupeesCompact(r.now) }}</td>
                <td class="num"><ChangeCell :now="r.now" :before="r.before" up-is-good /></td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>

      <section class="card p-3" data-testid="report-expense-categories">
        <div class="mb-2 flex items-baseline gap-2">
          <h2 class="card-title">Spending by category</h2>
          <span class="text-sm text-slate-600">{{ monthLabel(month) }} against the month before</span>
        </div>
        <p v-if="comparison.error.value && !comparison.data.value" class="text-sm text-expense" role="alert">
          Couldn't load the categories. {{ describeError(comparison.error.value) }}
        </p>
        <p v-else-if="!comparison.data.value" class="muted py-6">Loading…</p>
        <p v-else-if="expense.rows.length === 0" class="py-4 text-slate-600">Nothing spent in {{ monthLabel(month) }}.</p>
        <table v-else class="dense-table">
          <thead>
            <tr>
              <th>Category</th>
              <th class="text-right">Entries</th>
              <th class="text-right">This month</th>
              <th class="w-[22%]">Share</th>
              <th class="text-right">Last month</th>
              <th class="text-right">Change</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in expense.rows" :key="r.key" :data-report-row="`expense-${r.key}`">
              <td>
                <RouterLink
                  :to="{ path: '/transactions', query: { month: monthKey(month), category: r.uncategorized ? 'uncategorized' : r.key } }"
                  class="flex items-center gap-2 hover:underline"
                >
                  <TxnAvatar v-if="r.uncategorized" kind="uncategorized" :size="28" />
                  <TxnAvatar v-else :category="r.category" :size="28" />
                  <span class="font-medium" :style="{ color: r.uncategorized ? undefined : readableTextColor(r.color) }">{{ r.name }}</span>
                </RouterLink>
              </td>
              <td class="num text-slate-600">{{ r.count }}</td>
              <td class="num font-semibold">{{ formatRupeesCompact(r.now) }}</td>
              <td>
                <span class="flex items-center gap-2">
                  <span class="h-2.5 flex-1 overflow-hidden rounded-full bg-slate-100" aria-hidden="true">
                    <span class="block h-full rounded-full" :style="{ width: share(r.now, expense.total) || '0%', background: r.color }" />
                  </span>
                  <span class="w-10 text-right text-slate-600 tabular-nums">{{ share(r.now, expense.total) }}</span>
                </span>
              </td>
              <td class="num text-slate-600">{{ formatRupeesCompact(r.before) }}</td>
              <td class="num"><ChangeCell :now="r.now" :before="r.before" /></td>
            </tr>
            <tr class="font-semibold">
              <td>Total</td>
              <td class="num">{{ expense.rows.reduce((s, r) => s + r.count, 0) }}</td>
              <td class="num">{{ formatRupeesCompact(expense.total) }}</td>
              <td></td>
              <td class="num text-slate-600">{{ formatRupeesCompact(expense.lastTotal) }}</td>
              <td class="num"><ChangeCell :now="expense.total" :before="expense.lastTotal" /></td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>

    <!-- Trends -->
    <div class="mt-1 flex flex-wrap items-center gap-3">
      <h2 class="text-lg font-semibold text-slate-800">Trends</h2>
      <span class="text-slate-600">{{ monthShortLabel(months[0]!) }} – {{ monthShortLabel(month) }}</span>
      <div class="inline-flex overflow-hidden rounded-md border border-slate-300 bg-white" role="group" aria-label="Months shown">
        <button
          v-for="n in [6, 12] as const"
          :key="n"
          type="button"
          class="px-3 py-1 text-dense"
          :class="span === n ? 'bg-primary font-semibold text-primary-contrast' : 'hover:bg-slate-100'"
          :aria-pressed="span === n"
          :data-testid="`span-${n}`"
          @click="span = n"
        >
          {{ n }} months
        </button>
      </div>
    </div>

    <div class="grid items-start gap-3 2xl:grid-cols-2">
      <section class="card p-3" data-testid="report-income-vs-spending">
        <div class="mb-1 flex flex-wrap items-baseline gap-x-3">
          <h2 class="card-title">Income and spending by month</h2>
          <span class="flex items-center gap-3 text-sm text-slate-700">
            <span class="inline-flex items-center gap-1"><span class="h-3 w-3 rounded-sm" :style="{ background: INCOME_COLOR }" />Income</span>
            <span class="inline-flex items-center gap-1"><span class="h-3 w-3 rounded-sm" :style="{ background: EXPENSE_COLOR }" />Spent</span>
          </span>
        </div>
        <p v-if="monthly.error.value && !monthly.data.value" class="text-sm text-expense" role="alert">
          Couldn't load the months. {{ describeError(monthly.error.value) }}
        </p>
        <template v-else-if="monthly.data.value">
          <BarChart
            :labels="labels"
            :titles="titles"
            :series="incomeSeries"
            mode="grouped"
            :highlight="last"
            summary="Income and spending by month; the numbers are in the table below"
          />
          <table class="dense-table mt-2" data-testid="income-vs-spending-table">
            <thead>
              <tr>
                <th>Month</th>
                <th class="text-right">Income</th>
                <th class="text-right">Spent</th>
                <th class="text-right">Net</th>
                <th class="text-right">Saved</th>
                <th class="text-right">Entries</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="m in [...trendMonths].reverse()" :key="monthKey(m.month)" :class="{ 'font-semibold': compareMonths(m.month, month) === 0 }">
                <td>{{ monthShortLabel(m.month) }}</td>
                <td class="num" :style="{ color: INCOME_COLOR }">{{ formatRupeesCompact(m.incomePaise) }}</td>
                <td class="num" :style="{ color: EXPENSE_COLOR }">{{ formatRupeesCompact(m.expensePaise) }}</td>
                <td class="num">{{ formatRupeesCompact(m.incomePaise - m.expensePaise) }}</td>
                <td class="num text-slate-600">{{ savedPercent(m.incomePaise, m.expensePaise) === null ? '–' : `${savedPercent(m.incomePaise, m.expensePaise)}%` }}</td>
                <td class="num text-slate-600">{{ m.expenseCount + m.incomeCount }}</td>
              </tr>
              <tr class="font-semibold">
                <td>Total</td>
                <td class="num">{{ formatRupeesCompact(trendTotals.income) }}</td>
                <td class="num">{{ formatRupeesCompact(trendTotals.spent) }}</td>
                <td class="num">{{ formatRupeesCompact(trendTotals.income - trendTotals.spent) }}</td>
                <td class="num text-slate-600">{{ savedPercent(trendTotals.income, trendTotals.spent) === null ? '–' : `${savedPercent(trendTotals.income, trendTotals.spent)}%` }}</td>
                <td></td>
              </tr>
            </tbody>
          </table>
        </template>
        <p v-else class="muted py-6">Loading…</p>
      </section>

      <section class="card p-3" data-testid="report-category-trend">
        <div class="mb-1 flex flex-wrap items-baseline gap-x-3">
          <h2 class="card-title">Spending by category, month by month</h2>
          <span class="text-sm text-slate-600">Top 5 in the chart, every category in the table</span>
        </div>
        <p v-if="monthlyCategories.error.value && !monthlyCategories.data.value" class="text-sm text-expense" role="alert">
          Couldn't load the categories. {{ describeError(monthlyCategories.error.value) }}
        </p>
        <p v-else-if="!monthlyCategories.data.value" class="muted py-6">Loading…</p>
        <p v-else-if="trend.rows.length === 0" class="py-4 text-slate-600">No spending in these months.</p>
        <template v-else>
          <ul class="mb-1 flex flex-wrap gap-x-4 gap-y-1 text-sm text-slate-700" data-testid="trend-legend">
            <li v-for="s in trend.series" :key="s.key" class="inline-flex items-center gap-1.5">
              <TxnAvatar v-if="s.category" :category="s.category" :size="18" />
              <TxnAvatar v-else-if="s.key === 'uncategorized'" kind="uncategorized" :size="18" />
              <span v-else class="h-3 w-3 rounded-sm" :style="{ background: s.color }" />
              {{ s.name }}
            </li>
          </ul>
          <BarChart
            :labels="labels"
            :titles="titles"
            :series="trendSeries"
            mode="stacked"
            :highlight="last"
            summary="Spending by category per month; the numbers are in the table below"
          />
          <div class="mt-2 overflow-x-auto">
            <table class="dense-table" data-testid="category-pivot">
              <thead>
                <tr>
                  <th class="sticky left-0 z-[1]">Category</th>
                  <th v-for="(m, i) in months" :key="monthKey(m)" class="text-right" :class="{ 'text-primary': i === last }">{{ labels[i] }}</th>
                  <th class="text-right">Total</th>
                  <th class="text-right">Average</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="r in trend.rows" :key="r.key">
                  <td class="sticky left-0 z-[1] bg-white">
                    <span class="flex items-center gap-2 whitespace-nowrap">
                      <TxnAvatar v-if="r.category" :category="r.category" :size="22" />
                      <TxnAvatar v-else-if="r.key === 'uncategorized'" kind="uncategorized" :size="22" />
                      {{ r.name }}
                    </span>
                  </td>
                  <td v-for="(v, i) in r.perMonth" :key="i" class="num" :class="v === 0 ? 'text-slate-500' : ''">
                    {{ v === 0 ? '–' : formatRupeesCompact(v) }}
                  </td>
                  <td class="num font-semibold">{{ formatRupeesCompact(r.total) }}</td>
                  <td class="num text-slate-600">{{ formatRupeesCompact(Math.round(r.total / months.length)) }}</td>
                </tr>
                <tr class="font-semibold">
                  <td class="sticky left-0 z-[1] bg-white">Total</td>
                  <td v-for="(v, i) in trend.monthTotals" :key="i" class="num">{{ formatRupeesCompact(v) }}</td>
                  <td class="num">{{ formatRupeesCompact(grand) }}</td>
                  <td class="num text-slate-600">{{ formatRupeesCompact(Math.round(grand / months.length)) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>
      </section>
    </div>
  </div>
</template>
