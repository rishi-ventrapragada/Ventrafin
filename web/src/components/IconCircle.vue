<script setup lang="ts">
// A glyph in a circle. Filled = a real category (its colour, readable glyph);
// outlined = a "no category" state (Uncategorized, Transfer, Auto), so it
// can't be mistaken for a category at a glance. Same as the phone's
// ColorIconCircle / OutlinedIconCircle, except that an outlined glyph is
// drawn in a shade readable on its tint (the amber "?" was 3.7:1).
import { computed } from 'vue'
import { foregroundOn, readableTextColor, withAlpha } from '@/lib/categoryStyle'
import AppIcon from './AppIcon.vue'

const props = withDefaults(
  defineProps<{
    icon: string
    color: string
    size?: number
    outlined?: boolean
    label?: string
  }>(),
  { size: 28, outlined: false, label: undefined },
)

const style = computed(() => {
  const s = `${props.size}px`
  const ink = readableTextColor(props.color)
  return props.outlined
    ? {
        width: s,
        height: s,
        background: withAlpha(props.color, 0.1),
        border: `${props.size >= 24 ? 2 : 1.5}px solid ${ink}`,
        color: ink,
      }
    : { width: s, height: s, background: props.color, color: foregroundOn(props.color) }
})
</script>

<template>
  <span
    class="inline-flex shrink-0 items-center justify-center rounded-full"
    :style="style"
    :title="label"
    :data-circle="outlined ? 'outlined' : 'filled'"
  >
    <AppIcon :name="icon" :filled="!outlined" :size="Math.round(size * (outlined ? 0.55 : 0.58))" :label="label" />
  </span>
</template>
