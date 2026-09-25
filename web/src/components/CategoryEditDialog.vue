<script setup lang="ts">
// Rename a category and pick its colour and icon from the curated sets
// (DECISIONS.md D13), or archive / restore it (PRD § 4.3). Same rules and
// wording as the phone's edit sheet. Opens on the name; Enter saves; X or
// Escape asks before throwing away a change.
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { useToast } from 'primevue/usetoast'
import { computed, ref, useId, watch } from 'vue'
import { useApp } from '@/data/appContext'
import { submitOnEnter } from '@/directives'
import { CATEGORY_ICON_GROUPS, CATEGORY_PALETTE, categoryIconKey, foregroundOn } from '@/lib/categoryStyle'
import { AppError, describeError } from '@/lib/errors'
import { CATEGORY_NAME_MAX, categoryNameError, type Category } from '@/lib/models'
import AppIcon from './AppIcon.vue'
import IconCircle from './IconCircle.vue'
import { useGuardedClose } from './useAsk'

const props = defineProps<{ category: Category | null }>()
const emit = defineEmits<{ close: [] }>()

const app = useApp()
const toast = useToast()
const formId = useId()

const name = ref('')
const icon = ref('')
const color = ref('')
const saving = ref(false)
const error = ref<string | null>(null)

watch(
  () => props.category,
  (c) => {
    if (!c) return
    name.value = c.name
    icon.value = categoryIconKey(c.icon)
    color.value = c.color
    error.value = null
  },
  { immediate: true },
)


const nameError = computed(() =>
  props.category
    ? categoryNameError(name.value, {
        kind: props.category.kind,
        existing: app.categories.data.value ?? [],
        exceptId: props.category.id,
      })
    : null,
)

const changed = computed(
  () =>
    !!props.category &&
    (name.value.trim() !== props.category.name || icon.value !== props.category.icon || color.value !== props.category.color),
)

const { requestClose, ask, asking } = useGuardedClose(
  () => changed.value,
  () => emit('close'),
)
const visible = computed({
  get: () => props.category !== null,
  set: (v) => {
    if (!v && !saving.value && !asking.value) void requestClose()
  },
})

// A colour from outside the palette (set some other way) stays selectable, first.
const swatches = computed(() =>
  props.category && !CATEGORY_PALETTE.includes(props.category.color) ? [props.category.color, ...CATEGORY_PALETTE] : [...CATEGORY_PALETTE],
)

async function save() {
  const c = props.category
  if (!c || nameError.value || !changed.value) return
  error.value = null
  saving.value = true
  try {
    app.requireOnline()
    await app.repo.updateCategory(c.id, { name: name.value.trim(), icon: icon.value, color: color.value })
  } catch (e) {
    error.value =
      e instanceof AppError && e.code === '23505'
        ? `Not saved. You already have ${c.kind === 'income' ? 'an income' : 'an expense'} category with that name.`
        : `Not saved. ${describeError(e)}`
    return
  } finally {
    saving.value = false
  }
  app.bump(['categories'])
  const newName = name.value.trim()
  toast.add({
    severity: 'success',
    summary: newName === c.name ? `${c.name} updated` : `${c.name} renamed to ${newName}`,
    life: 3000,
  })
  emit('close')
}

/** Archive (after asking) or restore: hidden from the pickers and auto-categorization, or back. */
async function setArchived(archived: boolean) {
  const c = props.category
  if (!c || saving.value) return
  if (
    archived &&
    !(await ask({
      header: `Archive ${c.name}?`,
      message:
        'It disappears from the category pickers and auto-categorization stops using it. Its past transactions keep it, and you can restore it any time.',
      acceptLabel: 'Archive',
      rejectLabel: 'Cancel',
      defaultFocus: 'reject',
      rejectProps: { severity: 'secondary', outlined: true },
    }))
  ) {
    return
  }
  error.value = null
  saving.value = true
  try {
    app.requireOnline()
    await app.repo.setCategoryArchived(c.id, archived)
  } catch (e) {
    error.value = `${archived ? 'Not archived' : 'Not restored'}. ${describeError(e)}`
    return
  } finally {
    saving.value = false
  }
  app.bump(['categories'])
  toast.add({ severity: 'success', summary: `${archived ? 'Archived' : 'Restored'} ${c.name}`, life: 3000 })
  emit('close')
}
</script>

