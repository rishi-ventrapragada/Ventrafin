<script setup lang="ts">
// Add or edit a recurring bill. Same fields and rules as the phone's bill
// form. The database fills in which month is owed first.
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { computed, ref, watch } from 'vue'
import { useApp } from '@/data/appContext'
import { billNameError, dueDayLabel } from '@/lib/bills'
import { describeError } from '@/lib/errors'
import { formatAmountInput, parseRupeesToPaise } from '@/lib/money'
import { BILL_KINDS, BILL_NAME_MAX, sortByName, type Bill, type BillKind } from '@/lib/models'
import AppIcon from './AppIcon.vue'

/** `undefined`: closed; `null`: a new bill; a bill: edit it. */
const props = defineProps<{ bill: Bill | null | undefined }>()
const emit = defineEmits<{ close: []; saved: [name: string] }>()

const app = useApp()

const name = ref('')
const kind = ref<BillKind>('utility')
const amount = ref('')
const dueDay = ref(10)
const accountId = ref('')
const categoryId = ref('')
const reminder = ref(true)
const tried = ref(false)
const saving = ref(false)
const error = ref<string | null>(null)
/** Generated once per opening, so retrying a failed save can't add the bill twice. */
let newId = ''

watch(
  () => props.bill,
  (b) => {
    if (b === undefined) return
    tried.value = false
    error.value = null
    if (b) {
      name.value = b.name
      kind.value = b.kind
      amount.value = formatAmountInput(b.amountPaise)
      dueDay.value = b.dueDay
      accountId.value = b.accountId
      categoryId.value = b.categoryId ?? ''
      reminder.value = b.reminderEnabled
    } else {
      newId = crypto.randomUUID()
      const accounts = app.accounts.data.value ?? []
      name.value = ''
      kind.value = 'utility'
      amount.value = ''
      dueDay.value = 10
      accountId.value = (accounts.find((a) => a.type === 'bank') ?? accounts[0])?.id ?? ''
      categoryId.value = ''
      reminder.value = true
    }
  },
  { immediate: true },
)

const visible = computed({
  get: () => props.bill !== undefined,
  set: (v) => {
    if (!v && !saving.value) emit('close')
  },
})

const nameError = computed(() => billNameError(name.value, BILL_NAME_MAX))
const paise = computed(() => {
  const p = parseRupeesToPaise(amount.value)
  return p !== null && p > 0 ? p : null
})
const expenseCategories = computed(() =>
  sortByName((app.categories.data.value ?? []).filter((c) => c.kind === 'expense' && (!c.archived || c.id === categoryId.value))),
)
const masterOff = computed(() => app.profile.data.value?.billRemindersEnabled === false)

async function save() {
  tried.value = true
  if (nameError.value || paise.value === null || !accountId.value) return
  error.value = null
  saving.value = true
  const draft = {
    name: name.value,
    kind: kind.value,
    amountPaise: paise.value,
    dueDay: dueDay.value,
    accountId: accountId.value,
    categoryId: categoryId.value || null,
    reminderEnabled: reminder.value,
  }
  try {
    app.requireOnline()
    if (props.bill) await app.repo.updateBill(props.bill.id, draft)
    else await app.repo.insertBill(newId, draft)
    app.bump(['recurring_bills'])
    emit('saved', draft.name.trim())
  } catch (e) {
    error.value = `Not saved. ${describeError(e)}`
  } finally {
    saving.value = false
  }
}

const field = 'w-full rounded-md border border-slate-300 bg-white px-2.5 py-1.5 outline-none focus:border-primary'
</script>

<template>
  <Dialog v-model:visible="visible" modal :header="bill ? 'Edit bill' : 'Add bill'" :style="{ width: 'min(34rem, 96vw)' }">
    <form class="flex flex-col gap-3" data-testid="bill-form" @submit.prevent="save">
      <label class="flex flex-col gap-1">
        <span class="font-medium text-slate-700">Name</span>
        <input v-model="name" :class="field" :maxlength="BILL_NAME_MAX + 10" data-testid="bill-name" autocomplete="off" />
        <span v-if="tried && nameError" class="text-sm text-expense">{{ nameError }}</span>
      </label>
      <div class="flex gap-2" role="radiogroup" aria-label="Kind">
        <button
          v-for="k in BILL_KINDS"
          :key="k.value"
          type="button"
          role="radio"
          :aria-checked="kind === k.value"
          class="inline-flex flex-1 items-center justify-center gap-1.5 rounded-md border px-3 py-1.5"
          :class="kind === k.value ? 'border-primary bg-primary-soft font-semibold text-primary' : 'border-slate-300 hover:bg-slate-50'"
          :data-testid="`bill-kind-${k.value}`"
          @click="kind = k.value"
        >
          <AppIcon :name="k.icon" :size="20" /> {{ k.label }}
        </button>
      </div>
      <div class="grid grid-cols-[1fr_9rem] gap-3">
        <label class="flex flex-col gap-1">
          <span class="font-medium text-slate-700">Usual amount (₹)</span>
          <input v-model="amount" :class="field" inputmode="decimal" data-testid="bill-amount" autocomplete="off" />
          <span v-if="tried && paise === null" class="text-sm text-expense">Enter an amount above zero</span>
        </label>
        <label class="flex flex-col gap-1">
          <span class="font-medium text-slate-700">Due day</span>
          <select v-model.number="dueDay" :class="field" data-testid="bill-due-day">
            <option v-for="d in 31" :key="d" :value="d">{{ d === 31 ? '31 (last)' : d }}</option>
          </select>
        </label>
      </div>
      <p class="-mt-1 text-sm text-slate-600">Due on the {{ dueDayLabel(dueDay) }}. Shorter months use their last day.</p>
      <div class="grid grid-cols-2 gap-3">
        <label class="flex flex-col gap-1">
          <span class="font-medium text-slate-700">Paid from</span>
          <select v-model="accountId" :class="field" data-testid="bill-account">
            <option v-for="a in app.accounts.data.value ?? []" :key="a.id" :value="a.id">{{ a.name }}</option>
          </select>
        </label>
        <label class="flex flex-col gap-1">
          <span class="font-medium text-slate-700">Category</span>
          <select v-model="categoryId" :class="field" data-testid="bill-category">
            <option value="">Auto (from the name)</option>
            <option v-for="c in expenseCategories" :key="c.id" :value="c.id">{{ c.name }}</option>
          </select>
        </label>
      </div>
      <label class="flex items-start gap-2">
        <input v-model="reminder" type="checkbox" class="mt-1 h-4 w-4 accent-[var(--vf-primary)]" data-testid="bill-reminder" />
        <span>
          <span class="font-medium">Remind me on the phone</span>
          <span class="block text-sm text-slate-600">
            {{ masterOff ? 'Bill reminders are switched off in the phone’s Settings.' : 'Before the due date and on the day, at 9:00 am.' }}
          </span>
        </span>
      </label>
      <p v-if="error" class="text-sm text-expense" role="alert">{{ error }}</p>
    </form>
    <template #footer>
      <Button label="Cancel" severity="secondary" text :disabled="saving" @click="emit('close')" />
      <Button :label="bill ? 'Save' : 'Add bill'" :loading="saving" data-testid="bill-save" @click="save" />
    </template>
  </Dialog>
</template>
