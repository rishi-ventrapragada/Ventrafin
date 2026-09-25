<script setup lang="ts">
// What was saved on this visit to Add, as the database returned it, so the
// category each row got (often chosen automatically) is visible right away.
import { computed } from 'vue'
import { RouterLink } from 'vue-router'
import AppIcon from '@/components/AppIcon.vue'
import MerchantBadge from '@/components/MerchantBadge.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { formatDateIndian } from '@/lib/dates'
import { formatRupees } from '@/lib/money'
import { readableTextColor } from '@/lib/categoryStyle'
import { methodLabel, type Account, type Category, type Txn } from '@/lib/models'

const readableTextColorFor = (c: Category | undefined) => (c ? readableTextColor(c.color) : '#64748b')

const props = defineProps<{
  saved: readonly Txn[]
  accounts: readonly Account[]
  categories: readonly Category[]
}>()

const categoryById = computed(() => new Map(props.categories.map((c) => [c.id, c])))
const accountById = computed(() => new Map(props.accounts.map((a) => [a.id, a])))
const spent = computed(() => props.saved.filter((t) => t.type === 'expense').reduce((s, t) => s + t.amountPaise, 0))
const autoCount = computed(() => props.saved.filter((t) => t.autoCategorized).length)
</script>

<template>
  <section class="card overflow-hidden" data-testid="saved-panel" aria-label="Saved this session">
    <header class="flex flex-wrap items-center gap-2 border-b border-slate-200 bg-green-50 px-3 py-2">
      <AppIcon name="check_circle" filled :size="18" class="text-income" />
      <h2 class="font-semibold text-slate-800" data-testid="saved-summary">
        {{ saved.length }} saved this session<template v-if="spent > 0"> · {{ formatRupees(spent) }} spent</template>
      </h2>
      <span v-if="autoCount" class="text-sm text-slate-600">
        · {{ autoCount }} categorized automatically (change any in Transactions; Ventrafin learns from it)
      </span>
      <RouterLink to="/transactions" class="ml-auto text-sm font-medium text-ocean hover:underline">Open Transactions</RouterLink>
    </header>
    <div class="max-h-80 overflow-auto">
      <table class="dense-table">
        <thead>
          <tr>
            <th>Date</th>
            <th>Description</th>
            <th class="text-right">Amount</th>
            <th>Category</th>
            <th>Account · Paid by</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="t in saved" :key="t.id" :data-saved-id="t.id">
            <td class="whitespace-nowrap">{{ formatDateIndian(t.date) }}</td>
            <td>
              <span class="flex items-center gap-1.5">
                <MerchantBadge :description="t.description" :size="15" />
                <span :class="t.description ? '' : 'italic text-slate-400'">{{ t.description || '(no description)' }}</span>
              </span>
            </td>
            <td
              class="num font-semibold"
              :class="t.type === 'expense' ? 'text-expense' : t.type === 'income' ? 'text-income' : 'text-transfer'"
            >
              {{ t.type === 'income' ? '+' : '' }}{{ formatRupees(t.amountPaise) }}
            </td>
            <td class="whitespace-nowrap" data-testid="saved-category">
              <span class="inline-flex items-center gap-1.5">
                <template v-if="t.type === 'transfer'">
                  <TxnAvatar kind="transfer" :size="20" /><span class="text-transfer">Transfer</span>
                </template>
                <template v-else-if="!t.categoryId">
                  <TxnAvatar kind="uncategorized" :size="20" /><span class="text-uncat">Uncategorized</span>
                </template>
                <template v-else>
                  <TxnAvatar :category="categoryById.get(t.categoryId) ?? null" :size="20" />
                  <span
                    class="font-semibold"
                    :style="{ color: readableTextColorFor(categoryById.get(t.categoryId)) }"
                    >{{ categoryById.get(t.categoryId)?.name ?? 'New category' }}</span
                  >
                  <span v-if="t.autoCategorized" class="rounded bg-slate-100 px-1 text-xs text-slate-500">auto</span>
                </template>
              </span>
            </td>
            <td class="whitespace-nowrap text-slate-600">
              {{ accountById.get(t.accountId)?.name ?? '' }}
              <template v-if="t.toAccountId"> → {{ accountById.get(t.toAccountId)?.name ?? '' }}</template>
              <template v-if="t.paymentMethod"> · {{ methodLabel(t.paymentMethod) }}</template>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
