<script setup lang="ts">
// The accounts with their type (PRD § 4.1) and this month's totals for each
// (get_account_totals: spent, income, transfers out and in, entries). Click
// an account for its transactions this month; Edit renames it, changes its
// type or archives it; archived ones wait at the bottom with a Restore
// button. Accounts are archived, never deleted, because their transactions
// and bills keep them. Same as the phone.
import Button from 'primevue/button'
import { computed, ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import AccountAvatar from '@/components/AccountAvatar.vue'
import AccountDialog from '@/components/AccountDialog.vue'
import AppIcon from '@/components/AppIcon.vue'
import LoadError from '@/components/LoadError.vue'
import { useNotify } from '@/components/useNotify'
import { useApp } from '@/data/appContext'
import { monthKey, monthLabel, monthOf } from '@/lib/dates'
import { describeError } from '@/lib/errors'
import { formatRupeesCompact } from '@/lib/money'
import { ACCOUNT_TYPES, sortByName, type Account, type AccountTotals } from '@/lib/models'
import { EXPENSE_COLOR, INCOME_COLOR } from '@/lib/theme'

const app = useApp()
const router = useRouter()
const notify = useNotify()

const accounts = computed(() => app.accounts.data.value)
const active = computed(() => (accounts.value ?? []).filter((a) => !a.archived))
const archived = computed(() => sortByName((accounts.value ?? []).filter((a) => a.archived)))

// This month's totals per account; a new entry or a new account re-fetches.
const thisMonth = computed(() => monthOf(app.today.value))
const totals = app.liveQuery(
  ['transactions', 'accounts'],
  () => app.repo.fetchAccountTotals(thisMonth.value),
  () => monthKey(thisMonth.value),
)
const totalsById = computed(() => new Map((totals.data.value ?? []).map((t) => [t.accountId, t])))
type Sums = Omit<AccountTotals, 'accountId' | 'month'>
const NONE: Sums = { expensePaise: 0, incomePaise: 0, transferOutPaise: 0, transferInPaise: 0, entryCount: 0 }
/** An account's totals; zeros for one added after the totals were fetched. */
const totalsOf = (id: string): Sums => totalsById.value.get(id) ?? NONE
const sumOf = (key: keyof Sums) => active.value.reduce((s, a) => s + totalsOf(a.id)[key], 0)

/** Transactions for this account, this month. */
const txnsLink = (a: Account) => ({ path: '/transactions', query: { month: monthKey(thisMonth.value), account: a.id } })

/** `undefined`: closed; `null`: adding; an account: editing it. */
const editing = ref<Account | null | undefined>(undefined)
const restoring = ref<string | null>(null)

/** No confirm: restoring hides nothing and can be archived again. */
async function restore(a: Account) {
  restoring.value = a.id
  try {
    app.requireOnline()
    await app.repo.setAccountArchived(a.id, false)
    app.bump(['accounts'])
    notify.success(`Restored ${a.name}`)
  } catch (e) {
    notify.error('Not restored', describeError(e))
  } finally {
    restoring.value = null
  }
}
</script>

<template>
  <div class="flex max-w-5xl flex-col gap-3">
    <div class="flex items-end gap-2">
      <div class="mr-auto">
        <h1 class="text-xl font-semibold text-slate-800">Accounts</h1>
        <p class="text-sm text-slate-600">
          Totals for {{ monthLabel(thisMonth) }}. Click an account to see its transactions; Edit renames it, changes its
          type or archives it.
        </p>
      </div>
      <Button label="Add account" data-testid="add-account" @click="editing = null">
        <template #icon><AppIcon name="add" :size="20" /></template>
      </Button>
    </div>

    <LoadError
      v-if="!accounts && app.accounts.error.value"
      :error="app.accounts.error.value"
      what="Couldn't load accounts."
      @retry="app.accounts.refresh()"
    />
    <div v-else-if="!accounts" class="muted">Loading…</div>
    <template v-else>
      <LoadError
        v-if="totals.error.value && !totals.data.value"
        compact
        :error="totals.error.value"
        what="Couldn't load this month's totals."
        @retry="totals.refresh()"
      />
      <div class="card overflow-x-auto">
        <table class="dense-table" data-testid="accounts-table">
          <thead>
            <tr>
              <th class="w-10"></th>
              <th>Account</th>
              <th>Type</th>
              <th class="text-right">Spent</th>
              <th class="text-right">Income</th>
              <th class="text-right">Transfers out</th>
              <th class="text-right">Transfers in</th>
              <th class="text-right">Entries</th>
              <th class="w-24"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="a in active" :key="a.id" class="cursor-pointer" :data-account-id="a.id" @click="router.push(txnsLink(a))">
              <td><AccountAvatar :type="a.type" :size="32" /></td>
              <td class="font-medium">
                <RouterLink
                  :to="txnsLink(a)"
                  class="hover:underline"
                  :title="`Transactions in ${monthLabel(thisMonth)}`"
                  :data-testid="`account-txns-${a.id}`"
                  @click.stop
                  >{{ a.name }}</RouterLink
                >
              </td>
              <td class="text-slate-600">{{ ACCOUNT_TYPES[a.type].label }}</td>
              <template v-if="totals.data.value">
                <td class="num font-semibold" :style="{ color: EXPENSE_COLOR }" data-testid="account-spent">
                  {{ formatRupeesCompact(totalsOf(a.id).expensePaise) }}
                </td>
                <td class="num font-semibold" :style="{ color: INCOME_COLOR }" data-testid="account-income">
                  {{ formatRupeesCompact(totalsOf(a.id).incomePaise) }}
                </td>
                <td class="num text-transfer" data-testid="account-out">{{ formatRupeesCompact(totalsOf(a.id).transferOutPaise) }}</td>
                <td class="num text-transfer" data-testid="account-in">{{ formatRupeesCompact(totalsOf(a.id).transferInPaise) }}</td>
                <td class="num text-slate-700" data-testid="account-entries">{{ totalsOf(a.id).entryCount }}</td>
              </template>
              <td v-else colspan="5" class="text-center text-slate-600">{{ totals.error.value ? '' : '…' }}</td>
              <td class="text-right">
                <button
                  type="button"
                  class="inline-flex items-center gap-1 rounded px-2 py-0.5 font-medium text-primary hover:bg-primary-soft"
                  :aria-label="`Edit ${a.name}`"
                  :data-testid="`edit-account-${a.id}`"
                  @click.stop="editing = a"
                >
                  <AppIcon name="edit" :size="19" /> Edit
                </button>
              </td>
            </tr>
            <tr v-if="totals.data.value && active.length > 1" class="font-semibold" data-testid="accounts-total">
              <td></td>
              <td>Total</td>
              <td></td>
              <td class="num">{{ formatRupeesCompact(sumOf('expensePaise')) }}</td>
              <td class="num">{{ formatRupeesCompact(sumOf('incomePaise')) }}</td>
              <td class="num">{{ formatRupeesCompact(sumOf('transferOutPaise')) }}</td>
              <td class="num">{{ formatRupeesCompact(sumOf('transferInPaise')) }}</td>
              <td></td>
              <td></td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="archived.length" class="card overflow-hidden">
        <table class="dense-table" data-testid="accounts-archived">
          <thead>
            <tr>
              <th class="w-10"></th>
              <th>Archived ({{ archived.length }})</th>
              <th>Type</th>
              <th class="w-28"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="a in archived" :key="a.id" :data-account-id="a.id">
              <td><AccountAvatar :type="a.type" :size="32" /></td>
              <td class="font-medium text-slate-700">{{ a.name }}</td>
              <td class="text-slate-600">{{ ACCOUNT_TYPES[a.type].label }}</td>
              <td class="text-right">
                <button
                  type="button"
                  class="inline-flex items-center gap-1 rounded px-2 py-0.5 font-medium text-primary hover:bg-primary-soft disabled:opacity-60"
                  :aria-label="`Restore ${a.name}`"
                  :disabled="restoring === a.id"
                  :data-testid="`restore-${a.id}`"
                  @click="restore(a)"
                >
                  <AppIcon name="unarchive" :size="19" /> Restore
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="text-sm text-slate-600">
        Spent and Income are this month's expenses and income booked to each account; transfers between your own
        accounts are not spending. Entries counts both sides of a transfer. Archived accounts are left out of the account
        pickers; their transactions and bills keep them.
      </p>
    </template>

    <AccountDialog :account="editing" @close="editing = undefined" />
  </div>
</template>
