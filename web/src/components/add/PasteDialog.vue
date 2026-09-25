<script setup lang="ts">
// Preview of rows pasted from Excel. Shows which column Ventrafin thinks is
// which (changeable), every row as it will be saved, and marks rows that
// can't be saved and why. Nothing is saved until the user confirms.
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { computed, ref, toRef, watch } from 'vue'
import RowsPreview from '@/components/import/RowsPreview.vue'
import { spentIn, usePreviewRows } from '@/components/import/previewRows'
import type { EntryContext, RawRow } from '@/lib/entryRow'
import { formatRupees } from '@/lib/money'
import { readPaste, type PasteDefaults } from '@/lib/paste'

const props = defineProps<{
  /** Text that was pasted into the grid ('' when opened from the button). */
  initialText: string
  context: EntryContext
  defaults: PasteDefaults
  saving: boolean
}>()

const visible = defineModel<boolean>('visible', { required: true })

const emit = defineEmits<{
  /** Save the ready rows; rows with problems go to the grid to be fixed. */
  save: [ready: RawRow[], problems: RawRow[]]
  /** Put every row into the grid without saving. */
  toGrid: [rows: RawRow[]]
}>()

const text = ref(props.initialText)
watch(
  () => props.initialText,
  (t) => (text.value = t),
)

const table = computed(() => readPaste(text.value, props.context.today))
const { roles, nonBlank, ready, problems } = usePreviewRows(table, toRef(props, 'context'), toRef(props, 'defaults'))
const spent = computed(() => spentIn(ready.value))
</script>

<template>
  <Dialog
    v-model:visible="visible"
    modal
    header="Paste rows from Excel"
    :style="{ width: 'min(1200px, 96vw)' }"
    :content-style="{ maxHeight: '72vh' }"
    :close-on-escape="!saving"
    :closable="!saving"
  >
    <div class="flex flex-col gap-3">
      <div>
        <label for="paste-box" class="mb-1 block text-sm font-semibold text-slate-700">
          Copy the rows in Excel, click in the box and press <kbd>Ctrl</kbd>+<kbd>V</kbd>
        </label>
        <textarea
          id="paste-box"
          v-model="text"
          rows="3"
          class="w-full rounded-md border border-slate-300 bg-slate-50 px-2 py-1.5 font-mono text-sm outline-none focus:border-primary focus:bg-white"
          placeholder="Date	Description	Amount	Category	Paid by"
          spellcheck="false"
          data-testid="paste-box"
        />
      </div>

      <template v-if="table.rows.length > 0">
        <div class="text-sm text-slate-600" data-testid="paste-summary">
          Found <strong>{{ nonBlank.length }}</strong> row{{ nonBlank.length === 1 ? '' : 's' }}.
          <span v-if="table.headings">The first line was read as column headings and is not saved.</span>
          Check the columns below; change any that Ventrafin guessed wrong.
        </div>
        <RowsPreview v-model:roles="roles" :table="table" :rows="nonBlank" :context="context" />
      </template>
    </div>

    <template #footer>
      <div class="flex w-full flex-wrap items-center gap-2">
        <div class="mr-auto text-sm" data-testid="paste-counts">
          <template v-if="nonBlank.length">
            <span class="font-semibold text-income">{{ ready.length }} ready</span>
            <span v-if="spent > 0" class="text-slate-600"> ({{ formatRupees(spent) }} spent)</span>
            <template v-if="problems.length">
              · <span class="font-semibold text-expense">{{ problems.length }} can't be saved yet</span>
              <span class="text-slate-600"> (they go into the grid for you to fix)</span>
            </template>
          </template>
        </div>
        <Button label="Cancel" severity="secondary" text :disabled="saving" @click="visible = false" />
        <Button
          label="Put in the grid to review"
          severity="secondary"
          outlined
          :disabled="saving || nonBlank.length === 0"
          data-testid="paste-to-grid"
          @click="emit('toGrid', nonBlank.map((r) => r.raw))"
        />
        <Button
          :label="`Save ${ready.length} row${ready.length === 1 ? '' : 's'}`"
          :loading="saving"
          :disabled="ready.length === 0"
          data-testid="paste-save"
          @click="emit('save', ready.map((r) => r.raw), problems.map((r) => r.raw))"
        />
      </div>
    </template>
  </Dialog>
</template>
