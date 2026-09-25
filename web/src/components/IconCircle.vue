<script setup lang="ts">
// A glyph in a circle. Filled = a real category (its colour, readable glyph);
// outlined = a "no category" state (Uncategorized, Transfer, Auto), so it
// can't be mistaken for a category at a glance. Same as the phone's
// ColorIconCircle / OutlinedIconCircle (DECISIONS.md D20): an outlined glyph
// is drawn in a shade readable on its tint over the theme's surfaces (the
// amber "?" was 3.7:1), and a filled colour too close to those surfaces
// (yellow on white) gets a thin darker outline.
import { computed } from 'vue'
import { circleEdgeFor, foregroundOn, outlinedInkFor, withAlpha } from '@/lib/categoryStyle'
import { activeTheme, themeSurfaces } from '@/lib/theme'
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

const surfaces = computed(() => themeSurfaces(activeTheme.value))
const edge = computed(() => (props.outlined ? null : circleEdgeFor(props.color, surfaces.value)))

const style = computed(() => {
  const s = `${props.size}px`
  if (props.outlined) {
    const ink = outlinedInkFor(props.color, surfaces.value)
    return {
      width: s,
      height: s,
      background: withAlpha(props.color, 0.1),
      border: `${props.size >= 24 ? 2 : 1.5}px solid ${ink}`,
      color: ink,
    }
  }
  return {
    width: s,
    height: s,
    background: props.color,
    color: foregroundOn(props.color),
    ...(edge.value ? { boxShadow: `inset 0 0 0 1px ${edge.value}` } : {}),
  }
})
</script>

<template>
  <span
    class="inline-flex shrink-0 items-center justify-center rounded-full"
    :style="style"
    :title="label"
    :data-circle="outlined ? 'outlined' : 'filled'"
    :data-edge="edge ? 'outlined' : undefined"
  >
    <AppIcon :name="icon" :filled="!outlined" :size="Math.round(size * (outlined ? 0.55 : 0.58))" :label="label" />
  </span>
</template>
