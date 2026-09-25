<script setup lang="ts">
// Recurring bills and EMIs, soonest due first: overdue ones in red, due
// within a week in amber. Due dates and status come from Postgres
// (get_bill_schedule), exactly as on the phone. No notifications here
// (ARCHITECTURE.md § 6): reminders pop up on the phone.
import Button from 'primevue/button'
import { useConfirm } from 'primevue/useconfirm'
import { useToast } from 'primevue/usetoast'
import { computed, ref } from 'vue'
import AccountAvatar from '@/components/AccountAvatar.vue'
import AppIcon from '@/components/AppIcon.vue'
import BillDialog from '@/components/BillDialog.vue'
import IconCircle from '@/components/IconCircle.vue'
import LoadError from '@/components/LoadError.vue'
import MarkPaidDialog from '@/components/MarkPaidDialog.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { useApp } from '@/data/appContext'
import { billStatusLabel, billStatusLook, dueDayLabel } from '@/lib/bills'
import { formatDateIndian, monthLabel, previousMonth } from '@/lib/dates'
import { describeError } from '@/lib/errors'
import { formatRupeesCompact } from '@/lib/money'
import { BILL_KINDS, formatTimeOfDay, type Bill, type MarkPaidResult } from '@/lib/models'
import { TRANSFER_COLOR, UNCATEGORIZED_INK } from '@/lib/theme'

const app = useApp()
const toast = useToast()
const confirmDialog = useConfirm()

// Status depends on today: re-fetch when the date ticks over.
const bills = app.liveQuery(['recurring_bills'], () => app.repo.fetchBills(), () => app.today.value)

const accountsById = computed(() => new Map((app.accounts.data.value ?? []).map((a) => [a.id, a])))
const categoriesById = computed(() => new Map((app.categories.data.value ?? []).map((c) => [c.id, c])))
const profile = computed(() => app.profile.data.value)

const list = computed(() => bills.data.value ?? [])
const overdue = computed(() => list.value.filter((b) => b.status === 'overdue'))
const soon = computed(() => list.value.filter((b) => b.status === 'due_today' || b.status === 'due_soon'))
const sum = (l: readonly Bill[]) => l.reduce((s, b) => s + b.amountPaise, 0)

const editing = ref<Bill | null | undefined>(undefined)
const paying = ref<Bill | null>(null)

function onSaved(name: string) {
  toast.add({ severity: 'success', summary: editing.value ? `Saved ${name}` : `Added ${name}`, life: 3000 })
  editing.value = undefined
}

function onPaid(bill: Bill, result: MarkPaidResult) {
  paying.value = null
  if (result.alreadyPaid) {
    toast.add({ severity: 'info', summary: `${bill.name} was already marked paid for ${monthLabel(result.paidThroughMonth)}.`, life: 4000 })
    return
  }
  const logged = result.transactionId !== null
  toast.add({
    severity: 'success',
    summary: `${bill.name} marked paid for ${monthLabel(result.paidThroughMonth)}`,
    detail: logged ? 'The payment was added to Transactions.' : undefined,
    life: 4000,
  })
}

async function toggleReminder(b: Bill) {
  try {
    app.requireOnline()
    await app.repo.setBillReminder(b.id, !b.reminderEnabled)
    app.bump(['recurring_bills'])
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Not changed', detail: describeError(e), life: 5000 })
  }
}

/** Moves the paid-up-to month back one. A payment already logged stays in Transactions. */
function markUnpaid(b: Bill) {
  const month = monthLabel(b.paidThroughMonth)
  confirmDialog.require({
    header: `Mark ${month} unpaid?`,
    message: `${b.name} will show ${month} as due again. A payment already added stays in Transactions.`,
    acceptLabel: 'Mark unpaid',
    rejectLabel: 'Cancel',
    defaultFocus: 'reject',
    rejectProps: { severity: 'secondary', outlined: true },
    accept: async () => {
      try {
        app.requireOnline()
        await app.repo.setBillPaidThrough(b.id, previousMonth(b.paidThroughMonth))
        app.bump(['recurring_bills'])
        toast.add({ severity: 'success', summary: `Marked ${month} unpaid for ${b.name}`, life: 3000 })
      } catch (e) {
        toast.add({ severity: 'error', summary: 'Not changed', detail: describeError(e), life: 5000 })
      }
    },
  })
}

