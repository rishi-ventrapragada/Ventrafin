<script setup lang="ts">
// Import transactions from a CSV file (PRD § 4.9): a bank statement saved
// from Excel, an old spreadsheet, or a Ventrafin export. The file goes
// through the same column detection, row parser and preview as "Paste from
// Excel", so it is checked exactly the same way. Rows already saved (same
// date, amount, type, account and description) are skipped unless asked.
// Nothing is saved until the user confirms; rows that can't be saved go to
// the Add grid to be fixed. Categories are left to the database's
// auto-categorization, like every other entry. Opens on "Choose a CSV
// file"; Enter saves.
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import Select from 'primevue/select'
import { computed, reactive, ref, shallowRef, useId, watch } from 'vue'
import { useRouter } from 'vue-router'
import AppIcon from '@/components/AppIcon.vue'
import { newRowKey } from '@/components/add/gridRow'
import { useNotify } from '@/components/useNotify'
import { useApp } from '@/data/appContext'
import { handOffToGrid } from '@/data/gridHandoff'
import { submitOnEnter } from '@/directives'
import { MAX_IMPORT_ROWS, decodeCsvBytes, fileProblem, readCsv } from '@/lib/csvImport'
import { dateSpan, findAlreadySaved } from '@/lib/duplicates'
import type { EntryContext } from '@/lib/entryRow'
import { describeError } from '@/lib/errors'
import { formatRupees } from '@/lib/money'
import { PAYMENT_METHODS, activeOnly, methodLabel, type PaymentMethod, type Txn } from '@/lib/models'
import { readTable } from '@/lib/paste'
import RowsPreview from './RowsPreview.vue'
import { spentIn, usePreviewRows } from './previewRows'

/** Rows per insert: each is one all-or-nothing statement, well inside the server's time limit. */
const BATCH = 500

const visible = defineModel<boolean>('visible', { required: true })

const app = useApp()
const notify = useNotify()
const router = useRouter()
const formId = useId()

const fileInput = ref<HTMLInputElement | null>(null)
const fileName = ref('')
const text = ref<string | null>(null)
const fileError = ref<string | null>(null)

const accounts = computed(() => app.accounts.data.value ?? [])
const context = computed<EntryContext>(() => ({
  accounts: accounts.value,
  categories: app.categories.data.value ?? [],
  today: app.today.value,
}))

// What rows that don't say get (a bank statement has no Account column):
// an active account (the remembered one only while it is still active).
const activeAccounts = computed(() => activeOnly(accounts.value))
const defaultAccountId = ref<string | null>(null)
const defaultMethod = ref<PaymentMethod>(app.prefs.lastMethod ?? 'upi')
watch(
  activeAccounts,
  (list) => {
    if (defaultAccountId.value && list.some((a) => a.id === defaultAccountId.value)) return
    defaultAccountId.value =
      (list.find((a) => a.id === app.prefs.lastAccountId) ?? list.find((a) => a.type === 'bank') ?? list[0])?.id ?? null
  },
  { immediate: true },
)
const defaults = computed(() => ({
  account: accounts.value.find((a) => a.id === defaultAccountId.value)?.name ?? '',
  method: methodLabel(defaultMethod.value),
}))
const methodOptions = PAYMENT_METHODS.map((m) => ({ value: m.value, label: m.label }))

const table = computed(() => (text.value === null ? readTable([], app.today.value) : readCsv(text.value, app.today.value)))
const tooMany = computed(() => table.value.rows.length > MAX_IMPORT_ROWS)
const { roles, nonBlank, ready, problems } = usePreviewRows(table, context, defaults)

// ---------------------------------------------------------------- the file

/** One id per line of this file, so saving again after a failure can't duplicate a row. */
let ids = new Map<number, string>()
const idFor = (line: number) => ids.get(line) ?? (ids.set(line, newRowKey()), ids.get(line)!)

function chooseFile() {
  fileInput.value?.click()
}

async function onFile(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = '' // choosing the same file again still fires
  if (!file) return
  fileName.value = file.name
  text.value = null
  fileError.value = fileProblem(file)
  ids = new Map()
  savedLines.clear()
  existing.value = null
  failure.value = null
  if (fileError.value) return
  try {
    const content = decodeCsvBytes(new Uint8Array(await file.arrayBuffer()))
    if (!content.trim()) fileError.value = 'The file is empty.'
    else text.value = content
  } catch {
    fileError.value = "Couldn't read that file."
  }
}

// ---------------------------------------------------------------- already saved?

