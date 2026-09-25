<script setup lang="ts">
// Rounded-square letter badge for the merchant in a description (D14).
// Renders nothing when the description names no merchant.
import { computed } from 'vue'
import { readableTextColor, tintOnWhite, withAlpha } from '@/lib/categoryStyle'
import { merchantBadgeFor } from '@/lib/merchant'

const props = withDefaults(defineProps<{ description: string; size?: number }>(), { size: 16 })

const badge = computed(() => merchantBadgeFor(props.description))
const style = computed(() => {
  const b = badge.value
  if (!b) return {}
  return {
    width: `${props.size}px`,
    height: `${props.size}px`,
    fontSize: `${Math.round(props.size * 0.62)}px`,
    borderRadius: `${props.size * 0.25}px`,
    background: withAlpha(b.color, 0.18),
    border: `0.8px solid ${withAlpha(b.color, 0.6)}`,
    // Readable on the badge's own tint, not just on white.
    color: readableTextColor(b.color, tintOnWhite(b.color, 0.18)),
  }
})
</script>

<template>
  <span
    v-if="badge"
    class="inline-flex shrink-0 items-center justify-center leading-none font-bold select-none"
    :style="style"
    :data-merchant-letter="badge.letter"
    aria-hidden="true"
    >{{ badge.letter }}</span
  >
</template>