<template>
  <Dialog v-model:visible="visible" modal :header="category ? `Edit ${category.kind} category` : ''" :style="{ width: 'min(46rem, 96vw)' }">
    <form v-if="category" :id="formId" class="flex flex-col gap-4" @submit.prevent="save" @keydown="submitOnEnter">
      <div class="flex items-start gap-3">
        <IconCircle :icon="icon" :color="color" :size="52" />
        <div class="flex-1">
          <label for="category-name" class="mb-1 block text-sm font-semibold text-slate-700">Name</label>
          <input
            id="category-name"
            v-model="name"
            :maxlength="CATEGORY_NAME_MAX"
            class="focus-ring w-full rounded-md border px-2.5 py-1.5 focus:border-primary"
            :class="nameError ? 'border-expense' : 'border-slate-300'"
            data-testid="category-name"
            autocomplete="off"
            autofocus
          />
          <p v-if="nameError" class="mt-1 text-sm text-expense" data-testid="category-name-error">{{ nameError }}</p>
          <p v-else class="mt-1 text-sm text-slate-600">
            Renaming keeps its automatic matches: if Food becomes "Khana", Swiggy still goes there.
          </p>
        </div>
      </div>

      <div>
        <div class="mb-1.5 text-sm font-semibold text-slate-700">Colour</div>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="hex in swatches"
            :key="hex"
            type="button"
            class="flex h-8 w-8 items-center justify-center rounded-full"
            :class="hex === color ? 'ring-2 ring-slate-800 ring-offset-2' : 'ring-1 ring-black/10'"
            :style="{ background: hex, color: foregroundOn(hex) }"
            :aria-label="`Colour ${hex}`"
            :aria-pressed="hex === color"
            :data-testid="`color-${hex}`"
            @click="color = hex"
          >
            <AppIcon v-if="hex === color" name="check" :size="21" />
          </button>
        </div>
      </div>

      <div class="max-h-[40vh] overflow-auto pr-1">
        <div v-for="group in CATEGORY_ICON_GROUPS" :key="group.name" class="mb-3">
          <div class="mb-1.5 text-sm font-semibold text-slate-700">{{ group.name }}</div>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="def in group.icons"
              :key="def.key"
              v-tooltip.top="def.label"
              type="button"
              class="flex h-10 w-10 items-center justify-center rounded-full"
              :class="def.key === icon ? 'ring-2 ring-slate-800' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'"
              :style="def.key === icon ? { background: color, color: foregroundOn(color) } : {}"
              :aria-label="def.label"
              :aria-pressed="def.key === icon"
              :data-testid="`icon-${def.key}`"
              @click="icon = def.key"
            >
              <AppIcon :name="def.key" filled :size="25" />
            </button>
          </div>
        </div>
      </div>

      <p v-if="error" class="text-sm text-expense" role="alert">{{ error }}</p>
    </form>
    <template #footer>
      <div class="flex w-full items-center gap-2">
        <Button
          v-if="category && !category.archived"
          label="Archive"
          severity="secondary"
          outlined
          class="mr-auto"
          :disabled="saving"
          data-testid="category-archive"
          @click="setArchived(true)"
        >
          <template #icon><AppIcon name="archive" :size="19" /></template>
        </Button>
        <Button
          v-else-if="category"
          label="Restore"
          severity="secondary"
          outlined
          class="mr-auto"
          :disabled="saving"
          data-testid="category-restore"
          @click="setArchived(false)"
        >
          <template #icon><AppIcon name="unarchive" :size="19" /></template>
        </Button>
        <Button label="Cancel" severity="secondary" text :disabled="saving" @click="emit('close')" />
        <Button
          type="submit"
          :form="formId"
          label="Save"
          :loading="saving"
          :disabled="!changed || !!nameError"
          data-testid="category-save"
        />
      </div>
    </template>
  </Dialog>
</template>