function remove(b: Bill) {
  confirmDialog.require({
    header: `Delete ${b.name}?`,
    message: 'Its reminders stop. Payments already added to Transactions stay there.',
    acceptLabel: 'Delete',
    rejectLabel: 'Cancel',
    defaultFocus: 'reject',
    acceptProps: { severity: 'danger' },
    rejectProps: { severity: 'secondary', outlined: true },
    accept: async () => {
      try {
        app.requireOnline()
        await app.repo.deleteBill(b.id)
        app.bump(['recurring_bills'])
        toast.add({ severity: 'success', summary: `Deleted ${b.name}`, life: 3000 })
      } catch (e) {
        toast.add({ severity: 'error', summary: 'Not deleted', detail: describeError(e), life: 5000 })
      }
    },
  })
}

const kindOf = (b: Bill) => BILL_KINDS.find((k) => k.value === b.kind)!
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-2">
      <h1 class="mr-2 text-xl font-semibold text-slate-800">Bills</h1>
      <span class="text-slate-600">Utility bills and loan EMIs</span>
      <Button class="ml-auto" label="Add bill" data-testid="add-bill" @click="editing = null">
        <template #icon><AppIcon name="add" :size="21" /></template>
      </Button>
    </div>

    <div class="grid gap-3 sm:grid-cols-3" data-testid="bill-summary">
      <div class="card flex items-center gap-3 p-3" :class="overdue.length ? 'border-red-300 bg-red-50' : ''">
        <AppIcon name="error" :size="28" :class="overdue.length ? 'text-red-700' : 'text-slate-500'" />
        <div>
          <div class="text-sm text-slate-700">Overdue</div>
          <div class="text-lg font-semibold" :class="overdue.length ? 'text-red-800' : 'text-slate-700'" data-testid="overdue-total">
            {{ overdue.length ? `${overdue.length} · ${formatRupeesCompact(sum(overdue))}` : 'None' }}
          </div>
        </div>
      </div>
      <div class="card flex items-center gap-3 p-3" :class="soon.length ? 'border-amber-300 bg-amber-50' : ''">
        <AppIcon name="schedule" :size="28" :style="{ color: soon.length ? UNCATEGORIZED_INK : undefined }" :class="soon.length ? '' : 'text-slate-500'" />
        <div>
          <div class="text-sm text-slate-700">Due in the next 7 days</div>
          <div class="text-lg font-semibold" :style="{ color: soon.length ? UNCATEGORIZED_INK : undefined }">
            {{ soon.length ? `${soon.length} · ${formatRupeesCompact(sum(soon))}` : 'None' }}
          </div>
        </div>
      </div>
      <div class="card flex items-center gap-3 p-3">
        <AppIcon name="event_note" :size="28" class="text-slate-500" />
        <div>
          <div class="text-sm text-slate-700">Every month</div>
          <div class="text-lg font-semibold text-slate-800">{{ formatRupeesCompact(sum(list)) }}</div>
        </div>
      </div>
    </div>

    <LoadError v-if="bills.error.value && !bills.data.value" :error="bills.error.value" what="Couldn't load bills." @retry="bills.refresh()" />
    <div v-else-if="!bills.data.value" class="muted">Loading…</div>
    <div v-else-if="list.length === 0" class="card flex items-center gap-4 p-6 text-slate-700" data-testid="bills-empty">
      <AppIcon name="event_note" :size="48" class="text-slate-500" />
      <p>
        No bills yet. Add electricity, water, gas, phone and internet bills and loan EMIs to see what's due, and to be
        reminded on the phone before they are due.
      </p>
    </div>
    <div v-else class="card overflow-x-auto">
      <table class="dense-table" data-testid="bills-table">
        <thead>
          <tr>
            <th>Status</th>
            <th>Bill</th>
            <th class="text-right">Amount</th>
            <th>Next due</th>
            <th>Due every month</th>
            <th>Paid from</th>
            <th>Paid up to</th>
            <th class="text-center">Reminder</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="b in list" :key="b.id" :data-bill="b.id" :data-status="b.status">
            <td>
              <span
                class="inline-flex items-center gap-1 rounded-md px-2 py-0.5 font-semibold whitespace-nowrap"
                :style="{ color: billStatusLook(b.status).fg, background: billStatusLook(b.status).bg }"
                data-testid="bill-status"
              >
                <AppIcon :name="billStatusLook(b.status).icon" :size="17" /> {{ billStatusLabel(b) }}
              </span>
            </td>
            <td>
              <span class="flex items-center gap-2">
                <TxnAvatar v-if="b.categoryId && categoriesById.get(b.categoryId)" :category="categoriesById.get(b.categoryId)" :size="28" />
                <IconCircle v-else :icon="kindOf(b).icon" :color="TRANSFER_COLOR" outlined :size="28" :label="kindOf(b).label" />
                <span>
                  <span class="block font-medium">{{ b.name }}</span>
                  <span class="block text-sm text-slate-600">{{ kindOf(b).label }}</span>
                </span>
              </span>
            </td>
            <td class="num font-semibold">{{ formatRupeesCompact(b.amountPaise) }}</td>
            <td class="whitespace-nowrap">{{ formatDateIndian(b.nextDueDate) }}</td>
            <td class="text-slate-700">{{ dueDayLabel(b.dueDay).replace(' of every month', '') }}</td>
            <td>
              <span v-if="accountsById.get(b.accountId)" class="flex items-center gap-1.5 whitespace-nowrap">
                <AccountAvatar :type="accountsById.get(b.accountId)!.type" :size="22" />
                {{ accountsById.get(b.accountId)!.name }}
              </span>
            </td>
            <td class="whitespace-nowrap text-slate-700">
              {{ monthLabel(b.paidThroughMonth) }}
              <button
                type="button"
                class="ml-1 text-sm text-primary hover:underline"
                :aria-label="`Mark ${monthLabel(b.paidThroughMonth)} unpaid for ${b.name}`"
                :data-testid="`unpay-${b.id}`"
                @click="markUnpaid(b)"
              >
                Mark unpaid
              </button>
            </td>
            <td class="text-center">
              <button
                type="button"
                class="rounded p-1 hover:bg-slate-100"
                :class="b.reminderEnabled ? 'text-primary' : 'text-slate-500'"
                :aria-pressed="b.reminderEnabled"
                :aria-label="b.reminderEnabled ? `Reminder on for ${b.name}` : `Reminder off for ${b.name}`"
                v-tooltip.left="b.reminderEnabled ? 'Reminder on (the phone). Click to turn off.' : 'Reminder off. Click to turn on.'"
                :data-testid="`reminder-${b.id}`"
                @click="toggleReminder(b)"
              >
                <AppIcon :name="b.reminderEnabled ? 'notifications_active' : 'notifications_off'" :filled="b.reminderEnabled" :size="22" />
              </button>
            </td>
            <td>
              <span class="flex items-center justify-end gap-1 whitespace-nowrap">
                <Button size="small" label="Mark paid" :data-testid="`pay-${b.id}`" @click="paying = b">
                  <template #icon><AppIcon name="task_alt" :size="18" /></template>
                </Button>
                <button type="button" class="rounded p-1 text-slate-600 hover:bg-slate-100" :aria-label="`Edit ${b.name}`" :data-testid="`edit-${b.id}`" @click="editing = b">
                  <AppIcon name="edit" :size="20" />
                </button>
                <button type="button" class="rounded p-1 text-slate-600 hover:bg-slate-100" :aria-label="`Delete ${b.name}`" :data-testid="`delete-${b.id}`" @click="remove(b)">
                  <AppIcon name="delete" :size="20" />
                </button>
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <p class="flex items-start gap-2 text-sm text-slate-700" data-testid="reminder-note">
      <AppIcon name="notifications" :size="19" class="mt-px shrink-0 text-slate-600" />
      <span v-if="!profile">Reminders pop up on the phone.</span>
      <span v-else-if="!profile.billRemindersEnabled">
        Bill reminders are switched off in the phone's Settings; the daily reminder is separate. This page still shows what is due.
      </span>
      <span v-else>
        Reminders pop up on the phone at 9:00 am,
        {{ profile.billReminderDaysBefore === 0 ? 'on the due date' : `${profile.billReminderDaysBefore} ${profile.billReminderDaysBefore === 1 ? 'day' : 'days'} before and on the due date` }},
        for bills with the bell on. Changes made here reach the phone the next time Ventrafin is open there.
        <template v-if="profile.dailyReminderEnabled">The daily "log today's expenses" reminder is at {{ formatTimeOfDay(profile.dailyReminderTime) }}.</template>
      </span>
    </p>

    <BillDialog :bill="editing" @close="editing = undefined" @saved="onSaved" />
    <MarkPaidDialog :bill="paying" @close="paying = null" @done="onPaid" />
  </div>
</template>
