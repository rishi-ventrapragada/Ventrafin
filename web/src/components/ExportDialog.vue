<script setup lang="ts">
// Download transactions as a CSV file that opens in Excel (PRD § 4.9). The
// file is built by Postgres (export_transactions_csv), so it is the same
// file the phone shares. From the Transactions page the first choice is
// exactly what's on screen, filters included. Opens on the chosen range;
// Enter downloads.
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { useToast } from 'primevue/usetoast'
import { computed, ref, useId } from 'vue'
import AppIcon from '@/components/AppIcon.vue'
import { useApp } from '@/data/appContext'
import { submitOnEnter } from '@/directives'
import { downloadCsv } from '@/lib/download'
import { describeError } from '@/lib/errors'
import {
  RANGE_PRESETS,
  exportFileName,
  financialYearLabel,
  financialYearStart,
  presetRange,
  rangeLabel,
  rangeProblem,
  type DateRange,
  type RangePreset,
} from '@/lib/exportRange'
import { splitDelimited } from '@/lib/paste'

const props = defineProps<{
  /** The Transactions page's current view: its month and, when filtered, the rows shown. */
  shown?: { range: DateRange; ids: readonly string[] | null; count: number; label: string }
}>()

const visible = defineModel<boolean>('visible', { required: true })

const app = useApp()
const toast = useToast()
const formId = useId()

type Choice = RangePreset | 'shown'
const choice = ref<Choice>(props.shown ? 'shown' : 'thisMonth')
const customFrom = ref('')
const customTo = ref(app.today.value)
const busy = ref(false)
const failure = ref<string | null>(null)

const options = computed(() => {
  const fy = financialYearStart(app.today.value)
  const lastFy = `${Number(fy.slice(0, 4)) - 1}-04-01`
  const list: { value: Choice; label: string; detail: string }[] = RANGE_PRESETS.map((p) => {
    const r = presetRange(p.value, app.today.value)
    const detail =
      p.value === 'thisFy'
        ? `${financialYearLabel(fy)}: ${rangeLabel(r!)}`
        : p.value === 'lastFy'
          ? `${financialYearLabel(lastFy)}: ${rangeLabel(r!)}`
          : r
            ? rangeLabel(r)
            : 'Any start and end date'
    return { value: p.value, label: p.label, detail }
  })
  if (props.shown) {
    list.unshift({
      value: 'shown',
      label: 'What the Transactions page shows',
      detail: `${props.shown.label} · ${props.shown.count} transaction${props.shown.count === 1 ? '' : 's'}`,
    })
  }
  return list
})

const range = computed<DateRange>(() => {
  if (choice.value === 'shown' && props.shown) return props.shown.range
  if (choice.value === 'custom') return { from: customFrom.value || null, to: customTo.value || null }
  return presetRange(choice.value as RangePreset, app.today.value)!
})
const problem = computed(() => rangeProblem(range.value))

async function download() {
  if (busy.value || problem.value) return
  failure.value = null
  busy.value = true
  try {
    app.requireOnline()
    const ids = choice.value === 'shown' ? (props.shown?.ids ?? undefined) : undefined
    const csv = await app.repo.exportTransactionsCsv({ ...range.value, ...(ids ? { ids } : {}) })
    const count = splitDelimited(csv, ',').length - 1
    if (count <= 0) {
      failure.value = 'There are no transactions in that range, so there is nothing to download.'
      return
    }
    downloadCsv(exportFileName(range.value, app.today.value, { filtered: Boolean(ids) }), csv)
    toast.add({
      severity: 'success',
      summary: `Downloaded ${count} transaction${count === 1 ? '' : 's'}`,
      detail: 'The CSV file is in your Downloads folder. Double-click it to open it in Excel.',
      life: 6000,
    })
    visible.value = false
  } catch (e) {
    failure.value = describeError(e)
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <Dialog v-model:visible="visible" modal header="Download transactions (CSV for Excel)" :style="{ width: 'min(40rem, 96vw)' }">
    <form :id="formId" class="flex flex-col gap-3" @submit.prevent="download" @keydown="submitOnEnter">
      <div role="radiogroup" aria-label="Which transactions" class="flex flex-col gap-1" data-testid="export-ranges">
        <label
          v-for="o in options"
          :key="o.value"
          class="flex cursor-pointer items-start gap-2 rounded-md border px-3 py-2"
          :class="choice === o.value ? 'border-primary bg-primary-soft' : 'border-slate-200 hover:bg-slate-50'"
          :data-range="o.value"
        >
          <input
            v-model="choice"
            type="radio"
            name="export-range"
            :value="o.value"
            :autofocus="o.value === choice"
            class="mt-1 accent-[var(--p-primary-color)]"
          />
          <span>
            <span class="block font-medium">{{ o.label }}</span>
            <span class="block text-sm text-slate-600">{{ o.detail }}</span>
          </span>
        </label>
      </div>

      <div v-if="choice === 'custom'" class="flex flex-wrap items-center gap-2">
        <label class="text-sm font-medium" for="export-from">From</label>
        <input id="export-from" v-model="customFrom" type="date" class="focus-ring rounded-md border border-slate-300 px-2 py-1" data-testid="export-from" />
        <label class="text-sm font-medium" for="export-to">to</label>
        <input id="export-to" v-model="customTo" type="date" class="focus-ring rounded-md border border-slate-300 px-2 py-1" data-testid="export-to" />
        <span class="text-sm text-slate-600">(leave "From" empty for everything up to the end date)</span>
      </div>

      <p class="text-sm text-slate-600">
        Columns: Date, Description, Amount (₹), Type, Category, Account, To account, Paid by. Oldest first. The phone's
        Settings › Export makes the same file. A CSV file can also be imported back in Settings.
      </p>
      <p v-if="problem" class="text-sm text-expense" role="alert">{{ problem }}</p>
      <p v-if="failure" class="text-sm text-expense" role="alert" data-testid="export-failure">
        <AppIcon name="error" filled :size="18" class="align-[-4px]" /> {{ failure }}
      </p>
    </form>
    <template #footer>
      <Button label="Cancel" severity="secondary" text :disabled="busy" @click="visible = false" />
      <Button type="submit" :form="formId" label="Download CSV" :loading="busy" :disabled="problem !== null" data-testid="export-download">
        <template #icon><AppIcon name="download" :size="20" /></template>
      </Button>
    </template>
  </Dialog>
</template>
