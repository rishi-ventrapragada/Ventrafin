<script setup lang="ts">
// The leading visual of a transaction or category: the category's icon in
// its colour; Uncategorized as an outlined amber "?"; transfers as an
// outlined grey arrow; "Auto" as an outlined sparkle.
import { computed } from 'vue'
import { TRANSFER_LOOK, UNCATEGORIZED_LOOK, categoryIconKey } from '@/lib/categoryStyle'
import type { Category } from '@/lib/models'
import { OCEAN_PRIMARY } from '@/lib/theme'
import IconCircle from './IconCircle.vue'

const props = withDefaults(
  defineProps<{
    /** 'category' needs `category`; the others are fixed looks. */
    kind?: 'category' | 'uncategorized' | 'transfer' | 'auto'
    category?: Category | null
    size?: number
  }>(),
  { kind: 'category', category: null, size: 28 },
)

const look = computed(() => {
  switch (props.kind) {
    case 'uncategorized':
      return { icon: UNCATEGORIZED_LOOK.icon, color: UNCATEGORIZED_LOOK.color, outlined: true, label: 'Uncategorized' }
    case 'transfer':
      return { icon: TRANSFER_LOOK.icon, color: TRANSFER_LOOK.color, outlined: true, label: 'Transfer' }
    case 'auto':
      return { icon: 'auto_awesome', color: OCEAN_PRIMARY, outlined: true, label: 'Auto category' }
    default: {
      const c = props.category
      // Category row not loaded yet (e.g. just auto-created): neutral circle.
      if (!c) return { icon: 'label', color: '#BDBDBD', outlined: false, label: 'Category' }
      return { icon: categoryIconKey(c.icon), color: c.color, outlined: false, label: c.name }
    }
  }
})
</script>

<template>
  <IconCircle :icon="look.icon" :color="look.color" :outlined="look.outlined" :size="size" :label="look.label" />
</template>
