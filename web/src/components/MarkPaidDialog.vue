<script setup lang="ts">
// "Mark October paid", optionally adding the payment to Transactions in the
// same step. The database does both at once and never twice
// (mark_bill_paid), so a retry, or the same bill marked paid on the phone,
// can't double-count. Same as the phone's sheet. Opens on the amount;
// Enter marks it paid.
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { computed, ref, useId, watch } from 'vue'
import { useApp } from '@/data/appContext'
import { submitOnEnter } from '@/directives'
import { defaultMethodFor } from '@/lib/bills'
import { formatDateIndian, monthLabel, monthOf } from '@/lib/dates'
import { describeError } from '@/lib/errors'
import { formatAmountInput, parseRupeesToPaise } from '@/lib/money'
import { PAYMENT_METHODS, type Bill, type MarkPaidResult, type PaymentMethod } from '@/lib/models'

const props = defineProps<{ bill: Bill | null }>()
const emit = defineEmits<{ close: []; done: [bill: Bill, result: MarkPaidResult] }>()

const app = useApp()
const formId = useId()

const log = ref(true)
const amount = ref('')
const method = ref<PaymentMethod>('upi')
const saving = ref(false)
const error = ref<string | null>(null)
let txnId = ''

const account = computed(() => app.accounts.data.value?.find((a) => a.id === props.bill?.accountId))

watch(
  () => props.bill,
  (b) => {
    if (!b) return
    log.value = true
    amount.value = formatAmountInput(b.amountPaise)
    method.value = defaultMethodFor(account.value?.type)
    error.value = null
    txnId = crypto.randomUUID()
  },
  { immediate: true },
)

const visible = computed({
  get: () => props.bill !== null,
  set: (v) => {
    if (!v && !saving.value) emit('close')
  },
})
const paise = computed(() => {
  const p = parseRupeesToPaise(amount.value)
  return p !== null && p > 0 ? p : null
})
const month = computed(() => (props.bill ? monthOf(props.bill.nextDueDate) : null))

async function confirm() {
  const b = props.bill
  if (!b || !month.value || (log.value && paise.value === null)) return
  error.value = null
  saving.value = true
  try {
    app.requireOnline()
    const result = await app.repo.markBillPaid({
      billId: b.id,
      month: month.value,
      txnId: log.value ? txnId : null,
      ...(log.value ? { amountPaise: paise.value!, paidOn: app.today.value, paymentMethod: method.value } : {}),
    })
    app.bump(['recurring_bills', 'transactions'])
    emit('done', b, result)
  } catch (e) {
    error.value = `Not marked paid. ${describeError(e)}`
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <Dialog v-model:visible="visible" modal :header="bill && month ? `Mark ${bill.name} paid for ${monthLabel(month)}` : ''" :style="{ width: 'min(30rem, 96vw)' }">
    <form v-if="bill" :id="formId" class="flex flex-col gap-3" data-testid="mark-paid-form" @submit.prevent="confirm" @keydown="submitOnEnter">
      <p class="text-slate-600">Due {{ formatDateIndian(bill.nextDueDate) }}</p>
      <label class="flex items-start gap-2">
        <input v-model="log" type="checkbox" class="mt-1 h-4 w-4 accent-[var(--vf-primary)]" data-testid="paid-log" />
        <span>
          <span class="font-medium">Also add it to Transactions</span>
          <span class="block text-sm text-slate-600">As an expense today{{ account ? `, from ${account.name}` : '' }}</span>
        </span>
      </label>
      <div v-if="log" class="grid grid-cols-[1fr_auto] items-end gap-3">
        <label class="flex flex-col gap-1">
          <span class="font-medium text-slate-700">Amount paid (₹)</span>
          <input
            v-model="amount"
            class="focus-ring w-full rounded-md border border-slate-300 px-2.5 py-1.5 focus:border-primary"
            inputmode="decimal"
            data-testid="paid-amount"
            autocomplete="off"
            autofocus
          />
        </label>
        <div class="flex gap-1" role="radiogroup" aria-label="Paid by">
          <button
            v-for="m in PAYMENT_METHODS"
            :key="m.value"
            type="button"
            role="radio"
            :aria-checked="method === m.value"
            class="rounded-md border px-2.5 py-1.5"
            :class="method === m.value ? 'border-primary bg-primary-soft font-semibold text-primary' : 'border-slate-300 hover:bg-slate-50'"
            :data-testid="`paid-method-${m.value}`"
            @click="method = m.value"
          >
            {{ m.label }}
          </button>
        </div>
      </div>
      <p v-if="log && paise === null" class="text-sm text-expense">Enter an amount above zero</p>
      <p v-if="error" class="text-sm text-expense" role="alert">{{ error }}</p>
    </form>
    <template #footer>
      <Button label="Cancel" severity="secondary" text :disabled="saving" @click="emit('close')" />
      <Button
        type="submit"
        :form="formId"
        label="Mark paid"
        :loading="saving"
        :disabled="log && paise === null"
        data-testid="paid-confirm"
      />
    </template>
  </Dialog>
</template>
