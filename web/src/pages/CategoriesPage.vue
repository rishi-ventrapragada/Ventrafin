<script setup lang="ts">
// Categories with their icons and colours; click one to rename it or change
// its icon and colour (same as the phone). Updates live, e.g. when
// auto-categorization creates one. (Adding and archiving come with the
// categorization phase, on both apps.)
import Button from 'primevue/button'
import { computed, ref } from 'vue'
import AppIcon from '@/components/AppIcon.vue'
import CategoryEditDialog from '@/components/CategoryEditDialog.vue'
import TxnAvatar from '@/components/TxnAvatar.vue'
import { useApp } from '@/data/appContext'
import { CATEGORY_ICON_LABELS, readableTextColor } from '@/lib/categoryStyle'
import { describeError } from '@/lib/errors'
import { sortByName, type Category, type CategoryKind } from '@/lib/models'

const app = useApp()
const editing = ref<Category | null>(null)

const groups = computed(() => {
  const all = app.categories.data.value ?? []
  return (['expense', 'income'] as CategoryKind[]).map((kind) => ({
    kind,
    title: kind === 'expense' ? 'Expense categories' : 'Income categories',
    items: sortByName(all.filter((c) => c.kind === kind)),
  }))
})
</script>

<template>
  <div class="flex max-w-4xl flex-col gap-3">
    <div class="flex items-end gap-2">
      <div class="mr-auto">
        <h1 class="text-xl font-semibold text-slate-800">Categories</h1>
        <p class="text-sm text-slate-600">Click a category to rename it or change its icon and colour.</p>
      </div>
    </div>

    <div v-if="!app.categories.data.value && app.categories.error.value" class="card flex items-center gap-3 p-4" role="alert">
      <span>Couldn't load categories. {{ describeError(app.categories.error.value) }}</span>
      <Button label="Retry" size="small" @click="app.categories.refresh()" />
    </div>
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
              <th class="w-24"></th>
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
                <span v-if="c.archived" class="ml-2 rounded bg-slate-100 px-1.5 text-sm text-slate-600">archived</span>
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
      <p class="text-sm text-slate-600">
        Renaming keeps a category's automatic matches: if Food becomes "Khana", Swiggy still goes there. Adding and
        archiving categories are coming in a later update.
      </p>
    </template>

    <CategoryEditDialog :category="editing" @close="editing = null" />
  </div>
</template>