const existing = shallowRef<Txn[] | null>(null)
const checking = ref(false)
const checkError = ref<string | null>(null)
const span = computed(() => dateSpan(ready.value.map((r) => r.parsed.draft!)))
let checkSeq = 0
watch(
  () => JSON.stringify(span.value),
  async () => {
    const s = span.value
    const mine = ++checkSeq
    existing.value = null
    checkError.value = null
    if (!s) return
    checking.value = true
    try {
      const found = await app.repo.fetchTransactionsBetween(s.from, s.to)
      if (mine === checkSeq) existing.value = found
    } catch (e) {
      if (mine === checkSeq) checkError.value = describeError(e)
    } finally {
      if (mine === checkSeq) checking.value = false
    }
  },
  { immediate: true },
)

/** Lines saved by this dialog (they no longer count as "already saved" duplicates of themselves). */
const savedLines = reactive(new Set<number>())
const alreadySaved = computed(() =>
  existing.value
    ? findAlreadySaved(
        ready.value.filter((r) => !savedLines.has(r.line)).map((r) => ({ key: r.line, draft: r.parsed.draft! })),
        existing.value,
      )
    : new Set<number>(),
)
const includeDuplicates = ref(false)

const skipped = computed(() => {
  const m = new Map<number, string>()
  for (const line of savedLines) m.set(line, 'Saved')
  if (!includeDuplicates.value) {
    for (const line of alreadySaved.value) m.set(line, 'Already in Transactions (same date, amount, account and description): skipped')
  }
  return m
})

const toSave = computed(() => ready.value.filter((r) => !skipped.value.has(r.line)))
const spent = computed(() => spentIn(toSave.value))

// ---------------------------------------------------------------- saving

const saving = ref(false)
const failure = ref<string | null>(null)

async function save() {
  if (saving.value || tooMany.value || checking.value || toSave.value.length === 0) return
  failure.value = null
  saving.value = true
  const rows = toSave.value
  let done = 0
  let auto = 0
  try {
    app.requireOnline()
    for (let i = 0; i < rows.length; i += BATCH) {
      const chunk = rows.slice(i, i + BATCH)
      const saved = await app.repo.insertTransactions(chunk.map((r) => ({ id: idFor(r.line), ...r.parsed.draft! })))
      chunk.forEach((r) => savedLines.add(r.line))
      done += chunk.length
      auto += saved.filter((t) => t.autoCategorized).length
    }
  } catch (e) {
    failure.value =
      (done > 0 ? `${done} of ${rows.length} rows were saved before this happened. ` : 'Nothing was saved. ') +
      `${describeError(e)} Press Save again to save the rest; rows already saved won't be saved twice.`
    return
  } finally {
    saving.value = false
    if (done > 0) app.bump(['transactions', 'categories'])
  }

  notify.success(`Imported ${done} transaction${done === 1 ? '' : 's'}`, {
    detail: auto ? `${auto} categorized automatically.` : undefined,
    life: 5000,
  })
  // Taken before closing: the dialog unmounts when it closes.
  const broken = problems.value.map((r) => r.raw)
  visible.value = false
  if (broken.length) {
    handOffToGrid(broken)
    await router.push('/add')
  }
}

function allToGrid() {
  handOffToGrid(nonBlank.value.filter((r) => !skipped.value.has(r.line)).map((r) => r.raw))
  visible.value = false // unmounts the dialog; the rows were taken first
  void router.push('/add')
}
</script>

