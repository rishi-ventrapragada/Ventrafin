<script setup lang="ts">
// Categories with their icons and colours (PRD § 4.3). Click one to rename
// it, change its icon and colour, or archive it; add new ones; archived ones
// wait at the bottom with a Restore button. Same as the phone. Updates live,
// e.g. when auto-categorization creates one.
import Button from 'primevue/button'
import { useToast } from 'primevue/usetoast'
import { computed, ref } from 'vue'
import AppIcon from '@/components/AppIcon.vue'
import CategoryAddDialog from '@/components/CategoryAddDialog.vue'
import CategoryEditDialog from '@/components/CategoryEditDialog.vue'
import LoadError from '@/components/LoadError.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { useApp } from '@/data/appContext'
import { CATEGORY_ICON_LABELS, readableTextColor } from '@/lib/categoryStyle'
import { describeError } from '@/lib/errors'
import { sortByName, type Category, type CategoryKind } from '@/lib/models'

const app = useApp()
const toast = useToast()
const editing = ref<Category | null>(null)
/** The kind a new category starts as (the section it was added from); null = closed. */
const adding = ref<CategoryKind | null>(null)

const all = computed(() => app.categories.data.value ?? [])
const groups = computed(() =>
  (['expense', 'income'] as CategoryKind[]).map((kind) => ({
    kind,
    title: kind === 'expense' ? 'Expense categories' : 'Income categories',
    items: sortByName(all.value.filter((c) => c.kind === kind && !c.archived)),
  })),
)
const archived = computed(() => sortByName(all.value.filter((c) => c.archived)))

const restoring = ref<string | null>(null)

/** No confirm: restoring hides nothing and can be archived again. */
async function restore(c: Category) {
  restoring.value = c.id
  try {
    app.requireOnline()
    await app.repo.setCategoryArchived(c.id, false)
    app.bump(['categories'])
    toast.add({ severity: 'success', summary: `Restored ${c.name}`, life: 3000 })
  } catch (e) {
    toast.add({ severity: 'error', summary: 'Not restored', detail: describeError(e), life: 5000 })
  } finally {
    restoring.value = null
  }
}
</script>

<template>
  <div class="flex max-w-4xl flex-col gap-3">
    <div class="flex items-end gap-2">
      <div class="mr-auto">
        <h1 class="text-xl font-semibold text-slate-800">Categories</h1>
        <p class="text-sm text-slate-600">Click a category to rename it, change its icon and colour, or archive it.</p>
      </div>
      <Button label="Add category" data-testid="add-category" @click="adding = 'expense'">
        <template #icon><AppIcon name="add" :size="20" /></template>
      </Button>
    </div>

    <LoadError
      v-if="!app.categories.data.value && app.categories.error.value"
      :error="app.categories.error.value"
      what="Couldn't load categories."
      @retry="app.categories.refresh()"
    />
    <div v-else-if="!app.categories.data.value" class="muted">Loading…</div>

    <template v-else>
      <section v-for="g in groups" :key="g.kind" class="card overflow-hidden">
        <table class="dense-table" :data-testid="`categories-${g.kind}`">
          <thead>
            <tr>
              <th class="w-10"></th>
              <th>{{ g.title }} ({{ g.items.length }})</th>
              <th>Icon</th>
              <th>Colour</th>
              <th class="w-24 text-right">
                <button
                  type="button"
                  class="inline-flex items-center gap-1 rounded px-2 py-0.5 font-medium text-primary hover:bg-primary-soft"
                  :aria-label="`Add ${g.kind} category`"
                  :data-testid="`add-${g.kind}-category`"
                  @click="adding = g.kind"
                >
                  <AppIcon name="add" :size="19" /> Add
                </button>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="c in g.items"
              :key="c.id"
              class="cursor-pointer"
              :data-category-id="c.id"
              @click="editing = c"
            >
              <td><TxnAvatar :category="c" :size="32" /></td>
              <td>
                <span class="font-semibold" :style="{ color: readableTextColor(c.color) }">{{ c.name }}</span>
              </td>
              <td class="text-slate-600">{{ CATEGORY_ICON_LABELS[c.icon] ?? 'Tag' }}</td>
              <td>
                <span class="inline-flex items-center gap-1.5 font-mono text-sm text-slate-600">
                  <span class="inline-block h-4 w-4 rounded-sm" :style="{ background: c.color }" />{{ c.color }}
                </span>
              </td>
              <td class="text-right">
                <button
                  type="button"
                  class="inline-flex items-center gap-1 rounded px-2 py-0.5 font-medium text-primary hover:bg-primary-soft"
                  :aria-label="`Edit ${c.name}`"
                  @click.stop="editing = c"
                >
                  <AppIcon name="edit" :size="19" /> Edit
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section v-if="archived.length" class="card overflow-hidden">
        <table class="dense-table" data-testid="categories-archived">
          <thead>
            <tr>
              <th class="w-10"></th>
              <th>Archived ({{ archived.length }})</th>
              <th>Kind</th>
              <th class="w-28"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="c in archived" :key="c.id" class="cursor-pointer" :data-category-id="c.id" @click="editing = c">
              <td><TxnAvatar :category="c" :size="32" /></td>
              <td class="font-medium text-slate-700">{{ c.name }}</td>
              <td class="text-slate-600">{{ c.kind === 'income' ? 'Income' : 'Expense' }}</td>
              <td class="text-right">
                <button
                  type="button"
                  class="inline-flex items-center gap-1 rounded px-2 py-0.5 font-medium text-primary hover:bg-primary-soft disabled:opacity-60"
                  :aria-label="`Restore ${c.name}`"
                  :disabled="restoring === c.id"
                  :data-testid="`restore-${c.id}`"
                  @click.stop="restore(c)"
                >
                  <AppIcon name="unarchive" :size="19" /> Restore
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <p class="text-sm text-slate-600">
        Renaming keeps a category's automatic matches: if Food becomes "Khana", Swiggy still goes there. Archived
        categories are left out of the pickers and of automatic matching; their past transactions keep them.
      </p>
    </template>

    <CategoryEditDialog :category="editing" @close="editing = null" />
    <CategoryAddDialog :kind="adding" @close="adding = null" />
  </div>
</template>
