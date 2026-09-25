<script setup lang="ts">
// This month against last month (get_month_totals) and spending by category
// (get_month_comparison): the phone's Dashboard, laid out for a wide screen.
// Numbers come from Postgres; the browser only draws them.
import Button from 'primevue/button'
import { computed, ref, watch } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import AppIcon from '@/components/AppIcon.vue'
import ChangeCell from '@/components/ChangeCell.vue'
import DonutChart from '@/components/DonutChart.vue'
import MonthSwitcher from '@/components/MonthSwitcher.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { useApp } from '@/data/appContext'
import { UNCATEGORIZED_LOOK, categoryIconKey, readableTextColor } from '@/lib/categoryStyle'
import { compareMonths, monthKey, monthLabel, monthOf } from '@/lib/dates'
import { describeError } from '@/lib/errors'
import { formatRupees, formatRupeesCompact } from '@/lib/money'
import type { Category } from '@/lib/models'
import { EXPENSE_COLOR, INCOME_COLOR } from '@/lib/theme'

const app = useApp()
const router = useRouter()

const currentMonth = computed(() => monthOf(app.today.value))
const month = ref(currentMonth.value)
// Midnight on the last day of the month: follow along if showing "this month".
watch(currentMonth, (now, before) => {
  if (compareMonths(month.value, before) === 0) month.value = now
})

const totals = app.liveQuery(['transactions'], () => app.repo.fetchMonthTotals(month.value), () => monthKey(month.value))
// Category names and colours are joined in the SQL, so a rename re-fetches too.
const comparison = app.liveQuery(
  ['transactions', 'categories'],
  () => app.repo.fetchMonthComparison(month.value),
  () => monthKey(month.value),
)

const categoriesById = computed(() => new Map((app.categories.data.value ?? []).map((c) => [c.id, c])))

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
            <template #icon><AppIcon name="add" :size="18" /></template>
          </Button>
        </RouterLink>
        <RouterLink v-slot="{ navigate }" :to="{ path: '/transactions', query: { month: monthKey(month) } }" custom>
          <Button label="Transactions" severity="secondary" outlined @click="navigate">
            <template #icon><AppIcon name="receipt_long" :size="18" /></template>
          </Button>
        </RouterLink>
      </div>
    </div>

    <div class="grid items-start gap-3 xl:grid-cols-[minmax(22rem,30rem)_1fr]">
      <div class="flex flex-col gap-3">
        <section class="card p-3" data-testid="month-totals">
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
                <td>Spent</td>
                <td class="num font-semibold" :style="{ color: EXPENSE_COLOR }" data-testid="spent-now">{{ t ? formatRupees(t.expensePaise) : '…' }}</td>
                <td class="num text-slate-600">{{ t ? formatRupeesCompact(t.lastExpensePaise) : '' }}</td>
                <td class="num"><ChangeCell v-if="t" :now="t.expensePaise" :before="t.lastExpensePaise" /></td>
              </tr>
              <tr>
                <td>Income</td>
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
          <TxnAvatar kind="uncategorized" :size="30" />
          <span>
            <span class="block font-semibold text-slate-800">{{ t.uncategorizedCount }} uncategorized in {{ monthLabel(month) }}</span>
            <span class="text-sm text-slate-600">Open them and pick a category. Ventrafin learns from it.</span>
          </span>
          <AppIcon name="chevron_right" :size="20" class="ml-auto text-slate-500" />
        </button>
      </div>

      <section class="card p-3" data-testid="category-breakdown">
        <div class="mb-2 flex items-baseline gap-2">
          <h2 class="card-title">Spending by category</h2>
          <span class="text-sm text-slate-500">{{ monthLabel(month) }} against the month before</span>
        </div>
        <p v-if="comparison.error.value && !comparison.data.value" class="text-sm text-expense" role="alert">
          Couldn't load the breakdown. {{ describeError(comparison.error.value) }}
        </p>
        <p v-else-if="!comparison.data.value" class="muted py-6">Loading…</p>
        <p v-else-if="rows.length === 0" class="py-4 text-slate-600">Nothing spent yet in {{ monthLabel(month) }}.</p>
        <div v-else class="flex flex-col gap-4 lg:flex-row lg:items-start">
          <div class="flex items-center gap-4">
            <DonutChart
              v-if="spentTotal > 0"
              :segments="segments"
              center-label="Spent"
              :center-value="formatRupeesCompact(spentTotal)"
            />
            <ul class="flex min-w-[11rem] flex-col gap-1 text-sm">
              <li v-for="r in rows.filter((x) => x.now > 0).slice(0, 6)" :key="r.key" class="flex items-center gap-2">
                <TxnAvatar v-if="r.uncategorized" kind="uncategorized" :size="18" />
                <TxnAvatar v-else :category="r.category" :size="18" />
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
                    <TxnAvatar v-if="r.uncategorized" kind="uncategorized" :size="22" />
                    <TxnAvatar v-else :category="r.category" :size="22" />
                    <span :style="{ color: r.uncategorized ? undefined : readableTextColor(r.color) }" class="font-medium">{{ r.name }}</span>
                  </span>
                </td>
                <td class="num font-semibold">{{ formatRupeesCompact(r.now) }}</td>
                <td class="num text-slate-600">{{ formatRupeesCompact(r.before) }}</td>
                <td class="num"><ChangeCell :now="r.now" :before="r.before" /></td>
                <td class="num text-slate-500">{{ share(r.now) }}</td>
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
