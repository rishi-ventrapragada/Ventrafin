<script setup lang="ts">
// A Material Symbols glyph from the generated registry (no icon font).
import { computed } from 'vue'
import { FILLED_ICONS, OUTLINED_ICONS } from '@/lib/icons.generated'

const props = withDefaults(
  defineProps<{
    name: string
    filled?: boolean
    size?: number | string
    /** Accessible name; without it the icon is decorative. */
    label?: string
  }>(),
  { filled: false, size: 18, label: undefined },
)

const path = computed(
  () =>
    (props.filled
      ? (FILLED_ICONS[props.name] ?? OUTLINED_ICONS[props.name])
      : (OUTLINED_ICONS[props.name] ?? FILLED_ICONS[props.name])) ?? FILLED_ICONS.label,
)
</script>

<template>
  <svg
    :width="size"
    :height="size"
    viewBox="0 -960 960 960"
    fill="currentColor"
    focusable="false"
    class="inline-block shrink-0"
    :data-icon="name"
    :role="label ? 'img' : undefined"
    :aria-label="label"
    :aria-hidden="label ? undefined : 'true'"
  >
    <path :d="path" />
  </svg>
</template>
