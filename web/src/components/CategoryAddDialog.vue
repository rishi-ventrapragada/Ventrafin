<script setup lang="ts">
// Add a category by hand (PRD § 4.3): a name and Expense or Income. The
// database picks its icon from the name and the first unused colour, as it
// does on the phone; both can be changed afterwards. Opens on the name;
// Enter adds; X or Escape asks before throwing away what was typed.
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { useToast } from 'primevue/usetoast'
import { computed, ref, useId, watch } from 'vue'
import { useApp } from '@/data/appContext'
import { submitOnEnter } from '@/directives'
import { AppError, describeError } from '@/lib/errors'
import { CATEGORY_NAME_MAX, categoryNameError, type CategoryKind } from '@/lib/models'
import { useGuardedClose } from './useAsk'

/** `null`: closed; a kind: open, starting on that kind. */
const props = defineProps<{ kind: CategoryKind | null }>()
const emit = defineEmits<{ close: [] }>()

const app = useApp()
const toast = useToast()
const formId = useId()

const KINDS: readonly { value: CategoryKind; label: string }[] = [
  { value: 'expense', label: 'Expense' },
  { value: 'income', label: 'Income' },
]

const name = ref('')
const kind = ref<CategoryKind>('expense')
const tried = ref(false)
const saving = ref(false)
const error = ref<string | null>(null)

watch(
  () => props.kind,
  (k) => {
    if (!k) return
    name.value = ''
    kind.value = k
    tried.value = false
    error.value = null
  },
  { immediate: true },
)

const nameError = computed(() => categoryNameError(name.value, { kind: kind.value, existing: app.categories.data.value ?? [] }))

const { requestClose, asking } = useGuardedClose(
  () => name.value.trim() !== '',
  () => emit('close'),
)
const visible = computed({
  get: () => props.kind !== null,
  set: (v) => {
    if (!v && !saving.value && !asking.value) void requestClose()
  },
})

async function save() {
  tried.value = true
  if (nameError.value || saving.value) return
  error.value = null
  saving.value = true
  const newName = name.value.trim()
  try {
    app.requireOnline()
    await app.repo.insertCategory(newName, kind.value)
  } catch (e) {
    error.value =
      e instanceof AppError && e.code === '23505'
        ? `Not added. You already have ${kind.value === 'income' ? 'an income' : 'an expense'} category with that name.`
        : `Not added. ${describeError(e)}`
    return
  } finally {
    saving.value = false
  }
  app.bump(['categories'])
  toast.add({ severity: 'success', summary: `Added ${newName}`, life: 3000 })
  emit('close')
}
</script>

<template>
  <Dialog v-model:visible="visible" modal header="Add category" :style="{ width: 'min(30rem, 96vw)' }">
    <form :id="formId" class="flex flex-col gap-3" data-testid="category-add-form" @submit.prevent="save" @keydown="submitOnEnter">
      <label class="flex flex-col gap-1">
        <span class="font-medium text-slate-700">Name</span>
        <input
          v-model="name"
          :maxlength="CATEGORY_NAME_MAX + 10"
          class="focus-ring w-full rounded-md border px-2.5 py-1.5 focus:border-primary"
          :class="(tried || name) && nameError ? 'border-expense' : 'border-slate-300'"
          data-testid="category-add-name"
          autocomplete="off"
          autofocus
        />
        <span v-if="(tried || name.trim()) && nameError" class="text-sm text-expense" data-testid="category-add-error">{{ nameError }}</span>
      </label>
      <div class="flex gap-4" role="radiogroup" aria-label="Kind">
        <label v-for="k in KINDS" :key="k.value" class="inline-flex cursor-pointer items-center gap-1.5">
          <input v-model="kind" type="radio" name="category-kind" :value="k.value" class="accent-[var(--vf-primary)]" :data-testid="`category-add-${k.value}`" />
          {{ k.label }}
        </label>
      </div>
      <p class="text-sm text-slate-600">Ventrafin picks an icon and colour from the name. Change them afterwards by opening the category.</p>
      <p v-if="error" class="text-sm text-expense" role="alert">{{ error }}</p>
    </form>
    <template #footer>
      <Button label="Cancel" severity="secondary" text :disabled="saving" @click="emit('close')" />
      <Button type="submit" :form="formId" label="Add category" :loading="saving" data-testid="category-add-save" />
    </template>
  </Dialog>
</template>