<template>
  <Dialog
    v-model:visible="visible"
    modal
    header="Import transactions from a CSV file"
    :style="{ width: 'min(1200px, 96vw)' }"
    :content-style="{ maxHeight: '74vh' }"
    :close-on-escape="!saving"
    :closable="!saving"
  >
    <form :id="formId" class="flex flex-col gap-3" @submit.prevent="save" @keydown="submitOnEnter">
      <div class="flex flex-wrap items-center gap-3">
        <input ref="fileInput" type="file" accept=".csv,.txt,.tsv,text/csv" class="hidden" data-testid="import-file" @change="onFile" />
        <Button
          :label="fileName ? 'Choose another file' : 'Choose a CSV file…'"
          :outlined="Boolean(fileName)"
          :disabled="saving"
          autofocus
          data-testid="import-choose"
          @click="chooseFile"
        >
          <template #icon><AppIcon name="upload_file" :size="20" /></template>
        </Button>
        <span v-if="fileName" class="font-medium" data-testid="import-file-name">{{ fileName }}</span>
        <span v-else class="text-sm text-slate-600">
          From Excel: File › Save As › "CSV UTF-8". Bank statements and Ventrafin's own export work too.
        </span>
      </div>

      <p v-if="fileError" class="text-sm text-expense" role="alert" data-testid="import-file-error">
        <AppIcon name="error" filled :size="18" class="align-[-4px]" /> {{ fileError }}
      </p>
      <p v-else-if="text !== null && table.rows.length === 0" class="text-sm text-expense" role="alert">
        No rows found in the file.
      </p>
      <p v-else-if="tooMany" class="text-sm text-expense" role="alert" data-testid="import-too-many">
        The file has {{ table.rows.length }} rows; one import takes at most {{ MAX_IMPORT_ROWS }}. Split it (for example one
        file per year) and import the parts one at a time.
      </p>

      <template v-if="text !== null && table.rows.length > 0 && !tooMany">
        <div class="flex flex-wrap items-center gap-x-5 gap-y-2 text-sm">
          <span data-testid="import-summary">
            Found <strong>{{ nonBlank.length }}</strong> row{{ nonBlank.length === 1 ? '' : 's' }}.
            <template v-if="table.headings">The first line was read as column headings.</template>
          </span>
          <label class="flex items-center gap-2">
            Rows without an account:
            <Select
              v-model="defaultAccountId"
              :options="activeAccounts"
              option-label="name"
              option-value="id"
              size="small"
              class="w-40"
              aria-label="Account for rows that don't say"
              data-testid="import-default-account"
            />
          </label>
          <label class="flex items-center gap-2">
            Expenses without "Paid by":
            <Select
              v-model="defaultMethod"
              :options="methodOptions"
              option-label="label"
              option-value="value"
              size="small"
              class="w-28"
              aria-label="Payment method for expenses that don't say"
            />
          </label>
        </div>

        <RowsPreview v-model:roles="roles" :table="table" :rows="nonBlank" :context="context" :skipped="skipped" />

        <div v-if="checking" class="text-sm text-slate-600">Checking for rows that are already in Transactions…</div>
        <div v-else-if="checkError" class="text-sm text-uncat-ink" role="status">
          <AppIcon name="warning" filled :size="18" class="align-[-4px]" /> Couldn't check for rows already saved
          ({{ checkError }}). Saving may add rows you already have.
        </div>
        <div
          v-else-if="alreadySaved.size > 0"
          class="flex flex-wrap items-center gap-2 rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-sm"
          data-testid="import-duplicates"
        >
          <AppIcon name="content_copy" :size="19" class="text-slate-600" />
          <span>
            <strong>{{ alreadySaved.size }}</strong> row{{ alreadySaved.size === 1 ? ' is' : 's are' }} already in Transactions
            (same date, amount, account and description) and {{ includeDuplicates ? 'will be saved again' : 'will be skipped' }}.
          </span>
          <label class="ml-auto flex items-center gap-1.5">
            <input v-model="includeDuplicates" type="checkbox" data-testid="import-include-duplicates" />
            Save them anyway
          </label>
        </div>
      </template>

      <p v-if="failure" class="text-sm text-expense" role="alert" data-testid="import-failure">
        <AppIcon name="error" filled :size="18" class="align-[-4px]" /> {{ failure }}
      </p>
    </form>

    <template #footer>
      <div class="flex w-full flex-wrap items-center gap-2">
        <div class="mr-auto text-sm" data-testid="import-counts">
          <template v-if="nonBlank.length && !tooMany">
            <span class="font-semibold text-income">{{ toSave.length }} to save</span>
            <span v-if="spent > 0" class="text-slate-600"> ({{ formatRupees(spent) }} spent)</span>
            <template v-if="problems.length">
              · <span class="font-semibold text-expense">{{ problems.length }} can't be saved yet</span>
              <span class="text-slate-600"> (they go into the Add grid for you to fix)</span>
            </template>
          </template>
        </div>
        <Button label="Cancel" severity="secondary" text :disabled="saving" @click="visible = false" />
        <Button
          label="Put in the Add grid to review"
          severity="secondary"
          outlined
          :disabled="saving || tooMany || nonBlank.length === 0"
          data-testid="import-to-grid"
          @click="allToGrid"
        />
        <Button
          type="submit"
          :form="formId"
          :label="`Save ${toSave.length} row${toSave.length === 1 ? '' : 's'}`"
          :loading="saving"
          :disabled="tooMany || checking || toSave.length === 0"
          data-testid="import-save"
        />
      </div>
    </template>
  </Dialog>
</template>
